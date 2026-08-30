# 07 — Kubernetes manifests: Deployment, Service, and DNS discovery

> **Backfilled.** Reconstructed from `manifests/links-service/deployment.yaml` and `service.yaml`, and git history (`a933c2a`).

## What we did

Wrote the two Kubernetes objects that turn the ECR image into a running, addressable service: a **Deployment** (run 2 copies, restart them when they fail) and a **Service** (give them one stable address).

These live in their own repository, `app-hub-manifests`, separate from the application code.

## Why

The image is in ECR and the cluster exists — but nothing connects them. Kubernetes needs to be told *what to run* and *how to reach it*. Those are two genuinely different problems, which is why they are two objects.

The separate repo is deliberate: it is what makes GitOps possible later (`R-06`). A CD tool like ArgoCD watches a manifests repository and reconciles the cluster to match it. Keeping manifests apart from application code means a deploy is a commit to the manifests repo, and the cluster's desired state is always exactly what is in git.

## Key concepts

### 1. Declarative, not imperative — the core idea

You do not tell Kubernetes "start a container". You tell it **"two of these should be running"**, and a controller works continuously to make reality match.

Kill a pod and a new one appears. A node dies and its pods are rescheduled elsewhere. You never wrote that logic — you declared a desired state and a control loop closes the gap.

**This is the single most important mental shift in Kubernetes.** Every object is a statement of desired state, and a controller is always running to enforce it.

### 2. Labels and selectors — how objects find each other

Kubernetes objects do not reference each other by name. They match on **labels** — arbitrary key/value pairs.

```yaml
spec:
  selector:
    matchLabels:
      app: links-service      # "I manage pods with this label"
  template:
    metadata:
      labels:
        app: links-service    # "...and pods I create carry it"
```

The Deployment's `selector` says which pods it owns; the `template.metadata.labels` puts that label on the pods it creates. **These two must match** — if they disagree, the Deployment creates pods it does not recognise and creates more, forever.

The Service uses the same mechanism independently:

```yaml
spec:
  selector:
    app: links-service
```

The Service has **no idea the Deployment exists**. It just routes to whatever pods currently carry `app: links-service`. That loose coupling is the point: replace the Deployment entirely and the Service keeps working, as long as the label holds.

### 3. Deployment → ReplicaSet → Pod

Three layers, and knowing which is which makes `kubectl get` output legible:

- **Pod** — one or more containers sharing a network namespace. The smallest deployable unit. **Ephemeral** — it gets a new IP each time, and it is never repaired, only replaced.
- **ReplicaSet** — keeps exactly N pods running.
- **Deployment** — manages ReplicaSets, and orchestrates rollouts by shifting pods from an old ReplicaSet to a new one.

You almost always create a Deployment. It creates the ReplicaSet, which creates the Pods. The extra layer is what makes rolling updates and rollbacks possible — the old ReplicaSet sticks around at zero replicas, ready to scale back up.

### 4. Liveness vs readiness — different questions

```yaml
livenessProbe:
  httpGet: { path: /health, port: 8000 }
  initialDelaySeconds: 5
  periodSeconds: 10
readinessProbe:
  httpGet: { path: /health, port: 8000 }
  initialDelaySeconds: 5
  periodSeconds: 10
```

Same endpoint here, but they answer different questions and have different consequences:

- **Liveness: "is this process broken?"** On failure, Kubernetes **kills and restarts** the container. For deadlocks and unrecoverable states.
- **Readiness: "can this pod serve traffic right now?"** On failure, Kubernetes **removes the pod from Service endpoints** but leaves it running. For warm-up, or a temporarily unavailable dependency.

Readiness is what makes zero-downtime rollouts work: a new pod receives no traffic until it reports ready.

`initialDelaySeconds: 5` gives the app five seconds to start before probing begins. **This value interacts directly with the Dockerfile defect from `learn/09`** — when `CMD` was `uv run`, the container spent startup time resolving and installing dependencies, so five seconds could easily be too short, producing a restart loop that looks like an application crash. Fixing the entrypoint made startup fast and the probe timing comfortable.

A common mistake worth avoiding: pointing a **liveness** probe at something that checks a database. If the database blips, Kubernetes restarts every pod — turning a dependency problem into an outage. `/health` here deliberately has no dependencies.

### 5. Service — a stable address over shifting pods

```yaml
spec:
  selector:
    app: links-service
  ports:
    - port: 8000
      targetPort: 8000
  type: ClusterIP
```

Pods get a new IP every time they are recreated. Nothing can rely on a pod IP.

A Service allocates a **stable virtual IP** that load-balances across whichever pods currently match its selector. Pods come and go behind it; the address does not change.

`port` is what the Service listens on; `targetPort` is the container port it forwards to. They are equal here, which is common and slightly obscures that they are independent.

