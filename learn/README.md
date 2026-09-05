# learn/

The learning record for app-hub. One file per step performed, written so you can redo that step yourself without help.

## Why this exists

This project began as a manual, step-by-step learning exercise with Claude chat. Moving to Claude Code was a decision about **speed**, not about handing over the understanding. So every step taken here gets written up: what we did, why, the concepts underneath it, and how to verify it yourself.

If a file here leaves you unable to explain the step to someone else, it has failed — say so and it gets rewritten.

## How to read this folder

Files are numbered in the order the steps were performed, so reading top to bottom retraces the project. Each one is self-contained enough to read on its own, but later files assume the concepts from earlier ones.

Every file follows the same shape:

| Section | What it gives you |
|---|---|
| **What we did** | The change, in plain terms |
| **Why** | The problem it solves; what breaks without it |
| **Key concepts** | The 2–5 ideas you need to understand it |
| **Walkthrough** | The real code and commands, explained piece by piece |
| **Gotchas** | What bit us, what would bite you next time |
| **Verify it yourself** | Commands to prove it actually works |
| **Going deeper** | Where to read more, if curious |

## Index

| # | File | Covers |
|---|------|--------|
| 00 | [00-project-setup-and-governance.md](00-project-setup-and-governance.md) | Orientation: why the project needs CLAUDE.md / README.md / PROGRESS.md, and how the polyrepo layout and WSL/Windows split shape everything else |
| 01 | [01-fastapi-service-basics.md](01-fastapi-service-basics.md) | `uv` and lockfiles; the request/response model split (`Link` vs `LinkCreate`); Pydantic validation at the boundary; CRUD handlers and `HTTPException` |
| 02 | [02-containerising-with-docker-and-uv.md](02-containerising-with-docker-and-uv.md) | Layer caching and instruction order; `COPY --from`; why the base image must satisfy `requires-python`; build-time vs container-start work; `0.0.0.0` as a bind address |
| 03 | [03-terraform-and-remote-state.md](03-terraform-and-remote-state.md) | What Terraform state is and why losing it is worse than losing code; the S3 backend and `use_lockfile`; version pinning; variables and outputs |
| 04 | [04-vpc-networking.md](04-vpc-networking.md) | CIDR sizing; public vs private subnets as a routing distinction; IGW vs NAT gateway (and which one costs money); the EKS subnet tags that are functional, not decorative |
| 05 | [05-eks-cluster-and-node-groups.md](05-eks-cluster-and-node-groups.md) | Control plane vs data plane; managed node groups; **the IAM-vs-RBAC trap** that `enable_cluster_creator_admin_permissions` solves; why kubeconfig goes stale on every rebuild |
| 06 | [06-ecr-container-registry.md](06-ecr-container-registry.md) | Registry/repository/image/tag; mutable vs immutable tags; **`force_delete` and why teardown fails without it**; token auth and why nodes need none |
| 07 | [07-kubernetes-deployment-and-service.md](07-kubernetes-deployment-and-service.md) | Declarative state and control loops; labels and selectors; Deployment→ReplicaSet→Pod; liveness vs readiness; ClusterIP and DNS-based service discovery |
| 08 | [08-n8n-workflows-as-code.md](08-n8n-workflows-as-code.md) | Version-controlling GUI-built workflows; how n8n separates workflows from credentials; using an API key without ever seeing it; the CRLF/`bad interpreter` trap |
| 09 | [09-first-defect-fixes.md](09-first-defect-fixes.md) | A write bug hiding behind a correct response; why `uv` papers over a wrong base image; build-time vs container-start work; per-repo git identity |
| 10 | [10-versioning-docs-in-a-polyrepo.md](10-versioning-docs-in-a-polyrepo.md) | Monorepo vs polyrepo; a repo that gitignores other repos; why not submodules; remote vs branch vs upstream; scanning for secrets before the first push |
| 11 | [11-aws-credentials-and-the-two-kubeconfigs.md](11-aws-credentials-and-the-two-kubeconfigs.md) | Why WSL and Windows never share `~/.aws` or `~/.kube`; credential resolution order; `sts get-caller-identity` as ground truth; the silent wrong-context trap |
| 12 | [12-reading-a-terraform-plan.md](12-reading-a-terraform-plan.md) | What a plan compares; the four symbols and why `-/+` matters; `(known after apply)`; what the 55 resources are; which three actually bill |
| 13 | [13-persistence-and-the-ephemeral-persistent-split.md](13-persistence-and-the-ephemeral-persistent-split.md) | Why a nightly-destroyed cluster cannot hold data; splitting Terraform into ephemeral and persistent stacks; DynamoDB vs RDS; IRSA; the repository pattern |
| 14 | [14-testing-fastapi-with-pytest.md](14-testing-fastapi-with-pytest.md) | **Guide, not a record** — `TestClient`; the module-level shared-state trap; fixtures and `autouse`; why tests come before the storage refactor |
| 15 | [15-safe-teardown.md](15-safe-teardown.md) | **Why `terraform destroy` cannot do this alone** — two control planes both writing to AWS, and why cleanup must happen while the cluster is still alive; ECR images, LoadBalancer ENIs, orphaned EBS volumes; the drain-then-destroy order; the verify step that catches silent billing |
| 16 | [16-first-end-to-end-deploy.md](16-first-end-to-end-deploy.md) | The apply dependency order and when billing starts; parallelising the ECR push with cluster creation; `update-kubeconfig`; Endpoints as the "is this Service wired up" check; DNS discovery proven in-cluster |
| 17 | [17-timestamps-and-the-tz-trap.md](17-timestamps-and-the-tz-trap.md) | Derive timestamps, do not type them; `%at` as an absolute instant; **Git Bash silently ignores `TZ`**; why a self-check that refuses to run beats a silent fallback |
| 18 | [18-exposing-a-service-externally.md](18-exposing-a-service-externally.md) | ClusterIP → NodePort → LoadBalancer as a ladder; NLB vs ALB vs Classic; `port` vs `targetPort`; the provisioning gap between a hostname and a working endpoint; why one-LB-per-service does not scale; ephemeral state proven by deleting the pod |
| 19 | [19-hardening-and-automating-the-loop.md](19-hardening-and-automating-the-loop.md) | Namespaces and why the file is `00-` prefixed; requests vs limits and the QoS class you get; non-root containers and pod- vs container-level `securityContext`; testing `readOnlyRootFilesystem` before trusting it; immutable tags forcing SHA-based versioning; Make as a task runner |
| 20 | [20-testing-a-workflow-and-a-silently-dead-monitor.md](20-testing-a-workflow-and-a-silently-dead-monitor.md) | Why a webhook 200 is not a success; using `runData` to prove which branch ran; the `$json.body` nesting; OAuth's three tokens and which one expires; **why a monitor fails invisibly — silence and death look identical** |

| 21 | [21-gateway-service-to-service-calls.md](21-gateway-service-to-service-calls.md) | **Guide, not a record** — a service that is also a client; `async def` + a blocking library as the worst available mistake; why the HTTP client outlives the request; the `LINKS_SERVICE_URL` config boundary; timeouts and 502/503/504; why `/health` must not check the upstream |

*Steps 22 onward get added as we do them.*

## A note on files 01–07

These steps were performed by hand, with Claude chat, before this folder existed. They were written up afterwards (task `P-07`) from the **committed code and git history** — so they explain what the code does and why it is that way, rather than narrating the original sessions. Where the current code differs from what was originally written, the file says so and points at the file that changed it.

Files 00, 08 and 09 were written as their steps happened.
