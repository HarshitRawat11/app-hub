# CLAUDE.md — app-hub

Operating manual for Claude Code sessions in this workspace. Read this first, every session.

---

## 0. THE FINISH LINE — defined, then unfrozen

**Locked 2026-09-19 18:34 IST. `FINISH-LINE.md` v1.0. UNFROZEN the same day, at
the owner's word.**

### CURRENT STATE: THE GATE IS OFF

**Do not classify requests as DEFECT or EXTRA, and do not ask permission before
acting on something that is not a written criterion.** The owner lifted that
rule immediately after locking it, having seen what it actually required.

**`FINISH-LINE.md` remains valid and useful as a roadmap**, not as a gate:

- **§ 5 is the remaining work** — eleven gap items, `G1`–`G11`.
- **§ 4 records what was deliberately excluded**, so a future session does not
  re-propose it as though it were an oversight.
- **§ 0 pins the eight repository HEADs** at lock time.
- **v1 = the platform complete; new apps are new projects.** Concretely: all 43
  rows of `PROGRESS.md § Status board` read DONE, and `D-24` and `D-25` closed.

**`BACKLOG.md` is still the right place** for an idea that is real but not being
done now — one line, no ceremony. Append to it freely; just do not gate work on
it.

If the owner says **FREEZE**, restore the rule preserved below verbatim.

<details>
<summary>The post-freeze rule, preserved verbatim and currently INACTIVE</summary>

### POST-FREEZE OPERATING RULE — INACTIVE

This project has a locked finish line in FINISH-LINE.md. On every new request, before doing anything, classify it into exactly one of two buckets:

  DEFECT — the request describes a failure of a criterion that is WRITTEN in FINISH-LINE.md. This is in scope. Fix it.

  EXTRA — anything else. This includes every improvement, addition, redesign, optimization beyond the locked thresholds, new page, new feature, and any suggestion from the user, from Claude, or from the client. Route it as follows:
    (a) Name it explicitly: "This is EXTRA — it is not a criterion in FINISH-LINE.md."
    (b) Append one line to BACKLOG.md: date, one-sentence description, source (user / Claude / client). Nothing more — no estimates, no client formatting.
    (c) Ask whether to proceed. Do not implement until told to.

There is no third bucket. If a request seems to fall between the two, it is EXTRA — the document is the only source of truth for what is in scope.

Reopening scope is a deliberate act, not a drift. It requires the explicit word UNFREEZE from the user, after which a new version of FINISH-LINE.md (v1.1, v2.0) is negotiated through Phases C–E again. Until then, the line holds.

</details>

### What the document still tells you

- **The remaining in-scope work is `FINISH-LINE.md § 5` and nothing else.** Eleven
  gap items: `G1`–`G11`.
- **"The platform is complete" is the v1 test**, and it is mechanical rather than
  a judgement: all 43 rows of `PROGRESS.md § Status board` read DONE, and `D-24`
  and `D-25` are closed.
- **A new app is a new project**, not unfinished v1 scope. This is what reconciles
  the freeze with § 1's instruction to *"design for a hub that grows"*.
- **§ 2 still decides who writes what.** The freeze decides whether it gets
  written at all; § 2 decides whether the owner or Claude writes it.
- **Claude's own suggestions are EXTRA too.** The rule names Claude explicitly
  because this project's habit is to notice adjacent improvements mid-task — that
  habit is useful, and it is exactly what the backlog is for.

---

## 1. Main objective

**app-hub is the owner's permanent home for every app, tool, and project they build for their own daily use** — self-hosted, running on AWS EKS, provisioned by Terraform, deployed from Git-tracked Kubernetes manifests.

This is not a throwaway exercise. It is infrastructure the owner intends to *live in*: as they build more software for themselves, it lands here and runs alongside everything else. Design for a hub that grows, not for one service that ships.

The owner has confirmed it serves three purposes *at the same time*, and all three are real — none is a pretext:

1. **Learning vehicle** — and specifically, learning **the toolset the owner's organisation is migrating toward**: AWS EKS, Terraform, Prometheus/Grafana, Jenkins, ArgoCD, n8n. The owner is the **Principal SRE who has to own that stack at work**, which is why it is what it is. It is not incidental, and it is why "just use a simpler tool" is rarely the right suggestion here.
2. **Real, daily-use software** — the apps hosted here get used, by the owner, every day. They have to actually work and stay up.
3. **Portfolio piece** — the finished thing should read as competent, documented, and deployable by someone else.

Of the three, **learning dominates** — but it is targeted, not universal. When speed and understanding conflict **on the infra stack above**, understanding wins. On the application layer, speed wins, because the application was never the lesson. § 2 draws that line precisely; read it before deciding who writes what.

`links-service` is service #1: a CRUD API over link records (`name`, `url`, `category`, `icon`) — the catalogue of what lives where. `gateway` is next (it exists to prove service-to-service calls by Kubernetes DNS name), `aggregator` is future.

Because all three purposes are live, the quality bar is *"would this survive a code review by someone I want to impress?"* — not *"does it work on my machine?"*. Shortcuts that are fine for pure learning (hardcoded values, skipped tests, undocumented steps) fail purposes 2 and 3, so they are not fine here.

### The drift test

Before starting any task, ask:

> Does this move a service closer to **running on EKS, reproducibly, from code committed to git**?

If no — say so before doing the work. Suggesting a better-scoped alternative is welcome; silently expanding scope is not.

---

## 2. How we work — hand-build the learning, delegate the scaffolding

**This is the most important rule in this file. It governs *how* every other task gets done.**

### The owner's context, in their words

This is a learning project. The goal is not to ship app-hub — it is for the owner to learn **Terraform, EKS, Prometheus/Grafana, Jenkins, ArgoCD and n8n**, because their organisation is migrating to that stack and **they are the Principal SRE who has to own it.**

The project originally ran a stricter rule: the owner hand-wrote everything, application code included. **They have since judged that a misallocation, and the evidence supports them.** Real time went into debugging Python fundamentals — variable scoping, dict versus set syntax, list append — and none of it taught anything about infrastructure. Meanwhile every durable lesson in `learn/` came from an infra failure they had to debug themselves: a rebuilt EKS cluster issuing a new endpoint hostname, ECR refusing to be destroyed while it held images, WSL DNS breaking, an n8n `onError` setting behaving unexpectedly.

