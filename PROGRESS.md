# PROGRESS.md — app-hub

Live status board. **Update this at the end of every working session** — status, blocker, next step, plus a line in the log.

**Last updated:** 2026-09-16

---

## ▶ START HERE NEXT SESSION

**Claude: surface this block first, before anything else.**

### ✅ Nothing is deployed — re-verified 2026-09-16 · 14:34 IST

`make status` run live: no EKS clusters, no NAT gateways, no load balancers, **0** running EC2, no available EBS volumes, no unassociated EIPs. **$0/hour.** The persistent stack is intact — `app-hub-links` still listed, exactly as designed.

The last real teardown was **2026-09-14**: `Destroy complete! Resources: 59 destroyed`, matching the 59 created, and verified with the AWS CLI **independently of `make down`'s own audit** — that script had just run and would otherwise be marking its own homework. The `C-05` IRSA role is gone; `app-hub-links` survived, `ACTIVE`, 0 items.

*(This block said "verified clean at 2026-08-31 · 17:05 IST" with 55 destroyed until 2026-09-16 — two teardowns out of date, in the one block this file instructs Claude to read first.)*

Confirm before assuming — it takes two seconds:

```bash
wsl -e bash -lc "aws eks list-clusters --region ap-south-1 --output text; aws ec2 describe-nat-gateways --filter Name=state,Values=available --region ap-south-1 --query 'NatGateways[*].NatGatewayId' --output text; aws elbv2 describe-load-balancers --region ap-south-1 --query 'LoadBalancers[*].LoadBalancerName' --output text; aws ec2 describe-volumes --filters Name=status,Values=available --region ap-south-1 --query 'Volumes[*].VolumeId' --output text"
```

All empty = clean. **To bring it back up**, the whole loop is proven and documented in `learn/16`; budget ~15 min for `terraform apply`, and remember `aws eks update-kubeconfig` from **WSL** afterwards.

**When tearing down again, order matters** (`learn/15`): delete LoadBalancer Services first so their ENIs release, then empty ECR **with `--filter tagStatus=ANY`** (the default hides untagged digests), then `terraform destroy`, then audit for orphans.

### ⚠️ The cost watchdog fired on schedule ONCE, then went silent when the laptop slept

`D-13` is **resolved** (2026-09-05). Both workflows moved off Gmail OAuth to `emailSend` with an SMTP credential, which removes the ~7-day refresh-token expiry for good. `destroy-notifier` is verified end to end: both branches route correctly and SMTP reported the mail accepted.

**`N-01b` CLOSED 2026-09-13.** `cost-watchdog` has now **actually sent an email, and it arrived in the inbox** — execution **38**, `mode=manual`, `status=success`, 07:25:25 UTC (12:55 IST). That is the first email this project has ever sent in its life, and the inbox is the only evidence that counts: a green tick means *"did not halt"*, not *"delivered"*.

**What is proven and what is not.** The email node sends, the SMTP credential works for *this* workflow, and the subject and body render. The **end-to-end** path — HTTP Request seeing a live cluster and triggering the email on its own — is still unproven, and needs a cluster. **That was the plan, and 2026-09-16 showed it does not hold** — see `D-24` below: the trigger fires reliably only until the host sleeps. **No pinned data was left behind** (verified via the API: `pinData` is empty, workflow still `active`), which matters — a pin would have made it email every day regardless of cluster state.

**What 2026-09-16 added, from reading the execution history rather than waiting for a mail.**

**The good half.** Execution **44**, `2026-09-14 21:00:05 IST`, `mode=trigger` — the first time in this project's life that `cost-watchdog` has fired **on its own schedule, at the intended IST hour**. It hit the EKS API, got `404 No cluster found for name: app-hub-eks`, and halted. That is textbook correct behaviour, and it confirms the `D-22` timezone fix on the *real* workflow rather than on the throwaway probe.

**And it also means a live cluster is no longer needed to prove the trigger fires.** The 404 path leaves an execution row just as the 200 path would. `D-22` said the remaining test was "leave a cluster up past 17:00"; it was not — the cheaper test was to look.

**The bad half, now `D-24`.** It has not fired since. 2026-09-15 had **both** trigger hours pass with the machine awake (11:16–21:41 IST), the container up continuously, and the workflow `active: true` — and there is **no execution row at all**. A host sleep sits between the last good fire and the silence.

**So keep verifying teardown with `make status`.** The watchdog is now known to be *intermittently* dead rather than reliably dead, which is worse: it will sometimes email, which is exactly what builds the trust it does not deserve.

### There is now a Makefile — use it

Run from **WSL**. `make` on its own prints the targets.

```bash
wsl -e bash -lc "cd /mnt/c/Users/harshit.rawat/Documents/Projects/app-hub && make status"
```

`make status` replaces the audit above. `make up` provisions **and refreshes the kubeconfig**. `make down` runs the whole teardown in the correct order. `make validate` works with no cluster.

### ⚠️ First thing when the cluster next comes up

**Refresh the kubeconfig before anything else.** EKS issues a new endpoint hostname on every create, so it is stale by definition — and it is *visibly* stale right now: the 2026-09-16 teardown log is full of `lookup 8A1389C0E89FB1263FA1B3657D3AE76F.gr7...: no such host`, which is the old cluster's endpoint. `make up` does this for you.

**Then check `cost-watchdog` actually fires** (`D-24`). Restarting the n8n container re-registers its crons; without that the cluster can sit up overnight with nothing watching it. Confirm by execution row, not by the workflow saying `active`.

