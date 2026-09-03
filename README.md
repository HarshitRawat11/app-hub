# app-hub

A self-hosted hub of small, independently deployed services running on AWS EKS — provisioned with Terraform, deployed from Git-tracked Kubernetes manifests.

The first service, **links-service**, is a FastAPI CRUD API over link records (`name`, `url`, `category`, `icon`) — the data behind an internal "which app lives where" dashboard. More services will join it under the same infra.

> **Status:** Phase 2 complete. The full loop is proven on real EKS — provision, build, push, deploy, reach `/health` by Kubernetes DNS name, expose publicly, tear down cleanly. Nothing is deployed right now by design; the cluster is destroyed between sessions. See [PROGRESS.md](PROGRESS.md).

---

## About this project

app-hub is deliberately three things at once:

- **A learning platform** — the full production path exercised by hand: service → container → ECR → EKS → CI/CD → observability.
- **A real internal tool** — the link catalogue is meant to actually get used, not just to compile.
- **A portfolio piece** — it should be legible and deployable by someone who has never seen it before.

That combination sets the bar: working-on-my-machine isn't the finish line. Reproducible-from-a-clean-clone is.

**Stack:** Python 3.14 · FastAPI · uv · Docker · Terraform 1.15 · AWS (EKS, ECR, VPC, S3) · Kubernetes 1.31

---

## Directory layout

`app-hub/` is an **umbrella git repository** tracking only the cross-cutting docs. The four component directories are independent repos with their own remotes, and are gitignored here so they stay that way.

```
app-hub/
├── CLAUDE.md          # Operating manual for Claude Code sessions — objective, constraints, read order
├── README.md          # This file
├── PROGRESS.md        # Live status board, blockers, known defects, progress log
├── TIMELINE.md        # GENERATED from git across all 5 repos -- never edit by hand
├── Makefile           # session automation: make status / up / deploy / down / validate
├── scripts/
│   ├── timeline.sh        # regenerates TIMELINE.md
│   └── validate-manifests.py  # offline manifest checks
│
├── learn/             # Learning record — one file per step performed, with the reasoning behind it
│   ├── README.md          # Index of learning files, in the order the steps were done
│   └── NN-*.md            # e.g. 00-project-setup-and-governance.md
│
├── infra/             # repo: HarshitRawat11/app-hub-infra    — AWS infrastructure (Terraform)
│   ├── providers.tf       # Terraform + AWS provider versions; S3 remote state backend
│   ├── vpc.tf             # VPC 10.0.0.0/16, 2 AZs, public + private subnets, single NAT gateway
│   ├── eks.tf             # EKS cluster "app-hub-eks" (k8s 1.31), 2x t3.medium managed node group
│   ├── ecr.tf             # ECR repo "app-hub/links-service", scan-on-push, force_delete
│   ├── outputs.tf         # cluster name/endpoint, VPC id, private subnet ids
│   ├── variables.tf       # aws_region (default ap-south-1)
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
├── manifests/         # repo: HarshitRawat11/app-hub-manifests — Kubernetes manifests
│   └── links-service/
│       ├── 00-namespace.yaml    # namespace app-hub, restricted Pod Security Standard
│       ├── deployment.yaml    # 1 replica, securityContext, resource limits, probes on /health:8000
│       └── service.yaml       # LoadBalancer (NLB), port 80 -> targetPort 8000
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
| ECR repository | `app-hub/links-service` |
| TF state       | `s3://app-hub-tfstate-314146298861/infra/terraform.tfstate` (S3 native locking) |

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
| `make deploy` | Build, push a git-SHA-tagged image, pin the manifest, apply, verify |
| `make down` | Drain Kubernetes, empty ECR, `terraform destroy`, audit for orphans |
| `make validate` | Offline manifest + Terraform checks — no cluster needed |

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

```bash
kubectl apply -f manifests/links-service/
```

The Service is `ClusterIP`, so nothing is reachable from outside the cluster yet. To poke at it:

```bash
kubectl port-forward svc/links-service 8000:8000
```

---

## Governance

### Working across three repos

There is no root repository, so there is no single commit that captures a cross-cutting change. Rules:

- Run git with an explicit target: `git -C links-service status`. Never a bare `git` at the root.
- A change touching a service **and** its manifests is two commits in two repos. Land both, and say so.
- Keep the three repos independently valid — someone cloning only `manifests/` should still find it coherent.

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
3. **The step is written up in [`learn/`](learn/README.md)** and added to that folder's index.
4. `PROGRESS.md` reflects the new reality — status moved, blocker cleared or restated, next step written, log line added.
5. Anything discovered but not fixed is recorded in `PROGRESS.md § Known Defects`, not left in chat history.

### Learning as a deliverable

This project is built to be understood, not just to ship. Every step gets explained in [`learn/`](learn/README.md) — what we did, why, the concepts underneath, and how to verify it yourself. That is a requirement of the work, not a nice-to-have: a step without its learning file is not finished. See [CLAUDE.md § 2](CLAUDE.md) for the full rule.

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
