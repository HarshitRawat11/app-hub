# PROGRESS.md — app-hub

Live status board. **Update this at the end of every working session** — status, blocker, next step, plus a line in the log.

**Last updated:** 2026-09-09

---

## ▶ START HERE NEXT SESSION

**Claude: surface this block first, before anything else.**

### ✅ Nothing is deployed — verified clean at 2026-08-31 · 17:05 IST

**Phase 2 is complete** (`E-02`–`E-05`) and everything was torn down afterwards: `Destroy complete! Resources: 55 destroyed`, with a full orphan audit showing no clusters, NAT gateways, load balancers, VPC, EC2, EBS volumes or unassociated EIPs. **$0/hour.**

Confirm before assuming — it takes two seconds:

```bash
wsl -e bash -lc "aws eks list-clusters --region ap-south-1 --output text; aws ec2 describe-nat-gateways --filter Name=state,Values=available --region ap-south-1 --query 'NatGateways[*].NatGatewayId' --output text; aws elbv2 describe-load-balancers --region ap-south-1 --query 'LoadBalancers[*].LoadBalancerName' --output text; aws ec2 describe-volumes --filters Name=status,Values=available --region ap-south-1 --query 'Volumes[*].VolumeId' --output text"
```

All empty = clean. **To bring it back up**, the whole loop is proven and documented in `learn/16`; budget ~15 min for `terraform apply`, and remember `aws eks update-kubeconfig` from **WSL** afterwards.

**When tearing down again, order matters** (`learn/15`): delete LoadBalancer Services first so their ENIs release, then empty ECR **with `--filter tagStatus=ANY`** (the default hides untagged digests), then `terraform destroy`, then audit for orphans.

### ✅ The email path is fixed — but `cost-watchdog` is still unproven

`D-13` is **resolved** (2026-09-05). Both workflows moved off Gmail OAuth to `emailSend` with an SMTP credential, which removes the ~7-day refresh-token expiry for good. `destroy-notifier` is verified end to end: both branches route correctly and SMTP reported the mail accepted.

**Still outstanding (`N-01b`):** `cost-watchdog` has the same fix applied but has **never actually sent an email**, because it cannot be tested without a cluster. It has no manual-run endpoint (the public API returns `405`), and with no cluster the EKS call 404s and `onError: stopWorkflow` halts it before the email node — which is correct behaviour, not a fault.

**So the next time a cluster is up, click "Test workflow" on `cost-watchdog` in the n8n UI.** Thirty seconds, and it closes the last gap in the cost safety net. Until then, still verify teardown with `make status` rather than trusting an email that has never been observed to arrive.

### There is now a Makefile — use it

Run from **WSL**. `make` on its own prints the targets.

```bash
wsl -e bash -lc "cd /mnt/c/Users/harshit.rawat/Documents/Projects/app-hub && make status"
```

`make status` replaces the audit above. `make up` provisions **and refreshes the kubeconfig**. `make down` runs the whole teardown in the correct order. `make validate` works with no cluster.

### ⚠️ First thing when the cluster next comes up

`R-01`–`R-04` (namespace, resource limits, securityContext, immutable tags) were all added on 2026-09-03 **without a cluster to test against**. They pass offline validation and the image was verified locally under `docker run --read-only`, but the `securityContext` and the restricted Pod Security Standard have **never been enforced by a real API server**. If `make deploy` fails at admission, that is why — read the rejection message for the specific field.

Also: `R-03` set ECR to `IMMUTABLE`, which only takes effect on the next `terraform apply`.

### ⚠️ The work split changed on 2026-09-09 — read `CLAUDE.md § 2` before writing anything

The old rule ("the owner hand-writes every new concept, including application code") has been **replaced**. The new rule is **hand-build what the owner is learning, delegate what is merely scaffolding for it.**

- **Claude now writes, without asking:** application code, Dockerfiles, tests, Makefile targets and scripts, boilerplate refactors, the docs, and Kubernetes manifests that are a *second instance of an object type the owner has already written*.
- **The owner still writes, after explanation and before review:** Terraform they have not written, Kubernetes manifests introducing a *new object type*, PromQL and alert rules, Grafana dashboards, Helm values, ArgoCD `Application`s, Jenkins pipelines, n8n GUI work — and **any infra failure gets debugged by them, not fixed for them** (20-minute time-box while the cluster bills).

`learn/` files are now written for **hand-built work only**. Delegated work gets a `PROGRESS.md` note instead.

### Then, in priority order — reordered 2026-09-09 so the owner is never idle

The naive order put four delegated tasks in front of `R-05`, which would have meant several sessions of the owner watching Claude write application code while Prometheus — the material they actually need for work — waited at the back. Reordered to run the two tracks in parallel:

1. **`S-01` steps 4–5 — Claude.** Steps 1–3 are owner-written and committed. Step 4 (`LINKS_SERVICE_URL`) and step 5 (Dockerfile) are now delegated: config plumbing and a copy of the `links-service` Dockerfile. No cluster, no cost. Also carries the `detail=str(e)` leak fix.

2. **`C-04` persistent stack + DynamoDB — OWNER, in parallel with the above.** This is the priority for the owner's own time. Terraform they have not written before, **needs no cluster, and costs ~$0** — DynamoDB on-demand bills nothing idle. Getting it wrong is free, which makes it ideal learning. Explanation first, then they write, then review.

3. **One batched cluster session** — bring the cluster up once and clear everything that needs it: `S-01` step 6 (ECR repo + manifests + deploy), `N-01b` (click **Test workflow** on `cost-watchdog` to finally prove it emails), and the **first real verification of `R-01`–`R-04`**, which have never been enforced by an actual API server. Tear down the same session.

4. **`R-05` Prometheus/Grafana — OWNER.** The real material: Helm values, dashboards, PromQL, and specifically translating Nagios checks the owner already knows from work. First stateful workload, so the PVC/EBS teardown checklist in `CLAUDE.md § 9` becomes mandatory from here.

5. **Background, Claude, between cluster sessions:** `C-02` tests (unblocks `C-06` immediately), `C-06` repository refactor, `S-02` aggregator, and the cosmetic defects `D-09`/`D-10`/`D-12`. These fill gaps rather than gating anything.

**Deferred, and still the owner's:** `C-05` IRSA (needs the cluster's OIDC provider), `E-06` Ingress + ALB controller, `R-06` Jenkins, `R-07` ArgoCD, `N-06` n8n on EKS.

---

## Where the project stands

**Milestone 2 is COMPLETE.** On 2026-08-31 the loop was rebuilt end to end on real EKS with every known defect fixed: `terraform apply` → build → push to ECR → deploy → reach `/health` by Kubernetes DNS name. Verified in-cluster, not just locally.

**Currently nothing is deployed, and that is the correct resting state.** Torn down 2026-08-31 · 17:05 IST after Phase 2 completed, verified clean by a full orphan audit. The cluster only exists while it is being worked on.

What that leaves:

- **`E-00` is resolved.** AWS credentials for `314146298861` (`terraform-learning`) live in **WSL's own `~/.aws/`**, separate from the Windows-side `.aws` holding untouched work profiles. Proven this session by a real `terraform apply`.
- **Phase 2 complete 2026-08-31** (`E-02`–`E-05`). Provisioned 55 resources, pushed the image, deployed, reached `/health` by Kubernetes DNS name, then exposed publicly via an NLB and verified full CRUD from the internet. Torn down cleanly afterwards — 55 destroyed, no orphans.
- **Code state:** `C-01`, `D-03`, `D-11` fixed and **verified on the cluster**, not just in a container. `replicas` pinned to 1 (`C-03` stopgap). Remaining: no tests yet (`C-02`), storage still ephemeral until `C-04`–`C-06`.
- **`kubectl` context:** Windows says `minikube`, WSL says `app-hub-eks`. They are **separate config files**. Run EKS-facing commands from WSL only (`CLAUDE.md § 5`, `learn/11`).

