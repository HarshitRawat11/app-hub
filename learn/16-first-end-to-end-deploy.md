# 16 — The first end-to-end deploy on EKS

## What we did

Provisioned the cluster, pushed the image, deployed the service, and reached it — on real AWS, in one sitting. `terraform apply` → 55 resources → build → push to ECR → `kubectl apply` → `curl http://links-service:8000/health` from *inside* the cluster.

`E-02`, `E-03` and `E-04` all landed on **2026-08-31**, taking roughly 20 minutes end to end.

## Why

Everything up to this point was pieces that had never been connected under this configuration: fixed code, a rewritten Dockerfile, corrected manifests, freshly configured credentials. Individually verified, never run together.

This step is where "it should work" becomes "it works," and it is also the rehearsal for the loop you will run every session from now on — because the cluster gets destroyed each night.

## Key concepts

### 1. The apply has a dependency order, and you can watch it

Terraform creates in dependency order, and polling AWS mid-apply shows it clearly:

```
VPC          available          ← created first, everything else needs it
NAT gateway  available          ← BILLING STARTS HERE
ECR repo     created            ← independent of the cluster
EKS cluster  CREATING           ← the 10-15 minute wait
node group   (not yet started)  ← waits for the cluster to be ACTIVE
```

Two things worth taking from that.

**The NAT gateway starts billing well before anything is usable.** It is available within a minute or two, while the cluster is still ten minutes from existing. Cost starts at `apply`, not at first use.

**The EKS control plane is genuinely slow.** Ten to fifteen minutes is normal, and the node group only begins after it. `terraform apply` has not hung — this is what EKS is like.

### 2. Parallelise the parts with no dependency

The image push (`E-03`) depends on the **ECR repository**, not on the cluster. ECR is created early. So instead of waiting for EKS and then pushing, we pushed while the control plane was still `CREATING`.

That is not a trick, it is just reading the dependency graph — but it turned a serial ~20 minute wait into overlapping work. **When something is slow, ask what actually depends on it.** Usually less than you assume.

### 3. `update-kubeconfig` — the step that is never optional

```bash
aws eks update-kubeconfig --region ap-south-1 --name app-hub-eks
```

```
Updated context arn:aws:eks:ap-south-1:314146298861:cluster/app-hub-eks in /home/harshitrawat/.kube/config
```

Note the path: **WSL's** home, not Windows'. This must run from WSL, because that is where the app-hub credentials live and where `kubectl` will be used (`learn/11`).

EKS mints a **new API endpoint hostname on every cluster creation**, so after each destroy/apply the old kubeconfig points at a hostname that no longer resolves. The failures look like network or auth problems, not staleness. It takes a second and is idempotent — treat it as a precondition, not a step to remember.

### 4. Nodes with no external IP is the design working

```
NAME                    STATUS   INTERNAL-IP   EXTERNAL-IP
ip-10-0-1-184...        Ready    10.0.1.184    <none>
ip-10-0-2-247...        Ready    10.0.2.247    <none>
```

Three things confirmed at once:

- **One node per AZ** — `10.0.1.x` and `10.0.2.x` are the two private subnets from `learn/04`
- **`EXTERNAL-IP: <none>`** — the nodes are genuinely unreachable from the internet, which is the whole point of putting them in private subnets
- **`kubectl` worked at all** — this is the proof that `enable_cluster_creator_admin_permissions = true` did its job. Without it, this exact command returns `error: You must be logged in to the server (Unauthorized)` despite you being an AWS administrator (`learn/05`)

### 5. Endpoints — the object that shows a Service is actually wired up

```
kubectl get svc links-service
NAME            TYPE        CLUSTER-IP      PORT(S)
links-service   ClusterIP   172.20.10.137   8000/TCP

kubectl get endpoints links-service
NAME            ENDPOINTS
links-service   10.0.2.118:8000
```

A Service is a stable virtual IP; **Endpoints** is the list of pod IPs it currently forwards to. That second command is the diagnostic worth knowing.

If `ENDPOINTS` is empty, the Service is matching nothing — almost always a **selector/label mismatch**, or pods that exist but are not `Ready` (readiness probe failing). The Service itself will look perfectly healthy while routing to nowhere. Checking Endpoints tells you *which* of those two problems you have.

Note `172.20.10.137` is from the **cluster service CIDR**, a different address space from the pod IPs (`10.0.x.x`). Services and pods live on separate networks.

### 6. Service discovery by DNS name — what `gateway` will rely on

```bash
kubectl run dns-test --image=curlimages/curl --restart=Never --rm -i -- \
  curl -sS http://links-service:8000/health
```

```
{"status":"ok"}
```

That request used **no IP address and no service registry** — just the Service's name. CoreDNS resolves `links-service` to the ClusterIP, which load-balances to whichever pods currently match the selector.

