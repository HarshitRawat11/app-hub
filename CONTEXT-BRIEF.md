# app-hub — context brief

**Purpose:** paste this into a fresh Claude chat before asking about the project. Chat has no filesystem access, so everything it needs is reproduced here, including the source of the short files.

**Snapshot: 2026-09-10 · 16:00 IST.** A point-in-time copy. Inside the repo, `CLAUDE.md`, `PROGRESS.md` and `TIMELINE.md` are authoritative; if they disagree with this file, they win.

> The embedded source blocks below are checked against the real files by
> `scripts/check-doc-drift.py`, which runs as part of `make validate`. They
> cannot silently go stale. **The prose can** — so prefer the repo docs for
> anything time-sensitive.

---

## 1. How I want you to help

**Teach the infra; just build the app.** I am the Principal SRE who has to own EKS, Terraform, Prometheus/Grafana, Jenkins and ArgoCD at work — that is what this project exists to teach me. Hand-writing the *application* code turned out to be a misallocation: I spent real time on Python fundamentals that taught me nothing about infrastructure, while every lesson that stuck came from an infra failure I had to debug myself.

- Explain the reasoning, not just the answer — what the alternatives were and why they lose.
- Name the mental model, not just the syntax.
- Say which parts are load-bearing and which are boilerplate.
- Tell me what breaks it, what the error looks like, and how to distinguish it from a similar failure.
- Assume I'm technically capable but new to the specific tool. Expand acronyms on first use.
- **Hand-build the learning, delegate the scaffolding** (revised 2026-09-09). **Mine to write by hand:** Terraform I have not written before, PromQL and alert rules, Grafana dashboards, Helm values, ArgoCD `Application`s, Jenkins pipelines, n8n GUI work, Kubernetes manifests introducing an object type I have not written, and **anything in the infra layer that broke** — explain it, let me write it, then review. **Not mine:** application code, Dockerfiles, tests, Makefile targets, scripts, boilerplate. Write those and keep the explanation short.
- **Never hand me a finished infra artifact and explain it afterwards.** Explanation first, then I write, then you review. I care more about the reasoning behind a technical direction than reaching a working state fast.
- **When infra breaks, do not just fix it.** Tell me what the error means, give me one or two things to check, and let me check them. If I am wrong about the cause, say so directly.
- Hinglish is welcome for conceptual explanation. **End responses with a short summary in Indian English.**

I keep a `learn/` folder — one Markdown file per step, structured as: What we did / Why / Key concepts / Walkthrough / Gotchas / Verify it yourself / Going deeper. Work I hand-built gets the full structure; work delegated to Claude gets a three-section short note. Format keepable explanations that way.

---

## 2. What the project is

**app-hub is my permanent home for every app I build for my own daily use** — self-hosted on AWS EKS, provisioned by Terraform, deployed from Git-tracked Kubernetes manifests.

Three purposes at once, all real:

1. **Learning vehicle** — specifically the toolset my org is migrating toward: EKS, Terraform, Prometheus/Grafana, Jenkins, ArgoCD, n8n. I am the Principal SRE who has to own it. That's why the stack is what it is; "just use something simpler" is usually the wrong suggestion.
2. **Real daily-use software** — it has to actually work.
3. **Portfolio piece** — legible and deployable by a stranger.

Of the three, **learning dominates — but it is targeted.** When speed and understanding conflict **on the infra stack**, understanding wins. On the application layer, speed wins: the application was never the lesson, it exists so the cluster has something real to run.

**Stack:** Python 3.14 · FastAPI · uv · Docker · Terraform 1.15 · AWS (EKS 1.31, ECR, VPC, S3, DynamoDB) · n8n · Make

**Deliberately excluded:** Eureka (Kubernetes DNS does service discovery natively), Ansible (nothing runs on bare EC2), Spring Boot (a fourth simultaneous unknown).

---

## 3. Structure — SIX git repos

The root is an **umbrella repo** tracking only cross-cutting docs; it gitignores the five component directories so they stay independent.