**The application was never the point. It exists so the cluster has something real to run.**

### The standing rule

> **Hand-build what the owner is trying to learn. Delegate what is merely scaffolding for it.**

Revised **2026-09-09**. This **replaces** the earlier "do not build ahead" rule, which applied to everything and is now wrong for the application layer. Do not reintroduce it.

### Write these yourself, completely, without asking

Treat them as patterns, not lessons. Do the work, then say what you did and why in a few lines.

- **Application code** — FastAPI services, routes, models, storage layers. Includes the upcoming `gateway` and `aggregator`.
- **Dockerfiles**
- **Kubernetes manifests that are a second instance of an object type the owner has already written** — see the line below
- **Tests**
- **Makefile targets, shell scripts, helper tooling**
- **Boilerplate refactors**, file moves, renames, formatting
- **Anything that is the second instance of a pattern the owner has already hand-written once**
- **The docs themselves** — this file, `PROGRESS.md`, `TIMELINE.md`, `README.md`, `CONTEXT-BRIEF.md`

**Keep the explanation short.** No Dockerfile walkthroughs. The owner does not need a tour of boilerplate they asked you to write.

### Do not write these — explain, let the owner write, then review

- **Terraform resources and modules they have not written before**
- **Kubernetes manifests introducing an object type they have not written before** — `Ingress`, `ServiceAccount` (IRSA), `ConfigMap`/`Secret`, `PersistentVolumeClaim`/`StatefulSet`/`StorageClass`, CRDs such as `ServiceMonitor`, `NetworkPolicy`, `HorizontalPodAutoscaler`, RBAC `Role`/`RoleBinding`
- **Prometheus alert rules and PromQL** — especially translations of Nagios checks the owner already knows from work, because that is where their existing expertise compounds
- **Grafana dashboard definitions**
- **Helm values files**
- **ArgoCD `Application` definitions**
- **Jenkins pipeline definitions**
- **n8n workflow construction in the GUI** (API read/inspect/verify stays yours)
- **Anything that broke in the *infra* layer and needs debugging**

For these: **explanation first, then they write, then you review.** Explain the *why* before the implementation — the reasoning behind a technical direction matters more here than reaching a working state fast. Say what the file needs to contain and why each part matters, then stop.

> **Never hand over a finished infra artifact and explain it afterwards.** That is backwards for everything on this list.

### The manifest line, and why it is drawn per object type

Kubernetes is item 2 on the learning list. Delegating *all* manifests would hand away every object type the owner has not yet met — including the IRSA `ServiceAccount` and the `Ingress`, two of the more instructive ones. So the line is **per object type, not per file**. `Deployment` and `Service` are learned; everything above is not.

### A new concept inside an otherwise-delegated file

`gateway`'s `deployment.yaml` is a second instance — except for the `env:` block injecting `LINKS_SERVICE_URL`, which is the one genuinely new Kubernetes idea in it.

Write the file, then **flag the new part in two or three lines.** No walkthrough. This stops concepts hiding inside repeat files.

### The Makefile is where infra knowledge goes to hide

`make down` encodes the teardown *ordering* — Ingresses first (only the ALB controller can clear their finalizer), then LoadBalancer Services so their ENIs release, then `terraform destroy`, then the orphan audit. That is `learn/15` and `D-28`, two of the most expensive lessons in the project.

**It used to empty ECR in the middle of that, and no longer does.** ECR moved to `infra/persistent/` on 2026-09-18 because the always-on host (`P-11`) pulls from it, so `destroy` cannot reach it and emptying it is no longer protective — only destructive. That is `make ecr-prune` now, opt-in. **A teardown step can outlive its reason**, which is exactly why this section says to state a constraint before encoding it.

The targets are yours to maintain. But **when a new ordering or teardown constraint appears, state the constraint before encoding it.** Otherwise the next hard-won rule disappears into a target nobody reads.

### Failures and errors — the most valuable moments here

When something breaks in the infra layer, **do not just fix it.**

- Say what the error actually **means**
- Give **one or two things to check**, and let the owner check them
- **If they are wrong about the cause, say so directly**
- When handed a broken infra thing, **ask whether they want it fixed or want to debug it. Default to debugging.**

**The 20-minute time-box.** Socratic debugging and cost discipline pull against each other — the cluster bills roughly **$0.20–0.30/hour**. So while the cluster is **up**, walk them toward it for 20 minutes, then say the box is up and give the answer. **Announce the switch; do not slide into it quietly.** With the cluster **down**, or for anything reproducible locally, there is no clock.

**Bugs in code you wrote are yours to fix.** Making the owner debug a defect in delegated application code is precisely the misallocation this section exists to remove. Fix it and say what it was.

### Verified versus written

For delegated work, **state plainly which it is.** "Builds and runs read-only, tested" and "written, never applied to a cluster" are different claims — `R-01`–`R-04` are still the second one.

An earlier session claimed a scoped IAM user existed when it had never been created, and the owner caught it. With more delegated output there is less surface for them to catch that, so the burden shifts to you to be explicit.

### Tests

You write them. **The owner reviews the coverage list, not the code** — which cases are covered and which are not. That preserves tests-as-specification without spending their time on `assert` syntax.

### The escape hatch

If the owner is stuck on something from the hand-write list and asks you to write it, **write it.** Being blocked teaches nothing. Say what you wrote, and flag which concept got skipped so it can be revisited.

### Guided build — the FIRST encounter with a tool

**Added 2026-09-14, at the owner's request, and it corrects a wrong assumption in the rule above.**

"Explain, then they write, then you review" assumes that after a good explanation the owner can produce the artifact. **That holds for their second Terraform resource. It does not hold for their first Helm chart.** A blank `values.yaml` and a thousand possible keys is not a learning exercise, it is a stall — and the owner said so directly about `R-05`:

> *"I don't know how to create these as this is my first time building this. So some hand holding has to be done from your side... when I build this at least 1 or 2 times then maybe in a different project we can start with just explanation."*

That is the right call, and it is now the rule.

**So there are three tiers, not two:**

