# PROGRESS.md — app-hub

Live status board. **Update this at the end of every working session** — status, blocker, next step, plus a line in the log.

**Last updated:** 2026-08-29

---

## Where the project stands

**The full deploy loop has already been proven once.** In an earlier manual session, `links-service` was built, pushed to ECR, deployed to EKS with 2 pods `Running`, and ClusterIP routing plus Kubernetes DNS discovery were confirmed working. Everything was then destroyed with `terraform destroy`, per the standing cost policy.

So **"nothing is currently deployed" is the normal resting state of this project, not a failure.** The NAT gateway bills continuously, so the cluster only exists while it is being worked on.

What that leaves:

- **Immediate blocker:** `E-00` — there is no working AWS profile for account `314146298861` on this machine. Verified 2026-08-29: credentials are rejected (`InvalidClientTokenId`), and the three configured profiles are all work-account. Nothing touching AWS can proceed until this is fixed.
- **Code state:** the Dockerfile defects (`D-03`, `D-11`) and the `POST /links` bug (`C-01`) are **fixed and committed** as of 2026-08-29. Remaining correctness gap: there are still **no tests anywhere** (`C-02`), and storage is still an in-process dict behind 2 replicas (`C-03`).
- **`kubectl` context is `minikube`.** After any rebuild, re-run `aws eks update-kubeconfig` — EKS issues a new endpoint hostname every time (see `CLAUDE.md § 9`).

**Milestone 2 — rebuild the loop cleanly, with the defects fixed and the steps captured in `learn/`.**

---

## Status board

Status values: `Not started` · `In progress` · `Blocked` · `Done` · `Needs verification`

### Phase 0 — Project hygiene

| ID | Task | Status | Blocker | Next step |
|----|------|--------|---------|-----------|
| P-01 | Version-control the root docs (`CLAUDE.md`, `README.md`, `PROGRESS.md`, `CONTEXT-BRIEF.md`, `learn/`) | Blocked | Root `app-hub/` is not a git repo; the three subdirs are separate repos. Needs an owner decision on where these live. | Decide: (a) `git init` a fourth `app-hub-docs` repo at the root, (b) move the docs into one existing repo, or (c) leave untracked and accept the risk. Then act on it. `learn/` makes this more urgent — it will hold the most irreplaceable content in the project. |
| P-02 | Commit the untracked `links-service/Dockerfile` | **Done** | None | Committed 2026-08-29 as `5e312ef`, after fixing `P-03` and `D-11` in the same file |
| P-03 | Fix Dockerfile base image / Python version mismatch | **Done** | None | Committed 2026-08-29 as `5e312ef`. Base moved to `python:3.14-slim` (verified to exist, currently 3.14.7) so the tag matches `requires-python >=3.14`. Fixed together with `D-11`. |
| P-04 | Rename `infra/vairables.tf` → `infra/variables.tf` | **Done** | None | Committed 2026-08-29 as `3cb9e57` via `git mv` (staged as a rename). `terraform validate` passes, `terraform fmt -check` clean. |
| P-05 | Remove or populate the empty `infra/main.tf` | **Done** | None | Removed 2026-08-29 in `3cb9e57`. Terraform loads all `.tf` files, so `main.tf` is convention only — nothing depended on it. |
| P-06 | Write `links-service/README.md` | **Done** | None | Committed 2026-08-29 as `f3203de`. Covers the API table, local + Docker run, and an explicit storage caveat pointing at `C-03`. |
| P-07 | Backfill `learn/` files for the steps done before this folder existed | Not started | None — needs a go-ahead, since it is ~7 files of writing. | Write up: Terraform scaffolding + S3 backend, VPC, EKS, ECR, FastAPI service, Docker/uv, K8s manifests. Listed in `learn/README.md § Not yet written up`. |

### Phase 1 — Correctness