| Directory | Remote | Tracks |
|---|---|---|
| `.` (root) | `HarshitRawat11/app-hub` | `CLAUDE.md`, `README.md`, `PROGRESS.md`, `TIMELINE.md`, this file, `learn/`, `scripts/`, `Makefile` |
| `infra/` | `HarshitRawat11/app-hub-infra` | Terraform — **two stacks**: `infra/` is ephemeral (destroyed every session), `infra/persistent/` is never destroyed. Separate state keys in the same S3 bucket; `terraform` does not recurse into subdirectories, so `make down` cannot reach the persistent one. |
| `links-service/` | `HarshitRawat11/app-hub-links-service` | FastAPI service (port 8000) |
| `gateway/` | `HarshitRawat11/app-hub-gateway` | FastAPI service (entry point, port 8001) |
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

**`gateway` is built but not deployed.** Steps 1–5 of 6 are done: it runs locally on 8001, proxies `GET /links` to `links-service`, maps upstream failures to `502`/`503`/`504`, is containerised, and has 15 tests. Step 6 (ECR repo + manifests + deploy) is **written and offline-validated but never applied** — no cluster.

**`C-04` (the DynamoDB table) is written and committed but NOT applied.** No table exists in AWS. Once applied, "nothing is deployed" stops being literally true — the resting state becomes *one DynamoDB table exists, by design*.

### AWS facts

| | |
|---|---|
| Account / region | `314146298861` / `ap-south-1` |
| EKS cluster | `app-hub-eks`, Kubernetes 1.31, 2× `t3.medium` in private subnets |
| ECR | `app-hub/links-service` and `app-hub/gateway`, **IMMUTABLE tags**, scan-on-push, `force_delete` |
| TF state | `s3://app-hub-tfstate-314146298861/` — key `infra/terraform.tfstate` (ephemeral) and `persistent/terraform.tfstate` (never destroyed). S3 native locking. |
| VPC | `10.0.0.0/16`, 2 AZs, public + private subnets, single NAT gateway |
| IAM | `terraform-learning` (admin, used by Terraform), `n8n-readonly` (`eks:DescribeCluster` only) |

Cost if left up 24×7: roughly **$150–200/month**. About $0.30/hour while running. On-demand DynamoDB is ~$0 idle.

### links-service — full source

<!-- embed: links-service/app/models.py -->
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

<!-- embed: links-service/app/main.py -->
```python
from fastapi import FastAPI, HTTPException, Response
from app.models import Link, LinkCreate

app = FastAPI()
links_db: dict[int, Link] = {}
next_id = 1

@app.get("/health")
def health():
    return {"status": "ok"}

@app.get("/links")
def get_links():
    return list(links_db.values())

@app.get("/links/{id}")
def get_link(id: int):
    if id not in links_db:
        raise HTTPException(status_code=404, detail="Link not found")
    return links_db[id]

# 201 Created, not 200 (D-16). A request that creates a resource says so, and
# the Location header points at where it now lives -- so a client does not have
# to know how to build that URL itself.
@app.post("/links", status_code=201)
def create_link(link: LinkCreate, response: Response):
    global next_id
    new_link = Link(id=next_id, **link.model_dump())
    links_db[next_id] = new_link
    next_id += 1
    response.headers["Location"] = f"/links/{new_link.id}"
    return new_link

@app.delete("/links/{id}")
def remove_link(id: int):
    if id not in links_db:
        raise HTTPException(status_code=404, detail="Link not found")
    del links_db[id]
    return {"deleted": id}
```

Handlers are `snake_case` as of 2026-09-10 (`D-10`), and `POST` returns **`201 Created`** with a `Location` header (`D-16`). **15 tests** in `tests/test_links.py`, via FastAPI `TestClient`; two are explicit regressions for the `D-01` bug where `POST` returned the right shape while every read lost its `id`.