| Situation | What Claude does |
|---|---|
| **First or second time with a genuinely new tool** | **Guided build.** Write the artifact completely, heavily commented so every decision is explained where it will be read. Give exact, runnable commands. **The owner runs every one of them**, reads the output, and debugs what breaks. |
| Third time onward with that tool | Explanation first, they write, Claude reviews — the § 2 default |
| Second instance of a pattern they have already written | Claude writes it outright |

**What makes a guided build still a learning exercise, and not just delegation:**

- **They run every command.** The understanding comes from watching it work, watching it fail, and fixing it — not from authoring a file from an empty buffer.
- **The comments live in the artifact**, not in chat, so the reasoning is there the next time they open it.
- **Say which decisions were made for them**, so the second build can revisit them deliberately.
- **Do not skip the failure.** If something will probably not schedule on a small cluster, say so and let them hit it, rather than pre-tuning it into invisibility.

**"New tool" means the tool, not the task.** Helm is new; a second Helm chart is not. IRSA was new; a second IRSA role is not. When in doubt, ask which it is rather than assuming.

### Push back

Say so when the owner is about to do something that will cost them later — in money, in rework, or in a lesson skipped. Flag trade-offs explicitly, **with the option you would pick and why.** They want the reasoning, not just a recommendation.

### Register

**Hinglish is preferred for conceptual explanation** — it is how the owner thinks about this material, and it makes the explaining part land better. Written deliverables (`learn/` files, READMEs, code comments, commit messages) stay in English.

### End every response with a summary — in English

**Changed 2026-09-13 at the owner's request.** This section previously required the
summary in Indian English mixing Hindi. **It is now plain English.** Do not
reintroduce the Hinglish summary.

**The summary itself is still required, not optional.** After the main answer, close
with a short recap under a `## Summary` heading.

Rules for that summary:

- **English.** Plain, direct, technical.
- **Five to seven pointers.** It is a recap, not a second version of the answer.
- **Lead with what actually matters**: what was done, what is pending, what the owner
  has to do next.
- **Never hide new information in the summary.** If it is important enough to say, it
  belongs in the main answer too. The summary only restates.
- **Anything cost-related or destructive gets repeated here**, even if already said
  above — a cluster left running, or a `destroy` that is pending, is exactly the thing
  worth saying twice.

Note the **Register** rule above is unchanged: Hinglish is still fine in the body for
*conceptual explanation*, where it helps a concept land. Only the closing summary
moved to English.

### The `learn/` folder — two tiers

**Revised 2026-09-09.** Every step gets a `learn/` file, but the depth depends on who wrote it. The folder stays a continuous record with no gaps where Claude worked — the owner should still be able to read it top to bottom and follow the whole project.

**Hand-built work gets the full file.** The seven-section structure below. Terraform, PromQL, Helm values, ArgoCD, Jenkins, n8n, a new Kubernetes object type, and any infra failure that was debugged.

**Delegated work gets a short note — three sections, under a page:**

```markdown
# NN — Step name  ·  *delegated, short note*

## What it does           (a paragraph — what changed and what it now does)
## Why it is this way     (the decisions that actually mattered; skip the ceremony)
## The one thing to know  (the gotcha, or the non-obvious bit that would bite a reader)
```

Rules for the short note:

- **Under a page.** If it is running long, it is turning into a walkthrough — cut it.
- **Write it for a reader who did not watch you work.** Not a diff summary; the reasoning.
- **Cover the surprise, not the syntax.** Nobody needs `COPY` explained. They need to know why the base image tag has to satisfy `requires-python`.
- **One file may cover several delegated steps** if they are one coherent piece of work — do not manufacture separate files per commit.

Files 01–09 predate this rule and cover application work. Leave them — they are accurate history, and `learn/01`, `02` and `09` still carry the FastAPI/Docker/uv concepts the delegated work builds on.

`learn/14` (testing) and `learn/21` (gateway) were written as *"guide, not a record — for the owner to write"*. That premise is now void, since both subjects are delegated. **The content is still correct; treat them as reference, not as pending assignments.**

Every step gets its own Markdown file in **`learn/`**.

- **Naming:** `NN-kebab-case-step-name.md`, numbered in the order the steps were performed — e.g. `01-fastapi-service-basics.md`, `02-containerising-with-docker.md`.
- **Index:** keep `learn/README.md` current — one line per file, in order, saying what it covers.
- **Audience:** someone technically competent but new to *this specific tool*. Plain language. Expand every acronym on first use. Assume no prior Kubernetes or Terraform knowledge.
- **Concrete over generic.** Use the real values from this project (`app-hub-eks`, `ap-south-1`, port `8000`), never `<your-cluster-name>` placeholders. The owner should recognise their own project in the explanation.

Each file follows this structure:

```markdown
# NN — Step name

## What we did          (one short paragraph — the change in plain terms)
## Why                  (the problem this solves; what would break without it)
## Key concepts         (the 2–5 ideas needed to understand this step)
## Walkthrough          (the actual code/commands, explained piece by piece)
## Gotchas              (what bit us, what would bite you next time)
## Verify it yourself   (commands the owner can run to prove it works)
## Going deeper         (what to read next, if curious)
```

**No step is done until its `learn/` file exists** — the full seven sections if the owner built it, the three-section short note if you did. See § 7.

---

## 3. Repository layout — read this before any git operation

**There are SEVEN independent git repositories here.** The root is an *umbrella* repo that tracks only the cross-cutting docs and gitignores the six component directories, so they stay fully independent (see `learn/10`). All seven have remotes and are pushed.

**Every new service directory must be added to the root `.gitignore` in the same change that creates it.** Forgetting does not fail loudly -- the umbrella just starts tracking a second copy of a repo that already has its own remote, and the two drift apart silently. Also add it to `REPOS` in `scripts/timeline.sh`, or its history vanishes from `TIMELINE.md`.

**That rule is about directories that are their own REPO, and `site/` is not one.** It is tracked by the umbrella deliberately, because **Cloudflare Pages deploys from this repository** -- **gitignoring it would publish an empty site.** Added 2026-09-17, because the rule above reads as "every new top-level directory" and following it literally here breaks the deploy. If a future directory is not a separate repo with its own remote, it does not belong in the root `.gitignore`.

