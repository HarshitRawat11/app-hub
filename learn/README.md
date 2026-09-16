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
| 17 | [17-timestamps-and-the-tz-trap.md](17-timestamps-and-the-tz-trap.md) | Derive timestamps, do not type them; `%at` as an absolute instant; **Git Bash silently ignores `TZ`**; why a self-check that refuses to run beats a silent fallback. **Postscript 2026-09-16:** wall clock vs **monotonic** — measure durations with one, report instants with the other; why publishing a monotonic reading as `checked_at` breaks across pods and runs backwards on restart |
| 18 | [18-exposing-a-service-externally.md](18-exposing-a-service-externally.md) | ClusterIP → NodePort → LoadBalancer as a ladder; NLB vs ALB vs Classic; `port` vs `targetPort`; the provisioning gap between a hostname and a working endpoint; why one-LB-per-service does not scale; ephemeral state proven by deleting the pod |
| 19 | [19-hardening-and-automating-the-loop.md](19-hardening-and-automating-the-loop.md) | Namespaces and why the file is `00-` prefixed; requests vs limits and the QoS class you get; non-root containers and pod- vs container-level `securityContext`; testing `readOnlyRootFilesystem` before trusting it; immutable tags forcing SHA-based versioning; Make as a task runner |
| 20 | [20-testing-a-workflow-and-a-silently-dead-monitor.md](20-testing-a-workflow-and-a-silently-dead-monitor.md) | Why a webhook 200 is not a success; using `runData` to prove which branch ran; the `$json.body` nesting; OAuth's three tokens and which one expires; **why a monitor fails invisibly — silence and death look identical**. **Postscript 2026-09-16:** the same monitor's *third* death — expired token, wrong timezone, then **host sleep** — why `active` never means "has run", the cheap-half question that made an expensive test unnecessary, and why a cost watchdog on a sleeping laptop is a design flaw rather than a bug |

| 21 | [21-gateway-service-to-service-calls.md](21-gateway-service-to-service-calls.md) | A service that is also a client; `async def` + a blocking library as the worst available mistake; why the HTTP client outlives the request; the `LINKS_SERVICE_URL` config boundary; timeouts and 502/503/504; why `/health` must not check the upstream |
| 22 | [22-gateway-config-and-container.md](22-gateway-config-and-container.md) | **Short note — delegated work** — why the default matters as much as the env var; reading config once at module scope; `str(e)` as an information leak; **`localhost` inside a container is the container**; proving service-to-service by DNS name on a Docker network before paying for EKS; `.dockerignore` is about the build context, not the image |

| 23 | [23-testing-the-links-api.md](23-testing-the-links-api.md) | **Short note — delegated work** — the 14-test coverage list; `TestClient` over ASGI rather than a real port; the module-level shared-state trap and why its failures are order-dependent; why a test asserting only on the `POST` response would have missed `D-01` entirely; `pythonpath` in `pyproject.toml` and the `ModuleNotFoundError` that looks like a broken install |

| 24 | [24-testing-a-proxy-and-preparing-the-deploy.md](24-testing-a-proxy-and-preparing-the-deploy.md) | **Short note — delegated work** — `httpx.MockTransport` for testing a proxy with no upstream running; why the `504` test also proves the `except` ordering; testing a design decision (`/health` must not check the upstream); `replicas: 2` vs `1` as a question of state rather than importance; why gateway's Service is `ClusterIP` despite being the front door; **`kubectl apply -f` sorts within a directory and not across directories** |

| 25 | [25-documentation-that-rots.md](25-documentation-that-rots.md) | **Short note — delegated work** — the five times docs in this project drifted silently and optimistically; **check mechanical duplication mechanically, delete rotting prose facts rather than testing them**; `scripts/check-doc-drift.py` with `--fix`; why `:v1` was worse than `:PLACEHOLDER`; **a validation tool is only worth what it is wired into** |

| 26 | [26-the-repository-layer.md](26-the-repository-layer.md) | **Short note — delegated work** — a `Protocol` rather than an ABC; why UUID ids were the load-bearing change and how `C-04`'s type `S` paid off; `ReturnValues=ALL_OLD` and the delete that cannot tell you what it deleted; contract tests that run against both backends; **a 573-second suite is a defect** — profiling named fixture scope, not moto |

| 27 | [27-the-dashboard-and-the-full-proxy.md](27-the-dashboard-and-the-full-proxy.md) | **Short note — delegated work** — why the dashboard is served BY gateway rather than being a fourth service; the `passthrough` rule, and why a 404 from `GET /links/{id}` is the caller's answer while a 404 from `GET /links` is a fault; why gateway must not restate links-service's schema; `textContent` and scheme-checked `href` as two halves of one guard; **every test passed and the page was visibly wrong** — `[hidden]` loses to any author `display` rule |
| 28 | [28-the-aggregator-and-fetching-urls-you-do-not-control.md](28-the-aggregator-and-fetching-urls-you-do-not-control.md) | **Short note — delegated work** — why `aggregator` proves discovery where `gateway` cannot; a down link is DATA while a down upstream is an ERROR; why 401 counts as up; **SSRF on URLs you did not choose, and why "block private address space" is the WRONG mitigation here**; a test that failed for a reason unrelated to what it measured |
| 29 | [29-irsa-an-aws-identity-for-a-pod.md](29-irsa-an-aws-identity-for-a-pod.md) | **Full file, though Claude wrote it** (escape hatch, `CLAUDE.md` § 2) — IRSA end to end: projected tokens, `AssumeRoleWithWebIdentity`, **trust policy vs permission policy**, and why a missing `sub` condition silently opens the role to the whole cluster; the two different OIDC module outputs; crossing a stack boundary with a data source; `D-18` and the pod that is healthy by every probe and broken for every request |
| 30 | [30-prometheus-grafana-and-the-operator-pattern.md](30-prometheus-grafana-and-the-operator-pattern.md) | **Full file — guided build** — `kube-prometheus-stack` is six components; **the operator pattern** and why you never write `prometheus.yml`; CRDs as new API nouns; node-exporter vs kube-state-metrics; why a PVC was the wrong first choice (no EBS CSI driver by default); **label cardinality and the UUID that must never become a label**; a ServiceMonitor that matches nothing says nothing; two reload delays, not one; Grafana OOMKilled at 256Mi and why the browser blamed a plugin |

*Steps 31 onward get added as we do them.*

## Two tiers, from 2026-09-09

`CLAUDE.md § 2` splits the work: infrastructure the owner is learning is hand-built, application scaffolding is delegated. The `learn/` folder follows that split in **depth, not coverage** — every step still gets a file, so this folder reads continuously top to bottom.

- **Full files** (seven sections) for hand-built work — Terraform, PromQL, Helm, ArgoCD, Jenkins, n8n, a new Kubernetes object type, and any infra failure that was debugged.
- **Short notes** (three sections, under a page) for delegated work — what it does, why it is that way, and the one thing that would bite a reader. Marked in the title.

Files 14 and 21 were written as *"guide, not a record"* before this split, intending the owner to implement them; both subjects are now delegated. **Their content stands as reference — they are not pending assignments.**

## A note on files 01–07

These steps were performed by hand, with Claude chat, before this folder existed. They were written up afterwards (task `P-07`) from the **committed code and git history** — so they explain what the code does and why it is that way, rather than narrating the original sessions. Where the current code differs from what was originally written, the file says so and points at the file that changed it.

Files 00, 08 and 09 were written as their steps happened.