- **The work split changed on 2026-09-09** — application code, Dockerfiles, tests, tooling and docs are now Claude's; Terraform, PromQL, Grafana, Helm values, ArgoCD, Jenkins, n8n GUI work, new Kubernetes object types and all infra debugging stay the owner's. See `CLAUDE.md § 2`; every open row below names its side.
- **`gateway` is half built** (`S-01`, steps 1–3 of 6, owner-written; steps 4–6 now Claude's). It runs locally on port 8001, proxies `GET /links` to `links-service`, and maps upstream failures to `502`/`503`/`504` — all verified live. Not containerised and not deployed yet.

**Next milestone — make it durable and repeatable:** finish `S-01` steps 4–5 (no cluster, no cost) → `C-02` (tests) → `C-04`/`C-05` (persistent DynamoDB stack + IRSA) → `C-06` (repository refactor, then raise replicas). `P-09` automates the loop so teardown is never skipped. `S-01` step 6 and `E-06` (shared ALB) fold into whichever session next brings the cluster up.

---

## Status board

Status values: `Not started` · `In progress` · `Blocked` · `Done` · `Needs verification`

### Phase 0 — Project hygiene

| ID | Task | Status | Blocker | Next step |
|----|------|--------|---------|-----------|
| P-01 | Version-control the root docs (`CLAUDE.md`, `README.md`, `PROGRESS.md`, `CONTEXT-BRIEF.md`, `learn/`) | **Done** | None | Done 2026-08-30 (`2dfcc93`). Chose an **umbrella repo at the root** that tracks only the cross-cutting docs and gitignores `infra/`, `links-service/`, `manifests/`, `n8n/` so they stay fully independent. Remote not created yet — see `P-08`. |
| P-02 | Commit the untracked `links-service/Dockerfile` | **Done** | None | Committed 2026-08-30 as `5e312ef`, after fixing `P-03` and `D-11` in the same file |
| P-03 | Fix Dockerfile base image / Python version mismatch | **Done** | None | Committed 2026-08-30 as `5e312ef`. Base moved to `python:3.14-slim` (verified to exist, currently 3.14.7) so the tag matches `requires-python >=3.14`. Fixed together with `D-11`. |
| P-04 | Rename `infra/vairables.tf` → `infra/variables.tf` | **Done** | None | Committed 2026-08-30 as `3cb9e57` via `git mv` (staged as a rename). `terraform validate` passes, `terraform fmt -check` clean. |
| P-05 | Remove or populate the empty `infra/main.tf` | **Done** | None | Removed 2026-08-30 in `3cb9e57`. Terraform loads all `.tf` files, so `main.tf` is convention only — nothing depended on it. |
| P-06 | Write `links-service/README.md` | **Done** | None | Committed 2026-08-30 as `f3203de`. Covers the API table, local + Docker run, and an explicit storage caveat pointing at `C-03`. |
| P-07 | Backfill `learn/` files for the steps done before this folder existed | **Done** | None | Done 2026-08-30: wrote `learn/01`–`07` (FastAPI, Docker/uv, Terraform+state, VPC, EKS, ECR, K8s manifests) from committed code and git history. Renumbered the two recent files to `08`/`09` so the folder reads chronologically. |
| P-08 | Create the `app-hub` GitHub remote for the umbrella docs repo and push | **Done** | None | Done 2026-08-30. Repo existed but empty and no local remote was configured; wired `origin` and pushed 3 commits. `git@github.com:HarshitRawat11/app-hub.git` |
| P-09 | Automate the deploy path so `update-kubeconfig` is never a remembered step | **Done** 2026-09-03 · 11:25 IST | `up`/`deploy`/`down` not yet exercised against a live cluster — `status` and `validate` are verified. | Root `Makefile`, run from WSL. `status` (am I billing?), `up` (apply + **update-kubeconfig** + verify nodes), `deploy` (build + push SHA tag + pin the manifest + apply + verify), `down` (delete LB Services → wait → delete PVCs → empty ECR with `tagStatus=ANY` → destroy → audit), `validate` (offline). A `guard` target fails fast with a clear message if run from Windows instead of WSL. Also added `scripts/validate-manifests.py`. See `learn/19`. |

### Phase 1 — Correctness

| ID | Task | Status | Blocker | Next step |
|----|------|--------|---------|-----------|
| C-01 | Fix `POST /links` storing the wrong object | **Done** | None | Committed 2026-08-30 as `7b7b0bd`. Verified by HTTP round-trip: `POST` then `GET /links` now both return `"id":1`. |
| C-02 | Add tests for the links CRUD endpoints | Not started — **CLAUDE's to write** (reassigned 2026-09-09) | None. **Was** held back for the owner to write; the `CLAUDE.md § 2` revision moves tests to Claude. | ✅ `pytest` + `httpx` added as dev deps. Claude writes `tests/test_links.py` using FastAPI `TestClient`, covering create → list → get → delete plus the two 404 paths. **The trap to handle:** `links_db` and `next_id` are module-level, so state leaks between tests — needs an `autouse` reset fixture. **The owner reviews the coverage list, not the code** (`CLAUDE.md § 2`). Background reference: `learn/14`. **Unblocks `C-06`.** |
| C-03 | Decide how link data persists across pods | **Decided** 2026-08-30 | None | **Decision: DynamoDB in a separate persistent Terraform stack, accessed via IRSA.** Rationale: the cluster is destroyed every session, so anything durable must live outside the destroyed stack; DynamoDB on-demand costs ~$0 idle, unlike RDS which bills continuously. Stopgap applied: `replicas` pinned to 1 (`93cea2c`) — removes inconsistent reads, does not add durability. Implementation split into `C-04`–`C-06`. See `learn/13`. |
| C-04 | Create the `persistent/` Terraform stack with the DynamoDB table | Not started — **OWNER's to write.** Priority 2, runs in parallel with `S-01` steps 4–5 | **No cluster needed** — a DynamoDB table has no dependency on EKS, and on-demand billing means an idle table costs ~$0. Getting it wrong is free. | Terraform the owner has not written before, so: **explanation first, then they write, then Claude reviews** (`CLAUDE.md § 2`). New directory, **own S3 state key** (`persistent/terraform.tfstate` — NOT the same key as `infra/`, or the two stacks overwrite each other's state). Declares the table only; the IRSA role belongs in `infra/` — see `C-05`. Never destroyed. See `learn/13`. Gets a `learn/` file, since it is hand-built. |
| C-05 | Wire IRSA: annotate the ServiceAccount, trust the OIDC provider | Not started — **OWNER's to write, in full** | **Needs the cluster up** — the trust policy references the cluster's OIDC provider. Depends on `C-04`. | **Both halves are the owner's** under the revised `CLAUDE.md § 2` — the Terraform IAM role and trust policy because it is Terraform they have not written, and the `ServiceAccount` because it is a Kubernetes object type they have not written. The object-type line is what keeps this task whole instead of split down the middle. <br><br>**Design correction (2026-09-03):** the IRSA role does NOT belong in the persistent stack. EKS issues a **new OIDC issuer URL on every cluster creation**, so a role whose trust policy names it would break on each rebuild. Correct split: **`persistent/` holds only the data** (the DynamoDB table, which genuinely outlives everything); **`infra/` holds the IRSA role**, because it is cluster-scoped and cheap to recreate. The persistent stack exports the table ARN; `infra/` consumes it and grants access. Cluster needs its OIDC provider enabled; trust policy scoped to the specific namespace + ServiceAccount; `eks.amazonaws.com/role-arn` annotation on the SA. No stored credential anywhere. |
| C-06 | Refactor `links-service` to a repository layer and swap to DynamoDB | Not started — **CLAUDE's to write** (reassigned 2026-09-09) | **Depends on `C-02`** — do not refactor storage without tests. Also needs `C-04` for a table to point at. | Application code and storage layer, so delegated under `CLAUDE.md § 2`. Extract a `LinkRepository` interface with in-memory + DynamoDB implementations. Move id generation off the `global next_id` counter (UUID/ULID preferred). Then raise `replicas` back above 1. **Note the boundary:** the code is Claude's, but if DynamoDB access fails once deployed that is an **IRSA** failure — infra, therefore the owner's to debug. |

### Phase 2 — First end-to-end deploy

| ID | Task | Status | Blocker | Next step |
|----|------|--------|---------|-----------|
| E-00 | Configure an AWS profile for the app-hub account | **Done** | None | Resolved 2026-08-30: `aws configure` run **inside WSL** (`~/.aws/`, separate from the Windows-side `.aws`), profile `default`, region `ap-south-1`, user `terraform-learning`, account `314146298861` confirmed via `sts get-caller-identity`. Windows-side `default` (work profiles) verified untouched and still rejected. `terraform init` now succeeds. |
| E-01 | Confirm whether `terraform apply` has ever run against the S3 backend | **Resolved** | None | **Answered by project history 2026-08-30: yes.** The full loop was proven once — image built, pushed to ECR, deployed to EKS, 2 pods `Running`, ClusterIP routing and Kubernetes DNS discovery confirmed — then torn down with `terraform destroy` per the cost policy. "Nothing deployed" is the normal resting state, not a failure. Live re-verification is blocked on `E-00`. |
| E-02 | Re-provision the infra (VPC + EKS + ECR) | **DONE** 2026-08-31 · ~16:10 IST | None | Owner ran `terraform apply`. Created: VPC `vpc-0c3e0c493dec78d8e`, NAT `nat-007a005277aac306c`, EKS `app-hub-eks` (1.31, platform `eks.68`), node group `default-20260831104239047500000013`, ECR repo. Both nodes `Ready` on `10.0.1.184` / `10.0.2.247` with **no external IP** — confirming private subnets. **Cluster is UP and billing.** 
| E-03 | Build and push `links-service:v1` to ECR | **DONE** 2026-08-31 · 16:13 IST | None | Built and pushed from **WSL via `docker.exe`**, digest `sha256:d9caf579…`, 70.7 MB. Done in parallel with the EKS control plane still `CREATING` — the push depends only on ECR, not the cluster. Note two **untagged** buildkit attestation digests also landed; `batch-delete-image --image-ids imageTag=v1` will not remove those at teardown (`learn/15`). 
| E-04 | Deploy manifests to EKS and reach `/health` | **DONE** 2026-08-31 · 16:15 IST | None | `kubectl apply` → 1 pod `Running` on `10.0.2.118`, Service ClusterIP `172.20.10.137`, endpoints resolved correctly. **Verified in-cluster by DNS name**: `curl http://links-service:8000/health` → `{"status":"ok"}`. Full CRUD round-trip passed, and `GET /links` returned `"id":1` — the `C-01` fix confirmed on real EKS. `GET /links/999` → 404. 
| E-05 | Expose the service outside the cluster | **DONE** 2026-08-31 · 16:32 IST | None | Switched the Service to `type: LoadBalancer` with the NLB annotation (`99381d0`), listening on port 80. Public at `a79280cd18615491e88aa093ea8dd157-273fe97dadab1bf9.elb.ap-south-1.amazonaws.com`. NLB took ~110s to go `provisioning` → `active`. Verified externally: full CRUD, 404 path, and `/docs` all reachable. **Right-sized for one service only** — see `E-06`. 
| E-06 | Migrate from per-service LoadBalancer to a shared ALB via Ingress | Not started — **OWNER's to write, in full** | `Ingress`/`IngressClass` are Kubernetes object types the owner has not written, and the ALB controller's Helm values are on the hand-write list — so this stays whole rather than splitting. Wait until `gateway` is deployed, so there are actually two services to route between. | Every `type: LoadBalancer` Service provisions its **own** ELB — N services means N load balancers and N bills. An Ingress + the AWS Load Balancer Controller gives one shared ALB with path-based L7 routing. Premature with a single service; the right move once there are two. |