| ID | Task | Status | Blocker | Next step |
|----|------|--------|---------|-----------|
| C-01 | Fix `POST /links` storing the wrong object | **Done** | None | Committed 2026-08-29 as `7b7b0bd`. Verified by HTTP round-trip: `POST` then `GET /links` now both return `"id":1`. |
| C-02 | Add tests for the links CRUD endpoints | **Ready — owner writes this** | None. Held back deliberately: there are no tests anywhere yet, so this is a *new concept* for the project and `CLAUDE.md § 2` says the first implementation is done by hand. | Add `pytest` + `httpx` as dev deps (`uv add --dev pytest httpx`), create `tests/test_links.py` using FastAPI `TestClient`. Cover create → list → get → delete plus the two 404 paths. Note the shared-state trap: `links_db` is a module-level dict, so tests leak into each other unless reset between them. Ask for an explanation of `TestClient` and fixtures before writing, not after. |
| C-03 | Decide how link data persists across pods | Not started | Needs an owner decision — this is an architecture call, not a bug fix. | `links_db` is an in-process dict while `deployment.yaml` runs 2 replicas, so reads hit inconsistent state and everything is lost on restart. Choose: scale to 1 replica as a stopgap, or add a real datastore (RDS/DynamoDB). See `D-02`. |

### Phase 2 — First end-to-end deploy

| ID | Task | Status | Blocker | Next step |
|----|------|--------|---------|-----------|
| E-00 | Configure an AWS profile for the app-hub account | **Blocked** | Owner action. No profile for account `314146298861` exists on this machine. | Configured profiles are `uzio-nonprod-audit`, `default`, `scripttest` — all work-account, and `default` is `us-east-1` with rejected keys (`InvalidClientTokenId`). Create a **named** profile (e.g. `app-hub`) for the `terraform-learning` IAM user; do not overwrite `default`, which belongs to work. |
| E-01 | Confirm whether `terraform apply` has ever run against the S3 backend | **Resolved** | None | **Answered by project history 2026-08-29: yes.** The full loop was proven once — image built, pushed to ECR, deployed to EKS, 2 pods `Running`, ClusterIP routing and Kubernetes DNS discovery confirmed — then torn down with `terraform destroy` per the cost policy. "Nothing deployed" is the normal resting state, not a failure. Live re-verification is blocked on `E-00`. |
| E-02 | Re-provision the infra (VPC + EKS + ECR) | Not started | Depends on `E-00` (no credentials); **requires explicit owner approval** — this starts real billing. | Review `terraform plan` output line by line, get approval, then apply. Remember `aws eks update-kubeconfig` afterwards — the endpoint hostname changes on every rebuild. |
| E-03 | Build and push `links-service:v1` to ECR | Not started | Depends on `P-03` (image will not build cleanly) and `E-02` (ECR must exist) | Follow README § Quick start step 4 |
| E-04 | Deploy manifests to EKS and reach `/health` | Not started | Depends on `E-03` | `aws eks update-kubeconfig`, verify context is **not** minikube, `kubectl apply -f manifests/links-service/`, then port-forward and curl |
| E-05 | Expose the service outside the cluster | Not started | Depends on `E-04` | Service is `ClusterIP` — nothing reaches it externally. Add an Ingress + AWS Load Balancer Controller, or switch to `type: LoadBalancer`. |

### Phase 3 — Production readiness

| ID | Task | Status | Blocker | Next step |
|----|------|--------|---------|-----------|
| R-01 | Add resource requests and limits to the Deployment | Not started | None | Without them pods are BestEffort and are evicted first under node pressure |
| R-02 | Add a `securityContext` (non-root, read-only rootfs) | Not started | None | Also add a non-root `USER` to the Dockerfile |
| R-03 | Replace the mutable `:v1` tag with immutable tags | Not started | None | Tag by git SHA; set `image_tag_mutability = "IMMUTABLE"` in `ecr.tf` |
| R-04 | Deploy into a dedicated namespace | Not started | None | Manifests currently have no `metadata.namespace`, so they land in `default` |
| R-05 | CI: **Jenkins, running as a Helm chart inside EKS** | Not started | Depends on Phase 2 being proven by hand first | Deliberately Jenkins-in-cluster rather than GitHub Actions — the point is learning the org's toolset. On push to `links-service` → test, build, push to ECR, bump the manifest tag. |
| R-06 | CD: **ArgoCD, GitOps from `app-hub-manifests`** | Not started | Depends on `E-04` | The manifests repo is already separate specifically to enable this. ArgoCD watches it and reconciles the cluster. |
| R-07 | Observability: **Grafana / Prometheus** | Not started | Depends on `E-04` | Part of the org toolset being learned. Structured logging in the service first, then metrics and dashboards. |

