# TIMELINE — app-hub

**Generated from git history. Do not edit by hand — run `./scripts/timeline.sh` to refresh.**

Every timestamp below is a real commit time, rendered in **IST (+05:30)**.
Git records an absolute instant, so these are accurate regardless of which
shell made the commit — relevant here, because Windows runs IST and WSL runs UTC.

| | |
|---|---|
| Commits | 40 across 5 repositories |
| Active days | 10 |
| First commit | 2026-07-29 12:09 IST |
| Latest commit | 2026-09-05 15:50 IST |

---

## 2026-07-29

| Time (IST) | Repo | Commit | Change |
|---|---|---|---|
| 12:09 | `links-service` | `5a21d5a` | Added health check endpoint |

## 2026-08-02

| Time (IST) | Repo | Commit | Change |
|---|---|---|---|
| 21:34 | `links-service` | `58e29cd` | Added CRUD operations |

## 2026-08-03

| Time (IST) | Repo | Commit | Change |
|---|---|---|---|
| 01:25 | `infra` | `66f8f16` | Add VPC module with public/private subnets, IGW, NAT gateway |
| 12:59 | `infra` | `838d446` | Added AWS EKS cluster and its admin access |
| 13:14 | `infra` | `009bd10` | Add outputs.tf for cluster and VPC values |
| 15:55 | `infra` | `19f7a5e` | Add ECR repository for links-service |

## 2026-08-04

| Time (IST) | Repo | Commit | Change |
|---|---|---|---|
| 11:05 | `infra` | `cdfa2d5` | Add force_delete to ECR repo for easier teardown |

## 2026-08-30

| Time (IST) | Repo | Commit | Change |
|---|---|---|---|
| 12:00 | `links-service` | `7b7b0bd` | Fix POST /links storing LinkCreate instead of the constructed Link |
| 12:00 | `links-service` | `5e312ef` | Add Dockerfile with Python 3.14 base and direct uvicorn entrypoint |
| 12:00 | `links-service` | `f3203de` | Add service README covering API, local run and storage caveat |
| 12:00 | `infra` | `3cb9e57` | Rename vairables.tf to variables.tf and remove empty main.tf |
| 14:52 | `infra` | `dd3c025` | Add .gitattributes to force LF line endings |
| 14:52 | `links-service` | `73ddaf6` | Add .gitattributes to force LF line endings |
| 14:52 | `manifests` | `ce67c58` | Add .gitattributes to force LF line endings |
| 15:00 | `app-hub` | `2b995c0` | Backfill learn/ files 01-07 and record P-01, P-07, N-06 outcomes |
| 19:03 | `app-hub` | `78e9788` | Record E-00 resolved and document the two-kubeconfig split |
| 23:15 | `manifests` | `93cea2c` | Pin links-service to a single replica until persistence lands |
| 23:21 | `app-hub` | `fe85d08` | Publish repos, plan infra, decide persistence, and close learn/ gaps |
| 23:44 | `app-hub` | `c71ef9e` | Correct the docker-from-WSL claim and harden the kubeconfig rule |

## 2026-08-31

| Time (IST) | Repo | Commit | Change |
|---|---|---|---|
| 00:22 | `app-hub` | `e2a97f8` | Correct the ECR force_delete claim and document safe teardown |
| 00:29 | `app-hub` | `46d2fc5` | Mark N-03 and N-05 done, C-02 in progress |
| 00:45 | `n8n` | `065b447` | Add eks-cost-watchdog and terraform-destroy-notifier workflows |
| 00:47 | `app-hub` | `e12bb6d` | Record N-04 done, all repos pushed, and next-session priorities |
| 12:49 | `links-service` | `1ece6ee` | Add pytest and httpx as dev dependencies |
| 12:50 | `infra` | `32a6c16` | Gitignore saved Terraform plan files |
| 16:07 | `app-hub` | `e1c865d` | Add generated TIMELINE.md and fix a one-day date drift |
| 16:24 | `app-hub` | `39c0a6e` | Milestone 2 complete: first end-to-end deploy on EKS |
| 16:32 | `manifests` | `99381d0` | Expose links-service via an internet-facing NLB |
| 16:35 | `app-hub` | `f9cb062` | Complete E-05: service exposed via NLB, Phase 2 done |
| 17:09 | `app-hub` | `de240c0` | Tear down cleanly and correct the ECR deletion gap |

## 2026-09-02

| Time (IST) | Repo | Commit | Change |
|---|---|---|---|
| 13:51 | `app-hub` | `5aac288` | Require an Indian English summary at the end of every response |
| 13:54 | `app-hub` | `de73a96` | Explain why terraform destroy cannot clean up Kubernetes-created AWS resources |
| 13:54 | `app-hub` | `d29591d` | Update learn index entry for 15 to lead with the why |

## 2026-09-03

| Time (IST) | Repo | Commit | Change |
|---|---|---|---|
| 11:22 | `links-service` | `98f355b` | Run as a non-root user and stop writing bytecode |
| 11:22 | `manifests` | `e073761` | Add namespace, resource limits and securityContext |
| 11:22 | `infra` | `c06d65f` | Make ECR image tags immutable |
| 11:29 | `app-hub` | `9c944ae` | Add Makefile automation, regenerate CONTEXT-BRIEF, refresh README |

## 2026-09-04

| Time (IST) | Repo | Commit | Change |
|---|---|---|---|
| 12:04 | `n8n` | `ff474a8` | Document the destroy-notifier webhook URL in the env template |
| 12:04 | `app-hub` | `7cb8890` | Add unattended teardown script for the destroy-notifier |

## 2026-09-05

| Time (IST) | Repo | Commit | Change |
|---|---|---|---|
| 15:50 | `n8n` | `0b84e25` | Add the completed destroy-notifier workflow |