<!-- embed: links-service/Dockerfile -->
```dockerfile
# Base image must satisfy pyproject.toml's `requires-python = ">=3.14"`.
# With a 3.12 base, uv silently downloaded its own managed 3.14 at build time —
# the image worked, but the FROM tag was a lie and the image carried two Pythons.
FROM python:3.14-slim

# Copy the uv binaries from the official image rather than pip-installing them.
# Keeps uv out of the app's dependency tree entirely.
COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /bin/

WORKDIR /app

# Dependencies are copied and installed BEFORE the app source, so this layer is
# cached and only re-runs when pyproject.toml or uv.lock actually change.
# Editing app code then rebuilds in seconds instead of re-resolving every dependency.
COPY pyproject.toml uv.lock ./

# --frozen: fail if uv.lock is out of date rather than silently re-resolving.
#           This is what makes the build reproducible.
# --no-install-project: install only the dependencies, not the project itself
#           (this project has no [build-system], so it is not an installable package —
#           it runs from source, which is why `app/` is simply copied in below).
RUN uv sync --frozen --no-install-project

COPY app/ ./app/

# Put the virtualenv first on PATH so `uvicorn` resolves to /app/.venv/bin/uvicorn.
# This is what lets CMD invoke uvicorn directly instead of going through `uv run`.
ENV PATH="/app/.venv/bin:$PATH"

# Don't write .pyc files. Two reasons: the image is immutable so the cache buys
# nothing, and it means the container never needs to write into /app -- which is
# what makes readOnlyRootFilesystem viable in the Deployment.
ENV PYTHONDONTWRITEBYTECODE=1
# Unbuffered stdout/stderr, so logs reach `kubectl logs` immediately instead of
# sitting in a buffer until the process exits or the buffer fills.
ENV PYTHONUNBUFFERED=1

# Run as a non-root user (R-02).
#
# By default a container runs as root. If anything escapes the container, it
# escapes AS ROOT. This app never needs to write to disk or bind a privileged
# port (<1024), so there is nothing to trade away.
#
# --system creates a user with no login shell and no password. 10001 is an
# arbitrary high UID chosen to avoid colliding with host users, and it is set
# explicitly so the Kubernetes securityContext can assert the same number.
RUN groupadd --system --gid 10001 appuser \
 && useradd --system --uid 10001 --gid appuser --no-create-home appuser \
 && chown -R appuser:appuser /app
USER appuser

EXPOSE 8000

# Run uvicorn straight from the venv.
#
# The previous CMD was `uv run uvicorn ...`, which re-resolves the environment and
# installs the project at *container start* — undoing the build-time sync, adding
# latency to every pod start, and turning a dependency problem into a runtime crash
# instead of a build failure. A container should start the app, not build it.
#
# 0.0.0.0 is a bind address meaning "listen on all interfaces" — not a browsable
# host. Reach the container at localhost:8000.
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
```

### gateway — full source

<!-- embed: gateway/app/main.py -->
```python
from fastapi import FastAPI, HTTPException
from contextlib import asynccontextmanager
import httpx2
import logging
import os

logger = logging.getLogger(__name__)

# Where links-service lives. This is config, not code: "http://localhost:8000"
# on a laptop, "http://links-service:8000" inside the app-hub namespace. The
# Deployment's env: block supplies the second one, so the same image runs in
# both places without a rebuild.
#
# rstrip("/") because a trailing slash in the variable produces "...8000//links",
# which some servers tolerate and some 404 on -- a miserable bug to read, since
# the URL looks correct.
LINKS_SERVICE_URL = os.getenv("LINKS_SERVICE_URL", "http://localhost:8000").rstrip("/")

@asynccontextmanager
async def lifespan(app: FastAPI):
    app.state.http_client = httpx2.AsyncClient(timeout=3.0)
    yield
    await app.state.http_client.aclose()

app = FastAPI(lifespan=lifespan)

@app.get("/health")
def health():
    # Deliberately does NOT check links-service. This backs the liveness probe,
    # so a failing upstream would get gateway killed and restarted as well --
    # one outage becoming two, with the restarts hiding the real cause.
    return {"status": "ok"}

@app.get("/links")
async def get_links():
    url = f"{LINKS_SERVICE_URL}/links"
    try:
        response = await app.state.http_client.get(url)
    except httpx2.TimeoutException:
        # The detail strings stay fixed. str(e) from httpx2 contains the URL it
        # tried, which in-cluster is "http://links-service:8000/links" -- that
        # is internal topology, and the caller has no business seeing it. The
        # real error goes to the logs, where it is actually useful.
        logger.warning("timeout after 3s calling %s", url)
        raise HTTPException(status_code=504, detail="links-service timed out")
    except httpx2.RequestError as e:
        logger.warning("cannot reach %s: %s", url, e)
        raise HTTPException(status_code=503, detail="links-service unavailable")
    if response.status_code >= 400:
        logger.warning("%s returned HTTP %s", url, response.status_code)
        raise HTTPException(status_code=502, detail="links-service returned an error")

    return response.json()
```