### Phase 4 — n8n workflows

Self-hosted n8n. Workflow definitions are version-controlled in `n8n/`; credentials never are.

| ID | Task | Status | Blocker | Next step |
|----|------|--------|---------|-----------|
| N-00 | Existing workflows: `cost-watchdog` (✅ working — checks whether EKS is up, emails via Gmail 5 PM & 9 PM) and `destroy-notifier` (🚧 in progress — local script posts destroy result to an n8n webhook, which emails it) | Partially done | None | `N-04` pulls both into git. `destroy-notifier` still needs finishing. Uses the `n8n-readonly` IAM user, scoped to `eks:DescribeCluster`. |
| N-01 | Scaffold the `n8n/` repo | Done | None | Done 2026-08-29: git repo, `.gitignore`, `.gitattributes` (LF enforcement), `.env.example`, `pull-workflows.sh`, README with security rules |
| N-02 | Create the `app-hub-n8n` GitHub remote and push | Not started | `gh` CLI is not installed — the repo must be created via the GitHub web UI | Create `HarshitRawat11/app-hub-n8n` (empty, no README), then `git -C n8n remote add origin ... && git -C n8n push -u origin master` |
| N-03 | Populate `n8n/.env` with the instance URL and API key | Not started | Owner action — the key must not be pasted into chat | `cp n8n/.env.example n8n/.env`, fill it in from **Settings → n8n API**, verify with `git -C n8n check-ignore -v .env` |
| N-04 | Pull the existing workflow into `n8n/workflows/` | Not started | Depends on `N-03`; Docker Desktop was not running at scaffold time | Run `scripts/pull-workflows.sh` from WSL, grep for hardcoded secrets, then commit |
| N-05 | Back up the n8n encryption key outside the repo | Not started | Owner action | Copy the key from `~/.n8n` into a password manager. Without it, every stored credential is unrecoverable if the instance is lost. |
| N-06 | Decide whether n8n moves onto the EKS cluster | Not started | Needs an owner decision; depends on Phase 2 landing first | Running it in-cluster needs a Postgres backing store, `N8N_ENCRYPTION_KEY` as a Kubernetes Secret, and a persistent volume. Not urgent — local Docker is fine for now. |

### Phase 5 — Further services

| ID | Task | Status | Blocker | Next step |
|----|------|--------|---------|-----------|
| S-01 | Build `gateway` — calls `links-service` **by Kubernetes DNS name** | Not started | Depends on Phase 2. **Owner builds this by hand** (`CLAUDE.md § 2` — do not build ahead). | Its purpose is to prove service-to-service discovery. Repo `app-hub-gateway` does not exist yet. |
| S-02 | Build `aggregator` | Not started | Future — after `gateway` | Scope not yet defined |

---

## Known defects