### Phase 3 — Production readiness

| ID | Task | Status | Blocker | Next step |
|----|------|--------|---------|-----------|
| R-01 | Add resource requests and limits to the Deployment | **Done** 2026-09-03 · 11:20 IST | None | `e073761`. requests 50m/64Mi, limits 500m/256Mi → **Burstable** QoS. Previously **BestEffort**, i.e. first evicted under node pressure. Numbers are starting points, not measurements — revisit once `R-05` shows real usage. 
| R-02 | Add a `securityContext` (non-root, read-only rootfs) | **Done** 2026-09-03 · 11:20 IST | Cluster-side enforcement not yet confirmed — needs a real `make up && make deploy`. | `98f355b` + `e073761`. Dockerfile creates `appuser` uid 10001 and switches to it; Deployment sets `runAsNonRoot`, matching uid, `readOnlyRootFilesystem`, drops ALL capabilities, RuntimeDefault seccomp. **Verified locally**: the image runs as uid 10001 and serves fine under `docker run --read-only` with no tmpfs mounted at all. |
| R-03 | Replace the mutable `:v1` tag with immutable tags | **Done** 2026-09-03 · 11:20 IST | None | `c06d65f`. `image_tag_mutability = "IMMUTABLE"` in `ecr.tf`; the Makefile derives the tag from the links-service commit SHA (a dirty tree gets a timestamp suffix so the push stays unique). A tag now names exactly the code it was built from. **Takes effect on the next `terraform apply`.** |
| R-04 | Deploy into a dedicated namespace | **Done** 2026-09-03 · 11:20 IST | None | `e073761`. New `00-namespace.yaml` (the `00-` prefix is load-bearing — `kubectl apply -f dir/` goes in filename order and everything else references the namespace). Enforces the **restricted** Pod Security Standard, so non-compliant manifests are rejected at admission rather than quietly running as root. 
| R-05 | Observability: **Prometheus / Grafana via `kube-prometheus-stack`** | Not started — **OWNER's to write, in full.** Priority 4 — the real material | Depends on `E-04`. **Phase 2 in the owner roadmap — comes before CI/CD.** | Helm chart. Note this is *why* the node group is EC2 and not Fargate: `node-exporter` is a DaemonSet, which Fargate does not support. First stateful workload — the PVC/EBS teardown checklist in `CLAUDE.md § 9` becomes mandatory from here on. |
| R-06 | CI: **Jenkins in-cluster via Helm** | Not started — **OWNER's to write** (pipeline definitions + Helm values) | Depends on `R-05` landing first (owner roadmap phase 3) | Build, test, push image, then **commit a bumped image tag into the `manifests` repo**. Jenkins must never run `kubectl apply` — that is ArgoCD deliberately (see Decisions). |
| R-07 | CD: **ArgoCD, GitOps from `app-hub-manifests`** | Not started — **OWNER's to write** (`Application` definitions) | Depends on `R-06` (owner roadmap phase 4) | ArgoCD watches the manifests repo and reconciles. Current state is *GitOps-shaped, not GitOps*: declarative and versioned, but still applied by hand. ArgoCD supplies the missing reconciliation half. |

### Phase 4 — n8n workflows

Self-hosted n8n. Workflow definitions are version-controlled in `n8n/`; credentials never are.

| ID | Task | Status | Blocker | Next step |
|----|------|--------|---------|-----------|
| N-00 | `cost-watchdog` — ✅ **working, published/active** | None | Schedule Trigger (5 PM + 9 PM, two rules) → HTTP Request → Gmail. Calls `GET https://eks.ap-south-1.amazonaws.com/clusters/app-hub-eks` with Predefined Credential Type → AWS (IAM) → `n8n-readonly`. **On Error must be `Stop Workflow`** — 404 (cluster gone) halts silently, 200 (still up) proceeds to Gmail. Gmail via OAuth2, Google Cloud project `n8n-app-hub`. |
| N-00b | `destroy-notifier` | **Done** 2026-09-05 · 16:25 IST | None | All four nodes wired (`Webhook → If → Success/Failure`), active, using `emailSend` + SMTP. **Verified end to end:** success payload → `Success` node, failure payload → `Failure` node, both with SMTP reporting `accepted:[...], rejected:[]`. Committed `51a7aab`. Remaining follow-up: schedule `scripts/scheduled-destroy.sh` via Windows Task Scheduler. |
| N-01b | Prove `cost-watchdog` actually sends its email | **Needs verification — OWNER** (n8n GUI) | Cannot be tested without a cluster — no manual-run endpoint (API returns `405`), and with no cluster the EKS call 404s and `onError: stopWorkflow` halts before the email node. | **Next time a cluster is up**, click **Test workflow** on `eks-cost-watchdog` in the n8n UI. The HTTP Request should get a 200 and the email should fire. Thirty seconds, and it closes the last gap in the cost safety net. |
| N-01 | Scaffold the `n8n/` repo | Done | None | Done 2026-08-30: git repo, `.gitignore`, `.gitattributes` (LF enforcement), `.env.example`, `pull-workflows.sh`, README with security rules |
| N-02 | Create the `app-hub-n8n` GitHub remote and push | **Done** | None | Done 2026-08-30. The scaffold had **zero commits** — made the initial commit, wired `origin`, pushed. Secret-scanned before pushing; no real `.env` exists. |
| N-03 | Populate `n8n/.env` with the instance URL and API key | **Done** 2026-08-31 | None | Verified: both values populated, `.env` matched by `.gitignore:2`, absent from `git status`. API returns **HTTP 200** and lists both workflows (`eks-cost-watchdog`, `terraform-destroy-notifier`). Key never entered the transcript. |
| N-04 | Pull the existing workflows into `n8n/workflows/` | **Done** 2026-08-31 | None | Pulled 2 workflows via the API (`065b447`): `eks-cost-watchdog` (active) and `terraform-destroy-notifier` (inactive). Count checked against `jq .data | length` **before** writing — an earlier grep had matched nested node names and suggested 14. Secret-scanned: only credential *references* (`AWS (IAM) account`, `Gmail account`), no values. |
| N-05 | Back up the n8n encryption key outside the repo | **Done** 2026-08-31 (owner-reported) | None | Owner confirms the key from the `n8n_data` volume (`/home/node/.n8n/config`) is stored in a password manager. Not independently verifiable by design — nothing in this repo should ever be able to see it. Unblocks `N-06`. |
| N-06 | Move n8n onto the EKS cluster | **Decided: YES** (2026-08-30) — **mostly OWNER**: `ConfigMap`/`Secret`/`PVC` and Helm values are new object types and hand-write items; the Deployment/Service are second instances, so Claude's | Depends on Phase 2 landing first. Not urgent — local Docker is fine meanwhile. | Needs: a Postgres backing store (n8n defaults to SQLite, unsuitable in a pod), `N8N_ENCRYPTION_KEY` supplied as a Kubernetes Secret (**must be the existing key from `~/.n8n`, or every stored credential becomes undecryptable** — see `N-05`), and persistent storage. Note this interacts with the destroy-every-session policy: the database must live outside the destroyed stack. See the `C-03` note on splitting Terraform into ephemeral and persistent stacks. |

### Phase 5 — Further services

