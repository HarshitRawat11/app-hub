# app-hub

A self-hosted hub of small, independently deployed services running on AWS EKS — provisioned with Terraform, deployed from Git-tracked Kubernetes manifests.

The first service, **links-service**, is a FastAPI CRUD API over link records (`name`, `url`, `category`, `icon`) — the data behind an internal "which app lives where" dashboard. **gateway** is service #2: one front door, so internal services stop being publicly reachable. More will join them under the same infra.

> **Status:** Phase 2 complete. The full loop is proven on real EKS — provision, build, push, deploy, reach `/health` by Kubernetes DNS name, expose publicly, tear down cleanly. Nothing is deployed right now by design; the cluster is destroyed between sessions. See [PROGRESS.md](PROGRESS.md).

---

## About this project

app-hub is deliberately three things at once:

- **A learning platform** — the full production path: service → container → ECR → EKS → CI/CD → observability. The **infrastructure** half is hand-built deliberately; the application half is scaffolding for it. See [CLAUDE.md § 2](CLAUDE.md).
- **A real internal tool** — the link catalogue is meant to actually get used, not just to compile.
- **A portfolio piece** — it should be legible and deployable by someone who has never seen it before.

That combination sets the bar: working-on-my-machine isn't the finish line. Reproducible-from-a-clean-clone is.

**Stack:** Python 3.14 · FastAPI · uv · Docker · Terraform 1.15 · AWS (EKS, ECR, VPC, S3, DynamoDB) · Kubernetes 1.31 · n8n · Make

---

## Directory layout

`app-hub/` is an **umbrella git repository** tracking only the cross-cutting docs. The five component directories are independent repos with their own remotes, and are gitignored here so they stay that way.

```
app-hub/
├── CLAUDE.md          # Operating manual for Claude Code sessions — objective, constraints, read order
├── README.md          # This file
├── PROGRESS.md        # Live status board, blockers, known defects, progress log
├── TIMELINE.md        # GENERATED from git across all 6 repos -- never edit by hand
├── Makefile           # session automation: make status / up / deploy / down / test / validate
├── scripts/
│   ├── timeline.sh        # regenerates TIMELINE.md
│   ├── validate-manifests.py  # offline manifest checks
│   ├── check-doc-drift.py     # verifies CONTEXT-BRIEF's embedded source still matches
│   └── scheduled-destroy.sh   # unattended teardown, POSTs the result to n8n
│
├── learn/             # Learning record — one file per step performed, with the reasoning behind it
│   ├── README.md          # Index of learning files, in the order the steps were done
│   └── NN-*.md            # e.g. 00-project-setup-and-governance.md
│
├── infra/             # repo: HarshitRawat11/app-hub-infra    — AWS infrastructure (Terraform)
│   #                     TWO STACKS: this directory is EPHEMERAL (destroyed every
│   #                     session); infra/persistent/ is never destroyed. Separate
│   #                     state files -- terraform does not recurse into subdirs.
│   ├── providers.tf       # Terraform + AWS provider versions; S3 remote state backend
│   ├── vpc.tf             # VPC 10.0.0.0/16, 2 AZs, public + private subnets, single NAT gateway
│   ├── eks.tf             # EKS cluster "app-hub-eks" (k8s 1.31), 2x t3.medium managed node group
│   ├── ecr.tf             # ECR repos for links-service and gateway, IMMUTABLE, force_delete
│   ├── outputs.tf         # cluster name/endpoint, VPC id, private subnet ids
│   ├── variables.tf       # aws_region (default ap-south-1)
│   ├── persistent/        # SECOND STACK, never destroyed -- own state key.
│   │                      # The DynamoDB table (C-04). terraform does not
│   │                      # recurse, so `make down` cannot reach it.
│   └── .terraform/        # ~800 MB vendored providers + upstream modules. Gitignored. Never read this.
│
├── links-service/     # repo: HarshitRawat11/app-hub-links-service — the FastAPI service
│   ├── app/
│   │   ├── main.py        # FastAPI app: /health + CRUD on /links
│   │   └── models.py      # Pydantic models: Link, LinkCreate
│   ├── Dockerfile         # python:3.14-slim, uv, non-root appuser (uid 10001)
│   ├── pyproject.toml     # requires-python >=3.14; fastapi, uvicorn
│   ├── uv.lock            # pinned dependency lockfile
│   └── .python-version    # 3.14
│
├── gateway/           # repo: HarshitRawat11/app-hub-gateway — the entry-point service, port 8001
│   ├── app/
│   │   └── main.py        # /health + /links proxied to links-service, 502/503/504 mapping
│   ├── tests/
│   │   ├── test_gateway.py    # 15 tests, upstream faked with httpx.MockTransport
│   │   └── fake_upstream.py   # manual fixture: ok / 404 / html500 / slow
│   ├── Dockerfile         # as links-service, port 8001
│   ├── pyproject.toml     # requires-python >=3.14; fastapi, uvicorn, httpx
│   └── uv.lock            # pinned dependency lockfile
│
├── manifests/         # repo: HarshitRawat11/app-hub-manifests — Kubernetes manifests
│   ├── 00-namespace.yaml   # SHARED by every service, so it sits above them.
│   │                      # namespace app-hub, restricted Pod Security Standard
│   ├── links-service/
│   │   ├── deployment.yaml   # replicas: 1 (in-memory state), securityContext, limits
│   │   └── service.yaml      # LoadBalancer (NLB), port 80 -> targetPort 8000
│   └── gateway/
│       ├── deployment.yaml   # replicas: 2 (stateless), env: LINKS_SERVICE_URL
│       └── service.yaml      # ClusterIP -- see E-06
│
└── n8n/               # repo: HarshitRawat11/app-hub-n8n — workflow automation (self-hosted)
    ├── .env.example       # Template for N8N_BASE_URL / N8N_API_KEY
    ├── .env               # Real API key. GITIGNORED — never commit
    ├── workflows/         # One JSON file per workflow, pulled from the instance
    └── scripts/
        └── pull-workflows.sh  # Fetch all workflows from the n8n API
```