| ID | Severity | Where | What is wrong |
|----|----------|-------|---------------|
| ~~`D-01`~~ | **RESOLVED** 2026-08-29 (`7b7b0bd`) | [links-service/app/main.py:29](links-service/app/main.py:29) | `createLink` builds `new_link = Link(id=next_id, ...)` but then stores the *incoming* `link` (a `LinkCreate`, which has no `id`). It returns `new_link`, so `POST` looks correct — but `GET /links` and `GET /links/{id}` return records with no `id` field. Fix: store `new_link`. |
| `D-02` | **High** | [manifests/links-service/deployment.yaml](manifests/links-service/deployment.yaml) + [links-service/app/main.py:5](links-service/app/main.py:5) | `links_db` is an in-process dict, but the Deployment runs `replicas: 2`. The two pods hold independent data, so reads are non-deterministic and a restart loses everything. Tracked as task `C-03`. |
| ~~`D-03`~~ | **RESOLVED** 2026-08-29 (`5e312ef`) | [links-service/Dockerfile:1](links-service/Dockerfile:1) | Base is `python:3.12-slim` while `pyproject.toml` requires `>=3.14` and `.python-version` says `3.14`. `uv sync` will silently download a managed Python 3.14 rather than use the base image's interpreter — bloating the image and making the base tag a lie. Tracked as `P-03`. |
| ~~`D-04`~~ | **RESOLVED** 2026-08-29 (`5e312ef`) | [links-service/Dockerfile](links-service/Dockerfile) | Untracked in git — the build is not reproducible from a clean clone. Tracked as `P-02`. |
| `D-05` | Medium | [manifests/links-service/service.yaml](manifests/links-service/service.yaml) | `ClusterIP` with no Ingress means the app is unreachable from outside the cluster. Fine for now, blocking for "real internal app hub". Tracked as `E-05`. |
| ~~`D-06`~~ | **RESOLVED** 2026-08-29 (`3cb9e57`) | [infra/vairables.tf](infra/vairables.tf) | Filename typo (`vairables` → `variables`). Terraform loads all `.tf` files so behaviour is unaffected, but it reads as sloppy in a portfolio repo. Tracked as `P-04`. |
| ~~`D-07`~~ | **RESOLVED** 2026-08-29 (`3cb9e57`) | [infra/main.tf](infra/main.tf) | Empty file (0 bytes). Tracked as `P-05`. |
| ~~`D-08`~~ | **RESOLVED** 2026-08-29 (`f3203de`) | [links-service/README.md](links-service/README.md) | Empty file (0 bytes), yet referenced as `readme` in `pyproject.toml`. Tracked as `P-06`. |
| `D-09` | Low | [links-service/pyproject.toml:4](links-service/pyproject.toml:4) | `description = "Add your description here"` — leftover scaffold text. |
| ~~`D-11`~~ | **RESOLVED** 2026-08-29 (`5e312ef`) | [links-service/Dockerfile:8](links-service/Dockerfile:8) + `:14` | Build runs `uv sync --frozen --no-install-project`, but `CMD` uses `uv run`, which re-resolves and installs the project **at container start**. That defeats the build-time sync, moves dependency work into startup (slowing pod readiness, risking a cold-start failure), and will bite when the base image changes. Fix: install the project at build time and invoke `uvicorn` directly in `CMD`. Missed in the 2026-08-29 audit; surfaced from project history. |
| `D-10` | Low | [links-service/app/main.py](links-service/app/main.py) | Function names are `camelCase` (`getLinks`, `createLink`, `removeLink`), against PEP 8. Cosmetic, but easy to fix before the file grows. |
| `D-12` | Low | `infra/`, `links-service/`, `manifests/` | No `.gitattributes`, so git warns `LF will be replaced by CRLF` on every commit. Harmless for Python and exec-form `CMD`, but the same setting that breaks shell scripts under WSL (see `learn/01`). `n8n/` already has one. Add `* text=auto eol=lf` to the other three. |

---

## Decisions on record

| Date | Decision | Rationale |
|------|----------|-----------|
| 2026-08-29 | **Every step must be taught, not just done** — explained in-session and written up in `learn/`. A step without its learning file is not finished. | Owner started this project learning manually with Claude chat and moved to Claude Code for speed, not to outsource the understanding. Recorded in `CLAUDE.md § 2`. |
| 2026-08-29 | app-hub is the permanent home for every app the owner builds for daily use — not a one-off project around `links-service` | Owner-confirmed. Means designing for a hub that grows. |
| 2026-08-29 | app-hub serves three goals at once: learning platform, real daily-use software, and portfolio piece | Owner-confirmed. Sets the quality bar above "works on my machine". |
| 2026-08-29 | AWS EKS (`ap-south-1`) is the canonical deploy target; minikube is a local sandbox only | Owner-confirmed |
| 2026-08-29 | **Do not build ahead** — the first implementation of each new concept is written by the owner, by hand, even when slower | From project history. A finished artifact that skips the wrestling defeats the reason the project exists. Recorded in `CLAUDE.md § 2`. |
| — | **Service discovery is Kubernetes-native DNS, not Eureka** | Eureka is a Spring Boot–ecosystem tool; this stack is Python. Services find each other by Kubernetes service name. |
| — | **CI is Jenkins, in-cluster via Helm; CD is ArgoCD** | Deliberately the org's toolset rather than the easiest option — that is the point of the learning goal. The separate `app-hub-manifests` repo exists to enable GitOps. |
| — | **Ansible and Eureka explicitly dropped from scope** | Not needed for this stack |
| — | **Cluster destroyed at the end of every session** | NAT gateway bills continuously. `cost-watchdog` in n8n enforces it by emailing if EKS is still up. |
| — | Git identity set per-repo, never globally | Work-managed laptop; personal commits must not carry the work identity |
| — | Branch name stays `master` | Nothing in the stack cares; renaming is churn |
| — | Three separate git repos rather than a monorepo | Pre-existing choice, inherited. Revisit only if cross-repo coordination becomes painful. |
| — | Terraform state in S3 with native lockfile locking | Already configured in `providers.tf`; no DynamoDB table needed |