| ID | Task | Status | Blocker | Next step |
|----|------|--------|---------|-----------|
| S-01 | Build `gateway` — entry point, routes to `links-service` by Kubernetes DNS name | **In progress — owner writing.** Steps 1–3 of 6 done 2026-09-06/07 | None for steps 4–5. Step 6 needs a cluster. | **Repo `app-hub-gateway` exists and is pushed** (sixth repo — `CLAUDE.md § 3`). Owner writes every line; Claude reviews and verifies. Six-step build order and rationale in `learn/21`. <br><br>**Done:** (1) skeleton + `/health` on port **8001** — `36feb40`, 2026-09-06 · 12:22 IST. (2) `GET /links` calling `links-service`, `async def` + `httpx.AsyncClient`, client moved to app scope via `lifespan` — `7c52711`/`1d5c088`, 2026-09-07 · 11:27–13:27 IST. (3) explicit 3s client timeout + upstream failure mapping — `261e5db`, 2026-09-07 · 18:35 IST. **All four paths verified live** against a fake upstream: nothing listening → `503`; hangs 30s → `504` at 3.01s; upstream 4xx/5xx → `502`; healthy → `200`. <br><br>**Steps 4–6 reassigned to Claude on 2026-09-09** by the `CLAUDE.md § 2` revision — step 4 is config plumbing, step 5 is a copy of the `links-service` Dockerfile, and step 6's Deployment/Service are second instances of object types the owner has already written. Steps 1–3 stay owner-written and are not to be rewritten. <br><br>**Step 4 DONE** 2026-09-09 · 13:10 IST (`cb39f11`, Claude-written). `LINKS_SERVICE_URL` read at module scope with `.rstrip("/")`; the `503`/`504` handlers no longer pass `str(e)` to the caller, so the upstream URL stops leaking — fixed strings out, real exception to the log. Added `tests/fake_upstream.py` (port + mode aware: `ok`/`404`/`html500`/`slow`). **Verified, five cases against a freshly started gateway:** unset → `200`; `:9999` → `503`; `:8000/` → `200` (rstrip); `:8002` 404 → `502`; `:8003` slow → `504` at 3.02s. Bodies carry no URL. <br><br>**Next: step 5** — Dockerfile, copy the `links-service` one, port 8001, test under `docker run --read-only`. Then step 6 (ECR repo + manifests + deploy — the only step that costs money, batched into the next cluster session). <br><br>**`learn/22` will not be written** — steps 4–6 are delegated, and `learn/` is for hand-built work only. `learn/21` already carries the design rationale; treat it as reference, not a pending assignment. |
| S-02 | Build `aggregator` — calls `links-service` internally; **the service that truly proves discovery** | Not started — **CLAUDE's to write** (reassigned 2026-09-09) | Deferred; background work between cluster sessions. Gates nothing. | Application code, named explicitly in the `CLAUDE.md § 2` delegation list. Distinct from `gateway`: `gateway` is the external entry point, `aggregator` exercises purely internal pod-to-pod discovery. Its Deployment/Service are second instances, so also Claude's; anything new in the manifest gets flagged in a few lines rather than walked through. |
| S-03 | Build `frontend` — static page / SPA talking to the gateway | Not started — **CLAUDE's to write** (reassigned 2026-09-09) | Depends on `S-01` | Application code. The actual dashboard UI — what makes app-hub a usable daily start page rather than an API. |

---

## Known defects

| ID | Severity | Where | What is wrong |
|----|----------|-------|---------------|
| ~~`D-01`~~ | **RESOLVED** 2026-08-30 (`7b7b0bd`) | [links-service/app/main.py:29](links-service/app/main.py:29) | `createLink` builds `new_link = Link(id=next_id, ...)` but then stores the *incoming* `link` (a `LinkCreate`, which has no `id`). It returns `new_link`, so `POST` looks correct — but `GET /links` and `GET /links/{id}` return records with no `id` field. Fix: store `new_link`. |
| `D-02` | **Mitigated** (was High) | [manifests/links-service/deployment.yaml](manifests/links-service/deployment.yaml) + [links-service/app/main.py:5](links-service/app/main.py:5) | `links_db` is an in-process dict, but the Deployment runs `replicas: 2`. **Inconsistent-read half fixed 2026-08-30** by pinning `replicas: 1` (`93cea2c`). Data is still lost on restart — durability lands with `C-04`–`C-06`. Do not raise replicas before then. |
| ~~`D-03`~~ | **RESOLVED** 2026-08-30 (`5e312ef`) | [links-service/Dockerfile:1](links-service/Dockerfile:1) | Base is `python:3.12-slim` while `pyproject.toml` requires `>=3.14` and `.python-version` says `3.14`. `uv sync` will silently download a managed Python 3.14 rather than use the base image's interpreter — bloating the image and making the base tag a lie. Tracked as `P-03`. |
| ~~`D-04`~~ | **RESOLVED** 2026-08-30 (`5e312ef`) | [links-service/Dockerfile](links-service/Dockerfile) | Untracked in git — the build is not reproducible from a clean clone. Tracked as `P-02`. |
| ~~`D-05`~~ | **RESOLVED** 2026-08-31 (`99381d0`) | [manifests/links-service/service.yaml](manifests/links-service/service.yaml) | Was: `ClusterIP` with no Ingress meant the app was unreachable from outside the cluster. Fixed by `E-05` — the Service is now `type: LoadBalancer` with the NLB annotation, and full CRUD was verified from the internet. **Note the follow-on cost concern, tracked separately as `E-06`:** one LoadBalancer Service means one ELB and one bill, so this does not scale past a couple of services. |
| ~~`D-06`~~ | **RESOLVED** 2026-08-30 (`3cb9e57`) | [infra/vairables.tf](infra/vairables.tf) | Filename typo (`vairables` → `variables`). Terraform loads all `.tf` files so behaviour is unaffected, but it reads as sloppy in a portfolio repo. Tracked as `P-04`. |
| ~~`D-07`~~ | **RESOLVED** 2026-08-30 (`3cb9e57`) | [infra/main.tf](infra/main.tf) | Empty file (0 bytes). Tracked as `P-05`. |
| ~~`D-08`~~ | **RESOLVED** 2026-08-30 (`f3203de`) | [links-service/README.md](links-service/README.md) | Empty file (0 bytes), yet referenced as `readme` in `pyproject.toml`. Tracked as `P-06`. |
| `D-09` | Low | [links-service/pyproject.toml:4](links-service/pyproject.toml:4) | `description = "Add your description here"` — leftover scaffold text. |
| ~~`D-11`~~ | **RESOLVED** 2026-08-30 (`5e312ef`) | [links-service/Dockerfile:8](links-service/Dockerfile:8) + `:14` | Build runs `uv sync --frozen --no-install-project`, but `CMD` uses `uv run`, which re-resolves and installs the project **at container start**. That defeats the build-time sync, moves dependency work into startup (slowing pod readiness, risking a cold-start failure), and will bite when the base image changes. Fix: install the project at build time and invoke `uvicorn` directly in `CMD`. Missed in the 2026-08-30 audit; surfaced from project history. |
| `D-10` | Low | [links-service/app/main.py](links-service/app/main.py) | Function names are `camelCase` (`getLinks`, `createLink`, `removeLink`), against PEP 8. Cosmetic, but easy to fix before the file grows. |
| ~~`D-13`~~ | **RESOLVED** 2026-09-05 (`51a7aab`) | n8n credential | Was: the Gmail OAuth refresh token expired, silently disabling **both** workflows -- `cost-watchdog` shared the credential, so it reported `active` but could not email. **Fixed by moving both workflows off Gmail OAuth to `emailSend` nodes with an SMTP credential**, which removes the ~7-day refresh-token expiry entirely. Verified: `destroy-notifier` executions now report `status=success`, and the SMTP server returned `accepted:[harshitrawat2011@gmail.com], rejected:[]` on both branches. **`cost-watchdog` remains unverified end to end** -- see `N-01b`. |
| `D-12` | Low | `infra/`, `links-service/`, `manifests/` | No `.gitattributes`, so git warns `LF will be replaced by CRLF` on every commit. Harmless for Python and exec-form `CMD`, but the same setting that breaks shell scripts under WSL (see `learn/08`). `n8n/` already has one. Add `* text=auto eol=lf` to the other three. |

---

## Decisions on record

