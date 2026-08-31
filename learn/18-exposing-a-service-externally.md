# 18 — Exposing a service to the internet, and proving the data is ephemeral

## What we did

Switched `links-service` from `ClusterIP` to `type: LoadBalancer`, annotated for a Network Load Balancer, listening on port 80. AWS provisioned an internet-facing NLB and the API became reachable from the public internet — no `kubectl`, no port-forward.

Then deleted the pod and watched every stored link vanish, which is `C-03` demonstrated rather than argued.

## Why

Until now the Service was `ClusterIP` — a stable virtual IP reachable only from *inside* the cluster (`learn/07`). Fine for proving the deployment works, useless for an app you actually want to use. app-hub is meant to be a daily-use hub, so at some point it has to be reachable from a browser.

`E-05` was the last item in Phase 2, and the last thing gated on `E-02`.

## Key concepts

### 1. The Service types are a ladder, not alternatives

| Type | Reachable from | Mechanism |
|---|---|---|
| `ClusterIP` | inside the cluster only | virtual IP + kube-proxy |
| `NodePort` | any node's IP on a high port | opens the same port on every node |
| `LoadBalancer` | the internet | provisions a **real cloud load balancer** |

Each builds on the one below. A `LoadBalancer` Service *is* a NodePort Service with a cloud load balancer pointed at it — which is why the output still shows a node port:

```
PORT(S)        80:30569/TCP
```

`80` is what the load balancer listens on; `30569` is the NodePort it forwards to on each node. You did not ask for that port and will never use it directly, but seeing it explains what is underneath.

**The mental model: `LoadBalancer` is not a Kubernetes feature so much as a request to your cloud provider.** Kubernetes tells AWS "make me a load balancer pointing at these nodes on port 30569," and AWS obliges. On a cluster with no cloud integration, `type: LoadBalancer` stays `<pending>` forever — nothing exists to satisfy the request.

### 2. NLB vs ALB vs Classic — pick deliberately

```yaml
annotations:
  service.beta.kubernetes.io/aws-load-balancer-type: "nlb"
```

Without that annotation you get a **Classic Load Balancer** — AWS's oldest, effectively deprecated. The annotation is one line and worth always writing.

| | Layer | Good at |
|---|---|---|
| **NLB** | 4 (TCP) | Raw speed, static IPs, preserves client source IP, cheap |
| **ALB** | 7 (HTTP) | Path/host routing, TLS termination, one LB for many services |
| **CLB** | mixed | Nothing — legacy |

We took NLB because there is one service and no routing decisions to make. An ALB's advantage is *routing between multiple backends*, which does not exist yet.

### 3. `port` vs `targetPort` — and why 80 matters

```yaml
ports:
  - port: 80          # the load balancer listens here
    targetPort: 8000  # the container listens here
```

They are independent. Previously both were `8000`, which worked but meant every URL needed `:8000`. Setting `port: 80` means the browser's default HTTP port just works — `http://<host>/health` rather than `http://<host>:8000/health`.

The container is untouched; uvicorn still binds 8000. The Service does the translation.

### 4. The provisioning gap — a hostname is not a working endpoint

The hostname appeared in `kubectl get svc` after about **5 seconds**. The first successful request came about **110 seconds** later.

```
=== NLB state ===
a79280cd18615491e88aa093ea8dd157   network   provisioning   internet-facing
...
responded after ~110s: {"status":"ok"}
```

Kubernetes records the DNS name as soon as AWS *allocates* it. AWS then spends a couple of minutes actually building the thing, registering targets, and passing health checks. During that window the name resolves and the connection times out or refuses.

**This gap catches people constantly** — the Service looks ready, so the failure gets blamed on the app. Check the load balancer's own state:

```bash
aws elbv2 describe-load-balancers --region ap-south-1 --query "LoadBalancers[*].[LoadBalancerName,State.Code]" --output text
```

`provisioning` → wait. `active` → now it is your problem.

### 5. One LoadBalancer per Service does not scale

This is the part worth understanding before it becomes expensive.

**Every `type: LoadBalancer` Service provisions its own ELB.** Three services means three load balancers, three hostnames, three bills — at roughly $16–20/month each before traffic.

The alternative is an **Ingress**: a single ALB shared across many services, routing by path or hostname (`/links` → links-service, `/gateway` → gateway). One load balancer, one bill, one DNS name.