---

## Open questions for the owner

1. **`P-01`** — where should the root docs be version-controlled? Right now `CLAUDE.md`, `README.md`, and `PROGRESS.md` are not in any repo.
2. **`C-03`** — is the link catalogue meant to persist? If yes, that means a datastore and it should be planned before more endpoints are written.
3. Is there a frontend planned for the hub, or is the API the whole deliverable for now?

---

## Progress log

Newest first. One entry per working session — what changed, and what it unblocked.

### 2026-08-29 — Cleared the ready-now backlog (6 tasks, 4 commits, 2 repos)

- **`C-01`** — fixed `POST /links` storing the `LinkCreate` instead of the constructed `Link` (`7b7b0bd`). Verified by HTTP round-trip, not by reading the POST response: `GET /links` now returns `"id":1`, which it did not before.
- **`P-03` + `D-11`** — rewrote the Dockerfile (`5e312ef`). Base moved to `python:3.14-slim` (confirmed to exist via the Docker Hub tag API, currently 3.14.7) so the tag no longer lies about the interpreter; `CMD` now calls `uvicorn` from the venv on `PATH` instead of `uv run`, which was re-installing the project at container start.
- **`P-02`** — the Dockerfile is finally tracked, after being fixed.
- **`P-06`** — wrote `links-service/README.md` (`f3203de`), including an explicit storage caveat so nobody builds on the in-memory dict assuming it persists.
- **`P-04` + `P-05`** — renamed `vairables.tf` → `variables.tf` via `git mv` (staged as a rename) and removed the empty `main.tf` (`3cb9e57`). `terraform validate` passes and `terraform fmt -check` is clean.

**Trap hit before any commit:** three of the four repos had no git identity. `links-service` had a name but no email; `manifests` and `n8n` had neither; global was unset. The next commit in any of them would have failed with `fatal: empty ident name`. Set per-repo to match `infra` — deliberately not globally, since this is a work-managed laptop (`CLAUDE.md § 3`).

**Held back deliberately:** `C-02` (tests). No tests exist anywhere, so this is a new concept, and `CLAUDE.md § 2` says the owner writes the first implementation by hand. Handover notes are on the task row.

Defects closed: `D-01`, `D-03`, `D-04`, `D-06`, `D-07`, `D-08`, `D-11`. New: `D-12` (missing `.gitattributes` in the three older repos). `learn/02-first-defect-fixes.md` written.

### 2026-08-29 — Reconciled with prior Claude-chat project history

The owner supplied a handoff document summarising the manual sessions that preceded Claude Code. It resolved several things my audit could only guess at, and contradicted my docs in two places.

**Corrections to what I had written:**

- **`E-01` resolved.** I recorded "no confirmed `terraform apply`" based on the local `terraform.tfstate` stub. Wrong inference: the full loop *was* proven once — built, pushed to ECR, deployed to EKS, 2 pods `Running`, ClusterIP routing and DNS discovery confirmed — then destroyed per the cost policy. The stub proved nothing either way, which is exactly why the task existed.
- **`D-11` added.** The handoff named a Dockerfile defect I saw during the audit but failed to log: build-time `uv sync --no-install-project` versus `uv run` at `CMD`, which re-installs at container start. My `D-03` covered only the Python version mismatch on the same file.
- **Objective sharpened.** The learning goal is specifically the toolset the owner's organisation is migrating toward (EKS, Terraform, Grafana/Prometheus). That reframes "why this stack" and makes "use something simpler" usually the wrong suggestion.
- **`CLAUDE.md § 2` gained "Do not build ahead."** The owner writes the first implementation of each new concept by hand. Noted honestly: scaffolding the n8n repo earlier in this session ran against that rule.