| Date | Decision | Rationale |
|------|----------|-----------|
| 2026-09-09 | **The work split changed: hand-build the learning, delegate the scaffolding.** Application code, Dockerfiles, tests, Makefile targets, scripts, boilerplate and the docs go to Claude. Terraform, PromQL/alert rules, Grafana dashboards, Helm values, ArgoCD, Jenkins, n8n GUI work, **Kubernetes manifests introducing a new object type**, and **all infra debugging** stay with the owner — explanation first, then they write, then review. | Owner request, with evidence. Hand-writing application code was a misallocation: real time went into Python fundamentals (scoping, dict vs set, list append) that taught nothing about infrastructure, while every durable lesson in `learn/` came from an infra failure debugged by hand. The application was never the point — it exists so the cluster has something real to run. **Supersedes the 2026-08-30 "do not build ahead" decision below for the application layer only.** Recorded in `CLAUDE.md § 2`. |
| 2026-09-09 | **Kubernetes manifests split by object type, not wholesale** | Delegating all manifests would have handed away every object type the owner has not met — `Ingress`, the IRSA `ServiceAccount`, `PVC`/`StatefulSet`, `ServiceMonitor` — while EKS is item 2 on the learning list. Second instances of `Deployment`/`Service` go to Claude; a manifest introducing a new object type stays with the owner. This also keeps `C-05` and `E-06` whole rather than split mid-concept. |
| 2026-09-09 | **`learn/` files are written for hand-built work only** | `learn/` is the record of what the owner actually learned, not an index of everything that happened. A learning file about a Dockerfile they never wrote documents nothing. Delegated work gets a `PROGRESS.md` note instead. Consequence: `learn/14` and `learn/21` were written as *"guide, not a record — for the owner to write"*, and both subjects are now delegated; their content stands as reference, their framing is void. |
| 2026-09-09 | **Infra debugging is time-boxed to 20 minutes while the cluster is up** | Socratic debugging and cost discipline pull against each other at roughly $0.20–0.30/hour. So: walk the owner toward the answer for 20 minutes, then announce the box is up and give it. No clock when the cluster is down or the problem reproduces locally. Bugs in Claude-written code are Claude's to fix — making the owner debug those is the exact misallocation this split removes. |
| 2026-08-30 | **Every step must be taught, not just done** — explained in-session and written up in `learn/`. A step without its learning file is not finished. | Owner started this project learning manually with Claude chat and moved to Claude Code for speed, not to outsource the understanding. Recorded in `CLAUDE.md § 2`. |
| 2026-08-30 | app-hub is the permanent home for every app the owner builds for daily use — not a one-off project around `links-service` | Owner-confirmed. Means designing for a hub that grows. |
| 2026-08-30 | app-hub serves three goals at once: learning platform, real daily-use software, and portfolio piece | Owner-confirmed. Sets the quality bar above "works on my machine". |
| 2026-08-30 | AWS EKS (`ap-south-1`) is the canonical deploy target; minikube is a local sandbox only | Owner-confirmed |
| 2026-08-30 | **n8n will eventually run on EKS** (`N-06`) | Owner-confirmed. Implies a Postgres backing store and the existing encryption key as a Kubernetes Secret. Also forces the ephemeral-vs-persistent Terraform split, since a nightly-destroyed cluster cannot hold a database. |
| 2026-08-31 | **Every conversational response ends with a short summary in Indian English** | Owner request. The main answer stays in standard technical English; the recap is the part that has to land naturally. Cost and destructive items get repeated there deliberately. Written deliverables (`learn/`, READMEs, `PROGRESS.md`, commit messages) stay English-only. Recorded in `CLAUDE.md § 2`. |
| 2026-08-30 | ~~**Do not build ahead**~~ — **SUPERSEDED 2026-09-09 for the application layer.** Was: the first implementation of each new concept is written by the owner, by hand, even when slower. Still true for everything on the hand-write list in `CLAUDE.md § 2`; no longer true for application code, Dockerfiles, tests or tooling. | From project history. A finished artifact that skips the wrestling defeats the reason the project exists. Recorded in `CLAUDE.md § 2`. |
| — | **EC2 managed node groups, not Fargate** | Fargate does not support DaemonSets, and `kube-prometheus-stack`'s `node-exporter` is one — Fargate would break the Phase 2 observability work outright. Also closer to what a real EC2→EKS migration lands on. |
| — | **Jenkins builds and bumps a tag; ArgoCD deploys. Jenkins never runs `kubectl apply`.** | Clean separation of CI from CD. Jenkins pushes the image and commits a new tag into the `manifests` repo; ArgoCD notices the commit and reconciles. The cluster's desired state stays exactly what is in git. |
| — | **Each service must earn its place by teaching something distinct** | The service split exists to give the infra lessons something real to run — not to model a genuine domain. `gateway` teaches routing, `aggregator` teaches internal discovery, `frontend` makes it usable. |
| — | **Long-lived IAM access keys over IAM Identity Center / SSO** | Deliberate trade-off to unblock quickly. Known to be not-best-practice; recorded rather than pretended otherwise. |
| — | **Spring Boot dropped in favour of Python/FastAPI** | It would have been a fourth new thing to learn simultaneously. The language is not the lesson here; the infra is. |
| — | **EKS rather than self-hosted Kubernetes** | EKS cannot be self-hosted — it is AWS's managed control plane by definition. k3s/kubeadm on spare hardware would teach vanilla Kubernetes but skip IAM cluster auth, VPC CNI, ALB integration and EC2 node groups, which are the point. Parked as a deliberate follow-up comparison project. |
| — | **The S3 state bucket was created by hand** | The bootstrapping exception: Terraform cannot create its own backend. Versioning + AES256 enabled on `app-hub-tfstate-314146298861`. |
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

**Timestamps are IST (+05:30) and anchored to real commit times.** This machine runs two clocks — Windows on IST, WSL on UTC — so a bare time is ambiguous; always state the zone. Times marked `~` predate the umbrella repo, so they have no exact commit to anchor to.

**`TIMELINE.md` is the authoritative record** — it is generated from git across all six repos by `./scripts/timeline.sh`, so it cannot drift. This log carries the *narrative*; the timeline carries the *facts*. If they disagree, the timeline wins.

### 2026-09-09 · ~13:10 IST — `S-01` step 4, first delegated work under the new split

`gateway` now reads `LINKS_SERVICE_URL` (default `http://localhost:8000`) at module scope, with `.rstrip("/")` so a trailing slash cannot produce `...8000//links`. In-cluster the Deployment's `env:` block supplies `http://links-service:8000` — same image, no rebuild. Committed `cb39f11` in `app-hub-gateway`.

Also cleared the leak carried forward from step 3: the `503`/`504` handlers were passing `str(e)` to the client, and httpx includes the attempted URL in its message — which in-cluster is `http://links-service:8000/links`, i.e. internal topology handed to anyone who curls the public endpoint. Details are fixed strings now; the real exception goes to the log.

Added `gateway/tests/fake_upstream.py`, port- and mode-aware (`ok`/`404`/`html500`/`slow`). Worth noting the side benefit: **now that the address is configurable, testing the `502`/`504` paths no longer requires stopping the real `links-service`** — point `LINKS_SERVICE_URL` at the fake instead. The config boundary made its own tests easier.

**Verified — five cases, each against a freshly started gateway:** unset → `200`; `:9999` → `503`; `:8000/` → `200`; `:8002` (404) → `502`; `:8003` (hangs) → `504` at 3.02s. No URL in any response body.

**The instructive part was my own test harness, which reported all five as `200`.** `uv run uvicorn` spawns uvicorn as a *child*, so killing the `uv run` pid orphaned a server still bound to 8001; every later case silently hit the first, default-configured instance. The teardown helper then looped waiting for the port to free and **returned success anyway** when it never did. So a completely broken run looked like a clean pass — the same silent-success shape as the dead monitor (`learn/20`) and the dropped root commits in `timeline.sh`. Rewritten to kill by pattern, and to *assert* the port is free before starting and gone after stopping. Third instance of this failure mode in this project; the pattern is always "the check returned success because it never actually checked".

**No `learn/` file** — this was delegated work, and per the revised `CLAUDE.md § 2` `learn/` records what the owner hand-built. `learn/21` already carries the gateway design rationale.

### 2026-09-09 · ~12:00 IST — The work split changed

No code changed. The governing rule in `CLAUDE.md § 2` was replaced at the owner's request, and `PROGRESS.md` reallocated to match.

- **Old rule:** the owner hand-writes the first implementation of every new concept, application code included. **New rule:** hand-build what they are trying to learn, delegate what is merely scaffolding for it.
- **The owner's argument, which the evidence supports:** hand-writing application code was a misallocation. Real time went into Python fundamentals — variable scoping, dict versus set syntax, list append — none of which taught anything about infrastructure. Every durable lesson in `learn/` came from an infra failure debugged by hand: the new EKS endpoint hostname on rebuild, ECR refusing to be destroyed while holding images, WSL DNS, the n8n `onError` semantics. **The application was never the point; it exists so the cluster has something real to run.**
- **`CLAUDE.md § 2` was rewritten, not appended.** Its old table listed *"Scaffolding a concept they have not met yet"* and *"I went ahead and set it up for you"* under **Actively harmful** — both now correct behaviour for application code. Appending would have left a future session reading two contradictory policies and picking one at random.
- **Four ambiguities in the proposed split were resolved before writing it**, rather than papered over:
  - **Manifests split by object type, not wholesale.** Delegating all of them would have handed away `Ingress`, the IRSA `ServiceAccount`, `PVC`/`StatefulSet` and CRDs while EKS is item 2 on the learning list. This also stopped `C-05` and `E-06` splitting mid-concept.
  - **`learn/` files for hand-built work only.** Delegated work gets a `PROGRESS.md` note.
  - **Infra debugging time-boxed to 20 minutes while the cluster bills**, announced rather than slid into. Bugs in Claude-written code are Claude's to fix.
  - **Summary format fixed at 5–7 pointers**, keeping the existing colloquial register rather than formalising it.