This is the mechanism that made **Eureka unnecessary** (`PROGRESS.md` Decisions). It is also exactly what `S-01` (`gateway`) exists to demonstrate — now proven manually before writing the service that depends on it.

The `kubectl run --rm` pattern is worth keeping: a disposable pod, inside the cluster, deleted when the command exits. It is the cleanest way to test something that is only reachable internally.

### 7. Verify the fix, not the deploy

The deploy succeeding proves the *plumbing*. It does not prove the *application*. So the last check was a real CRUD round-trip:

```
-- POST /links --
{"id":1,"name":"Grafana","url":"https://grafana.local","category":"ops","icon":null}
-- GET /links --
[{"id":1,"name":"Grafana","url":"https://grafana.local","category":"ops","icon":null}]
-- GET /links/999 --
404
```

`GET /links` returning `"id":1` is the **`C-01` fix confirmed on real infrastructure**. That bug survived for weeks precisely because `POST` looked correct — the response was built from a different variable than the one being stored (`learn/09`). Reading back through a separate endpoint is the only check that catches it.

## Walkthrough — the session loop

The whole sequence, runnable from **one WSL shell** (`docker.exe` reaches Docker Desktop, `learn/02`):

```bash
cd infra && terraform apply                                        # ~15 min
aws eks update-kubeconfig --region ap-south-1 --name app-hub-eks    # mandatory
kubectl config current-context                                      # confirm NOT minikube
kubectl get nodes                                                   # expect 2 Ready
```

Meanwhile, in parallel — ECR exists early:

```bash
aws ecr get-login-password --region ap-south-1 \
  | docker.exe login --username AWS --password-stdin 314146298861.dkr.ecr.ap-south-1.amazonaws.com
docker.exe build -t 314146298861.dkr.ecr.ap-south-1.amazonaws.com/app-hub/links-service:v1 .
docker.exe push 314146298861.dkr.ecr.ap-south-1.amazonaws.com/app-hub/links-service:v1
```

Then deploy and verify:

```bash
kubectl apply -f manifests/links-service/
kubectl rollout status deployment/links-service
kubectl get endpoints links-service
kubectl run dns-test --image=curlimages/curl --restart=Never --rm -i -- curl -sS http://links-service:8000/health
```

This sequence is what `P-09` will encode as `make up` / `make deploy`.

## Gotchas

- **Billing starts at `apply`, not at first use.** The NAT gateway was live minutes in, while the cluster was still `CREATING`.
- **Buildkit pushes untagged digests alongside your tag.** `describe-images` showed two entries with no tag — attestation manifests. `batch-delete-image --image-ids imageTag=v1` will *not* remove them, so teardown needs the untagged digests too (`learn/15`).
- **`update-kubeconfig` writes to whichever environment runs it.** Run it on Windows and WSL's kubeconfig stays stale — and both will answer `current-context` confidently.
- **Empty `ENDPOINTS` means a selector or readiness problem**, not a Service problem. Check there before debugging networking.
- **`kubectl rollout status` blocks until ready or timeout.** Useful in scripts; give it `--timeout`.
- **One replica means no redundancy during a rollout.** Deliberate here (`C-03`), but there is a window with zero pods.

## Verify it yourself

Is a cluster running right now — i.e. am I being charged?

```bash
wsl -e bash -lc "aws eks list-clusters --region ap-south-1 --output text; aws ec2 describe-nat-gateways --filter Name=state,Values=available --region ap-south-1 --query 'NatGateways[*].NatGatewayId' --output text"
```

With the cluster up, confirm the whole chain in one go:

```bash
wsl -e bash -lc "kubectl config current-context && kubectl get nodes && kubectl get endpoints links-service && kubectl run t --image=curlimages/curl --restart=Never --rm -i --quiet -- curl -sS http://links-service:8000/health"
```

Prove the Service really is name-addressable and not a fluke — resolve it via DNS explicitly:

```bash
wsl -e bash -lc "kubectl run dnsq --image=busybox:1.36 --restart=Never --rm -i --quiet -- nslookup links-service.default.svc.cluster.local"
```

## Going deeper

- [EKS cluster endpoint access](https://docs.aws.amazon.com/eks/latest/userguide/cluster-endpoint.html)
- [Kubernetes Services and Endpoints](https://kubernetes.io/docs/concepts/services-networking/service/)
- [DNS for Services and Pods](https://kubernetes.io/docs/concepts/services-networking/dns-pod-service/) — the naming rules behind `links-service.default.svc.cluster.local`
- [`kubectl rollout`](https://kubernetes.io/docs/reference/kubectl/generated/kubectl_rollout/)

---

**Next:** the cluster is up and billing. Either continue to `S-01`/`C-04`, or tear down with the `learn/15` checklist. Do not leave it running by accident.