### AWS resources at a glance

| Resource       | Value |
|----------------|-------|
| Account        | `314146298861` |
| Region         | `ap-south-1` |
| EKS cluster    | `app-hub-eks` (Kubernetes 1.31) |
| Node group     | 2× `t3.medium` (min 1, max 2) |
| ECR repositories | `app-hub/links-service`, `app-hub/gateway` — IMMUTABLE tags |
| DynamoDB       | `app-hub-links`, on-demand — the **persistent** stack, never destroyed |
| TF state       | `s3://app-hub-tfstate-314146298861/` — keys `infra/terraform.tfstate` (ephemeral) and `persistent/terraform.tfstate`. S3 native locking. |

---

## Quick start

### The short version: use the Makefile

Everything below can be driven from **one WSL shell**:

```bash
wsl -e bash -lc "cd /mnt/c/Users/harshit.rawat/Documents/Projects/app-hub && make"
```

| Target | Does |
|---|---|
| `make status` | What is running right now, and what it costs |
| `make up` | `terraform apply`, then **refresh the kubeconfig**, then verify nodes |
| `make deploy` | For **every** service in `SERVICES`: build, push a git-SHA-tagged image, pin the manifest, apply, verify |
| `make down` | Drain Kubernetes, empty ECR, `terraform destroy`, audit for orphans |
| `make test` | Every service test suite — 29 tests, no cluster, no AWS |
| `make validate` | Offline checks: doc drift, manifests, both Terraform stacks |

`make down` exists because teardown has a **required order**: Kubernetes-created AWS resources (the load balancer, EBS volumes) must be deleted while the cluster is still alive, or they are orphaned permanently. See [learn/15](learn/15-safe-teardown.md).

The manual commands below are the same steps, spelled out.

### Prerequisites — mind the OS split

**All of it runs from WSL.** `terraform`, `uv`, `python3`, `jq` and `make` are WSL-native; Docker is reached as **`docker.exe`** through WSL interop. `kubectl` and `aws` exist on both sides but point at **different things** — Windows `kubectl` is minikube and Windows `aws` is your work account. Use WSL for anything touching app-hub. `gh` is not installed anywhere.

### 1. Run the service locally

From **WSL**:

```bash
cd /mnt/c/Users/harshit.rawat/Documents/Projects/app-hub/links-service && uv sync && uv run uvicorn app.main:app --reload --port 8000
```

Then check it (either OS):

```bash
curl http://localhost:8000/health
```

Interactive API docs: <http://localhost:8000/docs>

### 2. Build and run the container

From **WSL**:

```bash
docker.exe build -t links-service:dev ./links-service
```

```bash
docker.exe run --rm -p 8000:8000 links-service:dev
```

### 3. Plan infrastructure changes

From **WSL**. Read-only and safe:

```bash
wsl -e bash -lc "cd /mnt/c/Users/harshit.rawat/Documents/Projects/app-hub/infra && terraform init && terraform plan"
```

> **`terraform apply` costs real money** — roughly $150–200/month if left running 24×7 (EKS control plane + 2 nodes + NAT gateway; verify against current AWS pricing). Apply deliberately, and tear down when you are done for the day.

### 4. Push an image to ECR