- **Reassigned to Claude:** `C-02` (tests — unblocks `C-06`), `C-06`, `S-01` steps 4–6, `S-02`, `S-03`, `D-09`/`D-10`/`D-12`.
- **Confirmed as the owner's, and now whole rather than split:** `C-04`, `C-05`, `E-06`, `R-05`, `R-06`, `R-07`, `N-01b`, most of `N-06`.
- **Roadmap reordered, and this was the substantive finding.** The naive order put four delegated tasks ahead of `R-05`, which would have meant several sessions of the owner watching Claude write application code while Prometheus — the material they actually need at work — waited at the back. Now the two tracks run in parallel: Claude does `S-01` steps 4–5 while the owner writes `C-04` (Terraform, no cluster, ~$0 to get wrong), then one batched cluster session clears `S-01` step 6 + `N-01b` + the first real verification of `R-01`–`R-04`, then `R-05`. **Roughly two sessions to Prometheus instead of five.**

### 2026-09-06/07 — `S-01` started: `gateway` steps 1–3, owner-written

Four commits in the new `app-hub-gateway` repo, all owner-written; Claude explained the mechanisms first, then reviewed and verified. `learn/21` was written before any code existed, which is what the "do not build ahead" rule is for.

- **Step 1 (`36feb40`, 2026-09-06 · 12:22 IST)** — skeleton + `/health` on port **8001**. Plain `def`, correctly: it waits on nothing. Port 8001 is load-bearing — `links-service` owns 8000 and both run at once from step 2.
- **Step 2 (`7c52711` → `1d5c088`, 2026-09-07 · 11:27–13:27 IST)** — `GET /links` calling `links-service`. `async def` + `httpx.AsyncClient` + `await`, then the client moved off per-request creation to app scope via FastAPI `lifespan`, so connections pool. Verified by POSTing a link to 8000 and reading it back through 8001 — an empty `[]` proves nothing, since a working gateway and several broken ones both return it.
- **Step 3 (`261e5db`, 2026-09-07 · 18:35 IST)** — explicit 3s timeout on the client, and upstream failures mapped to the codes that name the right service. **All four paths verified live** against a purpose-built fake upstream: nothing listening → `503`; hangs 30s → `504` at 3.01s; upstream 4xx/5xx → `502`; healthy → `200`. `/health` deliberately does **not** check the upstream — that would let one outage kill gateway too.
- **The instructive bug:** the upstream-error case initially returned `200` with the error body passed through, then `500`, before reaching `502` — three different causes in sequence. The last was `detail=str(e)` in a block where `e` did not exist: **Python 3 deletes the `except ... as e` variable at the end of its block** ([PEP 3110](https://peps.python.org/pep-3110/)), to break the exception→traceback→frame→`e` reference cycle. So `e` is usable only inside its own `except`.
- **A near-miss worth recording:** an upstream returning `500` with an HTML body produced a `500` from gateway that *looked* correct, but came from `.json()` raising `JSONDecodeError` — right answer, wrong reason. Testing only that case would have hidden the missing `502` entirely. The `404`-with-JSON-body case is what exposed it.
- **Also caught:** two "done" reports were made against an unsaved editor buffer — file `mtime` was 2.5 hours stale. `uvicorn --reload` prints `StatReload detected changes` on every real save, so it is a free save-confirmation. Related: **under `--reload`, a syntax error makes the server *hang* rather than refuse connections**, because the reloader parent keeps the listening socket open while the worker is dead.
- **Carried forward:** `detail=str(e)` on the `503`/`504` handlers leaks the upstream URL to the caller. Harmless locally, becomes internal topology disclosure in the cluster — fix before step 6.

### 2026-09-08 · 12:00 IST — Documentation drift corrected

No code changed. Six places had gone stale while `gateway` was being built:

- **`CLAUDE.md § 3` said FIVE repos.** There are six — added the `gateway/` row, corrected the count and the gitignore list.
- **`CLAUDE.md § 6` still warned that `infra/vairables.tf` is misspelled.** `P-04` renamed it to `variables.tf` on 2026-08-30, so the note was actively misleading. Also added a `gateway` line to the read order.
- **`scripts/timeline.sh` had a hardcoded five-repo array**, so every gateway commit was being silently omitted from `TIMELINE.md`. The script cannot distinguish "no commits" from "not in the list" — added a comment saying so.
- **Then a real bug in the same script, found by checking rather than trusting.** After adding `gateway`, the timeline reported 48 commits where git had 54. Diffing the SHAs showed the six missing ones were **the first commit of every repo**. Cause: `git log --pretty=format:` has *separator* semantics — a newline between entries but none after the last — and `while read` returns false on an unterminated final line, so the loop body never runs for it. `git log` being newest-first, the dropped line is always the **root commit**. Fixed by switching to `--pretty=tformat:`, which terminates. **The timeline now carries all 54 commits, 13 active days, and the project's true start date is 2026-07-28 — a day earlier than it had been claiming.** This is the same failure shape as `D-13` and `learn/20`: nothing errored, the numbers looked plausible, and the loss was invisible until something was counted.
- **`PROGRESS.md` said `S-01` was "Not started"** when it was three commits in.
- **`D-05` was still listed as an open Medium defect.** `E-05` fixed it on 2026-08-31 (`99381d0`); marked resolved, with the per-service-ELB cost concern left where it belongs, on `E-06`.
- **The umbrella `.gitignore` had the `gateway/` line on disk but uncommitted**, so a fresh clone would have tried to track the gateway repo.

### 2026-09-05 · 16:10–16:30 IST — SMTP replaces Gmail OAuth; destroy-notifier verified

- **`D-13` resolved (`51a7aab`).** Owner moved both workflows off Gmail OAuth to `emailSend` nodes with an SMTP credential. That removes the ~7-day refresh-token expiry entirely rather than resetting the clock on it — the better fix, since reconnecting would have failed again next week.
- **`destroy-notifier` verified end to end.** Success payload routed to `Success`, failure payload to `Failure`, and this time both executions reported `status=success`. The SMTP server returned `accepted:[harshitrawat2011@gmail.com], rejected:[]` on both — the mail server taking delivery responsibility, not just n8n not erroring. `N-00b` is **done**.
- **`N-01b` opened.** `cost-watchdog` has the same fix but has still **never sent an email**. It cannot be tested without a cluster: no manual-run endpoint (public API returns `405`), and with no cluster the EKS call 404s and `onError: stopWorkflow` halts it before the email node — correct behaviour, but it means the path is unproven. Next cluster session: click **Test workflow** in the UI.
- **Process note:** the first pull attempt ran the script from Git Bash with `2>/dev/null`, so it failed silently (no `jq` on Windows) and git reported nothing to commit. Suppressing stderr hid the failure — the same anti-pattern `learn/20` warns about, committed by me one message after writing it down.

### 2026-09-05 · 15:30–15:55 IST — destroy-notifier verified; a dead monitor found

- **`N-00b` workflow is built and both branches are verified.** Owner added the `If` + two Gmail nodes and activated it. Tested with fake payloads rather than a real teardown: a `success` payload routed to the `Success` node, a `failure` payload routed to `Failure`. Confirmed via `runData`, not by assuming. Pulled and committed as `0b84e25`.
- **The `If` condition is right:** `{{ $json.body.status }}`. The Webhook node wraps the POSTed JSON under `body`, and a wrong expression there does not error -- it silently routes everything to the false branch.
- **Neither branch sent an email.** Both died at Gmail: *"The credential Gmail account needs to be reconnected."* The OAuth refresh token expired -- a Google policy, since apps in *Testing* publishing status expire refresh tokens after ~7 days. Not a workflow fault.
- **The finding that actually matters (`D-13`, HIGH):** `cost-watchdog` shares that credential. It reports `active: true` and looks healthy, but **it cannot email** -- so a cluster left running would produce no warning at all. Nothing surfaced this because a workflow that never fires never errors. **A monitor's normal state is silence, so a dead one and a working one look identical from outside.**
- **Also confirmed rather than assumed:** the n8n public API has no manual-run endpoint (`POST /workflows/{id}/run` returns **405**), so `cost-watchdog` can only be triggered by its schedule or the UI. And even with a working credential it would send nothing today -- with no cluster the EKS call 404s and `onError: stopWorkflow` halts it before Gmail. That is the design working.
- **Until the credential is reconnected: verify teardown with `make status`, never by waiting for an email.**

### 2026-09-03 · 11:00–11:30 IST — Hardening and automation (R-01..R-04, P-09)

All five done with **no cluster running**, so this cost nothing.

- **`R-04`** (`e073761`) — everything moved into an `app-hub` namespace enforcing the **restricted** Pod Security Standard. The file is `00-namespace.yaml` because `kubectl apply -f <dir>/` goes in filename order and every other object references the namespace; alphabetically `deployment` would otherwise have been applied first and failed.
- **`R-01`** (`e073761`) — requests 50m/64Mi, limits 500m/256Mi. The pod was previously **BestEffort**, meaning first evicted under node pressure; it is now Burstable. Numbers are deliberate starting points, not measurements — revisit when `R-05` can show real usage.
- **`R-02`** (`98f355b` + `e073761`) — `appuser` uid 10001 in the image, and a Deployment `securityContext` with `runAsNonRoot`, matching uid, `readOnlyRootFilesystem`, all capabilities dropped, RuntimeDefault seccomp. **Tested locally rather than assumed**: `docker run --read-only` with *no* tmpfs works, because the app writes nothing and `PYTHONDONTWRITEBYTECODE` stops `.pyc` creation. A security control you have not tested is a deployment failure scheduled for later.
- **`R-03`** (`c06d65f`) — ECR set to `IMMUTABLE`. Forces the useful consequence: every build needs a unique tag, so the Makefile derives it from the links-service commit SHA. A tag now names exactly the code it was built from.
- **`P-09`** — root `Makefile` with `status`/`up`/`deploy`/`down`/`validate`, plus `scripts/validate-manifests.py` for offline checks. `guard` fails fast if run from Windows rather than WSL. `make deploy` deliberately rewrites the image tag *in* the manifest, because ArgoCD (`R-07`) will apply this repo verbatim — desired state must live in git, not be injected at deploy time. That is precisely the step Jenkins (`R-06`) will automate.
- **`CONTEXT-BRIEF.md` regenerated** — it was stale on nearly every fact (claimed nothing deployed, the `POST` bug live, the Dockerfile uncommitted, four repos instead of five).

**Verified:** `make validate` passes (manifests + `terraform fmt` + `validate`), `make status` reports everything empty, Makefile has 77 tab-indented recipe lines and 0 space-indented. **Not verified:** the `securityContext`, the restricted PSS enforcement, and `make up`/`deploy`/`down` against a live cluster — that is the first thing to check next time it comes up.

### 2026-08-31 · 16:45–17:05 IST — Clean teardown; back to $0/hour

- **`Destroy complete! Resources: 55 destroyed.`** Symmetric with the 55 created. Full orphan audit clean: no clusters, NAT gateways, load balancers (v2 or classic), VPC, running EC2, available EBS volumes, or unassociated EIPs. Terraform state empty.
- **The teardown order proved itself.** Deleting the LoadBalancer Service released the NLB in ~10s. Going straight to `terraform destroy` would have left those ENIs attached, failing VPC deletion with an error that reads like a Terraform bug — while the NAT gateway kept billing.
- **Found a real gap in my own checklist.** `aws ecr list-images` defaults to `tagStatus=TAGGED`, so the obvious delete loop removed `v1` and **silently left two untagged buildkit attestation digests behind**. Needed `--filter tagStatus=ANY`. `learn/15` and `CLAUDE.md § 9` both corrected — the old wording said "repeat for untagged digests" without warning that the default command skips them.
- **Cost for the session:** roughly 40 minutes of cluster time, well under a dollar.

### 2026-08-31 · 16:20–16:35 IST — E-05: service exposed to the internet; Phase 2 complete

- **`E-05` done** (`99381d0`). Service switched from `ClusterIP` to `type: LoadBalancer` with the NLB annotation, listening on **port 80** so URLs need no `:8000`. Public at `a79280cd18615491e88aa093ea8dd157-273fe97dadab1bf9.elb.ap-south-1.amazonaws.com`. Verified from outside the cluster: full CRUD, the 404 path, and `/docs` all reachable with no `kubectl` involved.
- **The provisioning gap is real.** The hostname appeared in `kubectl get svc` after ~5s; the first successful request came ~110s later, while the NLB sat in `provisioning`. A hostname existing is not an endpoint working -- check `describe-load-balancers` `State.Code`, not just Kubernetes.
- **Chose NLB over Ingress deliberately.** An Ingress with a single backend is just a more complicated LoadBalancer -- its value is routing *between* services, and there is one. Logged `E-06` to migrate to a shared ALB once `S-01` (`gateway`) gives it something to route between. Right-sized now, wrong later.
- **`C-03` demonstrated, not asserted.** With the API public, POSTed two links, deleted the pod, and watched `GET /links` return `[]`. The pod name changed (`5chkn` → `jppz5`) because Kubernetes replaces pods rather than repairing them. This is the concrete case for `C-04`–`C-06`.
- **Left for the owner by their own rule:** `C-04`/`C-05` (persistent stack + IRSA) and `S-01` (`gateway`) were the other tasks gated on `E-02`. All three are marked owner-builds-by-hand in `CLAUDE.md § 2`, and are now unblocked -- the cluster OIDC provider exists.
- **⚠️ Teardown is now more involved.** The NLB and its ENIs are Kubernetes-created and invisible to Terraform. `kubectl delete svc links-service` must happen *before* `terraform destroy`. The START HERE block carries the ordered command.

### 2026-08-31 · 16:07–16:20 IST — Milestone 2: first end-to-end deploy on EKS

- **`E-02` done.** Owner ran `terraform apply`; 55 resources created. VPC `vpc-0c3e0c493dec78d8e`, NAT `nat-007a005277aac306c`, EKS `app-hub-eks` (1.31, platform `eks.68`), 2x t3.medium node group. Both nodes `Ready` on `10.0.1.184` / `10.0.2.247` with **no external IP**, confirming private subnets. `kubectl` working at all is the proof that `enable_cluster_creator_admin_permissions` did its job.
- **`E-03` done, in parallel.** The image push depends only on ECR, which is created early -- so it ran while the control plane was still `CREATING` instead of after. Built and pushed from **one WSL shell via `docker.exe`**, digest `sha256:d9caf579...`, 70.7 MB.
- **`E-04` done.** 1 pod `Running`, Service ClusterIP `172.20.10.137`, endpoints resolved to `10.0.2.118:8000`. **Service discovery proven in-cluster by DNS name alone** -- `curl http://links-service:8000/health` from a disposable pod returned `{"status":"ok"}`. That is the mechanism `S-01` (`gateway`) will use, and the reason Eureka was dropped.
- **`C-01` confirmed on real infrastructure.** Full CRUD round-trip: `POST` then `GET /links` both returned `"id":1`. The bug that hid for weeks behind a correct-looking `POST` response is genuinely gone.
- **Timestamp system built and debugged.** `scripts/timeline.sh` generates `TIMELINE.md` from git across all five repos. It produced wrong times twice before working -- Git Bash silently ignores `TZ` and falls back to GMT, so the first run was 5.5 hours out; then my own self-check constant was wrong by three minutes. Now uses epoch arithmetic with a guard that refuses to run if conversion is broken, and is byte-identical from both shells. Written up in `learn/17`.
- **Corrected a one-day drift**: 36 `PROGRESS.md` rows said `2026-08-29` for work git records on `2026-08-30`.

### 2026-08-31 · 00:45–00:47 IST — Workflows versioned, all five repos published

- **`N-04` done.** Pulled both workflows via the n8n API (`065b447`): `eks-cost-watchdog` (active) and `terraform-destroy-notifier` (inactive). **Checked the count with `jq '.data | length'` before writing anything** — an earlier `grep` had matched nested node names and reported 14, which would have meant something was wrong with the script. It was 2. Secret scan found only credential *references* by name and id, exactly as `learn/08` predicts.
- **All five repos now pushed.** `infra` (2), `links-service` (4), `manifests` (2) had local-only commits; reviewed the outgoing diffs, scanned for secrets, pushed. Every repo is at `0 unpushed`.
- **`N-03` / `N-05` confirmed done.** `.env` populated and verified ignored; API returns 200. Encryption key backed up by the owner — not independently verifiable by design, which is the point.
- **Added `P-09`** to automate the deploy path, and a **START HERE NEXT SESSION** block at the top of this file at the owner's request: `E-02` is to be raised first thing.

### 2026-08-31 · 00:22–00:29 IST — Reconciled with the second Claude-chat context document

Absorbed a fuller handoff from the manual sessions. It **corrected one thing I had documented wrongly** and added a cost risk that was not on the board at all.

**Correction — `force_delete` on ECR is not sufficient.** `CLAUDE.md § 9` and `learn/06` both stated that `force_delete = true` prevents the teardown failure. In practice it was **observed not to take effect**, and destroy failed anyway. Both files now keep the flag *and* carry the working fallback (`aws ecr batch-delete-image` before destroy). Stating a mitigation works when it has been seen to fail is the worst kind of doc error, since it stops you looking further.

**New risk — Kubernetes creates AWS resources Terraform cannot see.** EBS volumes behind PVCs are made by the EBS CSI driver, not Terraform: `destroy` leaves them and they bill indefinitely, silently. LoadBalancer ENIs additionally block VPC deletion with a confusing dependency error. Written up as `learn/15-safe-teardown.md` with a drain-then-destroy checklist and a verify step, and added to `CLAUDE.md § 9`. **Live from `R-05` onward** — `kube-prometheus-stack` is the first workload here wanting persistent storage.

**Roadmap reordered to match the owner sequence:** Prometheus/Grafana (`R-05`) → Jenkins (`R-06`) → ArgoCD (`R-07`). I previously had Jenkins first. Added `S-03` (`frontend`) as a fourth service, and sharpened `S-01`/`S-02`: `gateway` is the external entry point and the next core-app task; `aggregator` is the one that truly proves internal discovery.

**Decisions recorded with their rationale:** EC2 node groups over Fargate (Fargate has no DaemonSets, which `node-exporter` requires); Jenkins bumps a tag and ArgoCD deploys, so Jenkins never runs `kubectl apply`; each service must earn its place by teaching something distinct; long-lived access keys over SSO as a knowing trade-off; Spring Boot dropped to avoid a fourth simultaneous unknown; EKS over self-hosted, with the comparison parked as a follow-up; the S3 state bucket hand-created as the bootstrapping exception.

**Also recorded:** the `destroy-notifier` webhook payload nests under `body` (`{{ $json.body.status }}`); it will be scheduled via Windows Task Scheduler invoking `wsl.exe`, because a WSL cron is unreliable; the destroy stays local so destructive credentials never live in a long-running app; n8n pinned data can replay frozen output, and a green check means "did not halt", not "got a 200"; the `/etc/resolv.conf` symlink breaks after `wsl --shutdown`; n8n's volume is `n8n_data`, which pins down where the encryption key lives for `N-05`.

### 2026-08-30 · 23:13–23:44 IST — Repos published, infra planned, persistence decided

- **`P-08` / `N-02`** — both GitHub repos existed but were **empty, with no local remote configured**, and `n8n` had **zero commits**. Committed the n8n scaffold, wired `origin` on both, secret-scanned the staged content, pushed. Lesson recorded in `learn/10`: creating the GitHub repo and connecting to it are separate states — check `git remote -v` and `git log @{u}..`, not just the web UI.
- **`E-02`** — `terraform plan` run with the new credentials: **55 to add, 0 to change, 0 to destroy** (vpc 19, eks 37, ecr/root 3). No `forces replacement`. Confirmed `aws_eks_access_entry.this["cluster_creator"]` is in the plan — the flag that prevents the `Unauthorized` trap. **Not applied** — awaiting explicit approval, since it starts billing.
- **`C-03` decided** — DynamoDB in a separate **persistent** Terraform stack, reached via IRSA. The deciding constraint is the destroy-every-session policy: anything durable must live outside the stack being destroyed, and DynamoDB on-demand costs ~$0 idle where RDS bills continuously. Stopgap applied: `replicas` pinned to **1** (`93cea2c`) with an in-file comment explaining what must land before it is raised. Implementation broken out as `C-04`–`C-06`, all marked owner-builds-by-hand.
- **`C-02`** — still owner-written, but now has a full teaching guide at `learn/14` covering `TestClient`, the module-level shared-state trap, and fixtures.
- **Conformance sweep on the `learn/` rule.** Several completed steps had no learning file. Wrote `learn/10`–`14` to close the gap: polyrepo doc versioning, AWS credentials and the two-kubeconfig split, reading a Terraform plan, the persistence architecture, and the testing guide.
- **n8n runbooks** — `n8n/README.md` now has explicit numbered steps for `N-03` (fill `.env`) and `N-05` (back up the encryption key), including the check-ignore-before-you-paste ordering and a clipboard route that keeps the key off screen.

### 2026-08-30 · 12:00 IST — Cleared the ready-now backlog (6 tasks, 4 commits, 2 repos)

- **`C-01`** — fixed `POST /links` storing the `LinkCreate` instead of the constructed `Link` (`7b7b0bd`). Verified by HTTP round-trip, not by reading the POST response: `GET /links` now returns `"id":1`, which it did not before.
- **`P-03` + `D-11`** — rewrote the Dockerfile (`5e312ef`). Base moved to `python:3.14-slim` (confirmed to exist via the Docker Hub tag API, currently 3.14.7) so the tag no longer lies about the interpreter; `CMD` now calls `uvicorn` from the venv on `PATH` instead of `uv run`, which was re-installing the project at container start.
- **`P-02`** — the Dockerfile is finally tracked, after being fixed.
- **`P-06`** — wrote `links-service/README.md` (`f3203de`), including an explicit storage caveat so nobody builds on the in-memory dict assuming it persists.
- **`P-04` + `P-05`** — renamed `vairables.tf` → `variables.tf` via `git mv` (staged as a rename) and removed the empty `main.tf` (`3cb9e57`). `terraform validate` passes and `terraform fmt -check` is clean.

**Trap hit before any commit:** three of the four repos had no git identity. `links-service` had a name but no email; `manifests` and `n8n` had neither; global was unset. The next commit in any of them would have failed with `fatal: empty ident name`. Set per-repo to match `infra` — deliberately not globally, since this is a work-managed laptop (`CLAUDE.md § 3`).

**Held back deliberately:** `C-02` (tests). No tests exist anywhere, so this is a new concept, and `CLAUDE.md § 2` says the owner writes the first implementation by hand. Handover notes are on the task row.

Defects closed: `D-01`, `D-03`, `D-04`, `D-06`, `D-07`, `D-08`, `D-11`. New: `D-12` (missing `.gitattributes` in the three older repos). `learn/09-first-defect-fixes.md` written.

### 2026-08-30 · 19:03 IST — Reconciled with prior Claude-chat project history

The owner supplied a handoff document summarising the manual sessions that preceded Claude Code. It resolved several things my audit could only guess at, and contradicted my docs in two places.

**Corrections to what I had written:**

- **`E-01` resolved.** I recorded "no confirmed `terraform apply`" based on the local `terraform.tfstate` stub. Wrong inference: the full loop *was* proven once — built, pushed to ECR, deployed to EKS, 2 pods `Running`, ClusterIP routing and DNS discovery confirmed — then destroyed per the cost policy. The stub proved nothing either way, which is exactly why the task existed.
- **`D-11` added.** The handoff named a Dockerfile defect I saw during the audit but failed to log: build-time `uv sync --no-install-project` versus `uv run` at `CMD`, which re-installs at container start. My `D-03` covered only the Python version mismatch on the same file.
- **Objective sharpened.** The learning goal is specifically the toolset the owner's organisation is migrating toward (EKS, Terraform, Grafana/Prometheus). That reframes "why this stack" and makes "use something simpler" usually the wrong suggestion.
- **`CLAUDE.md § 2` gained "Do not build ahead."** The owner writes the first implementation of each new concept by hand. Noted honestly: scaffolding the n8n repo earlier in this session ran against that rule.

**New facts recorded:** cost policy (destroy every session) and the `cost-watchdog` / `destroy-notifier` workflows; roadmap (`gateway` → Jenkins-in-EKS → ArgoCD → Grafana/Prometheus); service discovery via Kubernetes DNS, not Eureka; Ansible and Eureka dropped; per-repo git identity on a work laptop; the WSL2 DNS fix; Hinglish preferred for conceptual explanation; five hard-won operational lessons now in `CLAUDE.md § 9`.

**Verified live, not assumed:** `kubectl` context is `minikube`. AWS credentials are **rejected** — `InvalidClientTokenId` — and no profile exists for account `314146298861`. Configured profiles are `uzio-nonprod-audit`, `default`, `scripttest`, all work-account, with `default` on `us-east-1`. Logged as `E-00`, now the first blocker in the deploy chain.

### 2026-08-30 · ~22:30 IST — n8n added as a fourth component

- Owner has a self-hosted n8n instance with an existing workflow, and expects to build more. Confirmed: self-hosted (Docker/local), and it gets its own repo, consistent with the one-repo-per-component pattern.
- Scaffolded `n8n/` as a git repo on `master`: `workflows/`, `scripts/pull-workflows.sh`, `.env.example`, README, `.gitignore` (blocks `.env` and any credential export), `.gitattributes`.
- Added `.gitattributes` with `eol=lf` after observing git warn about CRLF conversion. The scripts run in WSL; a CRLF shebang fails there with a misleading `bad interpreter` error. Prevented rather than debugged later.
- Verified `.env` is ignored (`git check-ignore` matches `.gitignore:2`) and that the script passes `bash -n`.
- Added the n8n API key handling rules to `CLAUDE.md § 4`: source-and-reference only, never print the file or the variable, never `curl -v`, never ask the owner to paste the key into chat.
- Docker Desktop was not running, so nothing was pulled from the live instance yet — that is `N-04`.
- Noted `N-05`: the n8n encryption key in `~/.n8n` needs backing up outside the repo. Losing it makes every stored credential unrecoverable.

### 2026-08-30 · ~15:00 IST — Teaching mandate and the `learn/` folder

- Owner clarified the working model: this project began as a manual, step-by-step learning exercise with Claude chat, and the move to Claude Code was for **speed, not for outsourcing the understanding**. Claude Code must teach at every step, not silently complete the work.
- Added `CLAUDE.md § 2 — How we work: teach, don't just ship`, and renumbered the sections that followed. It is placed second, immediately after the objective, because it governs *how* every other task is carried out.
- Sharpened the § 1 objective: app-hub is the permanent home for **every** app the owner builds for daily use — not a one-off project that ends with `links-service`.
- Created `learn/` with an index (`learn/README.md`) and the first entry, `00-project-setup-and-governance.md`, covering the audit findings, the no-root-repo trap, the WSL/Windows split, and a walkthrough of both high-severity bugs.
- Made the learning file part of the definition of done in `CLAUDE.md § 7` and `README.md § Governance`.
- Logged `P-07` to backfill learning files for the ~7 steps completed before this folder existed.

### 2026-08-30 · ~14:52 IST — Project documentation and baseline audit

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
