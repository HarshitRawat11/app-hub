# TIMELINE — app-hub

**Generated from git history. Do not edit by hand — run `./scripts/timeline.sh` to refresh.**

Every timestamp below is a real commit time, rendered in **IST (+05:30)**.
Git records an absolute instant, so these are accurate regardless of which
shell made the commit — relevant here, because Windows runs IST and WSL runs UTC.

| | |
|---|---|
| Commits | 25 across 5 repositories |
| Active days | 6 |
| First commit | 2026-07-29 06:39 IST |
| Latest commit | 2026-08-31 07:20 IST |

---

## 2026-07-29

| Time (IST) | Repo | Commit | Change |
|---|---|---|---|
| 06:39 | `links-service` | `5a21d5a` | Added health check endpoint |

## 2026-08-02

| Time (IST) | Repo | Commit | Change |
|---|---|---|---|
| 16:04 | `links-service` | `58e29cd` | Added CRUD operations |
| 19:55 | `infra` | `66f8f16` | Add VPC module with public/private subnets, IGW, NAT gateway |

## 2026-08-03

| Time (IST) | Repo | Commit | Change |
|---|---|---|---|
| 07:29 | `infra` | `838d446` | Added AWS EKS cluster and its admin access |
| 07:44 | `infra` | `009bd10` | Add outputs.tf for cluster and VPC values |
| 10:25 | `infra` | `19f7a5e` | Add ECR repository for links-service |

## 2026-08-04

| Time (IST) | Repo | Commit | Change |
|---|---|---|---|
| 05:35 | `infra` | `cdfa2d5` | Add force_delete to ECR repo for easier teardown |

## 2026-08-30

| Time (IST) | Repo | Commit | Change |
|---|---|---|---|
| 06:30 | `links-service` | `7b7b0bd` | Fix POST /links storing LinkCreate instead of the constructed Link |
| 06:30 | `links-service` | `5e312ef` | Add Dockerfile with Python 3.14 base and direct uvicorn entrypoint |
| 06:30 | `links-service` | `f3203de` | Add service README covering API, local run and storage caveat |
| 06:30 | `infra` | `3cb9e57` | Rename vairables.tf to variables.tf and remove empty main.tf |
| 09:22 | `infra` | `dd3c025` | Add .gitattributes to force LF line endings |
| 09:22 | `links-service` | `73ddaf6` | Add .gitattributes to force LF line endings |
| 09:22 | `manifests` | `ce67c58` | Add .gitattributes to force LF line endings |
| 09:30 | `app-hub` | `2b995c0` | Backfill learn/ files 01-07 and record P-01, P-07, N-06 outcomes |
| 13:33 | `app-hub` | `78e9788` | Record E-00 resolved and document the two-kubeconfig split |
| 17:45 | `manifests` | `93cea2c` | Pin links-service to a single replica until persistence lands |
| 17:51 | `app-hub` | `fe85d08` | Publish repos, plan infra, decide persistence, and close learn/ gaps |
| 18:14 | `app-hub` | `c71ef9e` | Correct the docker-from-WSL claim and harden the kubeconfig rule |
| 18:52 | `app-hub` | `e2a97f8` | Correct the ECR force_delete claim and document safe teardown |
| 18:59 | `app-hub` | `46d2fc5` | Mark N-03 and N-05 done, C-02 in progress |
| 19:15 | `n8n` | `065b447` | Add eks-cost-watchdog and terraform-destroy-notifier workflows |
| 19:17 | `app-hub` | `e12bb6d` | Record N-04 done, all repos pushed, and next-session priorities |

## 2026-08-31

| Time (IST) | Repo | Commit | Change |
|---|---|---|---|
| 07:19 | `links-service` | `1ece6ee` | Add pytest and httpx as dev dependencies |
| 07:20 | `infra` | `32a6c16` | Gitignore saved Terraform plan files |