**`type: ClusterIP` means internal-only.** Reachable from inside the cluster, not from the internet. This is why `E-05` exists — making it externally reachable needs an Ingress or a `LoadBalancer` Service.

### 6. DNS discovery — the point of `gateway`

Kubernetes runs CoreDNS and gives every Service a DNS name:

```
links-service                                  # same namespace
links-service.default                          # with namespace
links-service.default.svc.cluster.local        # fully qualified
```

So any pod in the cluster can call `http://links-service:8000/links` and reach a healthy pod. No service registry, no config, no hardcoded IPs.

**This is exactly what `gateway` (`S-01`) exists to prove**, and it is why Eureka was explicitly dropped from scope — Eureka solves service discovery for the Spring ecosystem, and Kubernetes already solves it natively for everything.

## Walkthrough

`deployment.yaml`, top to bottom:

```yaml
apiVersion: apps/v1        # which API group and version
kind: Deployment           # what kind of object
metadata:
  name: links-service      # its name in the cluster
  labels:
    app: links-service     # label on the Deployment itself (not the pods)
spec:
  replicas: 2              # desired pod count
  selector:
    matchLabels:
      app: links-service   # which pods this Deployment owns
  template:                # ---- the pod blueprint below ----
    metadata:
      labels:
        app: links-service # label applied to created pods; MUST match selector
    spec:
      containers:
        - name: links-service
          image: 314146298861.dkr.ecr.ap-south-1.amazonaws.com/app-hub/links-service:v1
          ports:
            - containerPort: 8000
```

Everything under `template:` describes a **pod**, not the Deployment. The nesting is the part people misread at first: `spec.replicas` is the Deployment's, `spec.template.spec.containers` is the pod's.

`containerPort: 8000` is documentation — like `EXPOSE`, it does not open anything. The container listens on 8000 because uvicorn was told to.

Applying both:

```bash
kubectl apply -f manifests/links-service/
```

`apply` is declarative: it creates what is missing and updates what differs. Running it twice is safe — the second run reports `unchanged`. That idempotency is what lets a GitOps controller run it continuously.

## Gotchas

- **`replicas: 2` is actively wrong for this service today.** `links_db` is an in-process dict, so the two pods hold independent data. A link created on pod A is invisible on pod B, and the Service load-balances between them at random. Tracked as `C-03` / `D-02` — the most consequential open item in the project.
- **No resource requests or limits.** Without `requests`, the scheduler cannot reason about capacity and pods are classed `BestEffort` — first to be evicted under node pressure (`R-01`).
- **No namespace.** These land in `default`. Fine for one service, messy as the hub grows (`R-04`).
- **The image tag is mutable `:v1`.** Two pods started at different times could be running different code (`R-03`).
- **Changing `selector` on an existing Deployment is rejected.** It is immutable — you must delete and recreate.
- **Always check `kubectl config current-context` first.** Default here is `minikube`, not EKS.
- **Delete `LoadBalancer` Services before `terraform destroy`.** They create AWS load balancers Terraform does not track, which can block VPC deletion.

## Verify it yourself

Confirm you are pointed at the right cluster — do this every time:

```bash
kubectl config current-context
```

Apply and watch the rollout:

```bash
kubectl apply -f manifests/links-service/ && kubectl rollout status deployment/links-service
```

See the three layers, and note each pod's ephemeral IP:

```bash
kubectl get deployment,replicaset,pods -l app=links-service -o wide
```

Check what the Service actually resolved to — these should be the pod IPs above:

```bash
kubectl get endpoints links-service
```

Reach it without exposing it publicly:

```bash
kubectl port-forward svc/links-service 8000:8000
```

```bash
curl -s localhost:8000/health
```

Prove DNS discovery works from inside the cluster — this is the mechanism `gateway` will rely on:

```bash
kubectl run tmp --rm -it --image=curlimages/curl --restart=Never -- curl -s http://links-service:8000/health
```

Watch the declarative loop close — delete a pod and see a replacement appear:

```bash
kubectl delete pod -l app=links-service --wait=false && kubectl get pods -l app=links-service -w
```

Demonstrate the split-state bug for yourself — POST through the Service a few times, then GET repeatedly. Results will vary depending on which pod answers.

## Going deeper

- [Kubernetes Deployments](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/)
- [Services](https://kubernetes.io/docs/concepts/services-networking/service/) — and the Service types beyond ClusterIP
- [DNS for Services and Pods](https://kubernetes.io/docs/concepts/services-networking/dns-pod-service/)
- [Liveness, readiness and startup probes](https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/)
- [Labels and selectors](https://kubernetes.io/docs/concepts/overview/working-with-objects/labels/)

---

**Next:** `learn/08` — n8n workflows as code. This is where the backfilled history ends and the Claude Code sessions begin.
