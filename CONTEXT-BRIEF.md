# app-hub — context brief

**Purpose:** paste this into a fresh Claude chat before asking about the project. Chat has no filesystem access, so everything it needs is reproduced here, including the source of the short files.

**Snapshot: 2026-08-31 · 17:40 IST.** A point-in-time copy. Inside the repo, `CLAUDE.md`, `PROGRESS.md` and `TIMELINE.md` are authoritative; if they disagree with this file, they win.

---

## 1. How I want you to help

**Teach, don't just answer.** I built this manually with Claude chat to learn it. Moving day-to-day work into Claude Code was about **speed, not outsourcing the understanding**.

- Explain the reasoning, not just the answer — what the alternatives were and why they lose.
- Name the mental model, not just the syntax.
- Say which parts are load-bearing and which are boilerplate.
- Tell me what breaks it, what the error looks like, and how to distinguish it from a similar failure.
- Assume I'm technically capable but new to the specific tool. Expand acronyms on first use.
- **Do not build ahead.** The first implementation of any new concept is mine to write by hand. Explaining a mechanism before I implement it is helpful; handing me a finished artifact is not.
- Hinglish is welcome for conceptual explanation. **End responses with a short summary in Indian English.**

I keep a `learn/` folder — one Markdown file per step, structured as: What we did / Why / Key concepts / Walkthrough / Gotchas / Verify it yourself / Going deeper. There are 18 files in it. Format keepable explanations that way.

---

## 2. What the project is

**app-hub is my permanent home for every app I build for my own daily use** — self-hosted on AWS EKS, provisioned by Terraform, deployed from Git-tracked Kubernetes manifests.

Three purposes at once, all real:

1. **Learning vehicle** — specifically the toolset my org is migrating toward: EKS, Terraform, Grafana/Prometheus. That's why the stack is what it is; "just use something simpler" is usually the wrong suggestion.
2. **Real daily-use software** — it has to actually work.
3. **Portfolio piece** — legible and deployable by a stranger.

Of the three, **learning dominates**. When speed and understanding conflict, understanding wins.

**Stack:** Python 3.14 · FastAPI · uv · Docker · Terraform 1.15 · AWS (EKS 1.31, ECR, VPC, S3) · n8n · Make

**Deliberately excluded:** Eureka (Kubernetes DNS does service discovery natively), Ansible (nothing runs on bare EC2), Spring Boot (a fourth simultaneous unknown).

---

## 3. Structure — FIVE git repos

The root is an **umbrella repo** tracking only cross-cutting docs; it gitignores the four component directories so they stay independent.

| Directory | Remote | Tracks |
|---|---|---|
| `.` (root) | `HarshitRawat11/app-hub` | `CLAUDE.md`, `README.md`, `PROGRESS.md`, `TIMELINE.md`, this file, `learn/`, `scripts/`, `Makefile` |
| `infra/` | `HarshitRawat11/app-hub-infra` | Terraform |
| `links-service/` | `HarshitRawat11/app-hub-links-service` | FastAPI service |
| `manifests/` | `HarshitRawat11/app-hub-manifests` | Kubernetes manifests |
| `n8n/` | `HarshitRawat11/app-hub-n8n` | Workflow JSON |

A bare `git` at the root works but **only sees the docs**. Use `-C <subdir>` for component work. Git identity is set **per-repo, never globally** — this is a work-managed laptop.

---

## 4. Environment — the WSL/Windows split

| Tool | Where |
|---|---|
| `terraform`, `uv`, `python3`, `jq`, `make` | **WSL only** |
| `docker` | Windows Docker Desktop — **but callable from WSL as `docker.exe`** via interop |
| `kubectl` | **Both**, and they are different tools: Windows → minikube, WSL → EKS |
| `aws` | **Both**, different accounts: Windows = work profiles (broken on purpose), WSL = app-hub |
| `gh` | **Not installed anywhere** — GitHub repo creation via web UI |

**Windows and WSL have separate `~/.aws/` and `~/.kube/config` files.** Configuring one does nothing for the other. Run all EKS-facing commands from WSL. Both sides answer `kubectl config current-context` confidently, which is the trap.

**Everything runs from one WSL shell** — that's what the Makefile assumes.

---

## 5. Current state

**Phase 2 is COMPLETE and everything is torn down.** The full loop was proven on real EKS on 2026-08-31: `terraform apply` (55 resources) → build → push to ECR → deploy → reach `/health` by Kubernetes DNS name → expose publicly via NLB → verify CRUD from the internet → `terraform destroy` (55 destroyed, no orphans).

**Nothing is deployed right now, and that is the correct resting state** — the cluster is destroyed between sessions because the NAT gateway bills continuously.

### AWS facts

| | |
|---|---|
| Account / region | `314146298861` / `ap-south-1` |
| EKS cluster | `app-hub-eks`, Kubernetes 1.31, 2× `t3.medium` in private subnets |
| ECR | `app-hub/links-service`, **IMMUTABLE tags**, scan-on-push, `force_delete` |
| TF state | `s3://app-hub-tfstate-314146298861/infra/terraform.tfstate`, S3 native locking |
| VPC | `10.0.0.0/16`, 2 AZs, public + private subnets, single NAT gateway |
| IAM | `terraform-learning` (admin, used by Terraform), `n8n-readonly` (`eks:DescribeCluster` only) |

Cost if left up 24×7: roughly **$150–200/month**. About $0.30/hour while running.

### links-service — full source

`app/models.py`:

```python
from pydantic import BaseModel

class Link(BaseModel):
    id: int
    name: str
    url: str
    category: str
    icon: str | None = None

class LinkCreate(BaseModel):   # no id -- the server assigns it
    name: str
    url: str
    category: str
    icon: str | None = None
```

