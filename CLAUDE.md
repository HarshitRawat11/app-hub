# CLAUDE.md — app-hub

Operating manual for Claude Code sessions in this workspace. Read this first, every session.

---

## 1. Main objective

**app-hub is the owner's permanent home for every app, tool, and project they build for their own daily use** — self-hosted, running on AWS EKS, provisioned by Terraform, deployed from Git-tracked Kubernetes manifests.

This is not a throwaway exercise. It is infrastructure the owner intends to *live in*: as they build more software for themselves, it lands here and runs alongside everything else. Design for a hub that grows, not for one service that ships.

The owner has confirmed it serves three purposes *at the same time*, and all three are real — none is a pretext:

1. **Learning vehicle** — and specifically, learning **the toolset the owner's organisation is migrating toward**: AWS EKS, Terraform, Grafana/Prometheus. That is why the stack is what it is. It is not incidental, and it is why "just use a simpler tool" is rarely the right suggestion here.
2. **Real, daily-use software** — the apps hosted here get used, by the owner, every day. They have to actually work and stay up.
3. **Portfolio piece** — the finished thing should read as competent, documented, and deployable by someone else.

Of the three, **learning dominates**. When speed and understanding conflict, understanding wins — see § 2.

`links-service` is service #1: a CRUD API over link records (`name`, `url`, `category`, `icon`) — the catalogue of what lives where. `gateway` is next (it exists to prove service-to-service calls by Kubernetes DNS name), `aggregator` is future.

Because all three purposes are live, the quality bar is *"would this survive a code review by someone I want to impress?"* — not *"does it work on my machine?"*. Shortcuts that are fine for pure learning (hardcoded values, skipped tests, undocumented steps) fail purposes 2 and 3, so they are not fine here.

### The drift test

Before starting any task, ask:

> Does this move a service closer to **running on EKS, reproducibly, from code committed to git**?

If no — say so before doing the work. Suggesting a better-scoped alternative is welcome; silently expanding scope is not.

---

## 2. How we work — teach, don't just ship

**This is the most important rule in this file. It governs *how* every other task gets done.**

### The owner's context, in their words

This project started as a deliberate, manual learning exercise — every step worked through one at a time with Claude chat, so the owner actually understood what they were building. Time pressure forced the move to Claude Code, because the hub is meant for daily use and it has to get finished.

**The move to Claude Code was for speed, not for outsourcing the understanding.** The owner has been explicit: they do not want Claude Code to blindly complete this project for them. They want to learn everything that happens in it.

### The standing rule

> **Never just do the work. Do the work *and* teach it.**
> The owner should finish every step able to redo it themselves, without you.

In practice:

- **Explain before you act** on anything non-trivial — what you are about to do, why this approach, what the alternatives were and why they lost.
- **Explain while you act.** When you write a config value, say what it controls and what happens if it changes. When you pick a flag, say why that flag.
- **Never hand over a black box.** If the owner could not explain your change to someone else afterwards, you have not finished the task.
- **Separate the load-bearing from the boilerplate.** Say which two lines actually matter and which fifteen are ceremony — that distinction is most of the learning.
- **Name the mental model, not just the syntax.** "A Service is a stable virtual IP that load-balances across whichever pods currently match its selector" beats "add a service.yaml".
- **Surface the failure modes.** What breaks this, what the error message will look like, how to tell it apart from a similar-looking failure.
- If the owner says "just do it" for a specific step, respect that — but still write the `learn/` file so the explanation is there when they want it.

Teaching is not a separate deliverable bolted on at the end. It is part of doing the task.

### Do not build ahead

**The single easiest way to ruin this project is to hand over a finished artifact.**

The first implementation of any *new concept* is done by the owner, by hand, deliberately — even when that is slower. A working thing that skipped the wrestling has negative value here: it looks like progress and removes the reason the project exists.

So before writing code for something new, stop and ask whether the owner wants to write it. The honest split:

| Genuinely helpful | Actively harmful |
|---|---|
| Reviewing code they already wrote | Scaffolding a concept they have not met yet |
| Rubber-ducking a specific error | "I went ahead and set it up for you" |
| Scaffolding *repetitive* work, **after** the concept is learned once by hand | Filling in the interesting part and leaving the boilerplate |
| Explaining a mechanism before they implement it | Optimising away the slow part |

