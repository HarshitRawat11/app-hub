# app-hub — context brief

**Purpose of this file:** paste it into a fresh Claude chat before asking questions about this project. Claude chat has no access to my filesystem, so everything it needs is reproduced here — including the actual source of the short files.

**Snapshot date:** 2026-08-30. This is a point-in-time copy. Inside the repo, `CLAUDE.md` and `PROGRESS.md` are authoritative; if they disagree with this file, they win and this file is stale.

---

## 1. How I want you to help

**Teach, don't just answer.** I started this project working through every step manually with Claude chat, specifically to learn it. Time pressure moved the day-to-day building into Claude Code — that was a decision about speed, **not** about outsourcing the understanding.

So when I ask you something:

- Explain the reasoning, not just the answer. What the alternatives were and why they lose.
- Name the mental model, not just the syntax.
- Tell me which parts are load-bearing and which are boilerplate.
- Tell me what breaks it, what the error will look like, and how to tell it apart from a similar failure.
- Assume I'm technically capable but new to the specific tool. Expand acronyms on first use.
- If I could not explain your answer to someone else afterwards, it wasn't a good answer.

I keep a `learn/` folder in the project — one Markdown file per step performed, structured as: What we did / Why / Key concepts / Walkthrough / Gotchas / Verify it yourself / Going deeper. If you produce an explanation worth keeping, format it that way and I'll save it.

---

## 2. What the project is

**app-hub is my permanent home for every app, tool, and project I build for my own daily use** — self-hosted, running on AWS EKS, provisioned with Terraform, deployed from Git-tracked Kubernetes manifests.

It serves three purposes at once, and all three are real:

1. **Learning vehicle** — practising production-grade DevOps end to end: service → Docker → ECR → EKS → CI/CD → observability.
2. **Real daily-use software** — the things hosted here get used by me, every day. They have to actually work.
3. **Portfolio piece** — it should read as competent and be deployable by someone who has never seen it.

That combination sets the bar: "works on my machine" is not the finish line. Reproducible-from-a-clean-clone is.

**Stack:** Python 3.14 · FastAPI · uv · Docker · Terraform 1.15 · AWS (EKS, ECR, VPC, S3) · Kubernetes 1.31 · n8n

---

## 3. Structure — four independent repos, no root repo

`app-hub/` is a plain folder, **not** a git repository. It contains four separate repos, each with its own GitHub remote:

| Directory | Remote | Purpose |
|---|---|---|
| `infra/` | `HarshitRawat11/app-hub-infra` | Terraform: VPC, EKS, ECR |
| `links-service/` | `HarshitRawat11/app-hub-links-service` | FastAPI service (service #1) |
| `manifests/` | `HarshitRawat11/app-hub-manifests` | Kubernetes manifests |
| `n8n/` | `HarshitRawat11/app-hub-n8n` *(remote not yet created)* | n8n workflow definitions |

Consequences: every git command needs `-C <subdir>`; a change spanning service + manifests is two commits in two repos; and the root-level files (`CLAUDE.md`, `README.md`, `PROGRESS.md`, `learn/`, this file) are currently in **no** repo — unversioned and unbacked-up. That's an open decision (`P-01`).

---

## 4. My environment — the WSL/Windows split

This trips up almost every generic instruction, so please account for it.

| Windows side | WSL Ubuntu side |
|---|---|
| `docker` (Docker Desktop 29.5.3) | `terraform` (v1.15.8) |
| `kubectl` (v1.34.1) | `uv` (v0.11.32) |
| `helm` | `python3` |
| `aws` (v2.33.15) | `jq` |

- Windows `python` is the Microsoft Store stub — it does not work. Use WSL `python3`.
- `gh` (GitHub CLI) is **not installed anywhere** — GitHub repo creation and PRs go through the web UI.
- `kubectl` currently points at **minikube**, not EKS.
- Running a WSL tool from Windows looks like:
  ```bash
  wsl -e bash -lc "cd /mnt/c/Users/harshit.rawat/Documents/Projects/app-hub/infra && terraform plan"
  ```

Please don't suggest "just install X on Windows" without flagging it as a change to this setup — the split is deliberate and working.

---

## 5. Current state

**Nothing has been deployed yet.** The three pieces exist but have never been connected end to end. No image has been built and pushed, no `terraform apply` is confirmed against the S3 backend, nothing runs on a cluster.

### AWS facts

| | |
|---|---|
| Account | `314146298861` |
| Region | `ap-south-1` |
| EKS cluster | `app-hub-eks`, Kubernetes 1.31 |
| Node group | 2× `t3.medium` (min 1, max 2) |
| ECR repo | `app-hub/links-service` |
| TF state | `s3://app-hub-tfstate-314146298861/infra/terraform.tfstate`, S3 native locking |
| VPC | `10.0.0.0/16`, 2 AZs, public + private subnets, single NAT gateway |

Estimated cost if left running 24×7: roughly **$150–200/month** (EKS control plane + 2 nodes + NAT gateway). I tear down when not using it.

### links-service — the full source

`app/models.py`:

```python
from pydantic import BaseModel

class Link(BaseModel):
    id: int
    name: str
    url: str
    category: str
    icon: str | None = None

class LinkCreate(BaseModel):
    name: str
    url: str
    category: str
    icon: str | None = None
```

`app/main.py`:

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
    links_db[next_id] = link          # <-- BUG: stores LinkCreate, not new_link
    next_id += 1
    return new_link

@app.delete("/links/{id}")
def removeLink(id: int):
    if id not in links_db:
        raise HTTPException(status_code=404, detail="Link not found")
    del links_db[id]
    return {"deleted": id}
```

`Dockerfile` (written but **not yet committed**):

```dockerfile
FROM python:3.12-slim
COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /bin/
WORKDIR /app
COPY pyproject.toml uv.lock ./
RUN uv sync --frozen --no-install-project
COPY app/ ./app/
EXPOSE 8000
CMD ["uv", "run", "uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
```

`pyproject.toml` requires `python >=3.14`; `.python-version` says `3.14`. Note the base image above is 3.12 — that mismatch is a known defect.

### manifests

`deployment.yaml`: `replicas: 2`, image `314146298861.dkr.ecr.ap-south-1.amazonaws.com/app-hub/links-service:v1`, liveness + readiness probes on `/health:8000`. No namespace, no resource requests/limits, no securityContext.

`service.yaml`: `ClusterIP`, port 8000 → targetPort 8000. No Ingress, so nothing is reachable from outside the cluster.

### infra

Seven `.tf` files: `providers.tf` (S3 backend), `vpc.tf`, `eks.tf`, `ecr.tf`, `outputs.tf`, `vairables.tf` *(filename typo, real)*, and an empty `main.tf`. Uses the community `terraform-aws-modules/vpc/aws ~> 5.0` and `terraform-aws-modules/eks/aws ~> 20.0`.

### n8n

Self-hosted (Docker/local). Repo scaffolded this session but nothing pulled in yet — Docker Desktop wasn't running. Holds `workflows/` (JSON, one file per workflow), `scripts/pull-workflows.sh` (fetches via the n8n API), `.env.example`, and a gitignored `.env` for `N8N_BASE_URL` + `N8N_API_KEY`.

---

## 6. Known defects

| ID | Severity | Where | Problem |
|---|---|---|---|
| D-01 | **High** | `main.py:29` | `createLink` builds `new_link = Link(id=next_id, ...)` then stores the incoming `link` (a `LinkCreate`, no `id`). It *returns* `new_link`, so POST looks fine — but GET returns records with no `id`. |
| D-02 | **High** | `deployment.yaml` + `main.py:5` | `links_db` is an in-process dict while the Deployment runs `replicas: 2`. Two pods, two independent datasets, non-deterministic reads, everything lost on restart. |
| D-03 | Medium | `Dockerfile:1` | Base `python:3.12-slim` vs `requires-python >=3.14`. `uv` will silently download a managed 3.14 rather than use the base interpreter. |
| D-04 | Medium | `Dockerfile` | Untracked in git — the build isn't reproducible from a clean clone. |
| D-05 | Medium | `service.yaml` | ClusterIP with no Ingress — unreachable from outside the cluster. |
| D-06 | Low | `infra/vairables.tf` | Filename typo. Terraform loads all `.tf` files so behaviour is unaffected. |
| D-07 | Low | `infra/main.tf` | Empty file. |
| D-08 | Low | `links-service/README.md` | Empty file, but referenced as `readme` in `pyproject.toml`. |
| D-09 | Low | `pyproject.toml:4` | `description = "Add your description here"` — leftover scaffold text. |
| D-10 | Low | `main.py` | Function names are camelCase (`getLinks`, `createLink`), against PEP 8. |

---

## 7. Task board — abbreviated

Full board with blockers and next steps lives in `PROGRESS.md`.

- **Phase 0, hygiene (`P-01`–`P-07`):** version-control the root docs; commit the Dockerfile; fix the Python version mismatch; rename `vairables.tf`; delete empty `main.tf`; write the service README; backfill `learn/` files for work done before that folder existed.
- **Phase 1, correctness (`C-01`–`C-03`):** fix the POST bug; add tests (none exist anywhere yet); decide how link data persists across pods.
- **Phase 2, first end-to-end deploy (`E-01`–`E-05`):** confirm whether `terraform apply` ever ran; provision infra; build and push to ECR; deploy and reach `/health`; expose the service externally.
- **Phase 3, production readiness (`R-01`–`R-06`):** resource limits; securityContext; immutable image tags; dedicated namespace; CI/CD; observability.
- **Phase 4, n8n (`N-01`–`N-06`):** repo scaffolded ✅; create the GitHub remote; fill in `.env`; pull existing workflows; back up the n8n encryption key; decide whether n8n eventually runs on EKS.

**Nearest milestone:** first end-to-end deploy. `P-03` blocks it; `C-01` should be fixed before calling the result working.

---

## 8. Open decisions I haven't made

1. **Where the root docs get version-controlled** (`P-01`) — a fourth `app-hub-docs` repo, folded into an existing repo, or left untracked. Currently unversioned.
2. **Whether link data should persist** (`C-03`) — scale to 1 replica as a stopgap, or add a real datastore. This is architectural and I want to understand the tradeoffs before choosing.
3. **Whether n8n moves onto the EKS cluster** (`N-06`) — would need Postgres, the encryption key as a Kubernetes Secret, and persistent storage.
4. **Whether there's a frontend**, or the API is the whole deliverable for now.

---

## 9. Conventions

- **Commit messages:** imperative, one line, no trailing period, no type prefix. e.g. `Add ECR repository for links-service`.
- **Secrets:** the AWS account ID is committed by choice. Nothing else is — no keys, no kubeconfigs, no credentials in `*.tfvars`. The n8n API key lives in a gitignored `.env` and is never pasted into a chat window, never printed, never passed to `curl -v` (verbose mode prints request headers).
- **Infrastructure:** `terraform plan` before every `apply`, and read it. State stays in S3 with locking. Tear down when idle.
- **Definition of done:** code actually run (not just written) → committed to the right repo → written up in `learn/` → `PROGRESS.md` updated → anything found-but-not-fixed recorded as a defect.

---

## 10. What changed in the session that produced this file

No application code was touched. What happened was setup and audit:

- Audited the workspace and found the two structural facts above (no root repo; the WSL/Windows toolchain split), plus the ten defects.
- Created `CLAUDE.md` (operating manual for Claude Code sessions), `README.md`, and `PROGRESS.md` at the root.
- Created the `learn/` folder with `00-project-setup-and-governance.md` and `01-n8n-workflows-as-code.md`.
- Scaffolded the `n8n/` repo with a gitignored `.env` pattern, a pull script, a `.gitattributes` enforcing LF line endings (CRLF would break the shell scripts under WSL with a misleading `bad interpreter` error), and security rules for the API key.

---

## 11. Good things to ask you about

Given the state above, the questions where I'd most value a proper explanation rather than just an answer:

- Why in-memory state breaks under multiple replicas, and what the realistic options are (`C-03`).
- What a Kubernetes Ingress actually does versus a `LoadBalancer` Service, and which fits a single small cluster (`E-05` / `D-05`).
- How `uv` resolves Python interpreters inside a container, and why the 3.12/3.14 mismatch is a problem rather than just untidy (`D-03`).
- What resource requests and limits really control, and what "BestEffort" means for eviction (`R-01`).
- How to structure CI/CD across four separate repos without it becoming unmanageable (`R-05`).
- Whether n8n belongs on the same cluster as everything else, and what that costs in complexity (`N-06`).