**15 tests** in `tests/test_gateway.py`. `links-service` is never started — upstream responses are faked with `httpx2.MockTransport`, which swaps the transport underneath the real `AsyncClient`, so client, `await`, timeout and exception handling are genuine while nothing touches a socket. **Both services are on `httpx2` 2.12.0** as of 2026-09-10 (`D-17`).

`Dockerfile` is near-identical to links-service's, port 8001.

### manifests

```
manifests/
  00-namespace.yaml          namespace app-hub, restricted Pod Security Standard
  links-service/
    deployment.yaml          replicas: 1 (in-memory state), securityContext, resources
    service.yaml             type: LoadBalancer, NLB annotation, port 80 -> 8000
  gateway/
    deployment.yaml          replicas: 2 (stateless), env: LINKS_SERVICE_URL
    service.yaml             type: ClusterIP (see E-06)
```

The namespace sits at the **top** of `manifests/`, not inside a service directory — it is shared, and `kubectl apply -f <dir>` sorts by filename *within* a directory and guarantees nothing across directories. `make deploy` applies it as an explicit first step.

Both Deployments carry: `runAsNonRoot`, uid 10001, `readOnlyRootFilesystem`, all capabilities dropped, RuntimeDefault seccomp, requests 50m/64Mi and limits 500m/256Mi (→ **Burstable** QoS), liveness + readiness on `/health`.

**Image tags in both Deployments are placeholders.** `make deploy` rewrites them to a real git-SHA tag before applying and tells you to commit the result. That matters for `R-07`: ArgoCD applies the repo *verbatim*, so the manifests must hold real, pushed tags before GitOps can work.

`replicas: 2` for gateway and `1` for links-service is a difference of **state, not importance** — links-service holds records in an in-process dict, gateway holds nothing.

### infra

**Ephemeral stack** (`infra/`): `providers.tf` (S3 backend, `use_lockfile = true`), `vpc.tf`, `eks.tf`, `ecr.tf` (two repositories), `outputs.tf`, `variables.tf`. Community modules `terraform-aws-modules/vpc/aws ~> 5.0` and `.../eks/aws ~> 20.0`. `enable_cluster_creator_admin_permissions = true` is **required** — without it the creating IAM user gets `Unauthorized` from `kubectl`.