*(This block warned until 2026-09-16 that `R-01`–`R-04` had never met a real API server. They have — verified on the cluster 2026-09-10 and again on 1.36 on 2026-09-14, and `R-03`'s `IMMUTABLE` setting has been applied. The warning had simply outlived the risk.)*

### ⚠️ The work split changed on 2026-09-09 — read `CLAUDE.md § 2` before writing anything

The old rule ("the owner hand-writes every new concept, including application code") has been **replaced**. The new rule is **hand-build what the owner is learning, delegate what is merely scaffolding for it.**

- **Claude now writes, without asking:** application code, Dockerfiles, tests, Makefile targets and scripts, boilerplate refactors, the docs, and Kubernetes manifests that are a *second instance of an object type the owner has already written*.
- **The owner still writes, after explanation and before review:** Terraform they have not written, Kubernetes manifests introducing a *new object type*, PromQL and alert rules, Grafana dashboards, Helm values, ArgoCD `Application`s, Jenkins pipelines, n8n GUI work — and **any infra failure gets debugged by them, not fixed for them** (20-minute time-box while the cluster bills).

`learn/` files are now written for **hand-built work only**. Delegated work gets a `PROGRESS.md` note instead.

### Then, in priority order — reordered 2026-09-09 so the owner is never idle

The naive order put four delegated tasks in front of `R-05`, which would have meant several sessions of the owner watching Claude write application code while Prometheus — the material they actually need for work — waited at the back. Reordered to run the two tracks in parallel:

1. **`S-01` steps 4–5 — Claude.** Steps 1–3 are owner-written and committed. Step 4 (`LINKS_SERVICE_URL`) and step 5 (Dockerfile) are now delegated: config plumbing and a copy of the `links-service` Dockerfile. No cluster, no cost. Also carries the `detail=str(e)` leak fix.

2. **`C-04` persistent stack + DynamoDB — OWNER, in parallel with the above.** This is the priority for the owner's own time. Terraform they have not written before, **needs no cluster, and costs ~$0** — DynamoDB on-demand bills nothing idle. Getting it wrong is free, which makes it ideal learning. Explanation first, then they write, then review.

3. ~~**One batched cluster session**~~ — **DONE 2026-09-13.** `S-01` step 6 deployed, ~~`N-01b`~~ closed (no cluster needed after all), `R-01`–`R-04` verified as the cluster enforces them, and beyond the original scope: `C-05` IRSA applied and proven, `C-06` verified against the real table from a pod, `S-02` and `S-03` deployed, and **`D-02` closed** — the `replicas: 1` pin held since 2026-08-30. Torn down the same night, by the scheduled task, unattended.

4. ~~**`R-05` Prometheus/Grafana**~~ — **DONE and verified on real EKS 2026-09-14.** 22 scrape targets all UP, five of them app-hub pods, from one `ServiceMonitor` with no config file edited and nothing restarted. Built as a **guided build**, the `CLAUDE.md § 2` tier added that day. `learn/30`.

5. ~~**Background, Claude, between cluster sessions**~~ — **ALL CLOSED.** ~~`C-02`~~, ~~`D-09`~~, ~~`D-10`~~, ~~`C-06` code~~, ~~`S-03` dashboard~~, and ~~`S-02` aggregator~~ (2026-09-13, once the owner created `HarshitRawat11/app-hub-aggregator` — the seventh repo).

   **Claude's queue is empty, and this time it was checked against the repositories rather than the task IDs** — which is how it was got wrong twice before. Everything remaining is the owner's under `CLAUDE.md § 2`.

**Remaining, all the owner's:** `E-06` Ingress + ALB controller, `R-06` Jenkins, `R-07` ArgoCD, `N-06` n8n on EKS. (~~`C-05` IRSA~~ done and verified 2026-09-13 — written by Claude via the § 2 escape hatch, with the skipped concept flagged in `learn/29`.)

**So the next task is `E-06` — Ingress and a shared ALB — and it is the owner's.** Everything ahead of it is closed, and Claude's queue is empty again.

`E-06` is the right next one rather than `R-06` Jenkins for two reasons. It is **smaller** — one new object type (`Ingress`) plus a second Helm chart, against Jenkins' pipeline language, credentials and agent model. And it **pays for itself immediately**: `gateway` becomes the one public entry point and `links-service` drops to `ClusterIP`, which removes a load balancer from every future session's bill and shrinks the teardown ordering problem that `learn/15` exists for.

**There is also a cheap follow-on to `R-05` whenever it is wanted:** Prometheus persistence, via the EBS CSI addon and a *second* IRSA role. It builds directly on `C-05`, and `learn/30` already explains why the first attempt used `emptyDir`.

---

## Where the project stands

**Milestone 2 is COMPLETE.** On 2026-08-31 the loop was rebuilt end to end on real EKS with every known defect fixed: `terraform apply` → build → push to ECR → deploy → reach `/health` by Kubernetes DNS name. Verified in-cluster, not just locally.

**Currently nothing is deployed, and that is the correct resting state.** Torn down 2026-09-14 after the `R-05` session — 59 destroyed, verified clean, and re-verified live on 2026-09-16. The cluster only exists while it is being worked on.

What that leaves:

- **`E-00` is resolved.** AWS credentials for `314146298861` (`terraform-learning`) live in **WSL's own `~/.aws/`**, separate from the Windows-side `.aws` holding untouched work profiles. Proven this session by a real `terraform apply`.
- **Phase 2 complete 2026-08-31** (`E-02`–`E-05`). Provisioned 55 resources, pushed the image, deployed, reached `/health` by Kubernetes DNS name, then exposed publicly via an NLB and verified full CRUD from the internet. Torn down cleanly afterwards — 55 destroyed, no orphans.
- **Code state:** `C-01`, `D-03`, `D-11` fixed and **verified on the cluster**, not just in a container. `replicas` pinned to 1 (`C-03` stopgap). Remaining: no tests yet (`C-02`), storage still ephemeral until `C-04`–`C-06`.
- **`kubectl` context:** Windows says `minikube`, WSL says `app-hub-eks`. They are **separate config files**. Run EKS-facing commands from WSL only (`CLAUDE.md § 5`, `learn/11`).

- **The work split changed on 2026-09-09** — application code, Dockerfiles, tests, tooling and docs are now Claude's; Terraform, PromQL, Grafana, Helm values, ArgoCD, Jenkins, n8n GUI work, new Kubernetes object types and all infra debugging stay the owner's. See `CLAUDE.md § 2`; every open row below names its side.
- **`gateway` is complete and was deployed on real EKS** (`S-01`, all six steps; 1–3 owner-written, 4–6 Claude's). It proxies the full links CRUD, maps upstream failures to `502`/`503`/`504`, and **serves the dashboard at `/`** (`S-03`, committed 2026-09-13 · 00:01 IST). *This line said "half built… not containerised and not deployed" for two days after `S-01` closed — noted here because it is the same rot the drift checker was built for, in prose it cannot reach.*
  **The dashboard has since run on the cluster** — deployed and exercised 2026-09-13, and its `/status` panel is what surfaced `D-21`.

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
| C-02 | Add tests for the links CRUD endpoints | **Done** 2026-09-10 (`fc753f8`) — Claude-written, **verified** | None. **Was** held back for the owner to write; the `CLAUDE.md § 2` revision moves tests to Claude. | **14 tests, all passing.** `tests/test_links.py` via FastAPI `TestClient` (in-process over ASGI — no uvicorn, no port, so it cannot collide with a real server on 8000). An `autouse` fixture resets `links_db` and `next_id`, which are module-level globals — without it the second test to run sees the first test's records, and the failures are **order-dependent**. <br><br>**Two tests are explicit `D-01` regressions**, reading the `id` back through both `GET /links` and `GET /links/{id}` — a test asserting only on the `POST` response would have passed throughout the original bug. <br><br>Also: `pythonpath = ["."]` added to `pyproject.toml`, without which `from app.main import app` fails with `ModuleNotFoundError` (reads like a broken install, not a path problem); and the dev dependency moved `httpx` → `httpx2`, since starlette's `TestClient` now deprecates the former. <br><br>**Coverage list is in `learn/23` for review** (`CLAUDE.md § 2` — the owner reviews what is covered, not the code). Not covered deliberately: concurrency (`replicas: 1` until `C-06`) and persistence across restarts (none until `C-04`–`C-06`). **`C-06` is now unblocked.** |
| C-03 | Decide how link data persists across pods | **Decided** 2026-08-30 | None | **Decision: DynamoDB in a separate persistent Terraform stack, accessed via IRSA.** Rationale: the cluster is destroyed every session, so anything durable must live outside the destroyed stack; DynamoDB on-demand costs ~$0 idle, unlike RDS which bills continuously. Stopgap applied: `replicas` pinned to 1 (`93cea2c`) — removes inconsistent reads, does not add durability. Implementation split into `C-04`–`C-06`. See `learn/13`. |
| C-04 | Create the `persistent/` Terraform stack with the DynamoDB table | **DONE and APPLIED** — owner-written, committed 2026-09-10 (`6adda96`), and the table is **live**: `app-hub-links`, `ACTIVE`, `PAY_PER_REQUEST`, created **2026-09-10 · 16:35 IST**. *This cell said "NOT APPLIED: no table exists in AWS yet" for three days after the table existed — found 2026-09-13 by a read-only audit, not by anything that was watching. It also kept `C-06` marked blocked on a blocker that had already cleared.* | **No cluster needed** — a DynamoDB table has no dependency on EKS, and on-demand billing means an idle table costs ~$0. Getting it wrong is free. | Terraform the owner has not written before, so: **explanation first, then they write, then Claude reviews** (`CLAUDE.md § 2`). **Four files written by the owner, committed `6adda96`.** `terraform fmt` clean, `validate` passes, plan reports **1 to add / 0 to change / 0 to destroy**, table named `app-hub-links`, `id` declared as type `S`. `.terraform.lock.hcl` committed too (pins aws 5.100.0) — the `D-15` fix applying to a stack that did not exist when it was closed. <br><br>**The only remaining step is `terraform apply`, which needs the owner's explicit approval.** Cost once applied: ~$0 — on-demand DynamoDB has no hourly charge. <br><br>**After applying, verify three things, not one:** the table is `ACTIVE`/`PAY_PER_REQUEST`; the S3 bucket lists **two separate state keys**; and `cd infra && terraform plan` still reports **no changes** — that third one is the proof the two stacks cannot see each other, and it is the one people skip. <br><br>**Note the invariant this changes:** once applied, "nothing is deployed" stops being literally true. The resting state becomes *one DynamoDB table exists, by design*. `make status` lists it below the divider, where an **empty** list is the bad outcome. <br><br>**Location decided 2026-09-09: `infra/persistent/`, inside the `app-hub-infra` repo** — not a seventh git repo. It is Terraform, maintained alongside `infra/`, and the polyrepo split exists to separate *components*, not directories. `terraform` does not recurse into subdirectories, so `make down` cannot reach it. <br><br>**Own S3 state key** (e.g. `persistent/terraform.tfstate` — NOT the same key as `infra/`, or each stack plans to destroy the other's resources, silently, with no warning). Note the `backend` block accepts no variables or interpolation — literal strings only. <br><br>**Name the table unmistakably `app-hub`-ish** (e.g. `app-hub-links`): the account already holds `tf-lock-devops-recipe-app-api` from an unrelated project, and `make status` now lists DynamoDB tables, so an ambiguous name makes that audit harder to read. <br><br>**Declare the `id` partition key as type `S` (string), not `N`** — even though ids are integers today. A key attribute's type **cannot be changed** without destroying and recreating the table, and `C-06` plans to move to UUID/ULID. Free now, a migration later. <br><br>`PAY_PER_REQUEST` billing (idle table ~$0 — the whole reason DynamoDB beat RDS here) and a `lifecycle { prevent_destroy = true }` block, which makes "never destroyed" enforced rather than a note in this file. Declares the table only; the IRSA role belongs in `infra/` — see `C-05`. Never destroyed. See `learn/13`. Gets a `learn/` file, since it is hand-built. |
| C-05 | Wire IRSA: annotate the ServiceAccount, trust the OIDC provider | **DONE and VERIFIED ON REAL EKS** 2026-09-13 — the webhook injected `AWS_ROLE_ARN` and a real 1214-byte projected token, and a write through the pod landed in the real table (confirmed by the AWS CLI). *Written by Claude* 2026-09-13 via the `CLAUDE.md` § 2 escape hatch, at the owner's request after a full explanation. **Validated offline, NOT applied** — needs a cluster. Three files: `infra/irsa.tf`, `manifests/links-service/00-serviceaccount.yaml`, and the two-line Deployment change (`serviceAccountName` + `LINKS_TABLE_NAME`, together, per `D-18`). **Concept skipped and worth revisiting: the trust policy's `sub` condition** — the first place here where a wrong Terraform detail grants access rather than breaking a deploy. Full walkthrough in `learn/29`, deliberately a seven-section file rather than a delegated short note | **Needs the cluster up** — the trust policy references the cluster's OIDC provider. Depends on `C-04`. | **Both halves are the owner's** under the revised `CLAUDE.md § 2` — the Terraform IAM role and trust policy because it is Terraform they have not written, and the `ServiceAccount` because it is a Kubernetes object type they have not written. The object-type line is what keeps this task whole instead of split down the middle. <br><br>**Design correction (2026-09-03):** the IRSA role does NOT belong in the persistent stack. EKS issues a **new OIDC issuer URL on every cluster creation**, so a role whose trust policy names it would break on each rebuild. Correct split: **`persistent/` holds only the data** (the DynamoDB table, which genuinely outlives everything); **`infra/` holds the IRSA role**, because it is cluster-scoped and cheap to recreate. The persistent stack exports the table ARN; `infra/` consumes it and grants access. Cluster needs its OIDC provider enabled; trust policy scoped to the specific namespace + ServiceAccount; `eks.amazonaws.com/role-arn` annotation on the SA. No stored credential anywhere. |
| C-06 | Refactor `links-service` to a repository layer and swap to DynamoDB | **DONE — VERIFIED IN CLUSTER** 2026-09-13. The deployed service now reads and writes the real `app-hub-links` table via IRSA, proven by the AWS CLI seeing a record written through gateway. Earlier the same day: 11 offline checks against the real table, 0 failures, table left byte-identical. **Manifest half shipped with `C-05`** per `D-18` | **Unblocked as of 2026-09-13.** `C-02` is done and `C-04` is applied, so a real table exists to point at. **The remaining verification needs no cluster:** boto3's default credential chain in WSL resolves to `terraform-learning`, which can already reach the table (confirmed by a read-only `scan`). Running links-service locally with `LINKS_TABLE_NAME=app-hub-links` exercises `DynamoDBLinkRepository` against the real thing. **IRSA (`C-05`) is what the POD needs, not what this laptop needs** — conflating the two is what kept this marked blocked. Writing to the persistent table needs the owner's approval first. | Application code and storage layer, so delegated under `CLAUDE.md § 2`. Extract a `LinkRepository` interface with in-memory + DynamoDB implementations. Move id generation off the `global next_id` counter (UUID/ULID preferred). Then raise `replicas` back above 1. **Note the boundary:** the code is Claude's, but if DynamoDB access fails once deployed that is an **IRSA** failure — infra, therefore the owner's to debug. |

### Phase 2 — First end-to-end deploy

| ID | Task | Status | Blocker | Next step |
|----|------|--------|---------|-----------|
| E-00 | Configure an AWS profile for the app-hub account | **Done** | None | Resolved 2026-08-30: `aws configure` run **inside WSL** (`~/.aws/`, separate from the Windows-side `.aws`), profile `default`, region `ap-south-1`, user `terraform-learning`, account `314146298861` confirmed via `sts get-caller-identity`. Windows-side `default` (work profiles) verified untouched and still rejected. `terraform init` now succeeds. |
| E-01 | Confirm whether `terraform apply` has ever run against the S3 backend | **Resolved** | None | **Answered by project history 2026-08-30: yes.** The full loop was proven once — image built, pushed to ECR, deployed to EKS, 2 pods `Running`, ClusterIP routing and Kubernetes DNS discovery confirmed — then torn down with `terraform destroy` per the cost policy. "Nothing deployed" is the normal resting state, not a failure. Live re-verification is blocked on `E-00`. |
| E-02 | Re-provision the infra (VPC + EKS + ECR) | **DONE** 2026-08-31 · ~16:10 IST | None | Owner ran `terraform apply`. Created: VPC `vpc-0c3e0c493dec78d8e`, NAT `nat-007a005277aac306c`, EKS `app-hub-eks` (1.31, platform `eks.68`), node group `default-20260831104239047500000013`, ECR repo. Both nodes `Ready` on `10.0.1.184` / `10.0.2.247` with **no external IP** — confirming private subnets. **Cluster is UP and billing.** 
| E-03 | Build and push `links-service:v1` to ECR | **DONE** 2026-08-31 · 16:13 IST | None | Built and pushed from **WSL via `docker.exe`**, digest `sha256:d9caf579…`, 70.7 MB. Done in parallel with the EKS control plane still `CREATING` — the push depends only on ECR, not the cluster. Note two **untagged** buildkit attestation digests also landed; `batch-delete-image --image-ids imageTag=v1` will not remove those at teardown (`learn/15`). 
| E-04 | Deploy manifests to EKS and reach `/health` | **DONE** 2026-08-31 · 16:15 IST | None | `kubectl apply` → 1 pod `Running` on `10.0.2.118`, Service ClusterIP `172.20.10.137`, endpoints resolved correctly. **Verified in-cluster by DNS name**: `curl http://links-service:8000/health` → `{"status":"ok"}`. Full CRUD round-trip passed, and `GET /links` returned `"id":1` — the `C-01` fix confirmed on real EKS. `GET /links/999` → 404. 
| E-05 | Expose the service outside the cluster | **DONE** 2026-08-31 · 16:32 IST | None | Switched the Service to `type: LoadBalancer` with the NLB annotation (`99381d0`), listening on port 80. Public at `a79280cd18615491e88aa093ea8dd157-273fe97dadab1bf9.elb.ap-south-1.amazonaws.com`. NLB took ~110s to go `provisioning` → `active`. Verified externally: full CRUD, 404 path, and `/docs` all reachable. **Right-sized for one service only** — see `E-06`. 
| E-06 | Migrate from per-service LoadBalancer to a shared ALB via Ingress | Not started — **OWNER's to write, in full.** **Direction decided 2026-09-10** (see next step) | `Ingress`/`IngressClass` are Kubernetes object types the owner has not written, and the ALB controller's Helm values are on the hand-write list — so this stays whole rather than splitting. Wait until `gateway` is deployed, so there are actually two services to route between. <br><br>**Decided 2026-09-10 — the flip is confirmed, only the implementation waits:** `gateway` becomes the publicly reachable service via Ingress + a shared ALB, and **`links-service` becomes `ClusterIP`, not reachable from outside at all.** That is the entire point of having a gateway, and it removes the public endpoint `E-05` verified — deliberately. Deciding now means `gateway`'s Service manifest never needs revisiting; it is `ClusterIP` today only to avoid a second ELB and a second bill before the Ingress exists. | Every `type: LoadBalancer` Service provisions its **own** ELB — N services means N load balancers and N bills. An Ingress + the AWS Load Balancer Controller gives one shared ALB with path-based L7 routing. Premature with a single service; the right move once there are two. |

### Phase 3 — Production readiness

| ID | Task | Status | Blocker | Next step |
|----|------|--------|---------|-----------|
| R-01 | Add resource requests and limits to the Deployment | **Done and VERIFIED on a live cluster** 2026-09-10 | None | `e073761`. requests 50m/64Mi, limits 500m/256Mi → **Burstable** QoS. Previously **BestEffort**, i.e. first evicted under node pressure. Numbers are starting points, not measurements — revisit once `R-05` shows real usage. 
| R-02 | Add a `securityContext` (non-root, read-only rootfs) | **Done and VERIFIED on a live cluster** 2026-09-10 | None — enforcement confirmed. | `98f355b` + `e073761`. Dockerfile creates `appuser` uid 10001 and switches to it; Deployment sets `runAsNonRoot`, matching uid, `readOnlyRootFilesystem`, drops ALL capabilities, RuntimeDefault seccomp. **Verified locally**: the image runs as uid 10001 and serves fine under `docker run --read-only` with no tmpfs mounted at all. |
| R-03 | Replace the mutable `:v1` tag with immutable tags | **Done** 2026-09-03 · 11:20 IST | None | `c06d65f`. `image_tag_mutability = "IMMUTABLE"` in `ecr.tf`; the Makefile derives the tag from the links-service commit SHA (a dirty tree gets a timestamp suffix so the push stays unique). A tag now names exactly the code it was built from. **Takes effect on the next `terraform apply`.** |
| R-04 | Deploy into a dedicated namespace | **Done and VERIFIED on a live cluster** 2026-09-10 — **admission control demonstrably rejected a non-compliant pod** | None | `e073761`. New `00-namespace.yaml` (the `00-` prefix is load-bearing — `kubectl apply -f dir/` goes in filename order and everything else references the namespace). Enforces the **restricted** Pod Security Standard, so non-compliant manifests are rejected at admission rather than quietly running as root. 
| R-05 | Observability: **Prometheus / Grafana via `kube-prometheus-stack`** | **DONE and VERIFIED ON REAL EKS** 2026-09-14 — 22 targets all UP, five of them app-hub pods, scraped because of one `ServiceMonitor` with no config file edited and nothing restarted. Built as a **guided build** (`CLAUDE.md § 2`), a tier added this day at the owner's request: Claude wrote `values.yaml` and the `ServiceMonitor`, the owner ran every command and hit every failure. `learn/30` | Depends on `E-04`. **Phase 2 in the owner roadmap — comes before CI/CD.** | Helm chart. Note this is *why* the node group is EC2 and not Fargate: `node-exporter` is a DaemonSet, which Fargate does not support. First stateful workload — the PVC/EBS teardown checklist in `CLAUDE.md § 9` becomes mandatory from here on. |
| R-06 | CI: **Jenkins in-cluster via Helm** | Not started — **OWNER's to write** (pipeline definitions + Helm values) | Depends on `R-05` landing first (owner roadmap phase 3) | Build, test, push image, then **commit a bumped image tag into the `manifests` repo**. Jenkins must never run `kubectl apply` — that is ArgoCD deliberately (see Decisions). |
| R-07 | CD: **ArgoCD, GitOps from `app-hub-manifests`** | Not started — **OWNER's to write** (`Application` definitions) | Depends on `R-06` (owner roadmap phase 4) | ArgoCD watches the manifests repo and reconciles. Current state is *GitOps-shaped, not GitOps*: declarative and versioned, but still applied by hand. ArgoCD supplies the missing reconciliation half. |

### Phase 4 — n8n workflows

Self-hosted n8n. Workflow definitions are version-controlled in `n8n/`; credentials never are.

| ID | Task | Status | Blocker | Next step |
|----|------|--------|---------|-----------|
| N-00 | `cost-watchdog` — ✅ **working, published/active** | None | Schedule Trigger (5 PM + 9 PM, two rules) → HTTP Request → Gmail. Calls `GET https://eks.ap-south-1.amazonaws.com/clusters/app-hub-eks` with Predefined Credential Type → AWS (IAM) → `n8n-readonly`. **On Error must be `Stop Workflow`** — 404 (cluster gone) halts silently, 200 (still up) proceeds to Gmail. Gmail via OAuth2, Google Cloud project `n8n-app-hub`. |
| N-00b | `destroy-notifier` | **Done** 2026-09-05 · 16:25 IST | None | All four nodes wired (`Webhook → If → Success/Failure`), active, using `emailSend` + SMTP. **Verified end to end:** success payload → `Success` node, failure payload → `Failure` node, both with SMTP reporting `accepted:[...], rejected:[]`. Committed `51a7aab`. Remaining follow-up: schedule `scripts/scheduled-destroy.sh` via Windows Task Scheduler. |
| N-01b | Prove `cost-watchdog` actually sends its email | **DONE 2026-09-13** — **the email arrived in the inbox.** Execution `38`, `mode=manual`, `status=success`, 07:25:25 UTC. First email this project has ever sent. | Cannot be tested without a cluster — no manual-run endpoint (API returns `405`), and with no cluster the EKS call 404s and `onError: stopWorkflow` halts before the email node. | **Correction 2026-09-10: this does not need a cluster, and saying so for a week is why it kept slipping.** The *end-to-end* path does — the HTTP Request node 404s without a cluster and `onError: stopWorkflow` halts there, which executions 29 and 33 both confirm (`node: HTTP Request, msg: The resource you are requesting could not be found`). But the **unproven** part is narrower than that: *does the email node actually send?* In n8n you can **execute a single node** — open the workflow, select the email node, run just that step. No cluster involved. <br><br>That will not exercise the 404-halts-silently branch, but executions 29 and 33 already prove it. It will prove the only thing that has never been proven: **that the mail leaves.** `destroy-notifier` established the SMTP credential works; what is untested is whether *this* workflow's email node is wired correctly. <br><br>Attempted 2026-09-10 with a live cluster and **no email arrived, and no execution was recorded.** Manual executions *are* persisted on this instance (ids 28 and 29 are `mode=manual`), so a click that reached the engine would have left a record — meaning the workflow did not run rather than ran and failed. |
| N-01 | Scaffold the `n8n/` repo | Done | None | Done 2026-08-30: git repo, `.gitignore`, `.gitattributes` (LF enforcement), `.env.example`, `pull-workflows.sh`, README with security rules |
| N-02 | Create the `app-hub-n8n` GitHub remote and push | **Done** | None | Done 2026-08-30. The scaffold had **zero commits** — made the initial commit, wired `origin`, pushed. Secret-scanned before pushing; no real `.env` exists. |
| N-03 | Populate `n8n/.env` with the instance URL and API key | **Done** 2026-08-31 | None | Verified: both values populated, `.env` matched by `.gitignore:2`, absent from `git status`. API returns **HTTP 200** and lists both workflows (`eks-cost-watchdog`, `terraform-destroy-notifier`). Key never entered the transcript. |
| N-04 | Pull the existing workflows into `n8n/workflows/` | **Done** 2026-08-31 | None | Pulled 2 workflows via the API (`065b447`): `eks-cost-watchdog` (active) and `terraform-destroy-notifier` (inactive). Count checked against `jq .data | length` **before** writing — an earlier grep had matched nested node names and suggested 14. Secret-scanned: only credential *references* (`AWS (IAM) account`, `Gmail account`), no values. |
| N-05 | Back up the n8n encryption key outside the repo | **Done** 2026-08-31 (owner-reported) | None | Owner confirms the key from the `n8n_data` volume (`/home/node/.n8n/config`) is stored in a password manager. Not independently verifiable by design — nothing in this repo should ever be able to see it. Unblocks `N-06`. |
| N-06 | Move n8n onto the EKS cluster | **Decided: YES** (2026-08-30) — **mostly OWNER**: `ConfigMap`/`Secret`/`PVC` and Helm values are new object types and hand-write items; the Deployment/Service are second instances, so Claude's | Depends on Phase 2 landing first. Not urgent — local Docker is fine meanwhile. | Needs: a Postgres backing store (n8n defaults to SQLite, unsuitable in a pod), `N8N_ENCRYPTION_KEY` supplied as a Kubernetes Secret (**must be the existing key from `~/.n8n`, or every stored credential becomes undecryptable** — see `N-05`), and persistent storage. Note this interacts with the destroy-every-session policy: the database must live outside the destroyed stack. See the `C-03` note on splitting Terraform into ephemeral and persistent stacks. |

### Phase 5 — Further services

| ID | Task | Status | Blocker | Next step |
|----|------|--------|---------|-----------|
| S-01 | Build `gateway` — entry point, routes to `links-service` by Kubernetes DNS name | **DONE** 2026-09-10 — all six steps, **deployed and verified on real EKS** | None | **Repo `app-hub-gateway` exists and is pushed** (sixth repo — `CLAUDE.md § 3`). Owner writes every line; Claude reviews and verifies. Six-step build order and rationale in `learn/21`. <br><br>**Done:** (1) skeleton + `/health` on port **8001** — `36feb40`, 2026-09-06 · 12:22 IST. (2) `GET /links` calling `links-service`, `async def` + `httpx.AsyncClient`, client moved to app scope via `lifespan` — `7c52711`/`1d5c088`, 2026-09-07 · 11:27–13:27 IST. (3) explicit 3s client timeout + upstream failure mapping — `261e5db`, 2026-09-07 · 18:35 IST. **All four paths verified live** against a fake upstream: nothing listening → `503`; hangs 30s → `504` at 3.01s; upstream 4xx/5xx → `502`; healthy → `200`. <br><br>**Steps 4–5 done; step 6 is written and validated but NOT applied** (2026-09-10). The ECR repository (`0b280cf` in `app-hub-infra`) and the manifests (`c698344` in `app-hub-manifests`) exist in git and pass offline validation; nothing has been applied because there is no cluster. What remains is `make deploy` against a live cluster. <br><br>**Steps 4–6 reassigned to Claude on 2026-09-09** by the `CLAUDE.md § 2` revision — step 4 is config plumbing, step 5 is a copy of the `links-service` Dockerfile, and step 6's Deployment/Service are second instances of object types the owner has already written. Steps 1–3 stay owner-written and are not to be rewritten. <br><br>**Step 4 DONE** 2026-09-09 · 13:10 IST (`cb39f11`, Claude-written). `LINKS_SERVICE_URL` read at module scope with `.rstrip("/")`; the `503`/`504` handlers no longer pass `str(e)` to the caller, so the upstream URL stops leaking — fixed strings out, real exception to the log. Added `tests/fake_upstream.py` (port + mode aware: `ok`/`404`/`html500`/`slow`). **Verified, five cases against a freshly started gateway:** unset → `200`; `:9999` → `503`; `:8000/` → `200` (rstrip); `:8002` 404 → `502`; `:8003` slow → `504` at 3.02s. Bodies carry no URL. <br><br>**Step 5 DONE** 2026-09-09 · 13:40 IST (Claude-written). `Dockerfile` near-identical to the `links-service` one, port 8001, plus a `.dockerignore` (see `D-14`). **Verified:** image builds; runs under `docker run --read-only` with no tmpfs; `id` reports uid 10001; `/health` 200; `/links` returns `503` correctly because inside the container `localhost:8000` is the *container's* localhost. <br><br>**Step 6's core claim was then rehearsed locally, for free:** both images on a Docker network, `gateway` pointed at `-e LINKS_SERVICE_URL=http://links-service:8000`, reaching `links-service` **by name** — seeded a record and read it back through `gateway`, both containers read-only and non-root. The Kubernetes version differs only in who supplies the DNS name (a Service rather than a network alias). Test containers and network removed; nothing pushed. <br><br>**Next: step 6** — second ECR repo in `infra/ecr.tf`, manifests (`Deployment` + `Service`, second instances so Claude's; the `env:` block is the one new part and gets flagged), deploy. **Costs money — batch into the next cluster session.** Note the teardown script currently empties only the `links-service` ECR repo; a second repo full of images is a new way for `destroy` to fail (`CLAUDE.md § 9`). <br><br>**`learn/22` WAS written** (short note, per the two-tier rule) and covers steps 4–5. *This cell previously said it would not be written, which was the plan before the 2026-09-09 revision made delegated work get short notes too. Caught 2026-09-13 during a `learn/` audit — and it had already caused a second error, an edit to `gateway/README.md` asserting the file did not exist.* `learn/21` carries the design rationale, `learn/27` the dashboard and full proxy. |
| S-02 | Build `aggregator` — calls `links-service` internally; **the service that truly proves discovery** | **DONE** 2026-09-13 (`83d4b1d`) — **written AND verified running locally** against real targets. Not deployed: needs a cluster. | None — the owner created `HarshitRawat11/app-hub-aggregator` on 2026-09-13, which cleared the last blocker. *Was: blocked on the owner, twice over.* (1) It needs a GitHub remote — there is no `gh` CLI on this machine, so `HarshitRawat11/app-hub-aggregator` has to be created in the web UI. (2) It has to pick an HTTP client, which is `D-17`. | Application code, named explicitly in the `CLAUDE.md § 2` delegation list. Distinct from `gateway`: `gateway` is the external entry point, `aggregator` exercises purely internal pod-to-pod discovery. Its Deployment/Service are second instances, so also Claude's; anything new in the manifest gets flagged in a few lines rather than walked through. <br><br>**What it actually does:** reads the catalogue from `links-service` and **probes every URL concurrently**, so the dashboard shows which apps are reachable rather than just listing them. That makes it real software rather than a discovery demo — and its workload genuinely differs from a CRUD API (waiting on slow third parties vs answering from memory), which is the honest test of whether something deserves to be its own service. <br><br>**The chain it completes:** browser → `gateway` → `aggregator` → `links-service`. `aggregator` is `ClusterIP` and never publicly reachable, so **neither end of the inner hop is the front door** — which is what makes it a real test of Kubernetes DNS rather than a restatement of "the entry point can reach a service". `gateway` gained `GET /status` to proxy it, because the same-origin dashboard has no other way to reach a ClusterIP service. <br><br>**Central rule: a down link is DATA, a down `links-service` is an ERROR.** `/status` answers 200 with the link marked `down`; only the upstream being unreachable is 5xx. Blurring them leaves the dashboard unable to tell "your NAS is off" from "the hub is broken". Anything under 500 counts as `up`, **including 401/403** — the question is "is it running", not "may I in". <br><br>**47 tests**, plus 6 added to `gateway` for the new hop. **Verified live against real targets:** a running n8n (`up`, 200, 4 ms), a stopped Grafana (`down`, `ConnectError`), example.com over the real internet (`up`, 78 ms), and `169.254.169.254` (`blocked`). Also verified that stopping `aggregator` leaves the dashboard working with grey dots and **no error banner** — liveness is a decoration on the catalogue, not a dependency. <br><br>See `D-20` for the SSRF consideration, and `learn/28`. |
| S-03 | Build `frontend` — the dashboard | **DONE** 2026-09-13 · 00:01 IST (`c522956`) — **written AND verified running locally** (two services, driven through a real browser). Not yet deployed: needs a cluster session. | None | Application code. **Built INTO `gateway` rather than as a fourth service, which is a deliberate change from how this row was originally written** — see `learn/27`. A separate frontend would have needed CORS on every gateway response, a second public endpoint (so a second ELB, which `E-06` is explicitly deferring), and a third GitHub repo only the owner can create. Served from gateway, every URL in the page is a bare path and none of that exists. Reversible if `E-06` later wants it behind its own nginx pod. <br><br>**gateway became a real proxy to make it useful:** `GET /links/{id}`, `POST /links` and `DELETE /links/{id}` added alongside the original `GET /links`, all through one `_proxy` helper holding the owner's step-1–3 error mapping — moved, not rewritten. <br><br>**The design point worth keeping: not every upstream 4xx is a gateway fault.** A `404` from `GET /links/{id}` is the correct answer about an id that does not exist, and a `422` from `POST` is about what the caller sent. Flattening either to `502` says *the server is broken* and sends someone to the wrong machine. `GET /links` passes nothing through, because the collection always exists — the asymmetry is the point. <br><br>**47 tests, up from 15.** Verified live: all four routes through gateway to links-service, `Location` round-trip followed, `503`/`504`/`502` all reproduced (504 at 3.006 s), and the XSS guards proven with a real payload rather than asserted. See `D-19` for the bug every test missed. |