| Directory        | Repo                                    | Tracks | Branch   |
|------------------|-----------------------------------------|--------|----------|
| `.` (root)       | `HarshitRawat11/app-hub`                 | `CLAUDE.md`, `README.md`, `PROGRESS.md`, `TIMELINE.md`, `CONTEXT-BRIEF.md`, `learn/`, `scripts/` | `master` |
| `infra/`         | `HarshitRawat11/app-hub-infra`           | Terraform — **two stacks**, see below | `master` |
| `links-service/` | `HarshitRawat11/app-hub-links-service`   | FastAPI service | `master` |
| `gateway/`       | `HarshitRawat11/app-hub-gateway`         | FastAPI service (entry point) + the dashboard | `master` |
| `aggregator/`    | `HarshitRawat11/app-hub-aggregator`      | FastAPI service (internal only) | `master` |
| `manifests/`     | `HarshitRawat11/app-hub-manifests`       | Kubernetes manifests | `master` |
| `n8n/`           | `HarshitRawat11/app-hub-n8n`             | Workflow JSON | `master` |

**A bare `git` command at the root now works — but it only sees the docs.** It will never show changes in `infra/`, `links-service/`, `gateway/`, `manifests/` or `n8n/`, because those are gitignored by the umbrella. Still use `-C <subdir>` for component work; the risk is no longer "git fails", it is "git succeeds and reports the wrong repo".

Consequences that bite:

- `git` commands **must** be run with `-C <subdir>` or from inside a subdir. A bare `git status` at the root fails, or worse, walks up to a parent repo.
- **The root docs are versioned** in the umbrella repo as of 2026-08-30 (`P-01`). They were previously untracked and unbacked-up; that is fixed.
- A change spanning service + manifests is **two commits in two repos**. Mention both in your summary; never claim "committed" when only one landed.
- **Git identity is set per-repo, never globally.** This is a work-managed laptop and personal commits must not carry the work identity. When creating a new repo, set `user.email` and `user.name` locally *before* the first commit — otherwise it fails with `fatal: empty ident name`.
- Branch name is `master` everywhere, deliberately not renamed. Nothing in the stack cares.

### Two Terraform stacks, one repo

**Decided 2026-09-09.** `app-hub-infra` holds two independent Terraform stacks:

| Directory | Lifecycle | Holds |
|---|---|---|
| `infra/` | **ephemeral** — destroyed every session | VPC, EKS, and the three IRSA roles (`C-05`, `E-06`, `R-06`) |
| `infra/persistent/` | **never destroyed** | the DynamoDB table (`C-04`), the budget guardrail, and **ECR** |

**ECR moved from the ephemeral stack to the persistent one on 2026-09-18**, and the reason generalises. The nightly destroy was deleting the repositories outright — fine while EKS was the only consumer, fatal once `compose/` (`P-11`) started pulling the same images to a host meant to stay up 24/7. **Ask what else reads a resource before putting it in the stack that dies every night.** The move also reversed a Makefile rule: `make down` no longer empties ECR, because destroy no longer needs it to and doing so would delete the always-on host's images. That is `make ecr-prune` now, opt-in.

A Terraform "stack" is not a language feature — it is just a directory with its own backend configuration and therefore **its own state file**. `infra/` uses state key `infra/terraform.tfstate`; the persistent stack uses a *different* key in the same bucket. **Sharing a key would make each stack plan to destroy the other's resources, silently.**

Consequences:

- `cd infra && terraform destroy` **does not recurse into subdirectories**, so `make down` cannot touch the persistent stack by construction rather than by care. `prevent_destroy` on the table — and now on all three ECR repositories — is the second line of defence.
- **The ephemeral stack now depends on the persistent one, and `plan` fails without it.** `infra/jenkins-irsa.tf` scopes its push permissions to the three repository ARNs, read with `data "aws_ecr_repository"` — the same cross-stack pattern `irsa.tf` already uses for the DynamoDB table, and for the same stated reason: constructing an ARN from account and region would be *"silently wrong the day anything moves"*. **Apply `infra/persistent/` before the next `make up`**, or it fails by name at plan time.
- The layout is deliberately asymmetric — the ephemeral stack sits at the repo root rather than in an `infra/ephemeral/` sibling. Moving it would touch the `Makefile`, `scripts/scheduled-destroy.sh`, the READMEs and several `learn/` files, to break a teardown path that is already proven. Not worth it for symmetry.
- One repo, so a change spanning both stacks is **one commit**, unlike the service/manifests split.

---

## 4. Constraints — hard rules

### Cost and blast radius

- **Never run `terraform apply`, `terraform destroy`, or any state-mutating Terraform command without explicit approval in the current session.** Prior approval does not carry over.
- `terraform plan`, `validate`, `fmt`, and `show` are fine unprompted.
- Running infra is not free. **Measured 2026-09-14 from the AWS Pricing API for `ap-south-1`**, run 24×7: EKS control plane $73 + 2× `t3.medium` $65 + NAT gateway $41 + NLB $17 + EBS $4 = **about $200/month**. A short session is about **$0.28/hour**; the 3.5-hour session on 2026-09-13 cost **$2.40 (~₹211)**.
- **The control plane price depends on the Kubernetes version, and this is not a footnote.** A version past standard support bills at **$0.50/hour instead of $0.10** — five times — which took that same session to $2.40 when it should have been $0.98 (`D-23`). Check before assuming the figure above still holds:
  ```bash
  aws eks describe-cluster-versions --region ap-south-1
  ```
  `infra/eks.tf` is on **1.36** (standard support to 2027-08-02) as of 2026-09-14.
- **Standing policy: the cluster is destroyed at the end of every session.** The NAT gateway is the main cost driver and bills whether or not anything runs on it. So "nothing is deployed" is the *normal* resting state of this project, not a sign something went wrong. Two n8n workflows back this up: `cost-watchdog` (emails at 5 PM and 9 PM if EKS is still up — wired and active, but **has never actually sent an email**; see `N-01b`) and `destroy-notifier` (posts destroy success/failure to an n8n webhook — **done and verified end to end** 2026-09-05). Both now use SMTP rather than Gmail OAuth, which removed a ~7-day token expiry that had silently killed both.
- Because of that policy, **`terraform apply` and `terraform destroy` are routine here, not exceptional** — but they still need explicit approval each session, because they cost money and the owner may not want the cluster up yet.
- **Never run `aws` commands that create, modify, or delete resources without approval.** Read-only calls (`describe-*`, `get-*`, `list-*`) are fine.