So why not do that now? Because **an Ingress with one backend is just a more complicated LoadBalancer**. Its whole value is routing *between* services, and there is currently one. Installing the AWS Load Balancer Controller to route to a single backend adds a Helm release, IAM permissions, and a controller to debug — for no benefit yet.

**Right-sized now, wrong later.** Tracked as `E-06`, to be done when `gateway` (`S-01`) gives it something to route between.

### 6. The data is ephemeral, and now you have seen it

With the service publicly reachable, the point could be demonstrated instead of asserted:

```
=== before ===
[{"id":1,"name":"Grafana",...},{"id":2,"name":"Notion",...}]
links-service-548d4455fd-5chkn   1/1   Running   16m

=== delete the pod ===
pod "links-service-548d4455fd-5chkn" deleted
deployment "links-service" successfully rolled out

=== after ===
links-service-548d4455fd-jppz5   1/1   Running   13s
links now: []
```

Everything gone. Not a bug — the deliberate consequence of `links_db` being a Python dict in a process (`learn/01`), and exactly what `C-04`–`C-06` exist to fix.

Two things worth noticing. The data survived earlier requests because it was **the same pod** — the id counter reaching `2` proved that. And the pod name changed (`5chkn` → `jppz5`), because Kubernetes does not repair pods, it **replaces** them (`learn/07`).

## Walkthrough

The whole change is the Service manifest:

```yaml
metadata:
  annotations:
    service.beta.kubernetes.io/aws-load-balancer-type: "nlb"
spec:
  ports:
    - port: 80
      targetPort: 8000
  type: LoadBalancer
```

Apply, then wait for AWS rather than for Kubernetes:

```bash
kubectl apply -f manifests/links-service/service.yaml
kubectl get svc links-service -w        # hostname appears in seconds
```

Then poll the endpoint until it actually answers — the hostname existing is not the finish line.

## Gotchas

- **⚠️ This creates AWS resources Terraform does not track.** The NLB and its ENIs are made by Kubernetes. **`kubectl delete svc links-service` BEFORE `terraform destroy`**, or the leftover ENIs block VPC deletion and the destroy fails partway — leaving the NAT gateway billing while you debug (`learn/15`).
- **The load balancer costs money independently of the cluster** — roughly $16–20/month if left running.
- **A hostname is not a ready endpoint.** Expect 1–3 minutes of `provisioning`.
- **No annotation means a Classic Load Balancer.** Always set the type explicitly.
- **This endpoint is public and unauthenticated.** Anyone with the URL can POST to your API. Acceptable for a short-lived learning cluster; not acceptable for anything that persists. Worth remembering when `C-04` makes the data durable.
- **`<pending>` forever means no cloud controller.** On minikube, `type: LoadBalancer` never resolves without `minikube tunnel`.

## Verify it yourself

Get the public hostname:

```bash
wsl -e bash -lc "kubectl get svc links-service -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'; echo"
```

Check whether AWS considers it ready:

```bash
wsl -e bash -lc "aws elbv2 describe-load-balancers --region ap-south-1 --query 'LoadBalancers[*].[LoadBalancerName,Type,State.Code]' --output text"
```

Hit it from anywhere — no cluster access needed:

```bash
curl -sS "http://$(wsl -e bash -lc 'kubectl get svc links-service -o jsonpath="{.status.loadBalancer.ingress[0].hostname}"')/health"
```

Prove the ephemerality for yourself — POST a link, delete the pod, GET again:

```bash
wsl -e bash -lc 'H=$(kubectl get svc links-service -o jsonpath="{.status.loadBalancer.ingress[0].hostname}"); curl -sS -X POST "http://$H/links" -H "Content-Type: application/json" -d "{\"name\":\"t\",\"url\":\"http://t\",\"category\":\"t\"}"; kubectl delete pod -l app=links-service; sleep 20; curl -sS "http://$H/links"'
```

## Going deeper

- [Kubernetes Service types](https://kubernetes.io/docs/concepts/services-networking/service/#publishing-services-service-types)
- [AWS Load Balancer Controller annotations](https://kubernetes-sigs.github.io/aws-load-balancer-controller/latest/guide/service/annotations/)
- [NLB vs ALB](https://docs.aws.amazon.com/elasticloadbalancing/latest/userguide/load-balancer-types.html)
- [Ingress](https://kubernetes.io/docs/concepts/services-networking/ingress/) — what `E-06` will use

---

**Teardown reminder:** there is now a live NLB. Delete the Service before destroying, and confirm no ENIs remain. `learn/15` has the full checklist.