---

## Known defects

| ID | Severity | Where | What is wrong |
|----|----------|-------|---------------|
| `D-24` | **High — the cost safety net's primary control is intermittently dead** | n8n `eks-cost-watchdog` (Schedule Trigger), n8n in Docker Desktop on the laptop | **The schedule trigger stops firing after the host sleeps, and still reports `active: true`.** <br><br>Evidence, all read 2026-09-16 with no cluster and no cost: execution **44** fired at `2026-09-14 21:00:05 IST`, `mode=trigger` — correct hour, correct timezone, the `D-22` fix working. Windows then slept `2026-09-14 22:45 UTC → 2026-09-15 05:46 UTC`. **Since that resume there has been no trigger execution at all**, although on 2026-09-15 the machine was awake `11:16–21:41 IST` — covering *both* the 17:00 and the 21:00 trigger — the container was up continuously (`StartedAt 2026-09-14 11:34 UTC`, never restarted), and the workflow is still `active: true` with empty `pinData`. <br><br>**Why this is worse than `D-22`, not a repeat of it.** `D-22` was reliably dead: wrong timezone, never fired, no email ever. This one fires *sometimes* — and an alert that arrives sometimes is what earns the trust that makes you stop running `make status`. <br><br>**The deeper problem is architectural and is the owner's call.** A watchdog for cloud spend runs on a laptop that sleeps. The window it must cover — cluster left up overnight — is *precisely* the window in which the laptop is off. Restarting the container re-registers the crons and is a workaround, not a fix. The durable answer is something that runs in AWS: an **AWS Budgets alert** (free, email, zero infrastructure) or an **EventBridge schedule**. Both are new services, so `CLAUDE.md § 4` says ask first. <br><br>**Until then: verify teardown with `make status`, never by the absence of an email.** |
| `D-25` | **Medium — a teardown failed and the notification about it also failed** | `scripts/scheduled-destroy.sh`, WSL DNS, n8n SMTP | **The 2026-09-14 nightly teardown exited 2, and nothing told anyone for two days.** <br><br>`logs/scheduled-destroy-2026-09-14_174528.log` ends: `Error: validating provider credentials: retrieving caller identity from STS: ... lookup sts.ap-south-1.amazonaws.com on 8.8.8.8:53: i/o timeout` → `destroy finished: failure (exit 2)`. That is the documented WSL2 DNS failure (`CLAUDE.md § 5`), here across a sleep/resume. <br><br>**Then the second layer failed too.** The script did POST to `destroy-notifier`, which ran (execution **45**) and could not send: `connect ECONNREFUSED 192.178.158.108:465`. So the failure notification failed. <br><br>**No money was lost** — the cluster had already been destroyed by hand that evening, so the teardown was a no-op that failed rather than a real teardown that was skipped. The 2026-09-16 run succeeded (`0 destroyed`, `HTTP 200`). **That is luck, not design:** had a cluster been up, it would have billed until someone opened the logs. <br><br>**Also worth noting:** the log's own filename (`17:45:28` UTC) and its first line (`04:15 IST`) disagree by about five hours, and 04:15 IST is exactly when Windows went to sleep. The clock behaviour across suspend is **UNKNOWN** and deliberately not explained here rather than guessed at. <br><br>**The teardown is also not running at 23:30.** Both recent runs finished at ~11:18 and ~11:24 IST, minutes after the machine woke — Task Scheduler catching up a missed start. Same root cause as `D-24`: the laptop is asleep at 23:30. |
| ~~`D-01`~~ | **RESOLVED** 2026-08-30 (`7b7b0bd`) | [links-service/app/main.py:29](links-service/app/main.py:29) | `createLink` builds `new_link = Link(id=next_id, ...)` but then stores the *incoming* `link` (a `LinkCreate`, which has no `id`). It returns `new_link`, so `POST` looks correct — but `GET /links` and `GET /links/{id}` return records with no `id` field. Fix: store `new_link`. |
| ~~`D-16`~~ | **RESOLVED** 2026-09-10 | [links-service/app/main.py](links-service/app/main.py) | Was: `POST /links` returned **`200`**, not `201 Created`. REST convention for a request that creates a resource is `201` plus a `Location` header pointing at it. Nothing is broken — `gateway` only checks `>= 400`, and the tests assert current behaviour — but it is a public API contract, so **flagged for the owner's decision rather than changed**. **Owner decided: change it.** Now `status_code=201` with a `Location` header pointing at `/links/{id}`, plus a test asserting the header resolves. Done while nothing external consumed the API and `gateway` only checks `>= 400` — the last cheap moment before something depended on `200`. |
| ~~`D-17`~~ | **RESOLVED** 2026-09-10 | [gateway/pyproject.toml](gateway/pyproject.toml) | Was: the two services used **different HTTP clients**: `links-service` moved to `httpx2` 2.12.0 (starlette's `TestClient` deprecates `httpx`), while `gateway` still uses `httpx` 0.28 as a **runtime** dependency for its `AsyncClient`. Nothing is broken and no deprecation applies to gateway's usage — but two services in one project on different HTTP clients will surprise someone later, and `S-02` will have to pick one. **Owner decided: move `gateway` to `httpx2` as well.** Done while gateway was still undeployed, which was the cheapest moment — its whole surface is one `AsyncClient`, one `get` and three exception types, and every name it uses (`TimeoutException`, `RequestError`, `ConnectError`, `MockTransport`, `Response`) exists identically in `httpx2` 2.12.0, with `TimeoutException` still subclassing `RequestError`. A pure import swap; 15 tests pass and the starlette deprecation warning is gone. **`S-02` now has an obvious answer instead of a coin-flip.** |
| ~~`D-23`~~ | **RESOLVED 2026-09-14** — `cluster_version` raised to **1.36** (standard support to 2027-08-02). `terraform validate` and `plan` both clean, 59 to add, plan confirms the new version. **Not yet exercised by a real `make up`** — the next cluster session is the proof. 1.34 was rejected deliberately: its standard support ends 2026-12-02, which would put this task straight back on the board. | [infra/eks.tf](infra/eks.tf) | **`cluster_version = "1.31"` is in EXTENDED support, and that is 74% of every cluster bill.** Verified 2026-09-13 via `aws eks describe-cluster-versions`: 1.31 left standard support on **2025-11-26** and extended support ends **2026-11-26**. The AWS Pricing API gives the only non-Auto EKS rate in `ap-south-1` as `APS3-AmazonEKS-Hours:extendedSupport` at **$0.50/hour — five times the $0.10 standard rate**. <br><br>**Measured, not estimated.** The 2026-09-13 session ran 3.54 control-plane hours and cost **$2.40 (~Rs 211)** in total, of which **$1.77 was the control plane**. On standard support the same session would have been **$0.98 (~Rs 87)**. <br><br>**`CLAUDE.md` § 4's "$150–200/month if left up 24×7" is therefore understated** — the control plane alone at $0.50/h is ~$365/month. That figure needs correcting once the version is decided. <br><br>**Also a deadline, not just a cost:** after 2026-11-26 AWS force-upgrades the control plane on its own schedule. <br><br>**Fix is one line** — `cluster_version` to `1.34` (standard support until 2026-12-02) or later. It is the owner's: a Terraform change to the EKS module, and a version jump can surface API deprecations, so it wants a `plan` read rather than a blind bump. |
| ~~`D-22`~~ | **RESOLVED AND BEHAVIOURALLY VERIFIED 2026-09-14** | n8n `cost-watchdog` (Schedule Trigger) | **The cost watchdog has never fired on schedule, and structurally cannot.** Its trigger is set to hours 17 and 21, but n8n interprets those in `GENERIC_TIMEZONE`, which is **unset on this container** — so n8n falls back to its default, `America/New_York`. Verified: `docker exec n8n env` shows neither `GENERIC_TIMEZONE` nor `TZ` set, the container clock is UTC, and the workflow's own `settings` carry no timezone override. **17:00 America/New_York = 02:30 IST and 21:00 = 06:30 IST** (EDT is `-0400`, IST is `+0530`). <br><br>**So it checks at 2:30am and 6:30am**, by which time the 23:30 nightly teardown has already destroyed the cluster — meaning it can never find one running and can never email. A monitor that runs at a time when the condition it watches for is impossible. <br><br>**Proven by omission on 2026-09-13**: the cluster was up from 20:30 IST, past both intended trigger times, and the n8n API shows **no scheduled execution at all** — the most recent run is that morning's manual test. n8n itself was up 12 hours, so it was not a downtime problem. <br><br>**This is `learn/17`'s timezone trap in a different tool**, and it is why `N-01b` closing was not the same as the watchdog working: `N-01b` proved the email NODE sends, never that the workflow FIRES. <br><br>**FIXED 2026-09-14.** The container was recreated with `-e GENERIC_TIMEZONE=Asia/Kolkata -e TZ=Asia/Kolkata`; the `n8n_data` volume persisted, and both workflows plus both credentials (`AWS (IAM) account`, `SMTP account`) came back intact. **`--restart unless-stopped` was added at the same time** — the container's restart policy had been `no`, which is why it was found `Exited (137)` earlier that day and needed a manual start. **A watchdog whose n8n is not running cannot fire either**, so that was part of the same defect. <br><br>**Verified behaviourally, not by reading the setting back** — reading it back is precisely what would have hidden this again. A throwaway workflow was created via the API with cron `22 0 * * *`, three minutes in the future **IST**. It fired at **00:22:08 IST**, `mode=trigger`, `status=success`. Under `America/New_York` that same cron would have been ~9.5 hours away and nothing would have happened. Probe deactivated and deleted; only the two real workflows remain. <br><br>**PARTLY ANSWERED 2026-09-16, and it did not need a cluster.** Execution **44** shows `cost-watchdog` firing at `2026-09-14 21:00:05 IST`, `mode=trigger` — on its own schedule, at the right IST hour, for the first time ever. It 404'd and halted because the cluster was already gone, which is correct. **So the trigger half is proven; only the "sees a live cluster, therefore emails" half is not.** <br><br>**But see `D-24`** — it has not fired since, and the fix verified here turns out to survive only until the host sleeps. |
| ~~`D-21`~~ | **RESOLVED same day** 2026-09-13 | [manifests/gateway/deployment.yaml](manifests/gateway/deployment.yaml) | `AGGREGATOR_URL` was added to gateway's code with a `http://localhost:8002` default but **never added to its Deployment**. In a pod `localhost` is the pod, so gateway dialled *itself* on 8002 and answered `503 aggregator unavailable` for every `/status` request. **Second instance of one pattern** — identical in shape to the `LINKS_SERVICE_URL` port bug of 2026-09-10 (`:8000` vs `:80`): a sensible local default, a Deployment that forgot to override it, and nothing consuming the value until the day something did. **A config variable whose default is `localhost` is a landmine unless the Deployment overrides it.** Worth noting the error mapping worked exactly as designed — it said *aggregator* unavailable, naming the right service, which is the whole reason gateway distinguishes 502/503/504. Also note aggregator's Service exposes **8002 targeting 8002**, unlike links-service's 80→8000; copying the `:80` out of symmetry is how this recurs. |
| `D-20` | Informational — **mitigated by design** | [aggregator/app/probe.py](aggregator/app/probe.py) | `aggregator` fetches URLs that **anyone who can `POST` to `links-service` chose**, from inside the cluster — textbook SSRF, where the value of the attack is precisely the network position the service has. **Logged even though it is mitigated**, because the mitigation is narrow on purpose and a future reader needs to know why rather than "fixing" it. The reflex answer — block private address space — is **wrong here**: app-hub exists to catalogue apps on `10.x`, `192.168.x` and `localhost`, so that would block the product, and a guard that breaks the use case gets deleted within a day. It refuses link-local (`169.254.0.0/16`, the instance metadata endpoint), cloud metadata hostnames, and non-HTTP schemes; hostnames are resolved before checking. **Known gap, stated rather than hidden:** DNS can answer differently between our lookup and the client's (DNS rebinding). Closing it means pinning the resolved address via a custom transport — worth doing if this ever probes URLs from an untrusted source. **This matters more after `C-05`**, which attaches a real IAM role to this namespace. |
| `D-19` | Informational — **fixed same day** | [gateway/app/static/style.css](gateway/app/static/style.css) | The dashboard's add form was marked `hidden` and rendered anyway, and the JS toggling `.hidden` did nothing at all — silently. `hidden` is not a behaviour, it is one rule in the browser's default stylesheet (`[hidden] { display: none }`), and **any author rule setting `display` outranks it**; `#add-form { display: flex }` did. Fixed with `[hidden] { display: none !important; }`. **Kept in this table because of what it says about the tests, not the bug:** all 47 passed, including seven that assert the page is served, typed correctly, does not shadow `/health`, and references only assets that exist. Every one was true and every one was blind to the rendered result. **"The tests pass" and "it works" are different claims about a user interface.** A follow-on of the same shape: the CSS fix appeared to do nothing because the browser reused a cached `style.css` without revalidating — which after a deploy means new HTML with an old stylesheet and no error anywhere. `/` and `/static/*` now send `Cache-Control: no-cache` (meaning *revalidate*, not *do not cache*). |
| ~~`D-18`~~ | **RESOLVED 2026-09-13** | [manifests/links-service/deployment.yaml](manifests/links-service/deployment.yaml) | **Closed by `C-05`**, which shipped `LINKS_TABLE_NAME` and `serviceAccountName` in one change as this defect required, and was then verified on a live cluster — a write through the pod landed in the real table. **The rule outlived the defect and is now mechanical**: `validate-manifests.py` fails if a Deployment sets `LINKS_TABLE_NAME` without a `serviceAccountName`, if that name has no ServiceAccount beside it, if the ServiceAccount lacks the role-arn annotation, or if `AWS_REGION` is missing. *Was:* the Deployment did not set `LINKS_TABLE_NAME`, so the deployed service stayed in-memory despite `C-06` landing. **That was deliberate until `C-05`.** Setting it without IRSA gives the pod a table it cannot authenticate to, and the failure is close to silent: `build_repository()` only constructs a boto3 resource so **startup succeeds**; `/health` does not touch storage so **the liveness probe passes and the pod stays `Running` and `Ready`**; every `/links` request then fails with `NoCredentialsError` → 500. Apply the env var and `serviceAccountName` in the same change as `C-05`. |
| ~~`D-02`~~ | **CLOSED 2026-09-13** (was High) | [manifests/links-service/deployment.yaml](manifests/links-service/deployment.yaml) + [links-service/app/main.py:5](links-service/app/main.py:5) | `links_db` is an in-process dict, but the Deployment runs `replicas: 2`. **Inconsistent-read half fixed 2026-08-30** by pinning `replicas: 1` (`93cea2c`). Data is still lost on restart — durability lands with `C-04`–`C-06`. Do not raise replicas before then. |
| ~~`D-03`~~ | **RESOLVED** 2026-08-30 (`5e312ef`) | [links-service/Dockerfile:1](links-service/Dockerfile:1) | Base is `python:3.12-slim` while `pyproject.toml` requires `>=3.14` and `.python-version` says `3.14`. `uv sync` will silently download a managed Python 3.14 rather than use the base image's interpreter — bloating the image and making the base tag a lie. Tracked as `P-03`. |
| ~~`D-04`~~ | **RESOLVED** 2026-08-30 (`5e312ef`) | [links-service/Dockerfile](links-service/Dockerfile) | Untracked in git — the build is not reproducible from a clean clone. Tracked as `P-02`. |
| ~~`D-05`~~ | **RESOLVED** 2026-08-31 (`99381d0`) | [manifests/links-service/service.yaml](manifests/links-service/service.yaml) | Was: `ClusterIP` with no Ingress meant the app was unreachable from outside the cluster. Fixed by `E-05` — the Service is now `type: LoadBalancer` with the NLB annotation, and full CRUD was verified from the internet. **Note the follow-on cost concern, tracked separately as `E-06`:** one LoadBalancer Service means one ELB and one bill, so this does not scale past a couple of services. |
| ~~`D-06`~~ | **RESOLVED** 2026-08-30 (`3cb9e57`) | [infra/vairables.tf](infra/vairables.tf) | Filename typo (`vairables` → `variables`). Terraform loads all `.tf` files so behaviour is unaffected, but it reads as sloppy in a portfolio repo. Tracked as `P-04`. |
| ~~`D-07`~~ | **RESOLVED** 2026-08-30 (`3cb9e57`) | [infra/main.tf](infra/main.tf) | Empty file (0 bytes). Tracked as `P-05`. |
| ~~`D-08`~~ | **RESOLVED** 2026-08-30 (`f3203de`) | [links-service/README.md](links-service/README.md) | Empty file (0 bytes), yet referenced as `readme` in `pyproject.toml`. Tracked as `P-06`. |
| ~~`D-09`~~ | **RESOLVED** 2026-09-10 (`fc753f8`) | [links-service/pyproject.toml](links-service/pyproject.toml) | Was: `description = "Add your description here"`, leftover `uv init` scaffold text in a repo that is also a portfolio piece. Now describes the service. |
| ~~`D-11`~~ | **RESOLVED** 2026-08-30 (`5e312ef`) | [links-service/Dockerfile:8](links-service/Dockerfile:8) + `:14` | Build runs `uv sync --frozen --no-install-project`, but `CMD` uses `uv run`, which re-resolves and installs the project **at container start**. That defeats the build-time sync, moves dependency work into startup (slowing pod readiness, risking a cold-start failure), and will bite when the base image changes. Fix: install the project at build time and invoke `uvicorn` directly in `CMD`. Missed in the 2026-08-30 audit; surfaced from project history. |
| ~~`D-10`~~ | **RESOLVED** 2026-09-10 (`fc753f8`, `c921f03`) | [links-service/app/main.py](links-service/app/main.py) + [gateway/app/main.py](gateway/app/main.py) | Was: `camelCase` handler names against PEP 8. Renamed in **both** services — `get_links`, `get_link`, `create_link`, `remove_link` — so the two do not diverge. Behaviour-neutral, and **the tests written first are what proved it**: all 14 still pass. The one externally visible effect is the OpenAPI `operationId` (now `get_links_links_get` and so on), which nothing consumes. `get_links` also lost a manual append loop in favour of `list()`. |
| ~~`D-13`~~ | **RESOLVED** 2026-09-05 (`51a7aab`) | n8n credential | Was: the Gmail OAuth refresh token expired, silently disabling **both** workflows -- `cost-watchdog` shared the credential, so it reported `active` but could not email. **Fixed by moving both workflows off Gmail OAuth to `emailSend` nodes with an SMTP credential**, which removes the ~7-day refresh-token expiry entirely. Verified: `destroy-notifier` executions now report `status=success`, and the SMTP server returned `accepted:[harshitrawat2011@gmail.com], rejected:[]` on both branches. **`cost-watchdog` remains unverified end to end** -- see `N-01b`. |
| ~~`D-14`~~ | **RESOLVED** 2026-09-09 | [links-service/.dockerignore](links-service/.dockerignore) | Was: no `.dockerignore` in `links-service`, so the whole directory — including a ~17 MB `.venv` — was tar'd and shipped to the Docker daemon as build context on every build. Nothing extra reached the *image* (the `COPY` lines are specific), so this was wasted transfer plus a missing safety net for the day someone writes `COPY . .`. Fixed by adding the same file `gateway/` got. Found while doing `S-01` step 5. |
| ~~`D-15`~~ | **RESOLVED** 2026-09-09 (`233d48b`) | [infra/.gitignore](infra/.gitignore) | Was: `.terraform.lock.hcl` gitignored, so with `required_providers` pinned only to `~> 5.0` a fresh clone could resolve a *different* AWS provider 5.x than the one this project was built and tested against — undercutting "deployable by someone else" (`CLAUDE.md § 1`), the same argument that justifies the S3 backend and `uv.lock`. Fixed: the file is committed and the gitignore now carries a comment explaining why it must stay committed. **Providers are now pinned at aws 5.100.0**, cloudinit 2.4.0, null and the rest. Scanned first — versions and checksums only, no secrets. Its `zh:` registry hashes cover every platform, so the WSL-generated copy does not lock anyone to `linux_amd64`. **`C-04` must commit its own lock file too.** |
| ~~`D-12`~~ | **RESOLVED** — already fixed, row was stale | all five component repos | Was: no `.gitattributes`, so git warned `LF will be replaced by CRLF` on every commit, and the same setting is what breaks shell scripts under WSL (`learn/08`). **Verified 2026-09-10: all five repos — `infra`, `links-service`, `gateway`, `manifests`, `n8n` — carry `* text=auto eol=lf`.** The row had simply not been closed when the files were added. Found while listing pending tasks. |

---

## Decisions on record

| Date | Decision | Rationale |
|------|----------|-----------|
| 2026-09-09 | **`persistent/` lives at `infra/persistent/`, inside the `app-hub-infra` repo** — not a seventh git repo, and not a restructure into `infra/ephemeral/` + `infra/persistent/` siblings | Owner-confirmed. It is Terraform, maintained alongside `infra/`, and the polyrepo split exists to separate *components* rather than directories. One repo also means a change spanning both stacks is one commit. The asymmetry (ephemeral at the root, persistent in a subdirectory) is accepted deliberately: making it symmetric would touch the `Makefile`, `scripts/scheduled-destroy.sh`, both READMEs and several `learn/` files in order to break an already-proven teardown path. **Safety does not depend on the layout** — `terraform` does not recurse into subdirectories, so `make down` cannot reach the persistent stack, and `prevent_destroy` on the table is a second line of defence. |
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

### 2026-09-16 — The validator was not validating the thing it was written for

**No cluster, no cost. Three findings, one fixed, two recorded.**

**1. `make validate` never opened `manifests/monitoring/`.** The loop was
`$(MANIFEST_ROOT) $(foreach s,$(SERVICES),...)`, and `SERVICES` is
`links-service gateway aggregator`. `monitoring/` is not a service, so it was
not in the list — which means the ServiceMonitor cross-check added on
2026-09-14, **written specifically for the file in that directory**, had never
once run under `make validate`. The command printed `all checks passed` without
opening the file it was built to check.

`SERVICES` could not simply be extended: it also drives build/push/deploy, so
`monitoring` would have been handed to `docker build` with no source tree.
**Fixed by deleting the list rather than extending it** — the loop is now a
shell glob over `$(MANIFEST_ROOT)/*/`, so a new manifest directory is covered
the moment it exists. Same failure family as `ECR_REPOS` and the root
`.gitignore`: a hand-maintained list that nothing reconciles against the
filesystem, failing by **omission**, which produces silence rather than an error.

**Proven, not assumed.** A copy of the real ServiceMonitor with `port: http`
changed to `port: bogus-port-name` was run through the validator: three `FAIL`
lines, exit 1. `make validate` now walks six directories including `monitoring`,
and passes.

**2. `cost-watchdog` fired on its own schedule for the first time ever — and
then stopped.** Execution **44**, `2026-09-14 21:00:05 IST`, `mode=trigger`:
correct hour, correct timezone, `404 No cluster found`, halted. The `D-22`
timezone fix confirmed on the real workflow rather than on the throwaway probe.

**The method is the transferable part.** `D-22`'s row said the one remaining
test was *"leave a cluster up past 17:00 IST"*. That was wrong, and expensively
so — it put a ~$0.28/hour cluster in the way of a question that the
**execution list already answered for free**. The 404 branch writes an execution
row exactly like the 200 branch would. *When a check needs an expensive
precondition, ask what the cheap half of it would already have told you.*

**3. But it has not fired since, and that is `D-24`.** On 2026-09-15 both
trigger hours passed with the machine awake (`11:16–21:41 IST`), the
container up continuously, `active: true`, empty `pinData` — and **no
execution row at all**. A Windows sleep sits between the last good fire and the
silence.

**This is worse than `D-22`, not a repeat of it.** `D-22` was reliably dead.
This is *intermittently alive*, and an alert that arrives sometimes is what
earns the trust that stops you running `make status`. **The architecture is the
real defect:** a watchdog for cloud spend runs on a laptop, and the window it
exists to cover — a cluster left up overnight — is precisely the window
in which the laptop is asleep. The durable answer runs in AWS (a Budgets alert
is free and needs no infrastructure), which is a new service and therefore the
owner's call under `CLAUDE.md § 4`.

**4. A teardown failed, and so did the notification about it — `D-25`.** The
2026-09-14 nightly run exited 2 on `lookup sts.ap-south-1.amazonaws.com ... i/o
timeout`, the documented WSL2 DNS failure, across a sleep/resume. It did POST to
`destroy-notifier`, which then could not send: `connect ECONNREFUSED
...:465`. **Both layers of the safety net failed in the same night and nothing
said so for two days.** No money was lost only because the cluster had already
been destroyed by hand — luck, not design.

Also visible in those logs: **the teardown is not running at 23:30.** Both
recent runs finished just after the machine woke, ~11:18 and ~11:24 IST —
Task Scheduler catching up a missed start, because the laptop is asleep at 23:30.
Same root cause as `D-24`.

**Verified live at 14:34 IST: nothing is billing.** No clusters, NAT gateways,
load balancers, running EC2, available EBS or unassociated EIPs. `app-hub-links`
intact.

**Stale-doc sweep of the START HERE block**, which is the block this file tells
Claude to read first and which still pointed at `R-05` as the next task. It
claimed a teardown two teardowns out of date, warned that `R-01`–`R-04` had
never met a real API server (they have, twice), and said the dashboard had never
run on the cluster (it has, since 2026-09-13). All corrected, each with a note
saying what it used to say — per `learn/25`, a silently corrected document
teaches nothing.

### 2026-09-14 — `R-05` done: Prometheus, Grafana, and the operator pattern proven

**The headline is not that Prometheus installed. It is that creating ONE Kubernetes object made it scrape five new endpoints, with no config file edited and nothing restarted.**

```
17 targets  ->  22 targets
UP  aggregator      http://10.0.1.109:8002/metrics
UP  gateway         http://10.0.2.157:8001/metrics
UP  gateway         http://10.0.1.199:8001/metrics
UP  links-service   http://10.0.1.38:8000/metrics
UP  links-service   http://10.0.2.117:8000/metrics
```

**Five targets for three services** — one per *pod*, because the operator resolves the Service to its endpoints. Querying across them returned real data: gateway 76, links-service 80, aggregator 31 requests.

**Built as a GUIDED BUILD, which is a new `CLAUDE.md § 2` tier added the same day at the owner's request.** Their reasoning, quoted in the rule: *"I don't know how to create these as this is my first time building this... when I build this at least 1 or 2 times then maybe in a different project we can start with just explanation."* That is correct — "explain, then you write" assumes a baseline a *first* Helm chart does not have. Claude wrote `values.yaml` and the `ServiceMonitor`, heavily commented; the owner ran every command and hit every failure. `learn/30` is a full seven-section file rather than a delegated short note, because the material is what `R-05` existed to teach.

**A recommendation reversed by checking rather than assuming.** The first draft said to use a PVC so the EBS-orphan lesson would land. `aws eks describe-addon-versions` showed **`aws-ebs-csi-driver` is a separate addon and is not installed by default** — so a PVC would have sat `Pending` forever with nothing saying why, and Prometheus would never have started. `emptyDir` instead; persistence becomes a follow-up teaching the CSI addon and a **second** IRSA role, building on `C-05`.

**Four defects found, three of them mine, two now mechanical.**

**1. The Services were unlabelled with unnamed ports.** A ServiceMonitor selects by **label** and references ports by **name**. With neither, it matches nothing and produces no target — and the operator, the monitor and Prometheus all stay silent. That is the commonest reason a ServiceMonitor "does not work". `validate-manifests.py` now cross-references every ServiceMonitor against the real Services and fails if a selected label or endpoint port name does not exist. **Proven to fire** against a reproduction of the pre-fix state.

**2. The validator crashed** on `manifests/monitoring/` because `values.yaml` is a Helm file with no `kind`. It now skips such documents **with a message** — silently skipping a manifest that lost its `kind` would be the exact gap the script exists to close.

**3. Grafana OOMKilled twice** at the 256Mi limit Claude set. Raised to 512Mi. **The instructive part is how it presented:** the browser said *"Error loading: timeseries — make sure it was compiled"*, which sends you into plugin documentation. Only `kubectl get pod -o json` said `reason=OOMKilled exitCode=137`. The memory limit was chosen *because* OOMKill fails loudly — and it does, in `kubectl`, not in the UI. **Where a failure is loud and where you are looking are different questions.**

**4. Disabling Alertmanager left a Grafana datasource pointing at it** — a Service that does not exist. **Turning a component off means turning off what points at it too**, or you get a permanently broken panel you learn to scroll past. Fixing it also needed a pod restart, not just a `helm upgrade`: **Grafana persists datasources in its own database once created**, so removing one from provisioning does not delete it.

**And one wrong call of Claude's, worth recording because it repeats a pattern.** 46 seconds after applying the ServiceMonitor, the target count was still 17 and Claude said *"the ServiceMonitor matched nothing"*. It had matched fine — the generated config already contained `job_name: serviceMonitor/monitoring/app-hub/0`. **There are two reload delays, not one**: operator → config secret, then config-reloader → Prometheus. Same impatience that nearly misdiagnosed the teardown as hung after two minutes. **Confirm against the generated config before concluding the operator failed.**

**`/metrics` on all three services**, via `prometheus-fastapi-instrumentator`. A library rather than a hand-rolled counter for one reason: **label cardinality**. A naive counter labels by request path, so `/links/<uuid>` creates a new series per id — unbounded, since ids are UUIDs, and the classic way to OOM Prometheus. The library groups by route template. **That claim is now a test**: `test_metrics.py` requests a fresh UUID and asserts it never reaches `/metrics` while `/links/{id}` does. 11 new tests, **149 total**.

**Also closed today:** `N-01b`'s full path finally ran — the owner clicked Execute on `eks-cost-watchdog` with a live cluster and **the email arrived**. And `D-23` is fully exercised: the 1.36 cluster came up clean and all three services deployed onto it with **no API deprecations** from the five-version jump.

### 2026-09-14 — Stale-doc sweep, and the localhost-default bug is now a check

**Asked whether anything was left for Claude, and rather than answer from memory the docs were actually swept.** Six stale claims turned up, all created by the previous day's work:

- `CLAUDE.md` and `CONTEXT-BRIEF.md` still said Kubernetes **1.31**; `README.md` said it three times and `infra/README.md` once
- `CONTEXT-BRIEF.md` still said **SIX git repos** — `aggregator` made it seven
- `CONTEXT-BRIEF.md` still said **"`C-06` is written and unit-tested but NOT verified against the real table"** and that the Deployment "deliberately does not set `LINKS_TABLE_NAME` yet (`D-18`)" — both false since the cluster session proved otherwise
- `README.md` and `CONTEXT-BRIEF.md` both described links-service as **`replicas: 1` (in-memory state)** — it is 2 and DynamoDB-backed since `D-02` closed
- `CONTEXT-BRIEF.md` and `infra/README.md` listed **two ECR repositories**, and `infra/README.md` had no row for `irsa.tf`

None of these would have failed anything. They are exactly the rot the drift checker was built for, in the prose it cannot reach — which is why the sweep has to be deliberate.

**The more useful outcome: `D-21`'s pattern is now a check rather than a lesson.**

`validate-manifests.py` reads each service's `app/main.py` for `os.getenv("NAME", "...localhost...")` and **fails if the Deployment does not override it**. It also fails if the override still contains `localhost`.

That pattern has now caused two production bugs:

- **2026-09-10** — `LINKS_SERVICE_URL` pointed at port **8000**, the container's port, when the Service exposes **80**. The symptom was `ConnectTimeout` rather than `ConnectError`, because the ClusterIP resolves and DNS works but no rule exists for that port, so packets are dropped rather than refused.
- **2026-09-13** — `AGGREGATOR_URL` was added to gateway's code and **never to its Deployment**, so in-cluster gateway dialled itself and answered `503` on every `/status`.

One pattern both times: a sensible local default, a Deployment that forgot to override it, and a value nothing consumed until something finally read it. **In a pod, `localhost` is the pod.**

**Proven to fire, not merely added.** Deleting the `AGGREGATOR_URL` entry from a copy of gateway's Deployment reproduces `D-21` exactly, and the validator returns `1 problem(s) found` naming the variable, the file, the default, and what would go wrong.

**Deliberately a regex over the source, not an import.** This script has to run with no service venv, no dependencies and no cluster. It reads one shape — `os.getenv("NAME", "default")` — which is what all three services use today. **If a service starts reading config another way the check goes quiet, so it is a floor and not a guarantee**, and the docstring says so rather than implying coverage it does not have. It also only reads `app/main.py`: `links-service` reads `LINKS_TABLE_NAME` from `app/repository.py`, which this would miss — that one is covered by the `D-18` check instead.

**138 tests passing** across the three services (38 + 53 + 47), `make validate` clean.

### 2026-09-14 — `D-22` and `D-23` fixed: both cost controls now actually work

**Two defects, both about money, both closed the same night they were found.**

**`D-23` — the EKS version was 74% of the bill.** `cluster_version` raised from **1.31 to 1.36**. 1.31 had been on extended support since 2025-11-26, billing **$0.50/hour against the $0.10 standard rate**. `terraform validate` and `plan` are clean and the plan confirms the new version; 59 to add, unchanged.

**1.34 was rejected deliberately.** Its standard support ends 2026-12-02 — about ten weeks out — which would have put this exact task back on the board before the year was done. 1.36 runs to 2027-08-02.

**The `CLAUDE.md` § 4 estimate turns out to have been right all along, for the wrong version.** At standard-support rates the stack costs about **$200/month** run 24x7 (EKS $73 + 2x t3.medium $65 + NAT $41 + NLB $17 + EBS $4), which is the top of the quoted "$150-200". On **extended** support it was nearer **$492/month**. The figure was not wrong; the cluster was.

**`D-22` — the watchdog could never fire.** Container recreated with `GENERIC_TIMEZONE=Asia/Kolkata` and `TZ=Asia/Kolkata`. The `n8n_data` volume persisted, and both workflows plus both credentials came back intact -- backed up via the API first regardless, because credentials live only in that volume and not in git.

**`--restart unless-stopped` went in at the same time, and belongs to the same defect.** The container's policy was `no`, which is why it was found `Exited (137)` that morning. **A watchdog whose n8n is not running cannot fire either** -- two independent ways for the same monitor to be silently dead.

**Verified behaviourally, which is the entire point.** Reading `GENERIC_TIMEZONE` back would have proved nothing -- that is the mistake that created the defect. Instead a throwaway workflow was created via the API with cron `22 0 * * *`, three minutes ahead **in IST**:

```
created probe 9d8BwoDf0eA636QG, activated
FIRED at 00:22:08 IST   mode=trigger  status=success  startedAt=18:52:00 UTC
probe deactivated and deleted; two real workflows remain, both active
```

Under `America/New_York` that cron would have meant 00:22 EDT -- **9.5 hours away**. The scheduler is now demonstrably on IST.

**What is still unproven, stated plainly:** the scheduler works, and `N-01b` proved the email node sends. **`cost-watchdog`'s own end-to-end path -- trigger fires, sees a live cluster, emails -- has still never run.** Leaving a cluster up past 17:00 IST will settle it, and now it finally can.

**Neither fix is exercised by a real session yet.** `D-23` needs the next `make up`; `D-22` needs a cluster alive at a trigger hour. Both are written, both are verified as far as they can be without one.

### 2026-09-13 — The nightly teardown fired by itself, and exposed a dead watchdog

**Two things happened at once at 23:43, and both are worth recording.**

**The automated teardown worked, unattended, for real.** Nobody triggered it. The task fired, `make down` began destroying the cluster, and the log written this afternoon captured every line of it. That is the first time this project has torn itself down without a human, on the very night a cluster was left running. The cost controls proved this morning stopped being theory.

**And checking why the OTHER control had not fired found a serious defect.** The cluster came up at 20:30 IST and was still running at 23:43 — past both of `cost-watchdog`'s intended trigger times of 17:00 and 21:00. **It never ran.** The n8n API shows no scheduled execution at all; the most recent is that morning's manual test.

n8n was not down (up 12 hours). The cause is a timezone:

```
docker exec n8n env  ->  GENERIC_TIMEZONE unset, TZ unset, container clock UTC
workflow settings    ->  no timezone override
```

**n8n defaults `GENERIC_TIMEZONE` to `America/New_York`.** So hours 17 and 21 are EDT (`-0400`), and against IST (`+0530`) that is:

```
17:00 America/New_York  =  02:30 IST
21:00 America/New_York  =  06:30 IST
```

**The watchdog checks at 2:30am and 6:30am** — hours after the 23:30 teardown has already destroyed the cluster. It cannot find a running cluster, so it cannot email. **A monitor scheduled for a time when the thing it watches for is impossible.** Logged as `D-22`.

**This is `learn/17`'s timezone trap wearing a different hat**, and it sharpens what `N-01b` actually closed. `N-01b` proved the email **node** sends — the message reached the inbox, that is real. It never proved the workflow **fires**, and those are separate claims that "the watchdog works" quietly merges. The project has now been caught by that exact conflation twice in one day: a green tick meaning "did not halt", and a closed task meaning "one node works".

**Why it went unnoticed for so long:** the watchdog only has anything to say when a cluster is up at the trigger hour, and the standing policy is that clusters do not survive the evening. A monitor that is correct to stay silent is indistinguishable from one that is broken — until you deliberately arrange the condition it is meant to catch. Tonight arranged it by accident.

### 2026-09-13 — Cluster session: `D-02` closed, `C-05`/`C-06` verified, `S-02` proven

**The longest-standing constraint in this project is gone.** `D-02` had `replicas` pinned to 1 since 2026-08-30. It is now 2, and the reason it could not be is genuinely fixed rather than worked around.

**`terraform apply`: 59 added, 0 changed, 0 destroyed**, two nodes `Ready`. The kubeconfig refresh earned its place immediately -- the new endpoint is `BC7AFF62...` where the previous cluster's was `96FCDE1C...`, which is the "EKS issues a new endpoint every rebuild" rule visible in one line.

**`C-05` verified before a single pod ran.** The role ARN Terraform created matched the one hardcoded in the ServiceAccount annotation byte for byte, and the trust policy came back scoped exactly as intended:

```
oidc.eks.ap-south-1.amazonaws.com/id/BC7AFF62...:sub = system:serviceaccount:app-hub:links-service
oidc.eks.ap-south-1.amazonaws.com/id/BC7AFF62...:aud = sts.amazonaws.com
```

That `sub` line is the concept flagged as skipped when the escape hatch was used. It is what limits the role to one ServiceAccount instead of every pod in the cluster.

**Then inside the pod:** `AWS_ROLE_ARN` and `AWS_WEB_IDENTITY_TOKEN_FILE` injected by the webhook, and a real **1214-byte** projected JWT on disk.

**The proof that actually counted.** A `POST` through gateway returned `201`, and then the **AWS CLI -- not our code** -- found the exact record in `app-hub-links`. Count went 0 to 1. **A `201` on its own proves nothing**, because the in-memory repository returns `201` identically; that distinction is the whole reason this was the chosen test.

**`D-02` closed, and tested so it could not pass by accident.** `replicas` was raised to 2 only *after* the single-replica deploy proved the credential path -- raising both at once would have made any failure ambiguous between IRSA and replication. The two pods landed on different nodes and were then addressed **directly by pod IP**, so the Service could not quietly send both requests to the same one:

```
pod A issued: f8f2197b-...     pod B issued: 782c6fd1-...     ids differ: True
pod A reading B's record: 200  pod B reading A's record: 200
both pods see 3 records
```

With `global next_id` both ids would have been `1`. With the in-process dict both cross-reads would have been `404`.

**One real defect, mine, and it is the second instance of one pattern.** `AGGREGATOR_URL` was added to gateway's code with a `localhost:8002` default and **never added to its Deployment**, so in-cluster gateway dialled itself and returned `503` for every `/status`. Identical in shape to the `LINKS_SERVICE_URL` port bug of 2026-09-10. **A config variable whose default is `localhost` is a landmine unless the Deployment overrides it** -- and both times the value went unconsumed until the day something finally read it. Logged as `D-21`.

Two things worth keeping from it. The error mapping **worked exactly as designed** -- `503 aggregator unavailable`, naming the right service, which is precisely what gateway distinguishing 502/503/504 is for. And the fix is not symmetrical with links-service: aggregator's Service exposes **8002 targeting 8002**, not 80 to 8002, so copying the `:80` across would have produced the same bug again.

**`S-02` proven on real EKS.** After the fix: gateway -> aggregator -> links-service by Kubernetes DNS, with aggregator reaching `aws.amazon.com` through the NAT gateway in 286 ms and links-service answering from DynamoDB. **Neither end of the inner hop is the front door**, which `gateway -> links-service` could never demonstrate.

**Security posture re-verified as the CLUSTER sees it, not as the YAML claims it.** All three containers `uid=10001`; a write to `/` refused, so `readOnlyRootFilesystem` is real; every pod `Burstable`; and admission control **actively rejected** a deliberately non-compliant pod with a four-point violation list. `S-03`'s dashboard served in-cluster with correct content types and `cache-control: no-cache`.

**Cleaned up afterwards.** The three test records were deleted **through the deployed service**, which exercised `DELETE` over IRSA as well, and the table is back to 0 items per the AWS CLI.

### 2026-09-13 — `C-05` written (escape hatch), and `D-18` made mechanical

**The owner asked for `C-05` twice, the second time after a full explanation. That is the escape hatch in `CLAUDE.md` § 2 — "if the owner is stuck on something from the hand-write list and asks you to write it, write it" — so it is written, with the skipped concept flagged rather than buried.**

**The concept skipped: the trust policy's `sub` condition.** Worth revisiting because it is the first place in this project where getting a Terraform detail wrong **grants access** instead of breaking a deploy. Without `sub`, every ServiceAccount in the cluster can assume the role — every pod, every namespace — and nothing fails, no test goes red, and DynamoDB is simply open to anything running there. The classic IRSA mistake is classic precisely because its symptom is that everything works.

**Three files.** `infra/irsa.tf` (role + trust policy + a four-action inline policy on one table ARN), `manifests/links-service/00-serviceaccount.yaml` (the `00-` prefix is load-bearing — `kubectl apply -f <dir>` sorts by filename and `deployment.yaml` would otherwise land first), and the Deployment gaining `serviceAccountName` and `LINKS_TABLE_NAME` **in one change**, per `D-18`.

**Two decisions worth recording.** The table ARN is read with `data "aws_dynamodb_table"` rather than `terraform_remote_state` or a constructed string: remote state couples this stack to another's internal shape for one value, a constructed ARN is silently wrong the day anything moves, and a data source **fails `plan` loudly** if the table is absent — which is the right failure for a role granting access to something that does not exist. And `irsa.tf` lives in the **ephemeral** stack because the OIDC provider is created with the cluster and its URL changes on every rebuild; the role *name* is fixed, so the ARN is stable and the manifest never has to change.

**`D-18` is now a check, not a paragraph.** `validate-manifests.py` fails if a Deployment sets `LINKS_TABLE_NAME` without a `serviceAccountName`, if that name has no ServiceAccount in the directory, if the ServiceAccount lacks the `eks.amazonaws.com/role-arn` annotation, or if `AWS_REGION` is missing. **Proven to fire**, not just added: deleting the `serviceAccountName` line from a copy produced `1 problem(s) found` and exit 1.

That matters more than the convenience. `D-18` describes a failure nothing else can see — `build_repository()` only constructs a boto3 resource, so startup succeeds; `/health` never touches storage, so both probes pass and the pod sits `Running` and `Ready`; every `/links` request then 500s with `NoCredentialsError`. **A rule about two lines that must ship together is exactly the kind a human forgets and a checker does not.**

**`replicas` stays at 1**, deliberately, even though `C-06` removed the reason it had to be. Raising it in the same change as a brand-new credential path would make a failure indistinguishable from a replica problem. Raise it after one deploy where `/links` actually works through IRSA; `D-02` closes then.

**Status: written and validated offline, NOT applied.** `terraform fmt`, `terraform validate` and `validate-manifests.py` all pass. Nothing has touched a cluster, and the whole thing is unproven until `kubectl exec ... env | grep AWS_` shows the injected variables.

**Cost: nothing. No cluster was created.**

### 2026-09-13 — Nightly teardown PROVEN end to end

**It works, and this is the first time that has been true.** Re-registered with the battery flags, triggered manually, and every link in the chain left evidence:

```
=== scheduled-destroy ===
user       : harshitrawat
home       : /home/harshitrawat
aws ident  : arn:aws:iam::314146298861:user/terraform-learning
=========================
[2026-09-13 14:31 IST] scheduled destroy starting
[2026-09-13 14:32 IST] destroy finished: success (exit 0)
reported to n8n (HTTP 200)
```

Task Scheduler events ran the full lifecycle -- 325, 110, 129, 100, 200, 201, 102 -- state back to `Ready`, `LastTaskResult 0`. **The previous run produced only 325 and 110 and then silence.** That contrast is the entire diagnosis in one line.

**The last mile was checked rather than assumed.** The script's own warning says a webhook `200` means RECEIVED, not SUCCEEDED. n8n execution **40**, `mode=webhook`, `status=success`, 09:02:09 UTC -- matching the log's 14:32 IST to the minute.

**One more defect found and fixed in the same pass.** The teardown's output was captured into a shell variable used only to build the n8n payload, so **it never reached the log**. On a successful no-op that is invisible. On a real failure the log would have read `failure (exit 2)` and nothing else, with the actual error surviving only inside the email -- and lost completely if the POST were the thing that failed. **A log that goes blank exactly when something breaks is not a log.** It is now `tee`d into both.

**A comment I had just written turned out to be wrong, and a two-line test caught it.** I justified using `PIPESTATUS[0]` by claiming that after a pipe `$?` is tee's status and therefore 0. Measured: true in plain bash, **false in this script**, which sets `pipefail` and so makes `$?` correct anyway. `PIPESTATUS[0]` stays because it names the thing we actually mean and does not quietly depend on an option someone could remove -- but the stated reason is now the true one. Learned in passing: **`PIPESTATUS` is clobbered by the very next command**, including the `echo` that tries to print it next to `$?`.

**Cost: nothing.** The teardown had nothing to tear down.

### 2026-09-13 — The nightly teardown would never have run, and said nothing about it

**Registered successfully, ran as the right account, and did absolutely nothing. Twice over, for two independent reasons — both mine.**

**Reason 1: Windows Scheduled Tasks do not run on battery power by default.** `New-ScheduledTaskSettingsSet` defaults to `DisallowStartIfOnBatteries = True` and `StopIfGoingOnBatteries = True`. Triggered on battery, the task went to state **`Queued`** and sat there — launched at 14:13, still `Queued` at 14:19, laptop unplugged. Not `Running`. Not `Failed`. **No completion event, no output, no error.**

Those defaults are correct for their intended purpose; background maintenance should not flatten a laptop. They are exactly wrong for a cost control. **23:30 is precisely when a laptop is likely to be unplugged**, so this would have skipped the teardown on the nights it mattered, billed the NAT gateway until morning, and reported nothing. `StopIfGoingOnBatteries` is worse still — unplugging mid-run aborts a `terraform destroy` halfway.

Fixed with `-AllowStartIfOnBatteries -DontStopIfGoingOnBatteries`, and the script now **asserts those settings took** after registering, exiting non-zero rather than claiming success.

**Reason 2: the job had no log.** `scheduled-destroy.sh` reported only by POSTing to the n8n webhook, and the Task Scheduler action (`wsl.exe -e bash -lc "..."`) captured stdout nowhere. **A run that failed before the POST therefore left no evidence at all.** That is the same disease as everything else this project has chased: a step that looked fine because nothing was watching. It now `tee`s to `logs/scheduled-destroy-<timestamp>.log` and prints its WSL user, `$HOME` and `aws sts get-caller-identity` first — the three lines that answer most failures of a scheduled WSL job.

**The diagnosis took four wrong turns, and the wrong turns are the lesson.**

- *"The task was never registered."* Wrong — `Get-ScheduledTask` unelevated returns nothing for a task it cannot read. Settled by a **control query**: a name known to be absent gives `cannot find the file specified`, this one gives `Access is denied`.
- *"It runs as the wrong account, so it has no AWS credentials."* Wrong — probed the exact `wsl.exe` invocation: WSL user `harshitrawat`, `$HOME=/home/harshitrawat`, `aws sts get-caller-identity` returns `terraform-learning`. Credentials were always there.
- *"`make down` hangs on `kubectl` against the stale EKS endpoint."* Plausible, and **wrong — measured it: kubectl fails in 3 seconds with NXDOMAIN.** Would have been a confident diagnosis and a pointless fix.
- *"No completion event means it crashed."* Wrong — it had been two minutes, and `make down` legitimately takes longer than that. Nearly a false negative from impatience.

**What actually settled it was noticing that `Queued` is not `Running`.** `Queued` means *waiting for a condition*, and the conditions are in the task's own settings.

**A fifth measurement artifact turned up during the diagnosis**, bringing the session's total to five: `wsl.exe` piped into PowerShell's capture returned `reached: ` with an empty `pwd` and nothing after it. The identical command through bash printed everything. `wsl.exe` emits UTF-16 to a redirected stdout and the capture truncates at the first NUL — a full environment probe that read as a catastrophic failure and was a quoting artifact.

**Nothing was billing throughout.** The teardown had nothing to tear down; the failure cost nothing this time, which is exactly why it was worth finding now rather than after a weekend.

### 2026-09-13 — `N-01b` closed at last, and a check that lied three times

**`N-01b` is DONE. The email arrived.** Execution `38`, `mode=manual`, `status=success`, 07:25:25 UTC (12:55 IST). **The first email this project has ever sent**, after weeks of being deferred. The inbox is the only evidence that counts here — a green tick on the canvas means *"did not halt"*, not *"delivered"*.

**Verified afterwards that no pinned data was left behind** (`pinData` empty, workflow still `active`). That check mattered: a pin on the HTTP Request node would have made the watchdog email every single day regardless of cluster state, and **a monitor that always alerts is one you stop reading** — worse than the situation it replaced.

**Still not proven, and worth being precise:** the email node sends and the SMTP credential works. The *end-to-end* path — HTTP Request detecting a live cluster and triggering the email by itself — has never run. It will test itself for free: the Schedule Trigger fires at 17:00 and 21:00, so any cluster left up past 5 PM exercises the whole chain with no clicking.

**Correction: my earlier `N-01b` advice was wrong.** I said n8n could "execute a single node, bypassing the HTTP Request entirely". It cannot — **"Execute step" runs a node's ancestors first to produce its input**, which is exactly what the owner hit: *"Problem in node 'HTTP Request'"* with `No data` in the email node's input panel. The workable no-cluster route was to pin mock output on the **upstream** node, which is easier than it sounds because the email node uses **no expressions at all** — both its subject and body are static strings, so the mock content is irrelevant and `[{}]` suffices.

---

**The scheduled task was registered all along, and my check said otherwise.**

I reported `TASK NOT FOUND`. It was there. `Get-ScheduledTask` run **unelevated returns nothing for a task that exists** — not an error, nothing. The proof came from the owner's own rerun, which failed with:

```
Register-ScheduledTask : Cannot create a file when that file already exists.  (0x800700b7)
```

You cannot get `ALREADY_EXISTS` for something absent. `schtasks` is more honest about the same state — it says **`ERROR: Access is denied`** rather than pretending the task is missing.

**The same shape produced a confident wrong answer three times in this one session:**

| Check | Reported | Reality |
|---|---|---|
| `aws dynamodb list-tables --query 'Tables'` | `None` | Field is `TableNames`; the table existed |
| `ps -eo cmd \| grep -c "[u]vicorn"` | 2 lingering processes | Zero — it matched its own shell |
| `Get-ScheduledTask` unelevated | `TASK NOT FOUND` | Registered and working |

And a fourth, live, in the command that diagnosed it: `Test-Path` on a protected path threw `UnauthorizedAccessException` and, because that is non-terminating, **fell through to the `else` branch and printed "no file at ..."**.

**Settled conclusively on the second attempt by running a CONTROL** — the same query against a name known to be absent:

```
schtasks /query /TN "zzz-definitely-not-a-real-task"  ->  ERROR: The system cannot find the file specified.
schtasks /query /TN "app-hub nightly teardown"        ->  ERROR: Access is denied.
```

Absent says *cannot find*; existing-but-unreadable says *denied*. `Get-ScheduledTask` returned "not found" for **both**, which is what made it produce a confident wrong answer twice.

**The lesson, now in `CLAUDE.md § 9`: "I cannot see it" and "it is not there" are different facts, and any check that renders them identically will eventually report the wrong one with total confidence. Control your negatives before believing them.** A permission-denied query, a typo'd field name, and a self-matching pattern all return the same comfortable emptiness. This is the same disease as every stale doc claim in this project, just wearing a shell prompt instead of a Markdown file.

**Then the guard itself turned out to be built on a wrong assumption, and was revised the same day.** I made the script *refuse* to run unelevated, on the belief that registering a scheduled task needs admin. It does not: creating a task that runs as **you** is a normal user action. What needs admin is reading, replacing or starting a task owned by **someone else** -- which is precisely the situation here.

**Diagnosis, with evidence rather than inference.** `Get-ScheduledTask` enumerates **205** tasks on this machine, including all four in the root folder, and simply omits this one. `schtasks /query` says `Access is denied` for it while saying `cannot find the file specified` for a name known to be absent. The task therefore exists, owned by another principal -- almost certainly because the script was elevated once under a different admin account on this work-managed laptop (`UZIO\harshit.rawat` is a domain user who is not a local admin).

**The consequence that actually matters is not visibility, it is the task's PRINCIPAL.** That decides who `wsl.exe` runs as, which decides the WSL home directory, which decides whether `~/.aws/` has app-hub credentials at all. A task owned by another account would run `make down` at 23:30 with no credentials and fail -- silently, on the night it was needed. Same WSL/Windows split that `CLAUDE.md § 5` already documents, reached from a new direction.

So the script now **warns and continues**, and afterwards **verifies what it actually created**: it reads the task back, prints the principal next to the current user, and says loudly if they differ. Refusing outright would have blocked the one workable path -- registering under a name this user owns.

**The orphaned task cannot cause damage even if it fires.** `infra/providers.tf` sets `use_lockfile = true`, so two concurrent destroys contend for an S3 lock rather than corrupting state, and `make down` on an empty account is a no-op regardless.

### 2026-09-13 — `S-02`: the service that actually proves discovery

**The owner created `HarshitRawat11/app-hub-aggregator`, which cleared the last blocker on Claude's side.** Seventh repo, pushed as `83d4b1d`.

**It is a liveness aggregator, not a discovery demo, and that was a deliberate choice.** It reads the catalogue from `links-service` and probes every URL concurrently, so the dashboard shows which self-hosted apps are actually reachable. Building it as a toy that merely *calls* another service would have proven the same networking and been deleted within a month.

**Its workload genuinely differs from the other two**, which is the honest test of whether something deserves to be its own service: a CRUD API answers from memory in microseconds, this one waits on dozens of slow third parties. Different timeouts, different concurrency, eventually a different replica count.

**The chain is the point:** browser → `gateway` → `aggregator` → `links-service`. `aggregator` is `ClusterIP` and never publicly reachable, so **neither end of the inner hop is the front door** — unlike `gateway → links-service`, which is the outside talking in. `gateway` gained `GET /status` to proxy it, and that is a constraint rather than a convenience: the dashboard is same-origin with no CORS, and `aggregator` has no public address, so there is no other route.

**Central design rule, and the one worth carrying: a down link is DATA; a down `links-service` is an ERROR.** `/status` answers **200** with the link marked `down`. Only the upstream being unreachable is 5xx. Blur those and the dashboard cannot distinguish *"your NAS is switched off"* from *"the hub is broken"* — which need completely different reactions. Relatedly, **anything under 500 counts as `up`, including 401 and 403**: the question is *"is the app running"*, not *"may I in"*. Marking every auth-protected app down would make the dashboard cry wolf, and one that cries wolf gets ignored — worse than not having it.

**`D-20`: SSRF, and why the reflex mitigation is wrong here.** This service fetches URLs anyone who can `POST` to `links-service` chose, from inside the cluster. The obvious answer is to block private address space — and that would block the product, since app-hub exists to catalogue apps on `10.x` and `localhost`. **A guard that breaks the use case gets deleted; a narrow one survives.** So it refuses link-local only (`169.254.169.254` is the instance metadata endpoint, the classic route from "will fetch a URL" to "hands over IAM credentials"), metadata hostnames, and non-HTTP schemes — resolving hostnames first, because a name can point there as easily as the literal. **The guard landed before `C-05` attaches a real IAM role to this namespace, not after.** The DNS-rebinding gap is documented rather than hidden.

**A test that failed for a reason unrelated to what it measured.** The concurrency test asserts probes run in parallel by wall-clock. It failed at 5.2 s against a 1 s budget, apparently proving they were serial. They were not — the SSRF guard was doing **real DNS lookups** for ten fake `.example` hostnames, so the test was timing NXDOMAIN. IP literals fixed it, and prompted a real improvement: an address that is already an IP literal has been checked, so re-resolving it is a wasted round trip. **The failure message will always be the claim, even when the cause is somewhere else entirely.**

**One bug of mine in the test helper**, worth the same note as gateway's: it called `TestClient.__enter__()` itself and then handed the object to `with`, which entered it a second time, re-ran `lifespan` and silently replaced both mocks with real clients. Eleven tests failed against `localhost:8000`.

**Verified running against real targets, not only mocks:** a live n8n (`up`, 200, 4 ms), a stopped Grafana (`down`, `ConnectError`), example.com over the real internet (`up`, 78 ms), `169.254.169.254` (`blocked`, request never made). Then `aggregator` was stopped and the dashboard reloaded: **links still render and stay clickable, dots go grey, no error banner** — liveness is a decoration on the catalogue, not a dependency of it.

**Wiring that would have failed quietly if missed:** `aggregator/` added to the root `.gitignore` (the umbrella would otherwise have tracked a second copy of a repo that has its own remote), to `REPOS` in `timeline.sh` (or its history vanishes from `TIMELINE.md`), to `SERVICES` and `ECR_REPOS` in the Makefile, and a third ECR repository in `infra/ecr.tf`. `CLAUDE.md` now says **seven** repositories and carries the rule to add the next one in the same change.

**`validate-manifests.py` now rejects `image: ...:latest` outright.** The ECR repositories are IMMUTABLE (`R-03`), so `latest` can never be repushed — the first push wins and every later one fails. Caught here rather than during a deploy with the cluster billing. The correct resting state is `:PLACEHOLDER`, which `make deploy` rewrites.

**Not done:** nothing is deployed. `manifests/aggregator/` exists and validates but has never been applied, and all three images need building and pushing.

**Cost: nothing. No cluster was created.**

### 2026-09-13 — `C-06` verified against the real table, and a blocker that was never real

**Approved by the owner, because it writes to the one table that is never destroyed.** Baseline captured first (0 items); table confirmed byte-identical to baseline afterwards.

**The blocker was never real, and that is the finding.** `C-06` sat marked *"NOT verified against the real table — needs `C-05`"*. IRSA is what a **pod** needs to reach DynamoDB. It is not what this laptop needs: boto3's default credential chain in WSL already resolves to `terraform-learning`, which owns the table. *"The deployed service cannot reach DynamoDB yet"* and *"this code cannot be verified yet"* are different statements, and treating them as one kept the task blocked for three days. It also turned out `C-04` had been **applied since 2026-09-10 16:35 IST** with the board still reading "NOT APPLIED" — so the stated blocker had cleared before it was written down.

**11 checks against `app-hub-links`, 0 failures.** `build_repository()` selects the DynamoDB backend from the environment; UUID strings work as the `S` key `C-04` declared; every field round-trips; `get` on an unknown id returns `None` rather than raising.

**`exclude_none` confirmed on the real thing** — the raw item, read back through the **AWS CLI rather than our own code**, has no `icon` attribute at all rather than a NULL. **`ReturnValues="ALL_OLD"` confirmed** — a second `DELETE` answers `404`, not `200`.

**The one genuine gap between `moto` and DynamoDB.** `moto` answers every read immediately; a real `get_item`/`scan` is **eventually consistent by default**, so a read after a write may legitimately return nothing. Here it returned in 0.036 s every attempt — the normal case, and **not a guarantee**. Nothing in links-service depends on read-after-write today, but a feature that did would pass every test in this repository and fail in production. Worth knowing before that feature gets written.

**`D-02`'s actual claim proven, not argued.** Two links-service processes against the same table, one record created by each: distinct ids, and **each process read the other's record back through its own API**. With `global next_id` both would have issued `1` and one write would have silently overwritten a different record; with the in-memory dict each would have answered `404` for the other's. Then the full stack end to end — dashboard → gateway → links-service → real DynamoDB — with the record confirmed present in AWS by the CLI.

**`D-02` stays "Mitigated", not closed.** The code is now proven; the *deployment* is still single-replica and still in-memory, and must stay that way until `C-05` (`D-18`). Proving the mitigation works is not the same as shipping it.

**Two measurement artifacts worth naming, since both produced confident wrong answers:**

- A cost audit reported **"DynamoDB tables: None"** because the query asked for `Tables` when the field is `TableNames`. A wrong `--query` returns `None` rather than erroring, so a wrong question reads exactly like a clean answer. `make down`'s audit uses the correct field; this was ad-hoc.
- A teardown check reported **2 lingering uvicorn processes** when there were none. The checking shell's own command line contained the word, so it counted itself — the same shape as the `pkill -f` that killed its own shell twice on 2026-09-10.

**Cost: a handful of on-demand DynamoDB requests, effectively zero. No cluster was created.**

### 2026-09-12/13 — `S-03`: app-hub gets a face, and gateway becomes a real proxy

*Worked through the evening of the 12th IST; the commit (`c522956`) lands 2026-09-13 · 00:01 IST. Dated from the commit rather than from memory — `CLAUDE.md § 7`.*

**No cluster, no cost, nothing owner-written.** Two local services and a browser.

**The dashboard is served BY gateway, not as a fourth service.** `S-03`'s row had said "static page / SPA talking to the gateway". Building it that way would have bought three problems and no benefit: a second origin (so CORS headers on every gateway response, plus a build-time answer to *"where is the API?"*), a second public endpoint (so a second ELB, on a cluster destroyed nightly, while `E-06` is explicitly deferring that decision), and a third GitHub repo only the owner can create — which would have blocked the work before it started. Served from gateway, every URL in the page is a bare path. It also matches what gateway already claims to be: **a front door that serves an API but not the page you open is a strange front door.** Reversible: moving a directory into an nginx image is small; standing up a service to find out would not have been.

**The design point worth keeping is about proxies, not dashboards.** With only `GET /links`, every upstream 4xx genuinely was a fault — the collection always exists. The moment `GET /links/{id}` exists, a `404` is the *correct* answer to a question about an id that is not there, and flattening it to `502` tells the caller the server is broken when they simply asked for something absent. Same in reverse for `POST`: a `422` is about what the **caller** sent. So `_proxy` takes an explicit `passthrough` set per route, and `GET /links` passes nothing through. **The asymmetry is the point, not an oversight.**

Also: `POST` forwards the body as an opaque `dict`. links-service owns the link schema, and restating it in gateway would give the project two definitions that drift — with a gateway silently stripping a field it had not been told about, which looks exactly like a client that never sent one.

**47 tests, up from 15**, and the failure mapping is now asserted across all four routes rather than one — twelve cases from two `parametrize` decorators. That matrix is the regression guard for factoring the owner's try/except into a shared helper: four routes sharing one helper is only an improvement while they really do share it.

**Two bugs found, both mine, both instructive.**

`D-19` is the one worth reading. The add form was marked `hidden` and rendered anyway, and the JavaScript toggling it did nothing — silently. `hidden` is one rule in the browser's default stylesheet and **any author `display` rule outranks it**. Every one of the 47 tests passed. Seven of them assert the page is served, correctly typed, not shadowing `/health`, and referencing only assets that exist — all true, all blind to the rendered result. **"The tests pass" and "it works" are different claims about a user interface**, and only opening it settles the second.

The second surfaced immediately after: fixing the CSS changed nothing, because the browser reused a cached `style.css` without revalidating. Same shape with a deploy in the middle — new HTML, old stylesheet, no error anywhere. Now `Cache-Control: no-cache`, which means *revalidate every time*, not *do not cache*.

**A latent fragility in the existing tests, exposed rather than introduced.** `test_gateway.py`'s two config tests call `importlib.reload(main)`, and reload re-executes a module into the **same namespace dict** — so `main.app` is rebound while any name already imported from it still points at the old object. The route handlers resolve `app` at call time, so they read the new one. It never mattered while that was the only test file, because the reload tests run last. `test_proxy_crud.py` sorts after it and broke instantly, with 25 failures and an `AttributeError` pointing nowhere useful. Helpers now resolve `main.app` per call.

**Security claims proven, not asserted.** Link records are attacker-controllable — anything that can `POST` decides what `name`, `icon` and `url` contain. Two guards: every value written with `textContent`, and `href` assigned only from a scheme-checked value (`textContent` does nothing for an `href`; a stored `javascript:` URL is inert as text and executes on click). Fed a record named `<img src=x onerror=alert(1)>` with URL `javascript:alert(document.domain)`: **zero injected elements**, and a plain `<span>` reading "unsupported URL".

**Verified live, end to end:** all four routes browser → gateway → links-service; `Location` header followed to a `200`; `404` and `422` passing through rather than becoming `502`; `503` with links-service stopped; `504` at **3.006 s** against a hanging upstream; `502` against a 500 with an HTML body. Add and delete driven through the actual page.

**A stale number corrected while re-running the suite.** `learn/26` and this log recorded the links-service suite at **39 seconds**. Re-timed twice: 102 s and 114 s. The improvement is real (573 s → ~110 s), but 39 s was a single warm run written down as fact, and nothing re-measured it. Both files now say so rather than quietly swapping the figure.

**Not done:** the dashboard is not deployed — that needs a cluster session, and the image must be rebuilt and pushed since `app/static/` is new. `manifests/gateway/service.yaml` stays `ClusterIP`; reach it with `kubectl -n app-hub port-forward svc/gateway 8001:8001`. **`E-06` is now more clearly worth doing** — there is finally a human-facing page that wants a stable public URL.

**Cost: nothing. No cluster was created.**

### 2026-09-12 — `C-06` code: repository layer, UUID ids, and a suite that was too slow to use

**Written and unit-tested. NOT verified against the real table** — that needs `C-05`. Committed `1f7ce47` in `app-hub-links-service`.

`links-service` no longer knows where its data lives. `app/repository.py` defines a `LinkRepository` **Protocol** — not an abstract base class, so nothing inherits and `DynamoDBLinkRepository` never imports the in-memory one — with a dict implementation and a DynamoDB one. The backend is chosen once at startup by whether `LINKS_TABLE_NAME` is set, rather than by a `LINKS_BACKEND` flag, because **one variable cannot disagree with itself**: a flag saying `dynamodb` with no table name is a configuration you can express and should not be able to.

**The id change is the load-bearing one, not the interface.** Ids are now server-generated UUID strings. `global next_id` could not survive more than one replica — each pod starts at 1 and hands out colliding ids, so a write on one pod silently overwrites a *different* record on the other. **This is where `C-04` pays off:** the table declares `id` as type `S`, decided before this code existed, and a key attribute's type cannot be changed without recreating the table — the one table in the project that is never meant to be destroyed.

Two visible API changes, stated rather than buried: ids are strings; and **`GET /links/abc` now returns `404` rather than `422`**, because with `id: str` there is no longer a malformed id, only an unknown one.

**Two DynamoDB behaviours that are quietly wrong by default:** `delete_item` succeeds whether or not the item existed, so without `ReturnValues="ALL_OLD"` a `DELETE` of a nonexistent record answers `200` — a delete that cannot say whether it deleted anything. And `put_item` with `exclude_none` omits absent optional fields instead of storing `NULL`, so readers never have to handle a value meaning "not set".

**Contract tests run every assertion twice**, against the dict and against a real DynamoDB table faked in-process by `moto`. An interface only the dict satisfies is a dict with extra steps, and that would surface in the cluster rather than in a test.

**The performance finding, which is the part worth keeping.** The suite first took **573 seconds** — a defect, not an inconvenience, because `make test` exists to be a fast loop and a ten-minute suite is one nobody runs. Profiled rather than guessed: `import boto3` 13.6s, `import moto` 5.6s, **first `boto3.resource()` 37.5s, second 0.0s**. Botocore loads service models from thousands of small JSON files and the project lives on `/mnt/c`, reached over WSL's slow 9p mount. That cost caches per process — but **`mock_aws()` per test defeated the cache and re-paid it every time**. Session-scoped fixture, per-test isolation by emptying the table through the repository's own interface: **roughly 100–115 seconds**.

> **Corrected twice on 2026-09-13, and the second correction is the useful one.** This entry first said **39 s**. Re-timing gave 102 s and 114 s, so it was changed to “~100–115 s”. An hour later the same suite ran in **22.8 s**. Three measurements, three answers, **two of them written down as facts**. The number is not a number: botocore reads thousands of small JSON service models, and on `/mnt/c` that is slow when cold and fast when Windows still has them cached — so the suite is **~20 s warm, ~115 s cold**. The *improvement* is what was real throughout (573 s → tens of seconds, from fixing fixture scope), and it held across every run. **Record what you controlled, not the stopwatch reading that came with it.**

The 0.0s second call is what named the cause. "Tests are slow" could have been moto, pytest collection or the filesystem; a cacheable cost being paid repeatedly points at **fixture scope**, not at the library. **Scope is a performance decision, not only a style one** — function-scoped is the right default until setup is both expensive and cacheable.

**`D-18` logged.** The Deployment deliberately does **not** set `LINKS_TABLE_NAME` yet, and must not until `C-05`. Setting it without IRSA gives the pod a table it cannot authenticate to, and the failure is close to silent: construction makes no AWS call so **startup succeeds**, `/health` does not touch storage so **the pod stays `Running` and `Ready`**, and every `/links` request returns 500. A pod that is healthy by every probe and broken for every real request.

**So `D-02` is not closed.** The id-collision half is fixed, but the deployed service is still in-memory and single-replica. Do not raise `replicas` until the DynamoDB path is actually live.

### 2026-09-10 — Teardown: clean, but only because the check ran twice

`make down` completed. **56 destroyed**, orphan audit empty across clusters, NAT gateways, load balancers, EC2, EBS and EIPs. **The `app-hub-links` DynamoDB table survived**, which is the persistent stack working exactly as designed — `terraform` does not recurse into subdirectories, so `make down` cannot reach it.

**It took two attempts, and the first failure was the valuable one.**

Attempt 1 stopped at stage 3 with:

```
app-hub/links-service: deleted 1 image(s)
WARNING: still holds 2 image(s) — destroy would fail. Stopping rather than proceeding blindly.
```

**buildkit pushes a manifest *index* plus the child manifests it points at** (the image, and an attestation). `list-images` shows the index; **deleting it makes the children visible as newly-untagged digests that were not in the first listing.** So `--filter tagStatus=ANY` is necessary but not sufficient — one pass never empties a buildkit-pushed repository.

Confirmed on the second run, which loops to convergence:

```
app-hub/gateway: pass 1 deleted 1
app-hub/gateway: pass 2 deleted 2      <- the children the index was hiding
app-hub/gateway: empty (confirmed, 3 deleted)
```

**The single-pass command documented in `CLAUDE.md § 9` has always been incomplete.** It simply never failed loudly, because until yesterday nothing re-checked afterwards. `make down` now loops until `describe-images` returns `0` and aborts if it has not converged in five passes.

**The general point is worth more than the fix:** without the re-check, this run would have proceeded into a `terraform destroy` that failed twenty minutes later — with the cluster billing throughout, and an error about a repository not being empty that points nowhere near buildkit. **The verification was worth more than the action it guarded.** Same shape as the `--filter tagStatus=ANY` discovery and the drift checker: a step that looked like it worked, and only a second look proved otherwise.

**`N-01b` is still open, and I had it wrong for a week.**

Attempted with a live cluster. No email arrived, and **no execution was recorded at all.** Manual executions *are* persisted on this instance — ids 28 and 29 are `mode=manual` — so a click that reached the engine would have left a record. The workflow did not run, rather than ran and failed.

**Correction: `N-01b` does not need a cluster, and repeating that it did is why it kept slipping.** The *end-to-end* path does — without a cluster the HTTP Request node 404s and `onError: stopWorkflow` halts there, which executions 29 and 33 both confirm (`node: HTTP Request, msg: The resource you are requesting could not be found`). But the **unproven** part is narrower: *does the email node actually send?* n8n can **execute a single node**, which bypasses the HTTP Request entirely. No cluster required.

That will not exercise the 404-halts-silently branch — but 29 and 33 already prove that. It will prove the one thing never proven in this project's life: **that the mail leaves.** `destroy-notifier` established the SMTP credential works; what is untested is whether *this* workflow's email node is wired correctly.

**Cost: nothing is billing.** The cluster ran roughly an hour.

### 2026-09-10 — Cluster session: `S-01` complete, `R-01`–`R-04` verified for real, one genuine bug

Owner applied `C-04` and brought the cluster up. Everything cluster-dependent except `C-05` and `N-01b` is now done.

**`C-04` verified with all three checks**, not just the easy one: table `ACTIVE`/`PAY_PER_REQUEST` with key `id` type `S`; **two separate state keys** in S3; and `cd infra && terraform plan` reporting `56 to add, 0 to change, **0 to destroy**`. That last one is the actual proof the stacks are isolated — a shared key would have had the ephemeral stack offering to delete the table. (56, not 55, is the new gateway ECR repository.)

**`S-01` step 6 done — the whole loop proven on real EKS.** `make deploy` built and pushed both services, pinned both manifests to real git SHAs, applied the namespace then both service directories, and rolled out cleanly. Then end to end: a `POST` through the public NLB returned `HTTP/1.1 201 Created` with `location: /links/1`, and the record read back **through gateway, by Kubernetes DNS name**. That is `D-16` confirmed on real infrastructure, and the claim gateway exists to prove.

**`R-01`–`R-04` verified against a real API server for the first time** (written 2026-09-03, never enforced until now). The restricted Pod Security Standard is genuinely enforcing: it **rejected my throwaway `curl` pod** for setting none of `runAsNonRoot`, `allowPrivilegeEscalation`, `capabilities.drop` or `seccompProfile`. Both services passed because they set all four. **The policy broke the verification, not the workload** — the correct outcome, and better evidence than a passing check.

**Two bugs in `make verify`, both mine.** It used `kubectl run curlimages/curl`, which the PSS rejects; and it ran `import httpx` hours after `D-17` moved gateway to `httpx2`. Rewritten to `exec` into the running gateway pod — compliant, and a *better* test, since it proves the real pod resolves the name rather than that a fresh one can.

**Then the genuine bug: gateway could not reach `links-service`.**

Symptom: `httpx2.ConnectTimeout`, from both gateway pods, same node and cross node. What each fact bought:

- **`ConnectTimeout`, not `ConnectError`** — packets left and nothing came back. DNS resolved; traffic to the address disappeared. `ConnectError` would have meant reached-and-refused.
- **Both pods failing ruled out node-to-node networking** — a security-group problem would have been cross-node only.
- **`links-service` was `1/1 Running` with populated endpoints**, so the kubelet's readiness probe was successfully hitting `/health:8000`. The app was listening and node→pod traffic worked, proven independently of anything being tested.

That left the Service layer, and the decisive test settled it: pod IP `10.0.2.85:8000` returned `{"status":"ok"}` while `<ClusterIP>:8000` timed out.

**Cause: the Service exposes `port: 80`, forwarding to `targetPort: 8000`. `LINKS_SERVICE_URL` was set to `:8000` — the *container's* port, not the *Service's*.** `http://links-service:80/health` works.

**Why it survived ten days:** it was correct during `E-04`, when the Service was `ClusterIP` on 8000. `E-05` changed it to `type: LoadBalancer` with `port: 80` for the NLB — and **nothing consumed the Service from inside the cluster until gateway existed**, so the change went unnoticed. `learn/07` and `learn/16` both assert `links-service:8000` and were true when written; `learn/21`, `learn/22` and the manifest were written *after* `E-05` and were simply wrong. The first two are annotated as historical, the rest corrected.

**Same silent-rot shape as the documentation drift, but in the cluster rather than a file** — a fact that was true, stopped being true, and had no consumer to notice. The general lesson: **a claim with no consumer is untested, wherever it lives.**

### 2026-09-10 — Owner cleared every no-cluster decision

All six no-cluster decisions taken and implemented, ahead of bringing the cluster up.

**`D-17` resolved — both services on `httpx2` 2.12.0** (`42ec560`). Done while `gateway` was still undeployed, which was the cheapest moment it will ever be. Checked compatibility *before* swapping rather than after: every name gateway uses — `AsyncClient`, `TimeoutException`, `RequestError`, `ConnectError`, `ReadTimeout`, `MockTransport`, `Response` — exists identically, and `TimeoutException` still subclasses `RequestError`, which the `except` ordering depends on. A pure import swap; 15 tests pass and starlette's deprecation warning is gone. **`S-02` now has an obvious client choice.**

**`D-16` resolved — `POST /links` returns `201 Created` with a `Location` header** (`701a6fd`). Nothing external consumes the API and `gateway` only checks `>= 400`, so this was the last cheap moment before something depended on `200`. New test asserts the header is present, correct, and actually resolves.

**`E-06` direction decided, implementation still pending:** `gateway` becomes the publicly reachable service via Ingress + a shared ALB, and **`links-service` becomes `ClusterIP`**. That deliberately removes the public endpoint `E-05` verified — which is the entire point of having a gateway. Deciding now means gateway's Service manifest never needs revisiting.

**`make up` gained `AUTO=1`,** mirroring `down`. The asymmetry was an oversight and it matters: a non-interactive shell *hangs* on the confirmation prompt rather than failing.

**`scripts/register-scheduled-destroy.ps1` written** for the Windows Task Scheduler follow-up, outstanding since `N-00b` on 2026-09-05. **Prepared rather than run** — it registers an unattended `terraform destroy`, and both the fire time and the tolerance for that are the owner's call. Defaults to 23:30. Safe to test immediately: `make down` on an empty account is a no-op.

**Three things found while making the changes:** a test docstring still said `createLink` (renamed under `D-10`); `links-service/.dockerignore` predated `tests/` existing, so the suite was being shipped to the Docker daemon on every build; and the README API table still documented `200`.

**The drift checker earned its keep within a day.** Both `main.py` files changed, and `make validate` failed on `CONTEXT-BRIEF.md` before anything was committed — exactly the class of rot it was built for, caught automatically rather than three weeks later by someone reading carefully. `--fix` rewrote the blocks; the surrounding prose still needed updating by hand, which is the honest limit of the tool.

### 2026-09-10 — Ten documentation fixes and a drift checker

The owner asked a third time whether any no-cluster work remained. I had said "no" twice and been wrong twice, so this time I swept the repos instead of answering from memory. Ten things, all verified before being reported.

**The pattern is now unmistakable and worth stating as a project lesson:** documentation that *describes* something rots every time the something changes, and nothing notices. Five instances so far — `timeline.sh` silently dropping every repo's root commit, `D-12` closed-but-open for a fortnight, `links-service/README.md` claiming a replica count that changed eleven days earlier, `CONTEXT-BRIEF.md` shipping handler names renamed the previous day, and the root README **contradicting itself** about whether `links-service` is `ClusterIP` or `LoadBalancer`. Every one failed **silently and optimistically**.

**New tool: `scripts/check-doc-drift.py`, wired into `make validate`.** `CONTEXT-BRIEF.md` reproduces source files verbatim, so a Claude chat with no filesystem access can see them. The script diffs each `<!-- embed: path -->` block against the real file, names the first differing line, and rewrites blocks from source with `--fix`. It caught all four blocks as drifted on first run.

**The two-halved fix, and the split matters:**

- **Mechanical duplication gets checked mechanically.** A verbatim copy either matches or it does not.
- **Prose facts get deleted rather than checked.** `CONTEXT-BRIEF.md` said *"There are 22 files"* in `learn/`; there were 24. The fix is not a file-counting test — it is to stop asserting a number that needs maintaining. **Prefer removing a rotting fact over building a checker for it.**

**Two READMEs written from nothing:** `infra/` (`5679306`) and `manifests/` (`db87dff`). The Terraform repo had no readme at all — two stacks, the S3 backend and every teardown hazard existed only in root docs that a stranger cloning that repo would not have. That failed *"deployable by someone else"* more directly than anything else in the project.

**`CONTEXT-BRIEF.md` regenerated.** Beyond the stale code it also said no tests existed (14 did), described `destroy-notifier` as "🚧 needs the IF node" (done and verified on 2026-09-05), and described `manifests/` as three files in one directory.

**Root README:** fixed the self-contradiction, added `-n app-hub` to the `kubectl` commands (`R-04` moved everything out of `default`, so following the README returned `No resources found` — which reads like a failed deploy rather than a missing flag), corrected the apply sequence to create the namespace first, and brought the layout tree, Makefile table and AWS resource table up to date.

**Image tags: `:v1` → `:PLACEHOLDER` in `links-service`.** `:v1` predates immutable SHA tags (`R-03`) and was deleted from ECR at the last teardown, so a direct apply failed either way — the only question was whether it failed *understandably*. This surfaced a real prerequisite for **`R-07`: ArgoCD applies the manifests repo verbatim**, with no build step and no `sed`, so GitOps cannot work until `make deploy` has run and its rewrite has been committed. `validate-manifests.py` now reports a placeholder tag as information rather than a failure — it is the correct resting state for an undeployed manifest.

**Also:** `gateway/app/__init__.py` added (`links-service` had one, gateway did not).

**The lesson in `learn/25` is not about docs.** It is that **a validation tool is only worth what it is wired into.** `validate-manifests.py` existed since 2026-09-03 and the `links-service` suite for a day, both one `make` target away from being automatic and neither wired in — so both depended on someone remembering. When you write a check, wire it into the thing that runs checks *in the same commit*, or you have written documentation of an intention.

### 2026-09-10 — `S-01` step 6 written offline; `gateway` tested; `make test` added

The owner asked whether anything was left that needed no cluster. My previous answer — "my free queue is empty" — was wrong: I had been reading task IDs rather than the repos. Four things were sitting there.

**`gateway` had no tests at all.** Four failure branches, verified only by hand with a fake upstream on a spare port. Now 15 tests (`e76d2a5`), using `httpx.MockTransport` — which swaps the transport *underneath* the real `AsyncClient`, so the client, the `await`, the timeout config and the exception handling are genuine while nothing touches a socket. That is what makes `502` and `504` testable in CI at all.

Four of them earn their keep beyond coverage:

- The `504` test **also proves the `except` ordering**. `TimeoutException` subclasses `RequestError`, so putting the general clause first silently swallows timeouts and you never see a `504` anywhere.
- The non-JSON-body test guards an **ordering, not a value**: an upstream `500` with an HTML body once produced a `500` from gateway — from `.json()` raising, not from the error handling. Right answer, wrong reason, and it hid the missing `502`. If the status check moves below `.json()`, the test fails.
- The leak test asserts on **absence** — no error body may contain `localhost`, `links-service:8000`, `http://` or `8000`.
- **`test_health_does_not_depend_on_the_upstream` makes a design decision executable.** Upstream hard down, `/links` confirmed `503`, `/health` still required to be `200`. If `/health` ever checks the upstream, `links-service` going down would get gateway killed by its own liveness probe.

**`S-01` step 6 was written and validated without a cluster** — ECR repository (`0b280cf`), manifests (`c698344`), Makefile generalised. Two decisions in there worth recording:

- **`replicas: 2` for gateway where `links-service` is 1.** The difference is **state, not importance**: `links-service` holds records in an in-process dict, gateway holds nothing. The `AsyncClient` on `app.state` is a connection pool, not shared state.
- **gateway's Service is `ClusterIP`, which looks wrong for a front door.** Giving it a `LoadBalancer` while `links-service` still has one from `E-05` means **two ELBs and two bills**. The correct end state inverts today's setup — gateway public via a shared ALB, `links-service` not externally reachable at all — and that is `E-06`. So this adds no cost and leaves the decision deliberate rather than a side effect. `kubectl port-forward` reaches gateway meanwhile, for free.

**`manifests/00-namespace.yaml` moved up** out of `manifests/links-service/`. It is shared, and keeping it inside one service's directory meant applying gateway alone into a fresh cluster fails with `namespaces "app-hub" not found`. Related lesson, now in `learn/24`: **`kubectl apply -f <dir>` sorts by filename within a directory and gives you nothing across directories** — so `make deploy` applies the namespace as its own explicit step rather than hoping a recursive apply reaches it first.

**`make test` added** — 29 tests across both services from the repo root. The suite written on 2026-09-10 was not wired into anything.

**Two inherited defects nobody had re-checked:** `gateway/README.md` was empty and its `pyproject.toml` still said `"Add your description here"` — the same problems as `D-08` and `D-09`, fixed for `links-service` and never verified for the newer repo. Both now written.

**Also refreshed `links-service/README.md`, which had three stale claims** (`8c11d8d`): it said the Deployment specifies `replicas: 2` "which means this is live today" (pinned to 1 since 2026-08-30), that `C-03` still "needs an architectural decision" (decided the same day), and gave `docker build` from Windows rather than `docker.exe` from WSL.

**Not done, and why:** `S-02` is blocked on the owner twice over — a GitHub remote only they can create (no `gh` CLI here), and `D-17`, the choice of HTTP client. `C-06` still needs `C-04` applied.

### 2026-09-10 — `C-04` committed (not applied)

Committed the owner's four `persistent/` files on their behalf (`6adda96` in `app-hub-infra`), because they existed only on local disk with no backup anywhere.

Checked before committing rather than after: `terraform fmt` clean, `validate` passes, plan reports **1 to add / 0 to change / 0 to destroy**, no `*.tfstate` / `*.tfvars` / saved plans present, and no credential-shaped strings in any file. `.terraform.lock.hcl` is included, pinning aws **5.100.0** — that is the `D-15` fix landing on a stack which did not exist when the defect was closed.

Git printed `CRLF will be replaced by LF` on all four `.tf` files. That is `.gitattributes` working, not a problem: the editor wrote CRLF, the repo stores LF. Worth noting given `D-12` was closed the same day — this is precisely the setting that row was about.

**`terraform apply` has not been run. No table exists in AWS.** It needs the owner's explicit approval, and after it lands the verification is three commands, not one — the table being `ACTIVE` is the easy part; the two separate state keys and `cd infra && terraform plan` reporting *no changes* are what actually prove the stacks are isolated.

### 2026-09-10 — `C-02` done; `D-09`, `D-10`, `D-12` closed

All delegated, all no-cluster, nothing billing.

**`C-02`: 14 tests, all passing** (`fc753f8` in `app-hub-links-service`). `tests/test_links.py` via FastAPI `TestClient`, which drives the app in-process over ASGI — no uvicorn, no port, so it cannot collide with a real `links-service` on 8000. **Coverage list is in `learn/23` for review**, per `CLAUDE.md § 2`. **This unblocks `C-06`**, which now waits only on `C-04` being applied.

The suite is built around one trap: `links_db` and `next_id` are module-level globals, so without isolation the second test to run sees the first test's records. An `autouse` fixture resets both — and note the asymmetry, `links_db.clear()` mutates in place while `next_id` must be **rebound on the module object**, because `from app.main import next_id` imports a copy of an immutable int. Same reason `create_link` needs its `global` declaration. Those failures are **order-dependent**, which is the signature worth recognising: run one test alone and it passes.

**Two tests are explicit `D-01` regressions.** The original bug stored the incoming `LinkCreate` rather than the constructed `Link`, so `POST` returned exactly the right shape while every read lost its `id`. **A test asserting only on the `POST` response would have passed throughout the bug's entire life.** Both read paths now assert the `id` independently.

**`D-09`** — the leftover `uv init` description replaced.

**`D-10`** — handlers renamed to `snake_case` in **both** services (`fc753f8`, `c921f03`), so they do not diverge. Behaviour-neutral in principle; all 14 tests passing afterwards is what makes it a fact. This is the small version of why `C-06` was gated on `C-02` — you do not restructure code you cannot verify. The one externally visible effect is the OpenAPI `operationId`, confirmed changed via `/openapi.json` and consumed by nothing. Smoke-tested both services afterwards: `POST` to `links-service`, read back through `gateway`.

**`D-12` closed as stale.** It claimed three repos lacked `.gitattributes`; all five carry `* text=auto eol=lf`. The files were added and the row never updated. Found while listing pending tasks — worth noting that the defect table can rot in the *optimistic* direction too, not just the pessimistic one.

**Two new defects, both flagged rather than fixed:**

- **`D-16`** — `POST /links` returns `200`, not `201 Created`. That is a public API contract, so it is the owner's call, not a silent change. The tests assert current behaviour.
- **`D-17`** — the two services are now on different HTTP clients. starlette's `TestClient` deprecates `httpx`, so `links-service` moved to `httpx2` 2.12.0; `gateway` still uses `httpx` 0.28 as a **runtime** dependency. Nothing broken, no deprecation applies to gateway, but `S-02` will have to pick one and the APIs differ, so it is not a version bump.

**Two harness lessons, both self-inflicted, both the same shape as earlier ones:**

- `pkill -f "[u]vicorn ..."` killed its own shell — twice. A `bash -lc '...'` process has the whole script in its command line, so the pattern matches the killer. Exit code 15 is the tell. Fixed by running the script from a **file**, so the process command line is just the filename.
- Git Bash translated a `/mnt/c/...` argument into `C:/Program Files/Git/mnt/c/...`. Passing it inside a quoted `bash -lc '...'` string avoids the translation.

### 2026-09-09 · ~15:00 IST — `D-15` fixed: provider versions are actually pinned now

`infra/.terraform.lock.hcl` is committed (`233d48b`) and the gitignore carries a comment saying why it must stay that way, so it does not get re-ignored by someone tidying up.

The gap was real rather than theoretical: `required_providers` pins `~> 5.0`, which is a *range*. Only the lock file names the exact build, and it was excluded — so a clean clone could resolve any AWS provider 5.x while this project was built and tested on **5.100.0**. Same reasoning that already justifies the S3 backend and `uv.lock`: reproducibility is a goal here, not a hope.

Checked before committing rather than assuming: the file carries provider versions and checksums only, no secrets. It also records `zh:` hashes from the registry, which cover **every** platform — so the copy generated under WSL does not pin anyone to `linux_amd64`. The gitignore notes what to do if a lock file ever ends up with only `h1:` entries (`terraform providers lock -platform=...`) rather than deleting it again, which is the mistake that created this defect.

**Carried into `C-04`:** the persistent stack generates its own lock file, and it must be committed too.

### 2026-09-09 · ~14:40 IST — `C-04` explained; `persistent/` located; `make status` made honest

**`C-04` explained ahead of implementation**, per `CLAUDE.md § 2` — the owner writes it. Covered: why a separate stack is structurally necessary (`terraform destroy` operates on a whole state file, so `prevent_destroy` inside `infra/` would break `make down` every night rather than protecting one resource); that a Terraform "stack" is not a language feature but simply a directory with its own backend and therefore its own state file; and the four decisions that actually matter — `PAY_PER_REQUEST` billing, declaring only *key* attributes, the partition-key type, and `prevent_destroy`.

**Location decided: `infra/persistent/`**, inside the existing `app-hub-infra` repo. Not a seventh git repo, and deliberately not a restructure into `infra/ephemeral/` + `infra/persistent/` siblings — that would touch the `Makefile`, `scripts/scheduled-destroy.sh`, both READMEs and several `learn/` files in order to break an already-proven teardown path, purely for symmetry. **Safety does not rest on the layout:** `terraform` does not recurse into subdirectories, so `make down` cannot reach the persistent stack by construction, and `prevent_destroy` is a second line of defence. Recorded in `CLAUDE.md § 3` with the asymmetry stated explicitly, so nobody later reads it as an oversight.

**`make status` was about to start lying, and now does not.** Its closing line was *"All empty = nothing is billing you"* — true today, false the moment `C-04` creates a table that is *meant* to exist. The output is now split: ephemeral resources above a divider where empty is the pass condition, and a separate **persistent** section listing DynamoDB tables, where an empty list is the *worse* outcome (it means the persistent stack was destroyed). `make validate` also now validates `infra/persistent/` offline via `terraform init -backend=false`, and says so when the directory does not exist yet rather than silently skipping.

**Two findings from running it:**

- The account already holds a DynamoDB table, `tf-lock-devops-recipe-app-api`, from an unrelated project — created 2025-02-16, `PAY_PER_REQUEST`, 3 items, 309 bytes, so **costing effectively nothing**. app-hub does not need a lock table of its own; it uses S3 native locking (`use_lockfile = true`). Consequence for `C-04`: **name the table unmistakably app-hub's**, since `make status` now lists tables and an ambiguous name makes that audit harder to read.
- **`D-15` logged (Medium).** `infra/.gitignore` excludes `.terraform.lock.hcl`. HashiCorp explicitly recommends committing it, and with `required_providers` pinned only to `~> 5.0` a fresh clone can resolve a different AWS provider 5.x than the one this project was built against. That undercuts purpose 3 — *"deployable by someone else"* — which is the same reason the S3 backend and `uv.lock` exist. Flagged rather than fixed: `infra/.gitignore` is not mine to change unasked, and `C-04` will generate a second lock file that inherits the same decision.

**One forward-looking note recorded on the `C-04` row:** declare the `id` partition key as type `S`, not `N`, even though ids are integers today. A key attribute's type cannot be changed without destroying and recreating the table — and `C-06` plans to move to UUID/ULID. Free to get right now; a table migration later.

### 2026-09-09 · ~14:15 IST — Closed both items flagged at step 5

Both were deliberately left open at step 5 rather than fixed silently; the owner asked for them done.

**`D-14` resolved.** `links-service/.dockerignore` added — the same file `gateway/` got. Neither service had one. It changes nothing about what reaches the image (the `COPY` lines are specific), but the whole directory including a ~17 MB `.venv` was tar'd and shipped to the Docker daemon on every build, and it is the safety net against a future `COPY . .`. Committed `2c35edf` in `app-hub-links-service`.

**The teardown hazard is now encoded, per the `CLAUDE.md § 2` Makefile rule** — constraint stated first, then implemented. `make down` emptied only `app-hub/links-service`, because that was the only repository when it was written. It now walks a new `ECR_REPOS` variable, and **`app-hub/gateway` went into that list before the repository exists** (`S-01` step 6 creates it). That ordering is the point: `terraform destroy` fails once a repository holds images, `force_delete` has been observed not to help here, and the alternative is discovering the gap *during* a teardown with the cluster still billing. **The cleanup for a resource should land before the resource does.**

Two details in that loop worth keeping:

- It reports **"does not exist yet"** separately from **"already empty"**. The easy way to tolerate a missing repository is `2>/dev/null`, which then reports a typo'd or not-yet-created repository as clean — a check that passes because it never checked. Fourth appearance of that shape in this project.
- After deleting, it re-reads `describe-images` and **aborts** if anything remains, rather than proceeding into a `destroy` that will fail. `CLAUDE.md § 9` already recommended that confirmation manually; it is now automatic.

Verified: `make -n down` parses, and the loop run against real AWS reports both repositories as *"does not exist yet"* — correct, since the infra is destroyed. That also confirms the existence check works rather than silently claiming they were empty.

`CLAUDE.md § 9` and `learn/15` updated with the per-repository rule. `learn/22` corrected, since it said `links-service` still lacked the file.

### 2026-09-09 · ~13:40 IST — `learn/` rule revised to two tiers; `S-01` step 5

**Rule change first.** The 2026-09-09 split had delegated work getting no `learn/` file at all. Changed at the owner's request: **every step still gets a file, but the depth depends on who wrote it.** Full seven sections for hand-built work; a three-section short note (what it does / why it is this way / the one thing to know, under a page) for delegated work. The reason is that the folder should read continuously top to bottom — gaps where Claude worked make it unusable as a record of the project, even if they are honest about authorship. `CLAUDE.md § 2` and § 7 updated, and `learn/README.md` now documents both tiers.

**`S-01` step 5 done.** `gateway/Dockerfile`, near-identical to the `links-service` one by design — those concepts were learned in `learn/02` and `learn/19`, so rewriting them here would only risk a fresh mistake. Only the port differs. Verified: builds; runs under `docker run --read-only` with no tmpfs mounted; `id` confirms uid 10001; `/health` returns 200; `/links` returns `503` because **inside the container `localhost:8000` is the container's own localhost**, not the host's — correct behaviour, not a fault in either service.

**Then rehearsed step 6's central claim locally, at no cost.** Put both images on a Docker network and pointed `gateway` at `-e LINKS_SERVICE_URL=http://links-service:8000`, i.e. addressing the other service **by name**. Seeded a record into `links-service` and read it back through `gateway`; both containers read-only and non-root. The Kubernetes version differs only in who supplies the DNS name — a Service instead of a Docker network alias. **This is worth repeating for future services: the service-discovery half of an EKS deploy can be de-risked on a laptop before the cluster is paid for.** Test containers and network removed afterwards; nothing pushed to ECR.

**Added `gateway/.dockerignore`, and logged `D-14`.** Neither service had one. It does not change what reaches the image — the `COPY` lines are specific — but the entire directory, `.venv` included, is tar'd and sent to the Docker daemon before every build. It is also the safety net for the day someone writes `COPY . .`. `links-service` still needs the same file.

**Step 6 carries a teardown hazard worth stating before it is encoded** (`CLAUDE.md § 2`, the Makefile rule): the teardown path currently empties only the `links-service` ECR repository. A second repo holding images is a new way for `terraform destroy` to fail, given `force_delete` has been observed not to take effect here.

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