**New facts recorded:** cost policy (destroy every session) and the `cost-watchdog` / `destroy-notifier` workflows; roadmap (`gateway` → Jenkins-in-EKS → ArgoCD → Grafana/Prometheus); service discovery via Kubernetes DNS, not Eureka; Ansible and Eureka dropped; per-repo git identity on a work laptop; the WSL2 DNS fix; Hinglish preferred for conceptual explanation; five hard-won operational lessons now in `CLAUDE.md § 9`.

**Verified live, not assumed:** `kubectl` context is `minikube`. AWS credentials are **rejected** — `InvalidClientTokenId` — and no profile exists for account `314146298861`. Configured profiles are `uzio-nonprod-audit`, `default`, `scripttest`, all work-account, with `default` on `us-east-1`. Logged as `E-00`, now the first blocker in the deploy chain.

### 2026-08-29 — n8n added as a fourth component

- Owner has a self-hosted n8n instance with an existing workflow, and expects to build more. Confirmed: self-hosted (Docker/local), and it gets its own repo, consistent with the one-repo-per-component pattern.
- Scaffolded `n8n/` as a git repo on `master`: `workflows/`, `scripts/pull-workflows.sh`, `.env.example`, README, `.gitignore` (blocks `.env` and any credential export), `.gitattributes`.
- Added `.gitattributes` with `eol=lf` after observing git warn about CRLF conversion. The scripts run in WSL; a CRLF shebang fails there with a misleading `bad interpreter` error. Prevented rather than debugged later.
- Verified `.env` is ignored (`git check-ignore` matches `.gitignore:2`) and that the script passes `bash -n`.
- Added the n8n API key handling rules to `CLAUDE.md § 4`: source-and-reference only, never print the file or the variable, never `curl -v`, never ask the owner to paste the key into chat.
- Docker Desktop was not running, so nothing was pulled from the live instance yet — that is `N-04`.
- Noted `N-05`: the n8n encryption key in `~/.n8n` needs backing up outside the repo. Losing it makes every stored credential unrecoverable.

### 2026-08-29 — Teaching mandate and the `learn/` folder

- Owner clarified the working model: this project began as a manual, step-by-step learning exercise with Claude chat, and the move to Claude Code was for **speed, not for outsourcing the understanding**. Claude Code must teach at every step, not silently complete the work.
- Added `CLAUDE.md § 2 — How we work: teach, don't just ship`, and renumbered the sections that followed. It is placed second, immediately after the objective, because it governs *how* every other task is carried out.
- Sharpened the § 1 objective: app-hub is the permanent home for **every** app the owner builds for daily use — not a one-off project that ends with `links-service`.
- Created `learn/` with an index (`learn/README.md`) and the first entry, `00-project-setup-and-governance.md`, covering the audit findings, the no-root-repo trap, the WSL/Windows split, and a walkthrough of both high-severity bugs.
- Made the learning file part of the definition of done in `CLAUDE.md § 7` and `README.md § Governance`.
- Logged `P-07` to backfill learning files for the ~7 steps completed before this folder existed.

### 2026-08-29 — Project documentation and baseline audit

- Audited the whole workspace: 3 independent git repos, 6 source files, 2 manifests, 7 Terraform files.
- Established `CLAUDE.md`, `README.md`, and `PROGRESS.md` at the root to stop objective drift across sessions.
- Confirmed with the owner: all three project goals are live; EKS is canonical, minikube is local-only.
- Mapped the environment split — `terraform`/`uv`/`python3` are WSL-only, while `docker`/`kubectl`/`helm`/`aws` are on Windows. Recorded in `CLAUDE.md § 5` because it silently breaks any command that assumes one shell.
- Found 10 defects, `D-01` through `D-10`. Two are high severity: the `POST /links` storage bug and the in-memory-state-with-2-replicas conflict.
- **No code was changed.** Everything above is documentation and analysis only.

### Earlier — from git history (pre-dating this log)

- `infra`: Terraform scaffold → VPC module → EKS cluster with admin access → outputs → ECR repository → `force_delete` for easier teardown (6 commits)
- `links-service`: uv project with FastAPI → `/health` endpoint → CRUD operations (3 commits). Dockerfile added but never committed.
- `manifests`: links-service Deployment and Service (1 commit)
