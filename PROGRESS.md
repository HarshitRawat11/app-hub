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

**When tearing down again, order matters** (`learn/15`): delete **Ingresses first** (only the ALB controller can clear their finalizer — `D-28`), then LoadBalancer Services so their ENIs release, then `terraform destroy`, then audit for orphans. Easiest: run `make down`, which encodes all of it.

**DO NOT EMPTY ECR AS PART OF A TEARDOWN ANY MORE.** This line said to, until 2026-09-18. ECR moved to `infra/persistent/`, so `terraform destroy` cannot reach it and has no reason to need it empty — and emptying it now deletes the images the always-on host pulls (`P-11`). `make down` no longer does this; `make ecr-prune` does, opt-in, behind a typed confirmation.

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

`E-06` is the right next one rather than `R-06` Jenkins for two reasons. It is **smaller** — one new object type (`Ingress`) plus a second Helm chart, against Jenkins' pipeline language, credentials and agent model. And it **fixes the shape**: `gateway` becomes the one public entry point and `links-service` drops to `ClusterIP`, so the gateway stops being a front door with the back door propped open beside it.

*(An earlier draft of this paragraph, written hours before the build, claimed E-06 "pays for itself immediately" by removing a load balancer from every session's bill. **That was wrong on both counts and is corrected here rather than quietly deleted.** One NLB is replaced by one ALB at roughly the same ~$16–18/month, so today it is cost-NEUTRAL; the saving arrives at services four and five, which become routing rules rather than more load balancers. And the teardown ordering gets **stricter**, not simpler — an Ingress-created ALB is invisible to the old `--field-selector spec.type=LoadBalancer` sweep.)*

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
| P-11 | **Always-on deployment target** — the dashboard that has to stay up | **WRITTEN 2026-09-18, NEVER DEPLOYED.** New repo `compose/` (`app-hub-compose`), Docker Compose running the same three images on one host behind a **Cloudflare Tunnel**. `docker compose config` validates; **zero published ports** verified in the resolved config, so nothing listens on the host. Guided build — Compose is a new tool. <br><br>**Pushed 2026-09-18** to `github.com/HarshitRawat11/app-hub-compose` at `d50e33e`. Verified against the remote rather than by the push reporting success: remote `refs/heads/master` matches local `HEAD`, ahead/behind is `0 0`, and the remote tree is exactly five files with **no `.env`** among them. | **Owner's**: the scoped IAM user + access key (by hand, NOT Terraform — `aws_iam_access_key` puts the secret in state), then the **Tailscale admin-console setup** and `.env` on the host. The GitHub repo is **done** (2026-09-18). <br><br>**HOSTNAME DECIDED 2026-09-18: Tailscale Funnel**, replacing `cloudflared`. A named Cloudflare Tunnel's hostname must sit on a zone in the account, and `manifests/ingress/README.md:199` already records this project as owning no domain — and there is **no free stable hostname for Tunnels** (`*.pages.dev` is Pages-only; Quick Tunnels change URL on every restart). Tailscale gives a stable `*.ts.net` HTTPS name free and permanently, with no domain. **A new service in the stack, approved by the owner** per § 4. The domain option stays open and would additionally unblock the ACM certificate `manifests/ingress/README.md:200` waits on. <br><br>**OWNER'S TAILSCALE STEPS, and step (e) is the one that bites later:** create the account, enable HTTPS certificates, **grant `funnel` in the ACL policy** (off by default — without it the node is healthy and unreachable), generate a **reusable, non-ephemeral** auth key, and **disable key expiry on the node** (180-day default would take the dashboard dark with no local cause). <br><br>**FUNNEL IS PUBLIC AND THE HOSTNAME IS NOT SECRET** — Certificate Transparency logs are public, and **gateway does not filter on the `public` flag**, so the private catalogue entries would be exposed. `"AllowFunnel": false` makes it tailnet-only on the same hostname. <br><br>**REGISTRY BLOCKER FOUND AND FIXED 2026-09-18.** `ecr.tf` was in the ephemeral stack, so the nightly destroy **deleted** the repositories — this host would have worked until the first teardown, then failed on `docker compose pull` with an error indistinguishable from the 12-hour login expiry. Moved to `infra/persistent/` with `prevent_destroy`, and `make down` no longer empties ECR (`make ecr-prune` does, opt-in). **`infra/persistent/` must now be applied before the next `make up`.** | **Laptop first, Oracle later.** Oracle's documented idle policy reclaims Always Free instances under 20% CPU/network/memory over 7 days, which is exactly a bookmark dashboard — and the common claim that Pay-As-You-Go exempts you is **not in the docs**. The laptop is also x86, so no `arm64` rebuild. Every file is identical for both, so Oracle becomes a redeploy rather than a rethink. <br><br>**Shares the `C-04` DynamoDB table** rather than a local store: a local one gives two divergent catalogues of the thing used daily, and shared is the cheaper direction to reverse. Costs a long-lived AWS key on disk — there is no IRSA outside EKS. |
| P-10 | Public project page — **LIVE on Cloudflare Pages** | **DONE 2026-09-18 — <https://app-hub-hr.pages.dev>.** Deployed from `master` with no build command, output directory `site`. **All four security headers verified live** by `curl -sI`, and `Cache-Control: public, max-age=300` on `/static/*` — so `_headers` works identically on Cloudflare and Netlify, which is why it was moved out of `netlify.toml`. `learn/32`. <br><br>Deploying found one real defect: **every nonexistent path returned `200` with the homepage** — Pages falls back to `index.html` when the output directory has no `404.html`. Fixed by adding one — **but that fix is NOT LIVE YET.** <br><br>**The Pages project is DISCONNECTED from the Git account**, so it is stuck on  and two commits behind. The dashboard shows *"Automatic deployments enabled"* and *"This project is disconnected from your Git account"* **at the same time** — a status claiming health while broken, which is why the live check was a  against the real URL rather than a glance at the console. Reconnect under Settings → Builds & deployments, or GitHub → Installed GitHub Apps → Cloudflare Pages → grant . <br><br>*(Was: BUILT 2026-09-16, NOT YET DEPLOYED — `site/` plus `netlify.toml` at the repo root. Landing page (architecture, cost policy, seven repos, write-ups) and **the real dashboard running with no backend** at `/demo.html`. Verified locally: every asset 200s, the stub matches the real API's status codes (201/204/404), and `check-doc-drift.py` gained a vendored-copy check. `learn/32` | **Needs the owner** — connecting the repo means logging into Netlify and authorising it against GitHub, which is not something to hand to an agent | Follow `site/README.md`: Netlify → Add new site → import `HarshitRawat11/app-hub`, **leave every build setting blank** (`netlify.toml` sets `publish = "site"` and an empty command). Every push to `master` redeploys after that. <br><br>**Projects section added 2026-09-17.** `site/projects.json` is the single source of truth, read by three things: the landing-page section, the demo catalogue, and `scripts/seed-projects.py`. A **`public` flag** decides where each entry may appear — three of the owner's four URLs are reachable only from their own machine (`localhost:4322`, `localhost:8001`, and a personal Xiaomi notes account), which is correct for a private start page and wrong on a public portfolio page. <br><br>**Projects updated 2026-09-20:** `Procedo` and `Acharya Amit Puri` both moved to Cloudflare Pages. **The old `procedoinfo-preview.netlify.app` now returns 404**, so the public page had a dead link on it until this change — found by checking the URL rather than by anyone reporting it. `Acharya Amit Puri` flipped to `public: true`, which its own note had pre-authorised *"once it has a real URL"*; it was `false` only because the URL was a localhost dev server. **Three publicly-visible cards now, not one**, and all six public links (three sites, three repos) verified `200` — the GitHub `200`s from an unauthenticated curl also confirm those repositories are genuinely public. *(was: Procedo has no URL and every blurb is empty)* |
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
| E-06 | Migrate from per-service LoadBalancer to a shared ALB via Ingress | **DONE and VERIFIED ON REAL EKS** 2026-09-18 — one internet-facing ALB in front of `gateway`, all three Services `ClusterIP` with `external=<none>`, and **exactly one load balancer in the account**. Dashboard, `/links` and `/status` all served through it, with the catalogue coming back from DynamoDB. The controller registered **pod IPs** (`10.0.1.112:8001`, `10.0.2.188:8001`), confirming `target-type: ip` and why the Services could stay `ClusterIP`. Guided build; `learn/33`. <br><br>**The teardown path is now live and was never exercised before today** — delete the Ingress, wait for the ALB, THEN uninstall the controller. `make down` encodes it. <br><br>*(Was: WRITTEN 2026-09-16, NEVER APPLIED TO A CLUSTER — built as a **guided build** at the owner's choice. Claude wrote `infra/alb-controller-irsa.tf`, `manifests/alb-controller/values.yaml`, `manifests/ingress/` (IngressClass + Ingress), flipped `links-service` to `ClusterIP`, and encoded the new teardown ordering in `make down`. Passes `make validate` offline — terraform `validate`/`fmt`, and the manifest checker — and **has met no API server**. The owner runs every command in `manifests/ingress/README.md`. No `learn/` file yet, deliberately: it gets written after it runs, so it records what happened rather than what was intended. **Its number is deliberately not stated here** — `learn/` files are numbered in the order steps are *performed*, so a number claimed in advance moves every time something else lands first. This one was written as `31`, then `32`, in a single day | `Ingress`/`IngressClass` are Kubernetes object types the owner has not written, and the ALB controller's Helm values are on the hand-write list — so this stays whole rather than splitting. Wait until `gateway` is deployed, so there are actually two services to route between. <br><br>**Decided 2026-09-10 — the flip is confirmed, only the implementation waits:** `gateway` becomes the publicly reachable service via Ingress + a shared ALB, and **`links-service` becomes `ClusterIP`, not reachable from outside at all.** That is the entire point of having a gateway, and it removes the public endpoint `E-05` verified — deliberately. Deciding now means `gateway`'s Service manifest never needs revisiting; it is `ClusterIP` today only to avoid a second ELB and a second bill before the Ingress exists. | Every `type: LoadBalancer` Service provisions its **own** ELB — N services means N load balancers and N bills. An Ingress + the AWS Load Balancer Controller gives one shared ALB with path-based L7 routing. Premature with a single service; the right move once there are two. |

### Phase 3 — Production readiness

| ID | Task | Status | Blocker | Next step |
|----|------|--------|---------|-----------|
| R-01 | Add resource requests and limits to the Deployment | **Done and VERIFIED on a live cluster** 2026-09-10 | None | `e073761`. requests 50m/64Mi, limits 500m/256Mi → **Burstable** QoS. Previously **BestEffort**, i.e. first evicted under node pressure. Numbers are starting points, not measurements — revisit once `R-05` shows real usage. 
| R-02 | Add a `securityContext` (non-root, read-only rootfs) | **Done and VERIFIED on a live cluster** 2026-09-10 | None — enforcement confirmed. | `98f355b` + `e073761`. Dockerfile creates `appuser` uid 10001 and switches to it; Deployment sets `runAsNonRoot`, matching uid, `readOnlyRootFilesystem`, drops ALL capabilities, RuntimeDefault seccomp. **Verified locally**: the image runs as uid 10001 and serves fine under `docker run --read-only` with no tmpfs mounted at all. |
| R-03 | Replace the mutable `:v1` tag with immutable tags | **Done** 2026-09-03 · 11:20 IST | None | `c06d65f`. `image_tag_mutability = "IMMUTABLE"` in `ecr.tf`; the Makefile derives the tag from the links-service commit SHA (a dirty tree gets a timestamp suffix so the push stays unique). A tag now names exactly the code it was built from. **Takes effect on the next `terraform apply`.** |
| R-04 | Deploy into a dedicated namespace | **Done and VERIFIED on a live cluster** 2026-09-10 — **admission control demonstrably rejected a non-compliant pod** | None | `e073761`. New `00-namespace.yaml` (the `00-` prefix is load-bearing — `kubectl apply -f dir/` goes in filename order and everything else references the namespace). Enforces the **restricted** Pod Security Standard, so non-compliant manifests are rejected at admission rather than quietly running as root. 
| R-05 | Observability: **Prometheus / Grafana via `kube-prometheus-stack`** | **DONE and VERIFIED ON REAL EKS** 2026-09-14 — 22 targets all UP, five of them app-hub pods, scraped because of one `ServiceMonitor` with no config file edited and nothing restarted. Built as a **guided build** (`CLAUDE.md § 2`), a tier added this day at the owner's request: Claude wrote `values.yaml` and the `ServiceMonitor`, the owner ran every command and hit every failure. `learn/30` | Depends on `E-04`. **Phase 2 in the owner roadmap — comes before CI/CD.** | Helm chart. Note this is *why* the node group is EC2 and not Fargate: `node-exporter` is a DaemonSet, which Fargate does not support. First stateful workload — the PVC/EBS teardown checklist in `CLAUDE.md § 9` becomes mandatory from here on. |
| R-06 | CI: **Jenkins in-cluster via Helm** | **WRITTEN, NEVER APPLIED — but no longer blocked on credentials (2026-09-20).** Both deploy keys verified at the access level (Jenkins write, ArgoCD read-only), and the admin password is generated and stored at `~/.app-hub/jenkins-admin.env` (mode 600, outside every repo, never printed). `make jenkins-password` done; `make jenkins-secrets` puts both Secrets in the cluster and is a **routine post-`make up` step**, since Secrets die with the cluster. **All that remains is a cluster.** <br><br>*(was: WRITTEN 2026-09-18, NEVER APPLIED.* Guided build — Jenkins is a genuinely new tool, so Claude wrote the artifacts and the owner runs every command. `infra/jenkins-irsa.tf` (third IRSA role, ECR push only, no delete), `manifests/jenkins/` (namespace at `baseline` PSS, values.yaml carrying the **entire** Jenkins config as JCasC), `links-service/Jenkinsfile`, and `make jenkins`. Passes offline checks; **no API server and no running Jenkins have seen it.** <br><br>**Owner's decisions, taken 2026-09-18:** JCasC over persistence (the cluster dies nightly, so a PVC buys nothing and adds an EBS orphan risk); **Kaniko** over Docker-in-Docker (DinD needs privileged, which `baseline` forbids and which is a real escape risk); a **deploy key** over a PAT (scoped to one repo). <br><br>**Known incomplete and stated in the file:** the Test stage is a placeholder — the Kaniko container has no Python, so the pipeline is **not yet a CI gate**. Adding a second container to the agent pod template is the first task after it runs. | Depends on `R-05` landing first (owner roadmap phase 3) | Build, test, push image, then **commit a bumped image tag into the `manifests` repo**. Jenkins must never run `kubectl apply` — that is ArgoCD deliberately (see Decisions). |
| R-07 | CD: **ArgoCD, GitOps from `app-hub-manifests`** | **DONE and VERIFIED ON REAL EKS 2026-09-19** — all six Applications `Synced`/`Healthy`, exactly one ALB, the app served through it (`HTTP 200`, catalogue from DynamoDB). Guided build — ArgoCD is a genuinely new tool, so Claude wrote it heavily commented and the owner runs every command. Chart `argo/argo-cd` **10.9.2** (ArgoCD v3.5.3), read from `helm search repo` rather than guessed. **App-of-apps**: one root Application applied by `make argocd`, five children in `manifests/argocd/apps/` ordered by sync wave (namespace -1, services 0, Ingress 1). `automated` + `prune` + `selfHeal`. `dex` and `notifications` disabled. <br><br>**THREE CLAIMS WERE TESTED RATHER THAN ASSERTED, AND ONE WAS FALSE.** (1) **`applicationSet.enabled: false` DID NOTHING** — that key does not exist in chart 10.9.2 (the only `enabled` beneath it is `applicationSet.pdb`), **Helm accepts unknown values silently**, and the controller ran anyway. Caught by reading `kubectl get pods`, not the file. Settled with `helm template`: `enabled=false` renders `replicas: 1`, `replicas=0` renders `replicas: 0`. Fixed to `replicas: 0`; note the Deployment object still exists with no pods. (2) **`enforce: restricted` survived** — proven by admission control actually rejecting a busybox pod, not by reading the label. (3) **`selfHeal` reverts in SECONDS, not ~3 minutes** — a `scale --replicas=0` was already back to 2 before the next command ran, because ArgoCD watches resources rather than only polling. The 3-minute figure was wrong in six places and is corrected. | **Owner's**: generate a **read-only** deploy key on `app-hub-manifests` (Jenkins's existing key is write; ArgoCD only reads) and create the labelled `app-hub-manifests-repo` Secret. `make argocd` refuses to install without it. Then a cluster. | ArgoCD watches the manifests repo and reconciles. **`make down` gained a step 0** because of it: with `selfHeal`, deleting the Ingress makes ArgoCD recreate it, the controller provisions a **second ALB**, and teardown orphans it — `D-28` again, with something actively undoing the fix. Step 0 deletes the root Application first (cascading, while the ALB controller is still alive) and **asserts zero Applications remain**. <br><br>**`make validate` now globs two directory levels**, because `manifests/argocd/apps/` sits deeper than anything before it and a one-level glob would have skipped it silently — the same failure that hid `manifests/monitoring/` until 2026-09-16. **Proven by deleting a namespace from a child Application and watching validate fail**, then restoring it. <br><br>**Not under ArgoCD, deliberately**: ArgoCD itself (bootstrap paradox), the ALB controller (must exist before the Ingress), Prometheus and Jenkins (Helm releases — the natural second step). `learn/35`. |

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
| N-06 | Move n8n off local Docker onto a managed host | **RE-TARGETED 2026-09-20 to the always-on host (`P-11`), not EKS — owner's decision.** Written into `compose/`: the service, a **tailnet-only** Tailscale route on `:8443` (the dashboard keeps the public `:443`), and the `n8n_data` volume declared **`external: true`** so Compose attaches the existing one. **Not yet migrated** — the running standalone container is untouched; `compose/README.md` carries the procedure. <br><br>**Why EKS was the wrong home**, and the reasoning outlived the original decision: it needed a Postgres surviving the nightly destroy (a permanently-billing RDS, against `O10`'s `$0` resting state); it would have put the **cost watchdog on the cluster it watches**; and it needed `N8N_ENCRYPTION_KEY` as a Secret — a problem that simply **does not exist** on the host, because the key lives inside the volume. <br><br>**The danger, stated once and loudly:** if that volume were ever not `external`, n8n would start blank, generate a fresh key, and every stored credential would become permanently undecryptable. `N-05` exists because this was foreseen. <br><br>*(was: Decided YES (2026-08-30) — **mostly OWNER**: `ConfigMap`/`Secret`/`PVC` and Helm values are new object types and hand-write items; the Deployment/Service are second instances, so Claude's | Depends on Phase 2 landing first. Not urgent — local Docker is fine meanwhile. | Needs: a Postgres backing store (n8n defaults to SQLite, unsuitable in a pod), `N8N_ENCRYPTION_KEY` supplied as a Kubernetes Secret (**must be the existing key from `~/.n8n`, or every stored credential becomes undecryptable** — see `N-05`), and persistent storage. Note this interacts with the destroy-every-session policy: the database must live outside the destroyed stack. See the `C-03` note on splitting Terraform into ephemeral and persistent stacks. |

### Phase 5 — Further services

| ID | Task | Status | Blocker | Next step |
|----|------|--------|---------|-----------|
| S-01 | Build `gateway` — entry point, routes to `links-service` by Kubernetes DNS name | **DONE** 2026-09-10 — all six steps, **deployed and verified on real EKS** | None | **Repo `app-hub-gateway` exists and is pushed** (sixth repo — `CLAUDE.md § 3`). Owner writes every line; Claude reviews and verifies. Six-step build order and rationale in `learn/21`. <br><br>**Done:** (1) skeleton + `/health` on port **8001** — `36feb40`, 2026-09-06 · 12:22 IST. (2) `GET /links` calling `links-service`, `async def` + `httpx.AsyncClient`, client moved to app scope via `lifespan` — `7c52711`/`1d5c088`, 2026-09-07 · 11:27–13:27 IST. (3) explicit 3s client timeout + upstream failure mapping — `261e5db`, 2026-09-07 · 18:35 IST. **All four paths verified live** against a fake upstream: nothing listening → `503`; hangs 30s → `504` at 3.01s; upstream 4xx/5xx → `502`; healthy → `200`. <br><br>**Steps 4–5 done; step 6 is written and validated but NOT applied** (2026-09-10). The ECR repository (`0b280cf` in `app-hub-infra`) and the manifests (`c698344` in `app-hub-manifests`) exist in git and pass offline validation; nothing has been applied because there is no cluster. What remains is `make deploy` against a live cluster. <br><br>**Steps 4–6 reassigned to Claude on 2026-09-09** by the `CLAUDE.md § 2` revision — step 4 is config plumbing, step 5 is a copy of the `links-service` Dockerfile, and step 6's Deployment/Service are second instances of object types the owner has already written. Steps 1–3 stay owner-written and are not to be rewritten. <br><br>**Step 4 DONE** 2026-09-09 · 13:10 IST (`cb39f11`, Claude-written). `LINKS_SERVICE_URL` read at module scope with `.rstrip("/")`; the `503`/`504` handlers no longer pass `str(e)` to the caller, so the upstream URL stops leaking — fixed strings out, real exception to the log. Added `tests/fake_upstream.py` (port + mode aware: `ok`/`404`/`html500`/`slow`). **Verified, five cases against a freshly started gateway:** unset → `200`; `:9999` → `503`; `:8000/` → `200` (rstrip); `:8002` 404 → `502`; `:8003` slow → `504` at 3.02s. Bodies carry no URL. <br><br>**Step 5 DONE** 2026-09-09 · 13:40 IST (Claude-written). `Dockerfile` near-identical to the `links-service` one, port 8001, plus a `.dockerignore` (see `D-14`). **Verified:** image builds; runs under `docker run --read-only` with no tmpfs; `id` reports uid 10001; `/health` 200; `/links` returns `503` correctly because inside the container `localhost:8000` is the *container's* localhost. <br><br>**Step 6's core claim was then rehearsed locally, for free:** both images on a Docker network, `gateway` pointed at `-e LINKS_SERVICE_URL=http://links-service:8000`, reaching `links-service` **by name** — seeded a record and read it back through `gateway`, both containers read-only and non-root. The Kubernetes version differs only in who supplies the DNS name (a Service rather than a network alias). Test containers and network removed; nothing pushed. <br><br>**Next: step 6** — second ECR repo in `infra/ecr.tf`, manifests (`Deployment` + `Service`, second instances so Claude's; the `env:` block is the one new part and gets flagged), deploy. **Costs money — batch into the next cluster session.** Note the teardown script currently empties only the `links-service` ECR repo; a second repo full of images is a new way for `destroy` to fail (`CLAUDE.md § 9`). <br><br>**`learn/22` WAS written** (short note, per the two-tier rule) and covers steps 4–5. *This cell previously said it would not be written, which was the plan before the 2026-09-09 revision made delegated work get short notes too. Caught 2026-09-13 during a `learn/` audit — and it had already caused a second error, an edit to `gateway/README.md` asserting the file did not exist.* `learn/21` carries the design rationale, `learn/27` the dashboard and full proxy. |
| S-02 | Build `aggregator` — calls `links-service` internally; **the service that truly proves discovery** | **DONE** 2026-09-13 (`83d4b1d`) — **written AND verified running locally** against real targets. **Deployed and verified on real EKS 2026-09-18** as part of `E-06` — this row said "not deployed" until then. | None — the owner created `HarshitRawat11/app-hub-aggregator` on 2026-09-13, which cleared the last blocker. *Was: blocked on the owner, twice over.* (1) It needs a GitHub remote — there is no `gh` CLI on this machine, so `HarshitRawat11/app-hub-aggregator` has to be created in the web UI. (2) It has to pick an HTTP client, which is `D-17`. | Application code, named explicitly in the `CLAUDE.md § 2` delegation list. Distinct from `gateway`: `gateway` is the external entry point, `aggregator` exercises purely internal pod-to-pod discovery. Its Deployment/Service are second instances, so also Claude's; anything new in the manifest gets flagged in a few lines rather than walked through. <br><br>**What it actually does:** reads the catalogue from `links-service` and **probes every URL concurrently**, so the dashboard shows which apps are reachable rather than just listing them. That makes it real software rather than a discovery demo — and its workload genuinely differs from a CRUD API (waiting on slow third parties vs answering from memory), which is the honest test of whether something deserves to be its own service. <br><br>**The chain it completes:** browser → `gateway` → `aggregator` → `links-service`. `aggregator` is `ClusterIP` and never publicly reachable, so **neither end of the inner hop is the front door** — which is what makes it a real test of Kubernetes DNS rather than a restatement of "the entry point can reach a service". `gateway` gained `GET /status` to proxy it, because the same-origin dashboard has no other way to reach a ClusterIP service. <br><br>**Central rule: a down link is DATA, a down `links-service` is an ERROR.** `/status` answers 200 with the link marked `down`; only the upstream being unreachable is 5xx. Blurring them leaves the dashboard unable to tell "your NAS is off" from "the hub is broken". Anything under 500 counts as `up`, **including 401/403** — the question is "is it running", not "may I in". <br><br>**47 tests**, plus 6 added to `gateway` for the new hop. **Verified live against real targets:** a running n8n (`up`, 200, 4 ms), a stopped Grafana (`down`, `ConnectError`), example.com over the real internet (`up`, 78 ms), and `169.254.169.254` (`blocked`). Also verified that stopping `aggregator` leaves the dashboard working with grey dots and **no error banner** — liveness is a decoration on the catalogue, not a dependency. <br><br>See `D-20` for the SSRF consideration, and `learn/28`. |
| S-03 | Build `frontend` — the dashboard | **DONE** 2026-09-13 · 00:01 IST (`c522956`) — **written AND verified running locally** (two services, driven through a real browser). **Deployed and verified on real EKS 2026-09-18** as part of `E-06`, served through the ALB — this row said "not yet deployed" until then. | None | Application code. **Built INTO `gateway` rather than as a fourth service, which is a deliberate change from how this row was originally written** — see `learn/27`. A separate frontend would have needed CORS on every gateway response, a second public endpoint (so a second ELB, which `E-06` is explicitly deferring), and a third GitHub repo only the owner can create. Served from gateway, every URL in the page is a bare path and none of that exists. Reversible if `E-06` later wants it behind its own nginx pod. <br><br>**gateway became a real proxy to make it useful:** `GET /links/{id}`, `POST /links` and `DELETE /links/{id}` added alongside the original `GET /links`, all through one `_proxy` helper holding the owner's step-1–3 error mapping — moved, not rewritten. <br><br>**The design point worth keeping: not every upstream 4xx is a gateway fault.** A `404` from `GET /links/{id}` is the correct answer about an id that does not exist, and a `422` from `POST` is about what the caller sent. Flattening either to `502` says *the server is broken* and sends someone to the wrong machine. `GET /links` passes nothing through, because the collection always exists — the asymmetry is the point. <br><br>**47 tests, up from 15.** Verified live: all four routes through gateway to links-service, `Location` round-trip followed, `503`/`504`/`502` all reproduced (504 at 3.006 s), and the XSS guards proven with a real payload rather than asserted. See `D-19` for the bug every test missed. |

---

## Known defects

| ID | Severity | Where | What is wrong |
|----|----------|-------|---------------|
| ~~`D-30`~~ | **RESOLVED 2026-09-20.** Continuous deployment restored: the owner granted the Cloudflare Pages GitHub App access to `app-hub`, the repository then **appeared in the connect dialog** (three entries where there had been two), and reconnecting produced a Git-triggered deployment of `f65f530` within two minutes. **The missing repository was the whole of it.** <br><br>*(was: Medium — continuous deployment is broken; the site is current but `git push` no longer publishes it)* <br><br>**WORKED AROUND 2026-09-19, NOT FIXED.** The owner reported the Cloudflare dashboard showing the build **failed** — so this was a failing build, not the 2026-09-18 Git-disconnect repeat I had suspected. A direct CLI upload (`wrangler pages deploy site --project-name=app-hub-hr --branch=master`) published 3 changed files in 1.6s and **production now matches local byte for byte**: 22,167 B, `<main>` present, 20 `var(--fs-*)` references, all four security headers intact, `/not-a-page` still 404. Lighthouse on the live page afterwards: **100 / 100 / 100 / 100, zero accessibility failures.** <br><br>**THE RESIDUAL IS THE IMPORTANT PART: the Git-integration build still fails.** Every future `git push` will leave the site stale, silently, exactly as it did today. The workaround publishes; it diagnoses nothing. <br><br>**Ruled out along the way:** three junk files named `review$name-*.png` (a mangled shell expansion of mine, committed in `ba0f0df`) were removed, but they sat at the repo root and the output directory is `site/`, so they were never uploaded. Not the cause. <br><br>*(was: a pushed commit has not reached the live site, and the cause cannot be determined from outside)* | Cloudflare Pages project `app-hub-hr`, deploying `site/` from the umbrella repo | **OPEN 2026-09-19.** Commit `ba0f0df` (the `<main>` landmark and the type/radius tokens) was pushed to `master` and **had not deployed ~7 minutes later**. Measured, not guessed: live `index.html` is **20,269 B** against **22,167 B** local, live contains **0** occurrences of `<main>` and **0** of `var(--fs-`, and still serves the old `font-size: 0.93rem` three times. <br><br>**Two candidates, and I cannot separate them without the dashboard:** (1) the build is queued or slow — but this is a no-build static site that normally publishes in under a minute; (2) **the Git integration has silently disconnected again**, which is exactly what happened on 2026-09-18, when the console reported *"Automatic deployments enabled"* and *"This project is disconnected from your Git account"* **simultaneously** while the site sat three commits stale. <br><br>**`projects.json` still matches local, and that is NOT evidence the deploy works** — that file has not changed since the last successful publish, so it would match either way. It is the same trap as reading `active: true` off a dead n8n workflow. | **ROOT CAUSE FOUND 2026-09-20, and it is specific: the Cloudflare Pages GitHub App has lost access to the `app-hub` repository.** Opening the project's *Connect to a repository* dialog shows the Git account **already authorised** (`HarshitRawat11` pre-selected, **no OAuth or password screen at all**) — and a repository list offering only **`Procedo`** and **`acharya-amit-puri`**. **`app-hub` is simply not in it.** <br><br>**That explains every symptom at once.** The account-level OAuth is intact, which is why `wrangler` reports `Git Provider: Yes` and why the other two Pages projects deployed normally 22 and 23 hours ago. Only this project's repository was dropped, so only this project stopped building — while a panel still read *"Automatic deployments enabled"* beside a banner reading *"disconnected from your Git account"*. **It was never an account problem and never a build-configuration problem; it was one repository missing from one app's access list.** <br><br>**Re-granting on GitHub was tried first and did not fix it** — a push of `74e44a5` afterwards produced **zero** deployments in four minutes. Tested, not assumed. <br><br>**STATE AS OF NOW: the project is DISCONNECTED**, at the owner's instruction, which is the correct precondition for a clean reconnect. **The build configuration disappeared with the link and must be re-entered on reconnect** — build command *empty*, **build output `site`**, root directory *empty*, production branch `master`. <br><br>**Remaining step, owner-only:** on GitHub, grant the Cloudflare Pages app access to `HarshitRawat11/app-hub` (Settings → Applications → Cloudflare Pages → Repository access). That page sits behind a GitHub password prompt, which is a hard stop for Claude. Then reconnect in Cloudflare and **prove it with a push**, not with the banner clearing — that banner has already been observed both lying and telling the truth. <br><br>*(Superseded: the earlier note below, which recorded the settings as correct but had not yet identified the missing repository.)* <br><br>**ROOT CAUSE CONFIRMED 2026-09-20 by reading the dashboard directly.** Every build setting is **correct**: build command *empty*, build output **`site`**, root directory *empty*, production branch **`master`**, automatic deployments **Enabled**, build watch paths **`*`**, build system **Version 3**. **So every hypothesis offered beforehand was wrong** — it was never a populated build command, and never a wrong output directory. <br><br>**The sole fault is the banner: _"This project is disconnected from your Git account."_ And the console contradicts itself on a single screen** — that banner sits directly above a panel reading _"Automatic deployments enabled"_. **`wrangler pages project list` also reports `Git Provider: Yes`.** Three signals; **the two reassuring ones are the wrong ones.** The banner is right, because nothing has deployed from git since 2026-09-18 01:19 IST. <br><br>**That is this project's recurring disease in a new costume** — a console that renders *"I cannot see it"* and *"it is not there"* identically, and then answers confidently. The only trustworthy signal was the served bytes. <br><br>**The repair lives on the GitHub side, not Cloudflare's.** The project's settings offer *Manage*, which opens the Cloudflare Pages GitHub App installation at `github.com/settings/installations/<id>`. **That page demands a password (GitHub sudo mode), which is a hard stop for Claude** — entering a password is not something to hand to an agent under any framing, so the final step is the owner's. <br><br>**DIAGNOSED 2026-09-19 from the deployment list, and it is not what either of us assumed.** `wrangler pages deployment list` shows the **last Git-triggered deployment was `215f04d`, committed 2026-09-18 01:19 IST** — whose message is, fittingly, *"P-10: the site is live but two commits stale"*. **Twelve commits have been pushed since and NOT ONE produced a deployment record** — not a failed one, not any. So this is most likely **a build that is never triggered**, rather than one that runs and fails. <br><br>**Repo-side causes ruled out:** 74 tracked files, largest 270 KB, `site/` holds 10 files none over 1 MB, `.git` is 9.4 MB — all far inside every Pages limit. Nothing here would break a build. <br><br>**I cannot fix this.** Reconnecting Cloudflare to GitHub is an OAuth login on the owner's accounts, which is not something to hand to an agent. <br><br>**MITIGATED, and the mitigation is the durable part: `make deploy-site`.** It publishes `site/` with `wrangler` and then **asserts against the live bytes** rather than trusting the upload's exit code — comparing the served `index.html` to the local one, checking a bad path still returns 404, and checking all four security headers survive. Each of those three has caught a real defect on this site before. Tested end to end. <br><br>**Owner's, still**: reconnect the Git integration if continuous deployment is wanted. Until then `git push` publishes nothing, and `make deploy-site` is the only thing that does. Two likely candidates to check on the same screen: **Build command** should be *empty* (a framework preset populating `npm run build` would fail instantly, with no `package.json` in the repo) and **Output directory** should be `site`. <br><br>Until the build is fixed, **publishing requires the CLI**:<br>`npx wrangler pages deploy site --project-name=app-hub-hr --branch=master`<br><br>And verify by comparing, never by reading the console, which has already been observed lying about this project's deploy state. **In PowerShell** (the default shell here — it has no `<(...)` process substitution, so the obvious `diff <(curl ...)` fails at the parser):<br>`curl.exe -s https://app-hub-hr.pages.dev/ -o "$env:TEMP\live.html"; if ((Get-FileHash "$env:TEMP\live.html").Hash -eq (Get-FileHash .\site\index.html).Hash) { "MATCH" } else { "DIFFER" }`<br>Full form, and the WSL equivalent, in `site/README.md`. |
| ~~`D-29`~~ | **RESOLVED same day** 2026-09-19 — was **High: it deadlocked a teardown with the cluster billing** | [manifests/ingress/00-ingressclass.yaml](manifests/ingress/00-ingressclass.yaml), [manifests/ingress/ingress.yaml](manifests/ingress/ingress.yaml) | **ArgoCD deleted the `IngressClass` alongside the `Ingress`, and that made the Ingress undeletable.** The Ingress carries the finalizer `ingress.k8s.aws/resources`, which only the AWS Load Balancer Controller can clear — and it clears it by *updating* the Ingress, an update checked by the controller's own validating webhook: <br><br>`admission webhook "vingress.elbv2.k8s.aws" denied the request: invalid ingress class: IngressClass "alb" not found` <br><br>So the controller could not finalize its own object. The Ingress never went, the `app-hub` namespace stayed `Terminating`, the `ingress` and `app-hub-root` Applications never finished deleting, and **`make down` step 0's assertion would have aborted the teardown with the cluster still running.** Observed live: 3 of 6 Applications stuck for 5+ minutes. <br><br>**Why it never appeared before ArgoCD.** `kubectl delete -f manifests/ingress/` deletes in FILENAME order, so `00-ingressclass.yaml` went first, the Ingress was already gone, and there was nothing left for the webhook to validate. **The `00-` prefix that makes creation safe makes deletion safe too — by accident.** ArgoCD does not use filenames, so the accident stopped happening. <br><br>**Unblocked** by re-applying the IngressClass; the finalizer cleared in **4 seconds**. **Fixed** with explicit sync waves — IngressClass `0`, Ingress `1` — because ArgoCD applies ascending and **deletes descending**, so the Ingress is now always removed while its class still exists. |
| ~~`D-28`~~ | **RESOLVED same day** 2026-09-18 — was **High, and it orphaned a real billing resource** | [Makefile](Makefile) `down` step 1 | **`make down` step 1 had never worked.** `kubectl delete ingress --all-namespaces --ignore-not-found` returns *"error: resource(s) were provided, but no name was specified"* — `--all-namespaces` chooses which NAMESPACES to search, `--all` chooses which OBJECTS. The `-` prefix made `make` swallow it. <br><br>So on the first teardown with an ALB present, the step whose entire purpose is preventing an orphaned load balancer deleted nothing, and the teardown carried on to **uninstall the controller while the Ingress still existed**. A watcher caught the forbidden state directly: `08:07:33 lb=1 helm=1 ingress=1`. <br><br>**A deadlock as well as an orphan.** The Ingress carries finalizer `ingress.k8s.aws/resources`, removed only by that controller — so the ALB kept billing AND the Ingress could never finish deleting. Recovery: reinstall the controller, delete the Ingress (ALB gone in 10s), then tear down. <br><br>**Why it hid:** the next line, `kubectl delete svc --all-namespaces --field-selector ...`, IS valid — the field selector supplies the object selection. Two adjacent lines that look like one idiom, one of which is wrong. <br><br>**Fixed twice over:** correct flags (`--all -A`), and an **abort guard** that refuses to uninstall the controller while any ingress survives. The ordering was documented correctly in three places and enforced in none — **sequencing two steps is not the same as enforcing that the first one worked.** `learn/33`. |
| ~~`D-26`~~ | **RESOLVED same day** 2026-09-16 | [aggregator/app/main.py](aggregator/app/main.py) | `/status` published `checked_at` as a **`time.monotonic()` reading** — responses carried `"checked_at": 120573.88`. Monotonic counts from an arbitrary epoch (boot), so the value is meaningless outside the producing process. **Three real failures, not cosmetics:** a field named `checked_at` reads as a timestamp so clients render 1970; it is **not comparable across pods**, so two replicas disagree about the same instant; and it **runs backwards after a restart**. <br><br>Monotonic was, and remains, correct for the cache TTL — a wall clock there could make an entry look an hour old, or an hour in the future, after an NTP correction. `age_seconds` also stays monotonic-derived, since subtracting wall-clock readings could report a negative age. **The bug was publishing it, never using it.** Cache now carries `monotonic` and `wall` under honest names. <br><br>**Found by running the app and reading the output, not by a test.** 50 aggregator tests asserted `age_seconds >= 0` and **nothing had ever asserted anything about `checked_at`**, which had been visible in every response since the service existed. `learn/17` postscript. |
| ~~`D-27`~~ | **RESOLVED same day** 2026-09-16 | [gateway/tests/test_gateway.py](gateway/tests/test_gateway.py) | **`importlib.reload(app.main)` left `/metrics` inert, silently.** `main.py` instruments at import time and `prometheus_client` keeps collectors in a process-wide `REGISTRY`; reloading re-registers the same names, the duplicate is swallowed rather than raised, and the reloaded app then **records nothing**. The old collectors survive holding their old values, so `/metrics` keeps serving a plausible body frozen at the moment of the reload. <br><br>This is what made `test_ids_do_not_become_labels` pass alone and fail in the suite for two days. **The application was never affected** — production imports the module once, and the live behaviour was confirmed correct against a running server (`handler="/links/{link_id}"` recorded, raw UUID absent). A test-harness artifact — and a good argument that **a flaky test is worse than no test**, since it went red for a reason unrelated to what it guards. <br><br>Fixed by unregistering the `http_` collectors before reload, so the fresh import registers cleanly. |
| ~~`D-24`~~ | **CLOSED 2026-09-19 — the evidence arrived.** A `mode=trigger` execution at **2026-09-19 21:00:05 IST**, the first scheduled firing since 2026-09-14, **after a sleep** (06:48:47 → 12:19:29). That was the stated closing condition, met by an execution row rather than by `active: true`. <br><br>**BUT TODAY'S 17:00 TRIGGER WAS STILL MISSED, and that is the honest limit of the fix.** The restart task ran at **17:50** — 65 minutes after its 16:45 schedule, because `StartWhenAvailable: True` catches up a missed run with a randomised delay — and the n8n container's `StartedAt` is **18:32:38**, which is 42 minutes later still and which I could not account for. Either way the crons were dead at 17:00 and alive by 21:00. <br><br>**So the fix converts "dead forever" into "dead until the next restart".** That is a real improvement and not full coverage: every trigger between a sleep and the following restart is still lost, silently. <br><br>**The resume trigger did not fire on the 12:19 wake** — had it, n8n would have been alive for 17:00. That is exactly the failure predicted when it was built: *modern standby does not always raise the resume event, and a monitor whose repair depends on an event that usually fires is a monitor that usually works.* **The 16:45 daily belt-and-braces is what actually saved it**, which is the argument for having added it. | *(was: High — the cost safety net's primary control is intermittently dead)* | n8n `eks-cost-watchdog` (Schedule Trigger), n8n in Docker Desktop on the laptop | **The schedule trigger stops firing after the host sleeps, and still reports `active: true`.** <br><br>Evidence, all read 2026-09-16 with no cluster and no cost: execution **44** fired at `2026-09-14 21:00:05 IST`, `mode=trigger` — correct hour, correct timezone, the `D-22` fix working. Windows then slept `2026-09-14 22:45 UTC → 2026-09-15 05:46 UTC`. **Since that resume there has been no trigger execution at all**, although on 2026-09-15 the machine was awake `11:16–21:41 IST` — covering *both* the 17:00 and the 21:00 trigger — the container was up continuously (`StartedAt 2026-09-14 11:34 UTC`, never restarted), and the workflow is still `active: true` with empty `pinData`. <br><br>**Why this is worse than `D-22`, not a repeat of it.** `D-22` was reliably dead: wrong timezone, never fired, no email ever. This one fires *sometimes* — and an alert that arrives sometimes is what earns the trust that makes you stop running `make status`. <br><br>**The deeper problem is architectural and is the owner's call.** A watchdog for cloud spend runs on a laptop that sleeps. The window it must cover — cluster left up overnight — is *precisely* the window in which the laptop is off. Restarting the container re-registers the crons and is a workaround, not a fix. The durable answer is something that runs in AWS: an **AWS Budgets alert** (free, email, zero infrastructure) or an **EventBridge schedule**. Both are new services, so `CLAUDE.md § 4` says ask first. <br><br>**MITIGATION WRITTEN 2026-09-16, not yet applied.** `infra/persistent/budget.tf` — a **daily** $3 AWS Budget with `ACTUAL` alerts at 100% and 200%, in the persistent stack so `make down` cannot destroy it. `terraform plan` clean: **1 to add, 0 to change, 0 to destroy**. It is a **backstop, not a replacement** — billing data updates roughly daily, so it catches "yesterday cost too much", never "the cluster came up 20 minutes ago". `learn/31`. <br><br>**ROOT CAUSE FIXED 2026-09-18.** n8n registers Schedule Triggers as in-process timers, and those do not survive the Docker VM being suspended with the host. On resume n8n is running, healthy, reporting `active: true` — and fires nothing, ever again, until restarted. `scripts/restart-n8n.ps1` plus a Scheduled Task with **two triggers**: on resume (`Power-Troubleshooter` event 1, verified as **11 events in 7 days** on this machine) and daily at 16:45 as a belt-and-braces. Registered unelevated, ran end to end, `LastTaskResult: 0`. <br><br>**PROVEN BY A REAL INCIDENT THE SAME DAY.** A half-finished teardown left the cluster up from 15:42. The machine was **awake 11:18–21:27 IST**, covering both the 17:00 and 21:00 triggers — and `cost-watchdog`'s latest execution was still `2026-09-14 21:00`. Nothing fired, machine awake, cluster running. ~$0.80. A manual restart at 01:12 that morning HAD re-registered the crons; the 02:29 sleep killed them again — **which is why a one-off restart is not a fix and a per-wake one is.** <br><br>**WHAT THIS STILL DOES NOT COVER:** if the machine is *asleep at the trigger time*, nothing running on it can fire — restarting on wake cannot help, because the wake comes afterwards. That case belongs to the **AWS budget guardrail, applied and verified 2026-09-18** (~daily lag), or to EventBridge. <br><br>**NOT PROVEN YET.** The task ran clean, but that proves a restart, not a firing — `active: true` was true throughout the four dead days. **Stays open until an execution row appears after a sleep.** Until then, and afterwards: verify teardown with `make status`, never by the absence of an email. <br><br>**CHECKED 2026-09-18 23:05 IST — and today cannot be evidence, which is worth writing down before someone reads the gap as a failure.** Both of today's trigger hours passed *before the fix existed*: the task's `Last Run Time` is **22:06:12** and the commit is 22:09 (`25c7e69`). So the absence of a 2026-09-18 row means nothing either way. <br><br>**What today did establish is the link that was missing.** The task's last run at **22:06:12** and the n8n container's `StartedAt` of **22:06:18** are six seconds apart — so the task demonstrably restarts n8n, which `LastTaskResult: 0` on its own never showed. <br><br>**And the diagnosis gained a corroborating asymmetry.** `terraform-destroy-notifier` fired normally on 2026-09-17 23:42 while `eks-cost-watchdog` stayed silent through the same period. The notifier is **webhook-triggered — it has no in-process timer to lose**, which is exactly what the Schedule Trigger diagnosis predicts. Two workflows on one instance, one dead and one alive, split precisely along trigger type. <br><br>**NEXT EVIDENCE: 2026-09-19 17:00 IST**, with the daily restart at 16:45 fifteen minutes ahead of it. Read it with `mode=trigger`, not by eye — `mode=manual` rows are test runs and have repeatedly made the history look healthier than it is. Expect `status=error` if no cluster is up: that is the documented `404 No cluster found` path, and it still counts as the row this defect is waiting for. |
| `D-25` | **Medium — a teardown failed and the notification about it also failed** | `scripts/scheduled-destroy.sh`, WSL DNS, n8n SMTP | **The 2026-09-14 nightly teardown exited 2, and nothing told anyone for two days.** <br><br>`logs/scheduled-destroy-2026-09-14_174528.log` ends: `Error: validating provider credentials: retrieving caller identity from STS: ... lookup sts.ap-south-1.amazonaws.com on 8.8.8.8:53: i/o timeout` → `destroy finished: failure (exit 2)`. That is the documented WSL2 DNS failure (`CLAUDE.md § 5`), here across a sleep/resume. <br><br>**Then the second layer failed too.** The script did POST to `destroy-notifier`, which ran (execution **45**) and could not send: `connect ECONNREFUSED 192.178.158.108:465`. So the failure notification failed. <br><br>**No money was lost** — the cluster had already been destroyed by hand that evening, so the teardown was a no-op that failed rather than a real teardown that was skipped. The 2026-09-16 run succeeded (`0 destroyed`, `HTTP 200`). **That is luck, not design:** had a cluster been up, it would have billed until someone opened the logs. <br><br>**Also worth noting:** the log's own filename (`17:45:28` UTC) and its first line (`04:15 IST`) disagree by about five hours, and 04:15 IST is exactly when Windows went to sleep. The clock behaviour across suspend is **UNKNOWN** and deliberately not explained here rather than guessed at. <br><br>**CORRECTED 2026-09-18 — the claim below was too strong and is left visible rather than edited away.** It read: *"The teardown is also not running at 23:30. Both recent runs finished at ~11:18 and ~11:24 IST... the laptop is asleep at 23:30."* <br><br>**It runs at 23:30 whenever the laptop is awake.** Reading the log filenames as UTC and converting: `2026-09-16_180004` = **23:30:04 IST** and `2026-09-17_181055` = **23:40:55 IST**, both on schedule and both `exit 0`. The two late-morning runs were nights the machine was asleep, and Task Scheduler caught them up on wake. <br><br>**So the risk is CONDITIONAL, not unconditional**, and that changes what the fix is. The task itself is fine; the variable is whether the laptop is awake at 23:30. A cluster left up on a night you shut the lid still bills until morning — roughly **12 hours × $0.28 ≈ $3.40** — so this stays open. **FIX APPLIED 2026-09-18, VERIFICATION PENDING.** `-WakeToRun` is set in `register-scheduled-destroy.ps1` and the owner re-registered the task from an elevated shell. <br><br>**The second half mattered more than the first.** `-WakeToRun` is only the task's *intent*; Windows power policy decides whether wake timers are honoured at all, and it was **disabled on battery** on this machine (`DC = 0x00000000`). Setting `-WakeToRun` alone would have looked exactly like a fix and changed nothing on the nights that matter. Now measured at `AC = 0x1, DC = 0x1` — enabled on both. <br><br>**Still unverified behaviourally**, and that is the only evidence that counts here: the task settings are **unreadable unelevated** (`Get-ScheduledTask` returns nothing, `schtasks` says *Access is denied* while a made-up name says *cannot find*), so the claim rests on the elevated run reporting success. **Closes when a `logs/scheduled-destroy-*.log` appears timestamped ~23:30 IST on a night the laptop was asleep.** |
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

### 2026-09-20 · 02:32 IST — The Jenkins secrets, split along "does this need a cluster"

**Asked to create the `jenkins-admin` Secret. It cannot be created right now** —
a Kubernetes Secret is an in-cluster object and there is no cluster. The
kubeconfig still points at a destroyed endpoint that no longer resolves, which
is `CLAUDE.md § 5`'s stale-kubeconfig certainty rather than a fault.

**That reshapes the task rather than blocking it.** The Secret dies with every
`make down`, so creating it was never going to be one-time setup — and if the
password were regenerated on each rebuild it would change nightly, which
`manifests/jenkins/values.yaml` already names as the thing to avoid. So the
password has to persist *outside* the cluster, and putting the Secret in has to
become a routine step.

**Two targets, split exactly on that line:**

| target | needs a cluster? | when |
|---|---|---|
| `make jenkins-password` | no | **once, ever** — done, 02:26 IST |
| `make jenkins-secrets` | yes | **after every `make up`** — pending a cluster |

**`make jenkins-password` has run.** A 32-character random password now lives at
`~/.app-hub/jenkins-admin.env`, mode `600`. **It was never printed** — the target
reports length and file mode only, the same discipline `CLAUDE.md` applies to the
n8n API key.

**Where it lives was a constraint, not a preference.** Not in any of the eight
repositories, obviously. Also **not under `/mnt/c`**: a Windows-mounted file
cannot hold Unix `0600`, so `chmod` there **reports success and changes
nothing** — the same silent-lie family as everything in § 9. WSL home is ext4,
so the mode is real, and `stat` confirms it. Verified not to be inside any git
repo, so it cannot be committed by accident.

**`make jenkins-secrets` creates BOTH secrets**, because `make jenkins` guards on
both and delivering one leaves you blocked in the same place. It verifies each
against its source by comparing 12-character sha256 prefixes — which proves
equality while revealing nothing. That check exists because **after a password
change, a Secret that *exists* and a Secret that is *correct* are different
facts**, and `kubectl get secret` cannot tell them apart.

**Five guard paths were tested by making each one fire**, not by reading them:
no cluster, missing store, missing deploy key, plus idempotency (re-running
`jenkins-password` must not rotate — confirmed unchanged) and a control that the
real deploy key is present, so the fake-path failure is genuinely detecting
absence. Each guard prints a distinct, actionable message and exits non-zero.

**The cluster guard earns its place**: without it the failure surfaces as a DNS
error about a stale EKS endpoint, which reads like a network problem and is
really just "no cluster".

**Docs**: `manifests/jenkins/README.md` steps 1a/1c rewritten (the old text had
you type `CHANGE-THIS` by hand), `make help` updated, and `learn/36` written.
Step 1b gained a cross-reference warning **not to delete ArgoCD's key** from the
same Deploy keys page — that is precisely where yesterday's deletion happened.

**`G3` now needs only a cluster.**

### 2026-09-20 · 02:18 IST — Both manifests deploy keys verified, and the ambiguity that deleted one is closed

**The Jenkins write key was added, and adding it deleted the ArgoCD one.** Not a
duplicate — two different credentials that GitHub's Deploy keys page renders as
two near-identical truncated `ssh-ed25519` lines. The owner re-added it.

**Both keys are now verified, and "verified" here means the access LEVEL, not
just that they authenticate:**

| key | `ls-remote` | `git-receive-pack` | correct? |
|---|---|---|---|
| `argocd_manifests_ro` | `336dabd` | `ERROR: ... marked as read only.` | yes |
| `app-hub-manifests-deploy` | `336dabd` | ref advertisement | yes |

**`ls-remote` alone could not have caught the failure that matters.** A key
wrongly granted write access passes it identically to one correctly denied it.
The `git-receive-pack` probe asks GitHub to start the receive process and closes
stdin immediately, so the verdict is **GitHub's own statement** about the key's
permission — and nothing is pushed.

**Three controls, because a check narrower than the failure reports success:**
`-o IdentitiesOnly=yes` (without it ssh offers every key in the agent and a
*different* key authenticates); a key registered nowhere, which must fail with
`Permission denied (publickey)`; and the documented command block **extracted
from the README with `awk` and executed verbatim**, rather than a command
resembling it.

**One result needed explaining rather than accepting.** The ArgoCD key reads
`app-hub` successfully. That is not over-privilege — `app-hub` is public, and
GitHub lets any authenticated key read a public repository. Against the private
repos it is refused, and the three failure modes are genuinely distinguishable:
`Permission denied (publickey)` = never authenticated; `ERROR: Repository not
found` = authenticated but not authorised, with GitHub declining to confirm a
private repo exists; a SHA = allowed. Same discipline as `CLAUDE.md` § 9.

**`manifests/argocd/README.md` gained the warning that was missing.** It already
said *"do NOT tick Allow write access"* — the instruction for **adding** a key
was fine. What did not exist was anything telling a reader **looking at the keys
page** that two similar rows are both meant to be there. That is now a table
keyed on the **key comments**, which differ (`app-hub jenkins` versus
`argocd-app-hub-manifests-readonly`) even when the visible key material does not,
plus the verification procedure above.

**Why this failed quietly:** deleting the ArgoCD key breaks nothing immediately.
The private half stays on disk, the in-cluster Secret still holds it, and with
the cluster down — the normal resting state — nothing complains. It surfaces at
the next `make argocd`, as Applications in `Unknown` with `repository not
accessible`. The gap between cause and symptom is the reason the note exists.

**`G3` is no longer blocked on a key.** Jenkins has its write key and ArgoCD has
its read-only one. What `G3` still needs is the `jenkins-admin` Secret and a
live cluster.

### 2026-09-19 — The project got an end: `FINISH-LINE.md` v1.0 locked

**The problem, named plainly:** this project had no defined end. Phases
completed, tasks were added, and nothing distinguished in-scope from extra.
`README.md § Definition of done` looked like it filled that gap and did not —
it is a **per-task** checklist (code run, committed, `learn/` written,
`PROGRESS.md` updated), never a statement about when the *project* is finished.

**Two owner rulings did the load-bearing work.**

> *v1 is the platform complete. New apps are new projects.*

That reconciles a finish line with `CLAUDE.md § 1`'s instruction to *"design for
a hub that grows, not for one service that ships"* — which otherwise contradicts
having an end at all. The **platform** is the finishable thing; growth happens
**on top of** a finished v1 rather than inside it as permanently unfinished
scope.

> *all of the phases should complete and fixed which is stated in status file.*

That makes v1 **mechanical rather than a judgement call**: all 43 rows of the
status board read DONE, and `D-24` and `D-25` are closed. No argument possible
about whether it is met.

**What was written.** `FINISH-LINE.md` v1.0 — 8 content criteria, 4 design
criteria describing the visual system **as observed** (7 palette tokens, one
monospace family, `prefers-color-scheme` theming) rather than as wished for, 11
optimization thresholds, 3 deployment criteria, a deliberately long out-of-scope
list, and an **11-item gap** that is now the only remaining in-scope work.
`BACKLOG.md` seeded with 8 extras already suggested, most of them Claude's.
`CLAUDE.md § 0` carries the post-freeze rule verbatim, ahead of everything else,
so a fresh session inherits the freeze without being told.

**Two criteria were written that had never been measured** — console errors
(`O8`) and the responsive floor (`D4`). So **the gap grew by two because the
document exists**, not because anything regressed. That is the right direction:
a criterion nobody has checked is worth more written down than assumed.

**Lighthouse was deliberately excluded**, with the reason recorded: the site is
62 KB of static HTML with no images, fonts or third-party scripts, so a score
would measure Cloudflare's CDN rather than any work in this repo. `O4`–`O8` cover
the same ground with checks that can fail for reasons we control.

**The tag is `v1-scope-locked`, not `v1.0`, and that distinction is deliberate.**
The lock freezes the **scope**, not the **completion** — eleven gap items remain.
A tag reading `v1.0` on that commit would tell a portfolio reader the project had
shipped v1, which is false. A release tag belongs on the commit that closes
`G11`.

**The polyrepo caveat is recorded rather than glossed:** a tag in the umbrella
captures only the umbrella, so `FINISH-LINE.md § 0` records the HEAD of all eight
repositories at lock time. That table, not the tag, is what makes the freeze
reconstructable.

**From here, every request is DEFECT or EXTRA.** There is no third bucket, and
Claude's own suggestions are EXTRA too — the rule names Claude explicitly,
because noticing adjacent improvements mid-task is exactly this project's habit.
Scope reopens only on the explicit word **UNFREEZE**.

**UNFROZEN the same day, minutes later.** The owner read what the freeze
actually required and said so rather than living with it: *"unfreeze and continue
working on the remaining tasks."* **The gate is off; the document stays.** The
criteria were never the problem — the DEFECT/EXTRA classification ritual on every
request was. `FINISH-LINE.md` is now a roadmap: § 5 is the remaining work, § 4
records what was deliberately excluded so a future session does not re-propose
it, and § 0 still pins the eight repository HEADs. `CLAUDE.md § 0` keeps the rule
verbatim but **inactive**, restorable with the word `FREEZE`.

**Then four gap items closed immediately.**

**`G8`** — `README.md`'s status line had said *"Phase 2 complete"* for three
phases. Now reads *Phases 1, 2 and 5 complete; 40 of 43 tasks done*, names the
three open tasks, and states that nothing being deployed is **by design**.

**`G9` — and the row understated the work.** It read *"remove `netlify.toml` and
its `README.md` reference"*. In fact `site/README.md` was **substantially a
Netlify runbook** — sign-in steps, `netlify-cli`, build-setting instructions — so
it needed rewriting, not a reference swap. Found by doing the task, not by
reading the criterion. `netlify.toml` deleted; `README.md`, `CLAUDE.md § 3` and
`site/README.md` corrected to Cloudflare Pages. The rewrite folded in two things
that had cost real time: the **Git-disconnect incident** (the dashboard reported
*"Automatic deployments enabled"* and *"disconnected from your Git account"*
simultaneously, with the site three commits stale, caught by `curl` and not by
the console) and the `wrangler` path trap. Netlify references in `learn/32` and
this log are **history and were left alone**.

**`G10` — zero console errors, VERIFIED.** Both `/` and `/demo` load with no
console messages of any level.

**`G11` — responsive floor, VERIFIED, and the mechanism is now known.** No
page-level horizontal scroll at 360 / 768 / 1280 on either page. The interesting
part is at 360px: the landing page's table **is** 480px wide and **does**
overflow — but it sits inside `div.table-wrap` with `overflow-x: auto`
(`clientWidth` 320, `scrollWidth` 480). **The table scrolls; the page does not.**
So the criterion passes through *containment*, not breakpoints — there are still
no width media queries anywhere — which is exactly the fix `learn/32` describes.

**Gap: 11 → 7.** What remains is `G1`/`G3`–`G5` (real work, needs a cluster),
`G2` (owner-only credentials), and `G6`/`G7`, which **cannot be worked on at
all** — both close by observation after a host sleep.


### 2026-09-19 — `R-07` applied: ArgoCD live on EKS, and three claims put to the test

**Cluster up, ArgoCD installed, all six Applications `Synced`/`Healthy`.**
`61 added, 0 changed, 0 destroyed`; both nodes Ready on 1.36, which confirms the
`D-23` version fix survives a rebuild (standard support, $0.10/hr not $0.50).

**Order mattered and was followed deliberately.** ALB controller (vpcId read
fresh from `terraform output`, never committed) → `make deploy` → **commit and
push `manifests/`** → Secret → `make argocd`. The push step was the one worth
not skipping: `links-service`'s manifest pinned `ed8915a` while HEAD was
`1eabb8d`, and ECR had been emptied by the stack move, so **neither tag
existed**. Every manifest tag was checked against `describe-images` before
committing — all three MATCH.

**The application layer was proven healthy BEFORE ArgoCD was installed**, so a
red Application afterwards could only be ArgoCD's doing. DNS discovery returned
`{"status":"ok"}`, gateway served all five catalogue items from DynamoDB.

**A real defect in the values file, found by looking at the cluster rather than
the file.** `applicationSet.enabled: false` **does nothing** — that key does not
exist in chart 10.9.2, and **Helm accepts unknown values without complaint**, so
the controller ran while the file said it was off. `dex` and `notifications` do
have `enabled`, which is exactly why they worked and hid the problem. Settled
with `helm template` instead of a second guess: `enabled=false` renders
`replicas: 1`, `replicas=0` renders `replicas: 0`. **A Helm value you invented
looks identical to one you got right, because the failure mode is silence.**

**`enforce: restricted` survived ArgoCD taking over the namespace** — and that
was proven properly, by watching admission control reject a busybox pod with a
four-clause violation, not by reading the label back. This is the failure
`CreateNamespace=true` would have caused silently.

**`selfHeal` works, and my documentation of it was wrong.** A
`kubectl scale --replicas=0` on gateway was **already back to 2 before the next
command ran**. ArgoCD watches resources rather than only polling, so the
3-minute reconciliation interval is the worst case when an event is missed, not
the expected latency. "About three minutes" appeared in six places and is
corrected to seconds.

**Exactly one ALB**, and the app answers through it: `GET /` → 200, `/links` →
the catalogue.

**TORN DOWN AND CONFIRMED 2026-09-19.** `Destroy complete! Resources: 61
destroyed`, matching the 61 created. Verified against AWS **independently of the
script that had just run** — that script would otherwise be marking its own
homework: no EKS cluster, no NAT gateway, 0 running EC2, no load balancers, no
unattached EBS, no unassociated EIPs, no app-hub VPC, and `terraform state list`
in `infra/` returns 0. The EKS query was run raw so the field name is visible,
with a deliberately wrong field returning `null` as the control.

**The persistent stack survived, and that is the first real proof of the ECR
move.** DynamoDB `ACTIVE` with its 5 items, and all three ECR repositories still
holding 3 images each. **Before 2026-09-18 this teardown would have DELETED
those repositories.** The always-on Compose host can now pull after a nightly
destroy, which was the entire point of the move.

**`make down` step 0 got its first real exercise, and it did its job** — the ALB
was deprovisioned while the controller was still installed, confirmed gone from
AWS before `terraform destroy` began. It also exposed `D-29` (see Known
Defects): the first delete timed out after 5 minutes and was only survived
because of the `-` prefix, and the assertion would correctly have aborted the
teardown had the deadlock not been cleared by hand.

### 2026-09-19 — `R-07` written: ArgoCD, and a teardown step that stops it undoing the fix

**Guided build — ArgoCD is a genuinely new tool. Written, never applied.**

**Three decisions were the owner's**, and all three went to the recommendation:
a **read-only deploy key** (separate from Jenkins's write key on the same
repository), **automated sync with prune and selfHeal**, and **app-of-apps**.

**The repository is private, and that was verified rather than assumed.** The
first check disagreed with itself: `curl` returned 404 while `git ls-remote`
succeeded. The `ls-remote` was the liar — `GIT_TERMINAL_PROMPT=0` disables
*prompting*, not the Windows credential manager, so git had silently sent a
token. Re-run with `-c credential.helper=` it asks for a username, which
settles it. **Three of the eight repositories are private** (`infra`,
`links-service`, `manifests`); a claim earlier in the same session that compose
was "public, like the other seven" was wrong and is corrected here.

**The teardown constraint, stated before it was encoded** (§ 2). With
`selfHeal`, ArgoCD recreates the Ingress the moment `make down` step 1 deletes
it. The ALB controller provisions a **second load balancer**, teardown proceeds
around it, and it is orphaned — billing, with no cluster left to manage it.
That is `D-28` exactly, except something is actively undoing the fix. So `down`
gained a **step 0**: delete the root Application (cascading through the
resources-finalizer, while the ALB controller is still installed), **assert zero
Applications remain**, then uninstall the chart. Verified with `make -n down`
that step 0 expands and precedes step 1.

**The namespace gets its own Application, and that is the subtle part.** ArgoCD
offers `CreateNamespace=true`, which would create `app-hub` **with no labels** —
silently dropping `pod-security.kubernetes.io/enforce: restricted`, the thing
`R-04` verified on a live cluster by watching admission control reject a
busybox. Everything would still deploy and nothing would error; the cluster
would just be quietly less safe than the repository claims.

**`make validate` globbed one directory level and would have skipped these
files entirely.** `manifests/argocd/apps/` is two deep. Same shape as
`manifests/monitoring/` going unchecked until 2026-09-16: failure by omission,
which reports success. Fixed to two levels and **proven by deleting a namespace
from a child Application, watching validate fail, and restoring it** — not by
reading the diff.

**Said rather than tuned away:** monitoring + Jenkins + ArgoCD together will
probably not all schedule on 2× `t3.medium`. The resource requests are honest
numbers, not numbers shrunk until the arithmetic worked. Expect to run one or
two at a time.

**Nothing applied, nothing billing.** Chart version 10.9.2 was read from
`helm search repo argo/argo-cd --versions`, because a version that does not
exist fails at install time rather than at review.

### 2026-09-18 — The always-on host had no registry, and nobody would have found out until it broke

**Asked to create the Cloudflare Tunnel. Did not, because two things sit in front of it and one was invisible.**

**1. `compose/` pulled from a registry that gets deleted every night.** `ecr.tf`
lived in `infra/` — the ephemeral stack — so `terraform destroy` did not merely
empty the three repositories, it **deleted them**. Harmless for two months,
because EKS was the only consumer and `make deploy` rebuilt on the way back up.
The moment `P-11` added a host meant to stay up 24/7 pulling those same images,
it became the defect that would have ended the whole exercise: the host works
until the first teardown, then fails on `docker compose pull` with an error that
**reads exactly like the 12-hour ECR login expiry documented two paragraphs
above it in its own README**. A wrong answer that is already written down next
to the symptom is the expensive kind.

Found by checking rather than by reasoning — `aws ecr describe-repositories`
returned three unrelated repositories from other projects and none of app-hub's.

**Moved to `infra/persistent/`, at the cheapest moment it will ever be.** The
repositories did not exist and `terraform state list` in `infra/` returned
**zero** resources, so there was nothing to migrate. Any other day this needs
`terraform state mv` across two state files. `prevent_destroy` added on all
three, matching the DynamoDB table.

**The move reversed a Makefile rule, and the constraint was stated before it was
encoded** (§ 2). `make down` step 3 emptied ECR on every teardown, for exactly
one reason: `destroy` fails on a non-empty repository. Destroy can no longer
reach ECR, so that reason is gone — and running it nightly would now delete the
always-on host's images. It is `make ecr-prune` now, opt-in, with a typed
confirmation. The multi-pass buildkit loop (`learn/15`) was kept intact rather
than deleted, because the lesson in it outlives the target it lived in.

**`terraform validate` caught the cross-stack reference I had not thought about.**
`jenkins-irsa.tf` scoped its push permissions to `aws_ecr_repository.*.arn`, and
those resources were no longer in the stack. Fixed with `data
"aws_ecr_repository"` — **not** by constructing the ARN from account and region,
which was my first instinct and which `irsa.tf`'s existing comment on the same
problem already rejects in writing: *"silently wrong the day anything moves"*.
The project had solved this once; the job was to notice, not to invent.

**Consequence worth stating loudly: `infra/persistent/` must be applied before
the next `make up`.** The ephemeral stack now fails at plan time, by name, if the
repositories are absent. That is the right failure, and it is new.

**2. A named Cloudflare Tunnel needs a domain, which `manifests/ingress/README.md`
already records this project as not having.** There is no free stable hostname
for Tunnels — `*.pages.dev` is a Pages feature and has no Tunnel equivalent.
Quick Tunnels are free but their URL changes on every restart, which is useless
for the one thing this host exists to be: a bookmark. Left with the owner:
register a domain (~$10/yr, and it also unblocks the ACM certificate that
`manifests/ingress/README.md:200` has been waiting on), or Tailscale Funnel,
which is free and permanent but a new service in the stack.

**Nothing was applied and nothing is billing.** Both stacks validate; `make -n
down` was checked to prove it now executes no ECR command at all.

**Owner chose Tailscale Funnel, and `cloudflared` was replaced the same day.**
New service `tailscale` with a declarative `TS_SERVE_CONFIG` rather than a
`tailscale funnel` command run by hand — a manual step after every recreate is
the kind that works once and is forgotten the second time. Userspace networking,
so no `/dev/net/tun`, no `NET_ADMIN`, no privileged container: the serve proxy
runs inside tailscaled, so reaching gateway is an ordinary Compose-network call.
`docker compose config` exits 0 with **zero published ports** still, and the
serve JSON was parsed to confirm it proxies `http://gateway:8001` on 443.

**Three traps written into the artifacts rather than discovered later.**
`docker compose down -v` destroys the node identity volume, the node
re-registers, and because the old `app-hub` node still exists Tailscale appends
a suffix — the URL silently becomes `app-hub-1.…` and every bookmark breaks.
Funnel is **off by default per tailnet** and must be granted in the ACL policy;
without it the container authenticates, reports healthy, and is unreachable,
which reads as a networking fault. And node keys **expire after 180 days**,
which would take the dashboard dark half a year from now with no local cause.

**Flagged, not decided for them: Funnel is public and its hostname is not a
secret.** It serves a Let's Encrypt certificate, and issued certificates are
published to Certificate Transparency logs — public and searchable. That matters
here because **gateway does not filter on the `public` flag**; verified by
reading the code and scanning the table, which holds all five entries including
`Notes`, `Acharya Amit Puri` and a localhost URL. `"AllowFunnel": false` makes it
tailnet-only on the same hostname — one line, documented in three places. Built
as asked, with the trade-off stated.

`learn/34` written; the always-on work had no `learn/` file at all until now.

**`infra/persistent/` APPLIED 2026-09-18 ~23:57 IST — 3 added, 0 changed, 0
destroyed.** Owner approved in session. Planned first, and **the plan showing
`0 to destroy` is what made it safe to run**: the DynamoDB table and the budget
were never in scope, so `prevent_destroy` was not even exercised.

**Verified against AWS rather than against the apply output.**
`describe-repositories` shows all three with `IMMUTABLE` and scan-on-push, and
the table is still `ACTIVE` with its 5 items — the apply saying "0 destroyed"
and the table actually being intact are different claims.

**The cross-stack fix then proved itself.** `terraform plan` in the ephemeral
stack now reads all three `data.aws_ecr_repository` lookups (`Read complete
after 3s`) and reports `61 to add, 0 to change, 0 to destroy`. `make up` is
unblocked.

**Stated precisely, because the distinction matters here:** the POSITIVE case is
observed. The predicted plan-time failure *before* the repositories existed was
never actually run, so that half rests on documented Terraform behaviour rather
than on having watched it fail. Recorded as a prediction, not as a result.

**Nothing is billing.** Empty ECR repositories are free; storage begins only
once images are pushed, at ~$0.10/GB/month. No cluster, no NAT gateway.


### 2026-09-18 — `E-06` done, `R-05` made reproducible, and a teardown that orphaned an ALB

**Cluster up 12:47–14:00 IST. `Destroy complete! Resources: 62 destroyed`,
independent audit clean on all nine ephemeral categories, both persistent things
intact.** Roughly **$0.35**.

**`E-06` is done and verified.** One internet-facing ALB in front of `gateway`,
all three Services `ClusterIP` with `external=<none>`, exactly one load balancer
in the account, dashboard and API both served, catalogue coming back from
DynamoDB. The controller registered **pod IPs** — `10.0.1.112:8001`,
`10.0.2.188:8001` — confirming `target-type: ip` and why the Services could
stay `ClusterIP`. `learn/33`.

**Both IRSA role ARNs matched their manifests across a full rebuild**, which is
the hardcoded-ARN decision proven rather than assumed. The VPC id did not, and
was derived — exactly the split the comments predicted.

**`R-05` was marked done and was not reproducible.** The cluster came back with
no `monitoring` namespace at all: a Helm release lives IN the cluster, so
`terraform destroy` takes it, and `make deploy` stops at the three services. The
one part of `R-05` that is not a committed manifest had to be retyped from
`learn/30` every session. **A step that only exists in a walkthrough is a step
that gets skipped.** `make monitoring` now does it, chart pinned to `91.2.3`;
ran it and got **22 targets, all 22 UP**, with gateway 542 / links-service 455 /
aggregator 215 requests.

**The catalogue is seeded and persisted** — five projects written through
gateway into DynamoDB, confirmed by `scan`, and still there after the teardown.

---

**AND THEN `make down` ORPHANED THE ALB — see `D-28`.**

The failure is worth reading in full because the shape is familiar and the
trigger was not. `make down` step 1 had **never worked**:

```
kubectl delete ingress --all-namespaces --ignore-not-found
  -> error: resource(s) were provided, but no name was specified
```

`--all-namespaces` chooses which *namespaces*; `--all` chooses which *objects*.
The `-` prefix made `make` swallow the error. So the step whose entire purpose is
preventing an orphaned load balancer deleted nothing, and the teardown went on to
uninstall the controller anyway.

A watcher polling AWS caught the forbidden state directly (UTC):

```
08:02:43  lb=1 helm=2 ingress=1     healthy
08:07:33  lb=1 helm=1 ingress=1     <- controller GONE, ALB and Ingress still there
08:10:31  lb=0 helm=2 ingress=1     recovery: controller reinstalled, ALB deleted
08:11:24  lb=0 helm=1 ingress=0     controller uninstalled, correctly this time
```

**It was a deadlock as well as an orphan**, which made it worse than the warning
predicted: the Ingress finalizer `ingress.k8s.aws/resources` is removed only by
that controller, so the ALB kept billing *and* the Ingress could never finish
deleting. Recovery meant reinstalling the controller, deleting the Ingress
properly — the ALB went in **ten seconds** — and only then destroying.

**Why it hid for as long as the line has existed:** the very next command,
`kubectl delete svc --all-namespaces --field-selector spec.type=LoadBalancer`,
**is** valid, because the field selector supplies the object selection. Two
adjacent lines that look like the same idiom, one of which is wrong.

**Fixed twice over.** The flags are corrected, and `make down` now **asserts**
no ingresses remain before uninstalling the controller, aborting if any do.
That second part is the point:

> **Sequencing two steps is not the same as enforcing that the first one worked.**

The ordering was documented correctly in `learn/33`, in the runbook, and in the
Makefile's own comments. All three described a *sequence*; none verified it. It
is `§ 9`'s *"I cannot see it" vs "it is not there"* wearing a shell prompt:
**"I ran it" and "it worked" are different facts, and `make`'s `-` prefix is a
machine for conflating them.**

**Two process notes.** The first teardown attempt also failed with `error asking
for approval: EOF` — `make down` prompts unless `AUTO=1`, and a backgrounded
run has no stdin. And the cost figures quoted in chat mid-session (1h25m, 1h50m,
2h20m) were **wrong**, counted from the wrong origin; real spend was ~70 minutes.

**`D-24` stays open.** Closing it needed the cluster alive at 17:00 and the
teardown happened at 14:00, so the watchdog's live-cluster path is still
unproven. The budget guardrail — applied and verified this session — is
the durable half regardless.

### 2026-09-17 — A projects section, and a flag for who a link actually works for

**One file, three readers.** `site/projects.json` holds the owner's other
projects; the landing-page section, the demo catalogue and
`scripts/seed-projects.py` all read it. Four links written out in three places
is the duplication this project keeps paying for, so the section is *rendered*
rather than written into the HTML and there is no copy to drift.

**The interesting part was the data, not the plumbing.** Of the four URLs
supplied, **three are reachable only from the owner's own machine**:
`acharya-amit` at `localhost:4322`, `app-hub` at `localhost:8001`, and `Notes`
behind a personal Xiaomi account that returns `200` to anyone and shows a login
screen to everyone but them.

Those are **correct** entries for a private start page — pointing at your own
dev server is what a start page is *for* — and **wrong** on a public
portfolio page, where every visitor gets a connection error and reads it as
carelessness. So `projects.json` gained a `public` flag, and it decides *where*
an entry may appear rather than being a quality judgement:

```
public: true    portfolio page + demo catalogue + real catalogue
public: false   real catalogue only
```

**The demo case is the subtler one.** It is served from the same public Netlify
site, and the stub does not really probe anything — so a `localhost` card
would render **and report itself `up`** in the status panel. **A dead link
claiming to be healthy is worse than no link.**

**`seed-projects.py` deliberately does NOT filter on `public`**, and that is
commented, because the asymmetry reads as an oversight otherwise. It writes into
the owner's own catalogue, so filtering there would strip three of the four and
defeat the point.

**Verified all three readers at once** rather than assuming the flag threaded
through: public landing page — one card, `log-book`, with its source link;
public demo — one project and **no `localhost` URL anywhere** in the
catalogue; real catalogue via the seeder — all four created, `localhost`
included, `Procedo` reported pending. The seeder is idempotent **by name**, so a
rename creates a second record rather than updating the first.

**URLs were checked, not assumed.** `log-book` returns 200; `localhost:4322` was
up on this machine and `localhost:8001` was not — which is precisely the
point being made.

**Two process notes worth keeping.** Twice in this session a `curl` immediately
after starting a server reported a connection failure that was **only a race
with startup**, and once two `uvicorn` processes **died silently because their
ports were still held** by servers from earlier — so a test appeared to pass
while running against something else entirely. Both are the same shape as the
measurement artifacts already recorded in `CLAUDE.md § 9`.

**And this entry itself was late.** The code was committed and pushed before
`PROGRESS.md` was touched, which `§ 7` does not allow; it was caught only
when the owner next asked for the pending list. Recorded rather than quietly
backdated.

### 2026-09-16 — A public page on Netlify, and what it deliberately is not

**Netlify is a new cloud provider, so `CLAUDE.md § 4` says flag it rather
than quietly add it.** The flag, and the scoping that followed, are the whole
story here.

**app-hub cannot run on Netlify.** Its Functions are JavaScript, TypeScript and
Go; all three services are Python/FastAPI, and two of them reach DynamoDB with
an IRSA-derived identity that exists only inside the cluster. So this deploys
**purpose 3 from § 1 — the portfolio piece** — and nothing else.
Said before building, not after.

**Pointing the page at the live cluster was considered and rejected**, and the
reason is already a lesson in this project: EKS issues a **new API endpoint
hostname on every creation**, and the cluster is destroyed nightly by policy. A
permanent link to the real thing would be dead most of the time and aimed at a
stale host the rest of it.

**The demo runs the REAL `app.js`, unmodified.** Every call it makes goes
through one `api()` helper calling `fetch(path, …)`, so
`site/static/demo-api.js` replaces `window.fetch` before `app.js` loads and
serves an in-memory catalogue. Verified against the running page: `POST` →
`201` with an id, `DELETE` → `204`, `DELETE` of a missing id → `404`,
list 8 → 9 → 8. **Adding and deleting genuinely work.**

**Nothing persists, deliberately.** `localStorage` would have been two lines and
would have made the demo lie in a subtler way — a visitor returning a week
later would see their own edits and conclude a backend was answering.

**The polyrepo forced a copy, so the copy is now checked.** `gateway/` is a
separate repository that the umbrella **gitignores**, so a Netlify checkout of
`app-hub` contains no `gateway/` at all. `style.css` and `app.js` are therefore
vendored into `site/static/`, and `scripts/check-doc-drift.py` gained a
`COPIES` byte-comparison with `--fix` to re-copy. **A portfolio page claiming to
show the real dashboard while showing a three-month-old one is worse than a
screenshot that admits what it is.**

`site/demo.html` cannot be a byte copy — it adds the banner and the stub
script tag — so the **mechanical part** is checked instead: every id
`app.js` looks up via `getElementById` must exist in `demo.html`. **Both checks
were proven by breaking them on purpose** and watching them report `DRIFT` and
`FAIL` with exit 1.

**A real layout bug, found by measuring rather than looking.** The stack table
overflowed at a **293px viewport** — 328px of content — giving the whole
document a horizontal scrollbar and pushing every section below it off-centre.
**Invisible at desktop width, and the first thing anyone opening the link on a
phone would have seen.** Fixed with `overflow-x: auto` on a wrapper so the table
scrolls inside its own box, plus a `min-width` so the columns do not crush
instead.

> A page that is only ever checked at the width you built it at has only ever
> been checked at one width.

**The `learn/` number was predicted twice and moved twice in a single day** —
E-06's file was going to be 31, then 32, and is now neither. The references to it
no longer name a number at all. Numbers follow the order steps are *performed*,
so predicting one creates a cross-reference that rots on the next commit; this
is the same failure as every stale claim here, just faster.

**Deploying needs a login and is the owner's to do.** Claude wrote the site and
the config; authorising Netlify against a GitHub account is not something to
hand to an agent. Steps are in `site/README.md`.

### 2026-09-16 — A spend guardrail that runs in AWS, and a budget that already existed

**Written, not applied.** `terraform plan` on the persistent stack is clean —
**1 to add, 0 to change, 0 to destroy** — and `0 to destroy` is the line
that matters there: the DynamoDB table is untouched. **Applying needs the
owner's approval and has not happened.**

Written by Claude via the `§ 2` escape hatch at the owner's request, with
the explanation given first. **Concept skipped and flagged in the file:**
`aws_budgets_budget` is this project's first Terraform resource with **nested
repeated blocks** — `notification` appears twice in one resource, the same
shape as `ingress` rules in a security group.

**Checking first changed the design, and that is the whole story of this
entry.** The account already had a budget: *"My Monthly Cost Budget"*, $15/month,
four notifications, all emailing the owner, created in the console on
2025-02-01 and **not in Terraform**. Two of its forecast alerts were **in
`ALARM` at the moment of checking** — forecast $24.10 against a $15 limit.

So the question stopped being *"add a budget"* and became *"what does the
existing one not do"*. One line of AWS documentation answered it:

> *"Actual alerts are only sent out once per budget, **per budget period**, when
> a budget first reached the actual alert threshold."*

**A monthly budget has a monthly voice.** Once it fires in September it is
silent for the rest of September whatever gets left running — and this one
had already fired. A **daily** budget's period is one day, so it can speak
again tomorrow. That is why the new file is `DAILY` rather than a second
monthly budget, and it is not a detail: a second monthly budget would have felt
like progress and added nothing.

**$3/day is a threshold between two measured numbers**, not a round guess. A
real 6-hour session is ~$1.70 at the measured $0.28/hour; a cluster forgotten
for 12 hours or more is $3.40+. Legitimate work stays under, anything that
outlived the session goes over. Thresholds are `ACTUAL` at 100% and 200% —
*"this outlived your session"* and *"this ran all day"*.

**Two facts I had stated wrongly in chat, corrected against the source.**

- I said budget data refreshes *"about three times a day"*. The AWS docs say
  billing data is updated **"at least once per day"**. That matters, because it
  is the difference between a watchdog and a backstop — and this is a
  backstop.
- I said *"first two budgets free, then $0.02/day"*. Alert-only budgets are
  **free regardless of count**; the two-free limit applies to **action-enabled**
  budgets, at **$0.10/day** beyond two. Budget *actions* remain a deliberate
  non-goal — a budget that can shut resources down is a far larger blast
  radius than an email, and the failure being fixed is "nobody was told".

**No cost filter, deliberately, and for the project's usual reason.** A tag
filter sounds more precise, but a tag only reaches cost data once activated as
a **cost allocation tag** in the Billing console — a manual step outside
Terraform. A filter on an unactivated tag matches nothing, so the budget would
sit at $0.00 forever and never fire. **A guardrail silent because it is broken
looks exactly like one silent because all is well.**

**`var.budget_alert_email` has no default on purpose.** A default would be
either a personal address committed to a public repo or an empty string that
applies cleanly and notifies nobody. With none, `plan` fails until a value is
supplied — the right failure. `infra/.gitignore`'s `*.tfvars` line covers
the persistent stack; **verified with `git check-ignore -v`** rather than
assumed.

**The existing console-created budget was left alone**, and that is a recorded
gap rather than an oversight: it works, it is the account-wide monthly
backstop, and importing it into Terraform is a separate task with its own
approval.

### 2026-09-16 — Ran the app for review, and the review found what 149 tests had not

**The owner asked to look at the app before moving further on infra.** It was
brought up locally — three uvicorn processes in WSL, no AWS, no cluster, no
cost — seeded with six links including one deliberately broken, and driven
through the dashboard. **That hour found two defects and produced one requested
change.**

**The requested change: links open in a new tab** (`target="_blank"`). The
dashboard is a launcher — open Grafana, look, come back — and
navigating the tab away meant re-fetching `/links` and `/status` every return
trip and losing whatever was typed in the search box.

**`rel="noopener noreferrer"` was already there, which is the wrong way round.**
That is precisely the mitigation `target="_blank"` requires, and it had been
guarding nothing since the dashboard shipped. The new test pins the **pair**,
because either half alone is a bug: without `noopener` the opened page can reach
back through `window.opener` and navigate this one, and these URLs are chosen by
anything that can `POST` to the API.

**`D-26`: `checked_at` was a monotonic reading published as a timestamp.**
`/status` returned `"checked_at": 120573.88`. The full reasoning is in `D-26`
and the `learn/17` postscript; the short version is that monotonic time counts
from an arbitrary epoch, so the value is not comparable **across pods** and runs
**backwards** after a restart. Monotonic was right for the cache TTL and still
drives it. **The bug was publishing it, not using it.**

**Fifty aggregator tests asserted `age_seconds >= 0`. Not one had ever asserted
anything about `checked_at`** — which had been sitting in every response,
in plain view, since the service was written. It took reading the output.

**`D-27`: `importlib.reload` silently killed `/metrics`.** This is the one worth
reading twice. `test_ids_do_not_become_labels` — the test written during
`R-05` to prove the label-cardinality claim — **passed alone and failed in
the suite**, and had done for two days.

**The application was never affected**, and that was established before touching
anything, by querying the live server rather than trusting either test result:

```
handler="/links/{link_id}",method="GET",status="4xx"    <- route template
raw uuid in metrics: 0
```

**Root-causing it took four wrong turns, and the wrong turns are the lesson.**
The first hypothesis — the reload tests — was tested directly and
**disproved**: reload test plus metrics test passed. Bisecting every single test
against the metrics test found **no** individual trigger. Only a prefix bisect
found it, and the minimal reproducer was a *pair*: a test that makes requests,
followed by a reload.

**The mechanism, once measured instead of reasoned about:** reloading
re-registers collector names already in the process-wide `REGISTRY`; the
duplicate is swallowed rather than raised, and the reloaded app records nothing
while the old collectors keep serving their frozen values. So `/metrics` returns
a plausible body that stopped updating.

```
fresh import, 3 hits             http_requests_total{...} 3.0
DIRTY reload, +5 hits            http_requests_total{...} 3.0   <- dead
CLEAN reload (cleared), +5 hits  http_requests_total{...} 5.0   <- alive
```

**And then the first regression test written for it was decoration.** It
reloaded *before* making any request, and **passed against the bug**. Checking
that — rather than accepting the green tick — revealed that a reload
alone is harmless: the damage needs a labelled child series to already exist.

```
3 requests, THEN reload, then 5 more  ->  3.0   (the 5 vanish)
reload FIRST, then 5 requests         ->  5.0   (fine)
```

**Every one of the three fixes was verified by removing it and watching the
matching test fail**, then restoring. That is the only reason the regression
tests are known to guard anything.

**A flaky test is worse than no test.** This one went red for a reason that had
nothing to do with what it guards, which makes ignoring it the *rational*
response — and that is how a real failure would have been ignored too.

**152 tests**, up from 149: 42 links-service, 59 gateway, 51 aggregator. All
green. Nothing is billing.

### 2026-09-16 — `E-06` written: Ingress, a shared ALB, and a teardown order that is not reversible

**Written, not verified.** Everything below passes `make validate` offline and
**has never met a real API server.** The runbook is
`manifests/ingress/README.md`; the owner runs every command in it. There is no
`learn/` file yet on purpose — writing the record before the thing runs is how
documents start lying. **Its number is deliberately not named**: `learn/`
files are numbered in the order steps are performed, and this one's predicted
number moved twice in a single day as other work landed first.

**Built as a guided build**, the owner's choice when asked which `CLAUDE.md
§ 2` tier applied. Helm encounter #2, and their first `Ingress`.

**What it does.** `gateway` becomes the single public entry point behind one
ALB; `links-service` drops from `LoadBalancer` to `ClusterIP` and is no longer
reachable from outside the cluster at all. That is the shape `gateway` was built
for — until now it was a front door with the back door propped open beside
it.

**Cost is neutral today, and an earlier claim of mine in this file said
otherwise.** One NLB is replaced by one ALB at roughly the same $16–18 a
month. The saving arrives at services four and five, which become routing rules
instead of more load balancers. The overstatement is corrected in place above
rather than deleted.

**The new teardown constraint, stated before it was encoded** (`§ 2`):

> An Ingress-created ALB is **neither Terraform-tracked nor a
> `Service type: LoadBalancer`**, so `make down`'s existing sweep did not match
> it. And the order looks reversible and is not — delete the Ingress, wait
> for the ALB, **then** uninstall the controller. Uninstall first and nothing
> remains to act on the deletion: the Ingress vanishes from Kubernetes while the
> ALB survives in AWS, unreachable by `kubectl`, billing quietly.

`make down` step 1 now deletes Ingresses first and uninstalls the controller
last. It also **warns when load balancers are still present after five
minutes** — that loop used to fall through in silence, so a stuck ALB
surfaced as a confusing `terraform destroy` failure minutes later instead of a
reason at the point of failure.

**The validator caught the first mistake within a minute of the directory
existing**, which is the morning's `make validate` fix paying for itself
immediately: `manifests/ingress/` was picked up automatically by the new glob,
and `00-ingressclass.yaml` failed with *"no namespace declared, would land in
'default'"*.

**That was a FALSE POSITIVE, and worth more than a true one.** `IngressClass` is
cluster-scoped; the check had only ever special-cased `Namespace`, the sole
cluster-scoped kind in the repo until now. Fixed with an explicit
`CLUSTER_SCOPED` allowlist rather than by loosening the rule — an
unrecognised kind still gets flagged, because a namespaced object silently
landing in `default` is a real deployment bug while a new cluster-scoped kind
costs one line. **A false positive in a validator is worse than a missing
check: the fix people reach for is to stop running it.**

**Two decisions worth naming, both made for the owner and both listed in the
runbook's table so the second build can revisit them.**

`target-type: ip` rather than `instance` is the most consequential line in the
Ingress. `instance` mode targets nodes on a NodePort — which would have
forced *both* Services to `type: NodePort`, added a kube-proxy hop and lost the
client IP. `ip` mode targets pod IPs directly and is only possible because EKS
uses the AWS VPC CNI. **That annotation and the Service type are one decision,
not two.**

`vpcId` is **not** in the committed values file, and the reason is the whole
ephemeral/persistent split in one line. The role ARN *is* hardcoded, because the
role name is fixed and survives rebuilds. The VPC id is destroyed and recreated
nightly, so committing today's value produces something correct this evening and
silently wrong tomorrow. It is passed from `terraform output` at install time.
**A value the nightly teardown changes cannot live in a committed file.**

**HTTP only, no TLS — an accepted gap, not an oversight.** HTTPS needs an
ACM certificate, which needs a domain this project does not own. Written into
the Ingress and the runbook so the day something sensitive gets hosted here is a
decision rather than a discovery.

**Verified rather than assumed:** `helm uninstall --ignore-not-found` exists on
the WSL Helm (v3.21.3) before being put in a teardown path that runs unattended.

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