### Deploy targets

- **AWS EKS in `ap-south-1` is canonical.** Cluster `app-hub-eks`, Kubernetes **`1.36`** (raised from 1.31 on 2026-09-14, `D-23` — 1.31 was on extended support at 5× the control-plane rate).
- **minikube is a local sandbox only.** `kubectl` currently points at `minikube` — always check `kubectl config current-context` before applying anything, and say which context you used.
- Never assume the current kube context is the one the owner meant.

### Secrets

- Account ID `314146298861` and the ECR/S3 names derived from it are already committed here — that is the owner's accepted risk, not a licence to add more.
- Never commit AWS keys, kubeconfigs, or `*.tfvars` containing credentials. `infra/.gitignore` already excludes `*.tfvars` and `*.tfstate` — do not weaken it.

**The n8n API key** lives in `n8n/.env` (gitignored) and grants full read/write/execute over every workflow on the instance. Use it, never see it:

- Source it and reference the variable — the value must never reach the transcript:
  ```bash
  set -a && . ./n8n/.env && set +a && curl -sS -H "X-N8N-API-KEY: $N8N_API_KEY" "$N8N_BASE_URL/api/v1/workflows"
  ```
- **Never `cat`, `echo`, `grep`, or otherwise print `n8n/.env`** or any variable sourced from it — not even to "check it loaded". Test with `[ -n "$N8N_API_KEY" ] && echo set`.
- **Never use `curl -v`** against the n8n API. Verbose mode prints request headers, key included.
- **Never ask the owner to paste the key into chat.** If it is missing, tell them to put it in `n8n/.env` themselves.
- Never commit n8n credential exports. `n8n export:credentials` writes real secrets; `--decrypted` writes them in plain text. `n8n/.gitignore` blocks `credentials/` and `*credentials*.json`.
- Workflow JSON exports contain credential *names and IDs* only — safe to commit. But secrets typed directly into node parameters do get exported, so grep before committing (see `n8n/README.md`).

### Scope

- Do not introduce a new service, database, cloud provider, or framework without asking. The stack is deliberately small.
- Do not refactor code you were not asked to touch. Note it in `PROGRESS.md` instead. § 2 delegates *boilerplate refactors* to you — that is permission to do them when they are part of the task, not licence to wander through unrelated files.

---

## 5. Environment — the WSL / Windows split

This is the single biggest source of confusion in this workspace. **The toolchain is split across two operating systems.**

| Tool        | Where it lives                                      | Notes |
|-------------|-----------------------------------------------------|-------|
| `terraform` | **WSL Ubuntu only** (`/usr/bin/terraform`, v1.15.8) | NOT on the Windows PATH |
| `uv`        | **WSL Ubuntu only** (`~/.local/bin/uv`, v0.11.32)   | NOT on the Windows PATH |
| `python3`   | **WSL Ubuntu** (`/usr/bin/python3`)                 | Windows `python` is the Store stub — it does not work |
| `docker`    | Windows (Docker Desktop, v29.5.3) — **but callable from WSL** | WSL's native `/usr/bin/docker` fails (`Input/output error`) because the Linux daemon isn't running. **Use `docker.exe` instead**: WSL interop resolves it at `/Docker/host/bin/docker.exe` and it reaches the Docker Desktop daemon. Verified 2026-08-30: a full `docker.exe build` with a `/mnt/c/...` context works. This means one WSL shell can drive the entire pipeline. |
| `kubectl`   | **Both**, but they are two different tools in practice | Windows kubectl → `~/.kube/config` on Windows, context `minikube`. WSL kubectl → its own separate `~/.kube/config`, context `app-hub-eks`. Different files, different clusters. See below. |
| `helm`      | **Both, and at DIFFERENT MAJOR VERSIONS** — Windows `v4.2.3` (winget), WSL `v3.21.3` | **Use the WSL one.** Helm reads `~/.kube/config`, and only WSL's points at EKS (see the two-kubeconfig row above). Running the Windows binary against an EKS release would target minikube, or nothing. The major-version gap makes it worse than a wrong context: Helm 4 and Helm 3 differ in behaviour and in what they write to release metadata, so mixing them across one release is a way to corrupt it. Pick WSL and stay there. |
| `aws`       | **Both**, with different accounts on each side       | Windows `~/.aws/` holds the **work** profiles (`default`, `uzio-nonprod-audit`, `scripttest`) — unrelated to app-hub, and `default` there is intentionally left broken. WSL `~/.aws/` holds the **app-hub** credentials (`default` profile, `terraform-learning` user, account `314146298861`). Two entirely separate files — configuring one never touches the other. |
| `gh`        | **Not installed anywhere**                          | Use the GitHub web UI for PRs, or install it |

Claude Code runs on the **Windows** side. So:

- A bare `terraform ...` **will fail with "command not found"**. Run it as:

  ```bash
  wsl -e bash -lc "cd /mnt/c/Users/harshit.rawat/Documents/Projects/app-hub/infra && terraform plan"
  ```

- Same pattern for `uv` and `python3`.
- The vendored providers under `infra/.terraform/providers/` are `linux_amd64` binaries — further confirmation that Terraform only ever runs from WSL. Do not try to "fix" this by reinstalling on Windows without asking.

### The two kubeconfigs — read this before every `kubectl` command

Windows and WSL each have their own home directory, so each has its own `~/.kube/config`. They are not synced and never will be automatically.

- **Windows kubectl** has only ever talked to **minikube**. That is its whole job here.
- **WSL kubectl** already has a leftover context, `arn:aws:eks:ap-south-1:314146298861:cluster/app-hub-eks`, from the proven manual deploy in project history. That is stale once the cluster is destroyed, but it confirms EKS work has always happened from WSL — consistent with Terraform and the AWS credentials both living there.

**Consequence for `E-04` and beyond: run `aws eks update-kubeconfig` and every EKS-facing `kubectl` command from WSL, not Windows.** Reserve Windows `kubectl` for minikube. Running `kubectl config current-context` on the wrong side is a silent trap — both return a plausible-looking answer, just not the one you meant.

```bash
wsl -e bash -lc "aws eks update-kubeconfig --region ap-south-1 --name app-hub-eks && kubectl config current-context && kubectl apply -f manifests/links-service/"
```