From **WSL** (`docker.exe` bridges to Docker Desktop), after the ECR repo exists:

```bash
aws ecr get-login-password --region ap-south-1 | docker login --username AWS --password-stdin 314146298861.dkr.ecr.ap-south-1.amazonaws.com
```

```bash
docker build -t 314146298861.dkr.ecr.ap-south-1.amazonaws.com/app-hub/links-service:v1 ./links-service
```

```bash
docker push 314146298861.dkr.ecr.ap-south-1.amazonaws.com/app-hub/links-service:v1
```

### 5. Point kubectl at the cluster and deploy

From **WSL**:

```bash
aws eks update-kubeconfig --region ap-south-1 --name app-hub-eks
```

Always confirm which cluster you are about to hit — Windows `kubectl` is minikube; WSL `kubectl` is EKS. They are separate config files:

```bash
kubectl config current-context
```

The namespace has to go first — `kubectl apply -f <dir>` sorts by filename *within* a directory and guarantees nothing across directories:

```bash
kubectl apply -f manifests/00-namespace.yaml
```

```bash
kubectl apply -f manifests/links-service/ && kubectl apply -f manifests/gateway/
```

**Every `kubectl` command needs `-n app-hub`** from here on (`R-04` moved everything out of `default`). Omitting it returns `No resources found` — which reads like a failed deploy rather than a missing flag.

`links-service` is exposed publicly through an NLB (`E-05`), so it has a real hostname:

```bash
kubectl -n app-hub get svc links-service -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
```

`gateway` is `ClusterIP` by design until `E-06` — giving it a second load balancer would mean a second bill. Reach it for free:

```bash
kubectl -n app-hub port-forward svc/gateway 8001:8001
```

---

## Governance

### Working across six repos

The root is an umbrella repo that tracks only the cross-cutting docs, so no single commit captures a change spanning components. Rules:

- Run git with an explicit target: `git -C links-service status`. A bare `git` at the root works but **only sees the docs** — the risk is not that it fails, it is that it succeeds and reports the wrong repo.
- A change touching a service **and** its manifests is two commits in two repos. Land both, and say so.
- Keep each repo independently valid — someone cloning only `manifests/` should still find it coherent.

### Commit messages

Follow the existing history: imperative mood, one line, no trailing period, no type prefix.

```
Add ECR repository for links-service
Added AWS EKS cluster and its admin access
Add VPC module with public/private subnets, IGW, NAT gateway
```

### Definition of done

A task is done when all of these hold:

1. The code works and has been *actually run*, not just written.
2. It is committed to the right repo (and pushed, if the owner asked).
3. **If the step was hand-built, it is written up in [`learn/`](learn/README.md)** and added to that folder's index. Delegated work is exempt — a `PROGRESS.md` note carries it instead.
4. `PROGRESS.md` reflects the new reality — status moved, blocker cleared or restated, next step written, log line added.
5. Anything discovered but not fixed is recorded in `PROGRESS.md § Known Defects`, not left in chat history.

### Learning as a deliverable

This project is built to be understood, not just to ship — but the understanding is **targeted**. The owner is the Principal SRE who has to own EKS, Terraform, Prometheus/Grafana, Jenkins and ArgoCD at work, so those are hand-built: the concept is explained first, the owner writes it, then it is reviewed. Application code, Dockerfiles, tests and tooling are scaffolding for that and are written for them.

Every **hand-built** step gets explained in [`learn/`](learn/README.md) — what we did, why, the concepts underneath, and how to verify it yourself. Such a step is not finished without its learning file. Delegated work does not get one: `learn/` records what the owner actually learned, not an index of everything that happened. See [CLAUDE.md § 2](CLAUDE.md) for the full split.

### Infrastructure discipline

- `terraform plan` before every `apply`. Read the plan; do not skim it.
- Never commit `*.tfstate` or `*.tfvars`. `infra/.gitignore` already blocks them.
- State lives in S3 with native locking. Do not add a local backend, and do not disable locking.
- Tear down when idle. The cluster is not free.

### Secrets

The AWS account ID appears throughout this repo by the owner's choice. That is the extent of it — no keys, no kubeconfigs, no credentials in `*.tfvars`, ever.

The n8n API key lives in `n8n/.env`, which is gitignored. It is never pasted into a chat window, never printed to a terminal, and never passed to `curl -v`. Full rules in [n8n/README.md](n8n/README.md).

### Working with Claude Code

[CLAUDE.md](CLAUDE.md) is the operating manual for AI sessions in this workspace: objective, hard constraints, the WSL/Windows split, and the per-session read order. Keep it current — it is what stops sessions from drifting off the objective.