Slow is a *choice* here, not a constraint to route around. Expect frequent "why" questions and pushback when things move too fast — that is the project working as intended, not friction to reduce.

### Register

**Hinglish is preferred for conceptual explanation** — it is how the owner thinks about this material, and it makes the explaining part land better. Written deliverables (`learn/` files, READMEs, code comments, commit messages) stay in English.

### The `learn/` folder

Every step we complete gets its own Markdown file in **`learn/`**.

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

**A step is not done until its `learn/` file exists.** See § 7.

---

## 3. Repository layout — read this before any git operation

**The `app-hub/` root directory is NOT a git repository.** It is a plain folder holding three *independent* git repos, each with its own GitHub remote:

| Directory        | Remote                                  | Branch   |
|------------------|-----------------------------------------|----------|
| `infra/`         | `HarshitRawat11/app-hub-infra`           | `master` |
| `links-service/` | `HarshitRawat11/app-hub-links-service`   | `master` |
| `manifests/`     | `HarshitRawat11/app-hub-manifests`       | `master` |
| `n8n/`           | `HarshitRawat11/app-hub-n8n` *(remote not created yet)* | `master` |

Consequences that bite:

- `git` commands **must** be run with `-C <subdir>` or from inside a subdir. A bare `git status` at the root fails, or worse, walks up to a parent repo.
- **`CLAUDE.md`, `README.md`, and `PROGRESS.md` at the root are currently untracked by any repo.** They are not backed up and not versioned. See PROGRESS.md task `P-01`.
- A change spanning service + manifests is **two commits in two repos**. Mention both in your summary; never claim "committed" when only one landed.
- **Git identity is set per-repo, never globally.** This is a work-managed laptop and personal commits must not carry the work identity. When creating a new repo, set `user.email` and `user.name` locally *before* the first commit — otherwise it fails with `fatal: empty ident name`.
- Branch name is `master` everywhere, deliberately not renamed. Nothing in the stack cares.

---

## 4. Constraints — hard rules

### Cost and blast radius

- **Never run `terraform apply`, `terraform destroy`, or any state-mutating Terraform command without explicit approval in the current session.** Prior approval does not carry over.
- `terraform plan`, `validate`, `fmt`, and `show` are fine unprompted.
- Running infra is not free. EKS control plane + 2× `t3.medium` + a NAT gateway is roughly **$150–200/month if left up 24×7** in `ap-south-1`. Treat that as an order-of-magnitude estimate, not a quote — verify against AWS pricing before relying on it.
- **Standing policy: the cluster is destroyed at the end of every session.** The NAT gateway is the main cost driver and bills whether or not anything runs on it. So "nothing is deployed" is the *normal* resting state of this project, not a sign something went wrong. Two n8n workflows back this up: `cost-watchdog` (emails at 5 PM and 9 PM if EKS is still up — working) and `destroy-notifier` (posts destroy success/failure to an n8n webhook — in progress).
- Because of that policy, **`terraform apply` and `terraform destroy` are routine here, not exceptional** — but they still need explicit approval each session, because they cost money and the owner may not want the cluster up yet.
- **Never run `aws` commands that create, modify, or delete resources without approval.** Read-only calls (`describe-*`, `get-*`, `list-*`) are fine.

### Deploy targets

- **AWS EKS in `ap-south-1` is canonical.** Cluster `app-hub-eks`, Kubernetes `1.31`.
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
- Do not refactor code you were not asked to touch. Note it in PROGRESS.md instead.

---

## 5. Environment — the WSL / Windows split

This is the single biggest source of confusion in this workspace. **The toolchain is split across two operating systems.**

| Tool        | Where it lives                                      | Notes |
|-------------|-----------------------------------------------------|-------|
| `terraform` | **WSL Ubuntu only** (`/usr/bin/terraform`, v1.15.8) | NOT on the Windows PATH |
| `uv`        | **WSL Ubuntu only** (`~/.local/bin/uv`, v0.11.32)   | NOT on the Windows PATH |
| `python3`   | **WSL Ubuntu** (`/usr/bin/python3`)                 | Windows `python` is the Store stub — it does not work |
| `docker`    | Windows (Docker Desktop, v29.5.3)                   | Not reachable from WSL — Docker Desktop's WSL integration isn't wired up. Builds and pushes happen on Windows. |
| `kubectl`   | **Both**, but they are two different tools in practice | Windows kubectl → `~/.kube/config` on Windows, context `minikube`. WSL kubectl → its own separate `~/.kube/config`, context `app-hub-eks`. Different files, different clusters. See below. |
| `helm`      | Windows (winget)                                    | |
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