**Everything can run from one WSL shell.** `terraform`, `aws`, and `kubectl` are WSL-native; Docker is reached with `docker.exe` (see the table above). So the deploy path no longer needs to hop between two shells — prefer a single WSL session for the whole build → push → deploy sequence, and reserve Windows for minikube.

### Stale kubeconfig is a certainty, not a risk

EKS issues a **new API endpoint hostname on every cluster creation**, so after each `destroy` + `apply` the kubeconfig is guaranteed stale. There is no way to pin the endpoint — the only fix is to refresh it.

`aws eks update-kubeconfig` is **idempotent and takes about a second**, so treat it as an unconditional precondition rather than a step to remember:

```bash
wsl -e bash -lc "aws eks update-kubeconfig --region ap-south-1 --name app-hub-eks && kubectl config current-context && kubectl get nodes"
```

Never run a bare `kubectl apply` against EKS without that prefix. Symptoms of skipping it — connection timeouts, TLS errors, `Unauthorized` — all look like network or permission faults, not staleness.

### WSL2 DNS

A fix is already applied and must not be reverted: `generateResolvConf = false` in `/etc/wsl.conf`, with `nameserver 8.8.8.8` set manually in `/etc/resolv.conf`. WSL2 DNS breaks by default. If name resolution fails inside WSL, check that these are still in place before debugging anything else.

### AWS credentials

**Resolved 2026-08-30.** App-hub credentials are configured in **WSL's `~/.aws/`** (`default` profile, `terraform-learning` user, account `314146298861`, region `ap-south-1`) — a completely separate file from the Windows-side `~/.aws/`, which still holds the unrelated work profiles (`default`, `uzio-nonprod-audit`, `scripttest`) untouched and still intentionally broken.

- Both sides use the profile name `default`, but they are **different files resolving to different accounts.** There is no conflict, because Windows and WSL never share a home directory.
- Run all `aws`/`terraform` commands for this project from **WSL**. Running `aws sts get-caller-identity` on Windows will still fail — that's the work side, and it's supposed to.
- The `n8n-readonly` IAM user (scoped to `eks:DescribeCluster`, used by the cost watchdog) is not configured here — it's used from within n8n's own container, not from a shell.

---

## 6. Read order for a new session

Work through these in order. Stop as soon as you have what the task needs — don't read the whole list reflexively.

1. **`CLAUDE.md`** (this file) — objective, constraints, environment. Always. **§ 2 decides who writes the thing you are about to write** — check it before starting, not after.
2. **`PROGRESS.md`** — status table, blockers, known defects, next steps. Always. This is where you find out what is half-finished, and each open task names which side of the § 2 split it falls on.
3. **`README.md`** — directory layout, quick start commands, governance. Read when you need to *run* something or are unsure of a workflow.
4. **`learn/README.md`** — the index of what has already been taught. Skim it before explaining anything: if a concept already has a file, build on it and link to it rather than re-explaining from scratch. If the current task extends an earlier step, read that step's file too.
5. Then, task-dependent only:
   - `links-service` work → `links-service/app/main.py`, `links-service/app/models.py`, `links-service/pyproject.toml`, `links-service/Dockerfile`
   - `gateway` work → `gateway/app/main.py`, `gateway/pyproject.toml`, and `learn/21` for the design rationale
   - Infra work → `infra/providers.tf`, `infra/vpc.tf`, `infra/eks.tf`, `infra/outputs.tf`, `infra/variables.tf` (**ECR is now `infra/persistent/ecr.tf`**). **Persistent-data work → `infra/persistent/` instead** — a separate stack with its own state file (§ 3).
   - Deploy work → `manifests/links-service/deployment.yaml`, `manifests/links-service/service.yaml`
   - n8n work → `n8n/README.md` first (it carries the security rules), then `n8n/workflows/*.json`
6. **Never read `infra/.terraform/`.** It is ~800 MB of vendored provider binaries and upstream module source. It is gitignored, it is not our code, and reading it wastes the entire context window.

---

## 7. Before you finish a task

- **Write the `learn/` file** and add it to `learn/README.md`. Per § 2, no task is done without it — the **full seven sections** if the owner built it, the **three-section short note** if you did. If the step was too small to warrant its own file, append to the most relevant existing one instead.
- **State which side of the § 2 split the work fell on**, and for delegated work, whether it was *verified* or merely *written*.
- Update **`PROGRESS.md`**: move the row's status, clear or restate the blocker, write the real next step, and add a timestamped line to the progress log.
- **Regenerate the timeline**: `./scripts/timeline.sh`. It rebuilds `TIMELINE.md` from git across all seven repos, so the project's chronology is derived rather than typed.

### Timestamps — do not type them from memory

**This has already gone wrong once.** Hand-written dates in `PROGRESS.md` drifted a full day out (36 rows said `2026-08-29` for work git shows on `2026-08-30`). The rule that follows:

- **Never write a date from memory.** Get it from `git log`, or from `date`. If you are recording when something happened, the commit is the evidence.
- **Always state the timezone.** This machine has two clocks — **Windows runs IST (+05:30), WSL runs UTC**. A bare `14:53` is ambiguous and will be misread later. Write `2026-08-30 14:53 IST`.
- **Format:** `YYYY-MM-DD HH:MM IST` in prose and table cells; session log headers use `### YYYY-MM-DD · HH:MM–HH:MM IST — title`.
- **Prefix an estimate with `~`** when there is no commit to anchor to, rather than inventing precision.
- Look up a commit's real time with:

  ```bash
  git log --pretty='%h %s' --date=format:'%Y-%m-%d %H:%M' -1 <sha>
  ```

`TIMELINE.md` is generated and authoritative; `PROGRESS.md` carries the narrative. When they disagree, the timeline is right.
- State plainly which repos you committed to, and which you did not.
- If you found a defect you did not fix, add it to the Known Defects table rather than leaving it in chat scrollback.
- Report failures as failures. A `terraform plan` that errors is not "mostly working".

---

## 8. Known defects at a glance

The authoritative list — with severity and next steps — lives in **`PROGRESS.md` § Known Defects**. The one you are most likely to trip over:

> `links-service/app/main.py:29` stores the incoming `LinkCreate` instead of the constructed `Link`, so every record read back from `GET /links` and `GET /links/{id}` is missing its `id`. `POST` returns the correct shape, which is why it looks fine at first glance.

---

## 9. Hard-won lessons — do not rediscover these

Each of these cost real time to find. They are here so no future session pays for them twice.

- **Windows and WSL each have their own `~/.kube/config` and `~/.aws/` — they are not the same file.** Configuring AWS credentials in WSL does nothing for Windows, and vice versa. `aws eks update-kubeconfig` writes to whichever side ran it. Run all EKS-facing `aws` and `kubectl` commands from WSL — that's where the app-hub credentials and Terraform both live — and reserve Windows `kubectl` for minikube. See § 5.

- **Re-run `aws eks update-kubeconfig --region ap-south-1 --name app-hub-eks` after every `destroy` + `apply` cycle.** EKS generates a *new endpoint hostname* each time, even with an identical cluster name. A stale kubeconfig is the single biggest source of confusing `kubectl` failures in this project — the errors look like network or auth problems, not staleness. Given the destroy-every-session policy (§ 4), this applies almost every time the cluster comes back.

- **ECR needs `force_delete = true` — and it is not always sufficient.** **MOVED 2026-09-18 — the repositories now live in `infra/persistent/ecr.tf`, so `terraform destroy` never reaches them and this lesson is now about `make ecr-prune`, not teardown.** Keep `force_delete` anyway; without it a *deliberate* destroy fails once the repository holds images. But it has been **observed not to take effect**, and destroy still failed. Working fallback: delete the images first, then destroy.

  ```bash
  aws ecr batch-delete-image --repository-name app-hub/links-service --region ap-south-1 --image-ids "$(aws ecr list-images --repository-name app-hub/links-service --region ap-south-1 --filter tagStatus=ANY --query 'imageIds[*]' --output json)"
  ```

  **`--filter tagStatus=ANY` is load-bearing.** `list-images` defaults to tagged only, and buildkit pushes untagged attestation manifests with every image — so the obvious version of this command silently leaves them behind (verified 2026-08-31). Confirm with `aws ecr describe-images --repository-name app-hub/links-service --region ap-south-1 --query "length(imageDetails)"` returning `0`.

  Deleting images by hand is safe — Terraform tracks the *repository*, never the images inside it.

  **One pass is not enough, and this bit on 2026-09-10.** buildkit pushes a manifest **index** plus the child manifests it points at (the image, and an attestation). `list-images` shows the index; **deleting it makes the children visible as newly-untagged digests that were not in the first listing.** Observed live: `app-hub/gateway` needed two passes — pass 1 deleted 1, pass 2 deleted 2. A single `batch-delete-image` leaves the repository non-empty and `destroy` then fails.

  So **loop until `describe-images` actually returns `0`**, rather than deleting once and assuming. `make ecr-prune` does this, and aborts rather than proceeding if the repository is still non-empty after five passes. The command above is the single-pass version — run it repeatedly, or use `make ecr-prune`. **It is no longer part of `make down`.**

  **This applies to every repository, and `make ecr-prune` walks `ECR_REPOS` in the Makefile rather than a single hardcoded name.** Add each new repository to that variable when you create it — a missing entry still does not fail loudly, but the symptom changed with the move: it used to break a later `destroy`, and now it simply means that repository is never pruned and its storage grows unwatched. The Makefile also reports *"does not exist yet"* separately from *"already empty"*, because swallowing `RepositoryNotFoundException` would make a typo'd repository name look like a clean one.

- **Kubernetes creates AWS resources Terraform does not know about, and they block or silently outlive `destroy`.** This is the most expensive trap in the project because it fails *quietly*.
  - **EBS volumes** behind PVCs are created by the EBS CSI driver, not Terraform. `terraform destroy` leaves them, and they keep billing.
  - **ENIs and load balancers** from `Service type: LoadBalancer` or an Ingress can block VPC deletion outright.

  **Before every destroy, once any stateful workload exists** (Prometheus, Jenkins, n8n-on-EKS, or the `C-04` datastore):

  ```bash
  helm uninstall <release> ; kubectl delete pvc --all --all-namespaces ; kubectl delete svc --all-namespaces --field-selector spec.type=LoadBalancer
  ```

  Then audit for orphans — anything listed here is costing money for nothing:

  ```bash
  aws ec2 describe-volumes --filters Name=status,Values=available --region ap-south-1 --query "Volumes[*].[VolumeId,Size,CreateTime]" --output table
  ```

- **WSL2 `/etc/resolv.conf` breaks after `wsl --shutdown`.** With `generateResolvConf = false`, the symlink target lives under `/run/`, which is wiped on restart. Fix by replacing the symlink with a real file:

  ```bash
  sudo rm -f /etc/resolv.conf && echo "nameserver 8.8.8.8" | sudo tee /etc/resolv.conf
  ```

  Corporate DNS has also interfered with AWS endpoint resolution here. Note `wsl --shutdown` is a **Windows** command — run it from PowerShell, not inside the WSL shell.

- **A Windows Scheduled Task will not run on battery power by default, and it fails SILENTLY.** `New-ScheduledTaskSettingsSet` defaults to `DisallowStartIfOnBatteries = True` and `StopIfGoingOnBatteries = True`. Triggered on battery, the task goes to state **`Queued`** and waits — not `Running`, not `Failed`. No completion event, no output, no error anywhere.

  Found 2026-09-13 on the first real test of the nightly teardown: launched 14:13, still `Queued` at 14:19, laptop unplugged. **23:30 is exactly when a laptop is likely to be on battery**, so the defaults would skip the teardown on precisely the nights it was needed, the cluster would bill until morning, and nothing would say so. `StopIfGoingOnBatteries` is worse — unplugging mid-run aborts a `terraform destroy` partway through.

  `scripts/register-scheduled-destroy.ps1` now passes `-AllowStartIfOnBatteries -DontStopIfGoingOnBatteries` and **asserts afterwards that they took**, refusing to report success otherwise. **`State: Queued` is the tell** — it means "waiting for a condition", and is not the same as `Running`.