`app/main.py` — **the id bug is FIXED**:

```python
from fastapi import FastAPI, HTTPException
from app.models import Link, LinkCreate

app = FastAPI()
links_db: dict[int, Link] = {}
next_id = 1

@app.get("/health")
def health():
    return {"status": "ok"}

@app.get("/links")
def getLinks():
    l = []
    for i in links_db.values():
        l.append(i)
    return l

@app.get("/links/{id}")
def getLink(id: int):
    if id not in links_db:
        raise HTTPException(status_code=404, detail="Link not found")
    return links_db[id]

@app.post("/links")
def createLink(link: LinkCreate):
    global next_id
    new_link = Link(id=next_id, **link.model_dump())
    links_db[next_id] = new_link       # fixed: was storing `link`, so reads lost the id
    next_id += 1
    return new_link

@app.delete("/links/{id}")
def removeLink(id: int):
    if id not in links_db:
        raise HTTPException(status_code=404, detail="Link not found")
    del links_db[id]
    return {"deleted": id}
```

`Dockerfile` — committed, Python 3.14, non-root, no `uv run` at CMD:

```dockerfile
FROM python:3.14-slim
COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /bin/
WORKDIR /app
COPY pyproject.toml uv.lock ./
RUN uv sync --frozen --no-install-project
COPY app/ ./app/
ENV PATH="/app/.venv/bin:$PATH"
ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1
RUN groupadd --system --gid 10001 appuser \
 && useradd --system --uid 10001 --gid appuser --no-create-home appuser \
 && chown -R appuser:appuser /app
USER appuser
EXPOSE 8000
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
```

`pyproject.toml` requires `python >=3.14`; dev deps `pytest` + `httpx` are installed but **no tests are written yet**.

### manifests

Three files in `manifests/links-service/`, applied in filename order:

- `00-namespace.yaml` — namespace `app-hub`, enforcing the **restricted** Pod Security Standard
- `deployment.yaml` — `replicas: 1` (deliberate — in-memory state), securityContext (`runAsNonRoot`, uid 10001, `readOnlyRootFilesystem`, all capabilities dropped, RuntimeDefault seccomp), resources (requests 50m/64Mi, limits 500m/256Mi → **Burstable** QoS), liveness + readiness on `/health:8000`
- `service.yaml` — `type: LoadBalancer` with the NLB annotation, port 80 → targetPort 8000

### infra

`providers.tf` (S3 backend, `use_lockfile = true`), `vpc.tf`, `eks.tf`, `ecr.tf`, `outputs.tf`, `variables.tf`. Uses community modules `terraform-aws-modules/vpc/aws ~> 5.0` and `.../eks/aws ~> 20.0`. `enable_cluster_creator_admin_permissions = true` is **required** — without it the creating IAM user gets `Unauthorized` from `kubectl`.

### Tooling at the root

- `Makefile` — `make status | up | deploy | down | validate`. Run from WSL. `down` encodes the teardown order.
- `scripts/timeline.sh` — generates `TIMELINE.md` from git across all five repos.
- `scripts/validate-manifests.py` — offline manifest checks.

### n8n

Self-hosted in Docker (`-v n8n_data:/home/node/.n8n`). Two workflows, both version-controlled:
- `eks-cost-watchdog` — ✅ working. Emails at 5 PM / 9 PM if the cluster is still up.
- `terraform-destroy-notifier` — 🚧 webhook done; needs the IF node, Gmail branches and the local destroy script. **Payload nests under `body`**, so expressions are `{{ $json.body.status }}`.

---

## 6. Open work

**Mine to write by hand:** `C-02` tests (deps installed, files not written — blocks `C-06`), `S-01` gateway, `C-04` persistent DynamoDB stack, `C-05` IRSA, `C-06` repository refactor, `E-06` Ingress, `N-00b` finish destroy-notifier.

**Decided, not built:** persistence goes to **DynamoDB in a separate `persistent/` Terraform stack via IRSA** — because the cluster is destroyed nightly, anything durable must live outside the destroyed stack, and DynamoDB on-demand costs ~$0 idle where RDS bills continuously.

**Roadmap order:** `R-05` Prometheus/Grafana (first stateful workload) → `R-06` Jenkins in-cluster → `R-07` ArgoCD → `S-02` aggregator → `S-03` frontend → `N-06` n8n onto EKS.

CI/CD split is deliberate: **Jenkins builds and bumps the image tag in the manifests repo; ArgoCD deploys. Jenkins never runs `kubectl apply`.**

---

## 7. Gotchas already paid for

- **Re-run `aws eks update-kubeconfig` after every destroy/apply.** EKS issues a new endpoint hostname each time. Stale-kubeconfig errors look like network or auth failures.
- **`terraform destroy` cannot clean up Kubernetes-created AWS resources.** The NLB and EBS volumes are made by controllers *inside* the cluster. Delete LoadBalancer Services and PVCs **first** — destroy the cluster and those controllers die, orphaning the resources permanently.
- **`aws ecr list-images` defaults to tagged only.** Use `--filter tagStatus=ANY` or untagged buildkit attestation digests survive.
- **`force_delete = true` on ECR is necessary but has been seen not to work.** Empty the repo manually as well.
- **Git Bash silently ignores `TZ`** and falls back to GMT. Timestamps were 5.5 hours wrong before this was caught.
- **n8n "Continue (using error output)" misbehaves** — use "Stop Workflow". A green check means "did not halt", not "got a 200".
- **`0.0.0.0` is a bind address, not a destination.** Browse to `localhost`.
- **WSL2 `/etc/resolv.conf` breaks after `wsl --shutdown`** with `generateResolvConf = false`. Replace the symlink with a real file.