Docker still has to build and push from Windows (Docker Desktop's WSL integration is not enabled here), so the deploy path genuinely straddles both: `docker build`/`push` on Windows, `aws eks update-kubeconfig` + `kubectl apply` on WSL.

### WSL2 DNS

A fix is already applied and must not be reverted: `generateResolvConf = false` in `/etc/wsl.conf`, with `nameserver 8.8.8.8` set manually in `/etc/resolv.conf`. WSL2 DNS breaks by default. If name resolution fails inside WSL, check that these are still in place before debugging anything else.

### AWS credentials

**Resolved 2026-08-29.** App-hub credentials are configured in **WSL's `~/.aws/`** (`default` profile, `terraform-learning` user, account `314146298861`, region `ap-south-1`) — a completely separate file from the Windows-side `~/.aws/`, which still holds the unrelated work profiles (`default`, `uzio-nonprod-audit`, `scripttest`) untouched and still intentionally broken.

- Both sides use the profile name `default`, but they are **different files resolving to different accounts.** There is no conflict, because Windows and WSL never share a home directory.
- Run all `aws`/`terraform` commands for this project from **WSL**. Running `aws sts get-caller-identity` on Windows will still fail — that's the work side, and it's supposed to.
- The `n8n-readonly` IAM user (scoped to `eks:DescribeCluster`, used by the cost watchdog) is not configured here — it's used from within n8n's own container, not from a shell.

---

## 6. Read order for a new session

Work through these in order. Stop as soon as you have what the task needs — don't read the whole list reflexively.

1. **`CLAUDE.md`** (this file) — objective, constraints, environment. Always.
2. **`PROGRESS.md`** — status table, blockers, known defects, next steps. Always. This is where you find out what is half-finished.
3. **`README.md`** — directory layout, quick start commands, governance. Read when you need to *run* something or are unsure of a workflow.
4. **`learn/README.md`** — the index of what has already been taught. Skim it before explaining anything: if a concept already has a file, build on it and link to it rather than re-explaining from scratch. If the current task extends an earlier step, read that step's file too.
5. Then, task-dependent only:
   - Service work → `links-service/app/main.py`, `links-service/app/models.py`, `links-service/pyproject.toml`, `links-service/Dockerfile`
   - Infra work → `infra/providers.tf`, `infra/vpc.tf`, `infra/eks.tf`, `infra/ecr.tf`, `infra/outputs.tf`, `infra/vairables.tf` *(yes, the filename is misspelled — see `P-04`)*
   - Deploy work → `manifests/links-service/deployment.yaml`, `manifests/links-service/service.yaml`
   - n8n work → `n8n/README.md` first (it carries the security rules), then `n8n/workflows/*.json`
6. **Never read `infra/.terraform/`.** It is ~800 MB of vendored provider binaries and upstream module source. It is gitignored, it is not our code, and reading it wastes the entire context window.

---

## 7. Before you finish a task

- **Write the `learn/` file for this step** — and add it to `learn/README.md`. Per § 2, the task is not done without it. If the step was too small to warrant its own file, append to the most relevant existing one instead.
- Update **`PROGRESS.md`**: move the row's status, clear or restate the blocker, write the real next step, and add a dated line to the progress log.
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

- **ECR needs `force_delete = true`.** Without it, `terraform destroy` fails when the repository still holds images. Already set in `ecr.tf`; do not remove it.

- **EKS needs `enable_cluster_creator_admin_permissions = true`.** Without it, the IAM user that *created* the cluster has no `kubectl` access to it. Already set in `eks.tf`.

- **n8n HTTP Request node: set "On Error" to "Stop Workflow", not "Continue (using error output)".** With "Continue", the downstream Gmail node fired on every execution regardless of cluster state, so the cost-watchdog emailed whether or not anything was running — a monitor that always alerts is a monitor you stop reading.

- **`0.0.0.0` is a bind address, not a browsable destination.** `--host 0.0.0.0` means "listen on all interfaces". Test the container at `localhost:8000`.