- **An unattended job needs a log file, not just a notification.** `scheduled-destroy.sh` reported only by POSTing to n8n, and the Task Scheduler action captured stdout nowhere. So a run that failed *before* the POST left no evidence at all — no log, no n8n execution, nothing. It now `tee`s everything to `logs/scheduled-destroy-<timestamp>.log` (gitignored) and prints its WSL user, `$HOME` and `aws sts get-caller-identity` at the top, because those three lines answer most of what goes wrong with a scheduled WSL job.

- **"I cannot see it" and "it is not there" are different facts.** Any check that renders them identically will eventually report the wrong one with total confidence — and this cost real time three separate ways in one session on 2026-09-13:

  - `aws dynamodb list-tables --query 'Tables'` returned `None`. The field is `TableNames`. **A wrong `--query` returns `None` rather than erroring**, so a wrong question reads exactly like a clean answer.
  - `ps -eo cmd | grep -c "[u]vicorn"` reported 2 lingering servers. There were none — **the checking shell's own command line contained the word**, so it counted itself. Same root cause as the `pkill -f` that killed its own shell twice.
  - `Get-ScheduledTask -TaskName ...` unelevated reported the nightly teardown task as missing. **It was registered and working.** Unelevated, that cmdlet returns nothing for a task that exists. `schtasks /query` is honest about the same state: it says `ERROR: Access is denied`.

  In the same breath, `Test-Path` on a protected path threw `UnauthorizedAccessException` and — being a non-terminating error — **fell through to the `else` branch and printed "no file"**.

  **The technique that finally settled it, and the transferable part: run the same query against a name you KNOW is absent.** If the real name and the fake name produce the *same* answer, your query cannot tell the difference and its result is UNKNOWN — not zero. If they differ, the difference is the evidence:

  ```
  schtasks /query /TN "zzz-definitely-not-a-real-task"  ->  ERROR: The system cannot find the file specified.
  schtasks /query /TN "app-hub nightly teardown"        ->  ERROR: Access is denied.
  ```

  Absent says *cannot find*; existing-but-unreadable says *denied*. Meanwhile `Get-ScheduledTask` returned "not found" for **both**, which is exactly why it produced a confident wrong answer — it is the wrong tool for that question.

  **So: prefer a tool that distinguishes "denied" from "absent", and control your negatives before believing them.** This is the same disease as every stale claim in the docs here; it just wears a shell prompt instead of a Markdown file.

- **A command written for bash and handed over on this machine will be run in PowerShell, and it will fail at the parser.** This has now cost the owner time **twice**, so it is a rule rather than an anecdote.

  The first time was the ALB controller install: `\"` does not escape a quote in PowerShell, it *ends the string*, which exposed the inner `&&` — and **PowerShell 5.1 has no `&&`** — producing *"The token '&&' is not a valid statement separator in this version."* Two failed attempts.

  The second was a verification command: **`diff <(curl -s ...) file`**. Process substitution `<(...)` is a bash and zsh feature; **PowerShell has no equivalent syntax at all**, so it does not run at all rather than running wrongly.

  **So: when handing the owner a command, label the shell, and prefer one that works in PowerShell** — or wrap the bash in `wsl -e bash -lc "..."`, which is the only reliable way to get bash semantics from here. `npx`, `git`, `kubectl`, `curl.exe` and `docker.exe` are shell-agnostic and safe as written; anything using `&&`, `$(...)`, `<(...)`, `|` into a shell builtin, or backslash-escaped quotes is not.

- **n8n nodes can replay pinned data instead of executing.** Right-click a node; if the menu offers "Unpin", its output is frozen and the node is not really running. Also: the green check on the canvas means "did not halt the workflow", **not** "received a 200".

- **EKS needs `enable_cluster_creator_admin_permissions = true`.** Without it, the IAM user that *created* the cluster has no `kubectl` access to it. Already set in `eks.tf`.

- **n8n HTTP Request node: set "On Error" to "Stop Workflow", not "Continue (using error output)".** With "Continue", the downstream Gmail node fired on every execution regardless of cluster state, so the cost-watchdog emailed whether or not anything was running — a monitor that always alerts is a monitor you stop reading.

- **`0.0.0.0` is a bind address, not a browsable destination.** `--host 0.0.0.0` means "listen on all interfaces". Test the container at `localhost:8000`.

- **Measure durations with a monotonic clock; report instants with the wall clock.** `time.monotonic()` counts from an arbitrary epoch, so it is right for a cache TTL (it cannot jump when NTP corrects the system time) and wrong in a response body. `aggregator` published it as `checked_at` for weeks: meaningless to a client, **not comparable between replicas**, and it runs **backwards** after a restart. Fifty tests asserted `age_seconds >= 0` and none had ever looked at `checked_at`. See `learn/17`.

- **A value the nightly teardown changes cannot live in a committed file.** The IRSA role ARN is hardcoded safely because the role NAME is fixed; the VPC id is not, because `make down` destroys the VPC and `make up` makes a new one. Committing today's id gives something correct this evening and silently wrong tomorrow. If it survives teardown, hardcode it. If it does not, derive it -- `terraform output` at the point of use.

- **A FALSE POSITIVE in a validator is worse than a missing check**, because the fix people reach for is to stop running it. When `manifests/ingress/` was added, the manifest checker failed `IngressClass` for having no namespace -- it is cluster-scoped, and the check had only ever special-cased `Namespace`. Fixed with an explicit allowlist rather than by loosening the rule, so an *unrecognised* kind is still flagged: a namespaced object landing silently in `default` is a real bug, while a new cluster-scoped kind costs one line.

- **A flaky test is worse than no test.** `test_ids_do_not_become_labels` passed alone and failed in the suite for two days, because `importlib.reload` re-registers Prometheus collectors into a process-wide registry, the duplicate is swallowed, and **the reloaded app then records nothing while `/metrics` keeps serving frozen values**. It went red for a reason unrelated to what it guards, which makes ignoring it the *rational* response -- and that is how a real failure gets ignored too. Root-causing it took four wrong hypotheses; only measuring settled it.

- **Two process traps met repeatedly on 2026-09-16/17, both the same family as the measurement artifacts above.** A `curl` fired immediately after starting a server reports a connection failure that is only a **race with startup** -- wait, then re-check, before believing it. And a `uvicorn` started on a port something else already holds **dies silently**, so a test can appear to pass while running against a completely different process. Check what is actually listening (`ss -ltnp`) rather than trusting that your own process is the one answering.