**Persistent stack** (`infra/persistent/`): one `aws_dynamodb_table`, `app-hub-links`, `PAY_PER_REQUEST`, hash key `id` declared as type **`S`** (ids are integers today, but a key attribute's type cannot be changed without recreating the table, and `C-06` moves to UUID/ULID), plus `lifecycle { prevent_destroy = true }`. Own state key. Written and committed, **not applied**.

`.terraform.lock.hcl` is committed (aws pinned at 5.100.0) — it was gitignored, which meant a fresh clone could resolve a different 5.x than this was built against (`D-15`).

### Tooling at the root

- `Makefile` — `make status | up | deploy | down | test | validate`. Run from WSL. `deploy` loops over a `SERVICES` list; `down` encodes the teardown order and walks a separate `ECR_REPOS` list.
- `scripts/timeline.sh` — generates `TIMELINE.md` from git across all six repos.
- `scripts/validate-manifests.py` — offline manifest checks.
- `scripts/check-doc-drift.py` — verifies the embedded source blocks in this file still match the real files.
- `scripts/scheduled-destroy.sh` — unattended `make down` that POSTs the result to an n8n webhook. **Not yet wired into Windows Task Scheduler.**

### n8n

Self-hosted in Docker (`-v n8n_data:/home/node/.n8n`). Two workflows, both version-controlled. **Both moved from Gmail OAuth to SMTP on 2026-09-05**, which removed a ~7-day refresh-token expiry that had silently killed both.

- `eks-cost-watchdog` — active, emails at 5 PM / 9 PM if the cluster is still up. **Has never actually sent an email** (`N-01b`): it cannot be tested without a cluster, since the EKS call 404s with no cluster and `onError: stopWorkflow` halts it before the email node. Correct behaviour, but the path is unproven.
- `terraform-destroy-notifier` — **done and verified end to end.** `Webhook → If → Success/Failure`; both branches route correctly and SMTP reported the mail accepted. **Payload nests under `body`**, so expressions are `{{ $json.body.status }}`.

---

## 6. Open work

**Mine to write by hand:** `C-05` IRSA (needs the cluster's OIDC provider, and `C-04` applied first), `E-06` Ingress + shared ALB, `R-05` Prometheus/Grafana, `R-06` Jenkins, `R-07` ArgoCD, most of `N-06` (n8n onto EKS). Plus **applying `C-04`**, which is one `terraform apply` away.

**Claude's, and blocked on me:** `C-06` repository refactor (needs `C-04` applied), `S-02` aggregator (needs a GitHub remote only I can create, plus a decision on `D-17`).

**Decided 2026-09-10:** `D-16` — `POST` now returns `201 Created` with `Location`. `D-17` — both services on `httpx2`. `E-06` direction — `gateway` becomes publicly reachable via Ingress and `links-service` becomes `ClusterIP`; only the implementation waits.

**Needs a cluster, batched into one session:** `S-01` step 6 deploy · `C-05` · `N-01b` · and the **first real verification of `R-01`–`R-04`** (namespace, resource limits, `securityContext`, immutable tags — all written 2026-09-03 with no cluster available, so never enforced by an actual API server).

**Roadmap order:** `E-06` → `R-05` Prometheus/Grafana (first stateful workload) → `R-06` Jenkins in-cluster → `R-07` ArgoCD → `N-06` n8n onto EKS → `S-03` frontend.

CI/CD split is deliberate: **Jenkins builds and bumps the image tag in the manifests repo; ArgoCD deploys. Jenkins never runs `kubectl apply`.**

---

## 7. Gotchas already paid for

- **Re-run `aws eks update-kubeconfig` after every destroy/apply.** EKS issues a new endpoint hostname each time. Stale-kubeconfig errors look like network or auth failures.
- **`terraform destroy` cannot clean up Kubernetes-created AWS resources.** The NLB and EBS volumes are made by controllers *inside* the cluster. Delete LoadBalancer Services and PVCs **first** — destroy the cluster and those controllers die, orphaning the resources permanently.
- **`aws ecr list-images` defaults to tagged only.** Use `--filter tagStatus=ANY` or untagged buildkit attestation digests survive. This applies to **every** repository — a new one missing from the Makefile's `ECR_REPOS` breaks a later destroy with an error about the repository not being empty.
- **`force_delete = true` on ECR is necessary but has been seen not to work.** Empty the repo manually as well.
- **`git log --pretty=format:` drops the last line when piped into `while read`.** `format:` separates rather than terminates, so the final entry has no newline. Since `git log` is newest-first, the lost commit is always the repo's *root* commit — the timeline silently omitted six of them. Use `tformat:`.
- **Git Bash silently ignores `TZ`** and falls back to GMT. Timestamps were 5.5 hours wrong before this was caught.
- **`pkill -f <pattern>` matches its own shell** when the pattern appears in a `bash -lc '...'` command line, so it kills the killer. Exit code 15 is the tell. Run the script from a file instead.
- **n8n "Continue (using error output)" misbehaves** — use "Stop Workflow". A green check means "did not halt", not "got a 200". And a webhook returning 200 means *received*, not *succeeded*.
- **`0.0.0.0` is a bind address, not a destination.** Browse to `localhost`.
- **Inside a container, `localhost:8000` is the container's own localhost.** A containerised gateway on default config returns `503`, correctly. Put both on a Docker network and address by name to rehearse Kubernetes DNS locally, for free.
- **WSL2 `/etc/resolv.conf` breaks after `wsl --shutdown`** with `generateResolvConf = false`. Replace the symlink with a real file.
- **A monitor fails invisibly, because its normal state is silence.** `cost-watchdog` reported `active: true` for days while unable to send mail. "It hasn't alerted" and "there is nothing to alert about" look identical from outside.
