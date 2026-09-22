# TIMELINE — app-hub

**Generated from git history. Do not edit by hand — run `./scripts/timeline.sh` to refresh.**

Every timestamp below is a real commit time, rendered in **IST (+05:30)**.
Git records an absolute instant, so these are accurate regardless of which
shell made the commit — relevant here, because Windows runs IST and WSL runs UTC.

| | |
|---|---|
| Commits | 225 across 8 repositories |
| Active days | 26 |
| First commit | 2026-07-28 15:27 IST |
| Latest commit | 2026-09-22 12:53 IST |

---

## 2026-07-28

| Time (IST) | Repo | Commit | Change |
|---|---|---|---|
| 15:27 | `links-service` | `a048c10` | Initial uv project setup with FastAPI dependency |

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
| 00:00 | `infra` | `c8f6c12` | Initial Terraform project scaffolld |
| 01:25 | `infra` | `66f8f16` | Add VPC module with public/private subnets, IGW, NAT gateway |
| 12:59 | `infra` | `838d446` | Added AWS EKS cluster and its admin access |
| 13:14 | `infra` | `009bd10` | Add outputs.tf for cluster and VPC values |
| 15:55 | `infra` | `19f7a5e` | Add ECR repository for links-service |
| 16:37 | `manifests` | `a933c2a` | Add links-service Deployment and Service |

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
| 14:53 | `app-hub` | `2dfcc93` | Add umbrella repo for cross-cutting project docs |
| 15:00 | `app-hub` | `2b995c0` | Backfill learn/ files 01-07 and record P-01, P-07, N-06 outcomes |
| 19:03 | `app-hub` | `78e9788` | Record E-00 resolved and document the two-kubeconfig split |
| 23:13 | `n8n` | `1c24503` | Add n8n workflow repo scaffold |
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
| 15:53 | `app-hub` | `8da8954` | Record destroy-notifier verification and log D-13 |
| 15:59 | `app-hub` | `3810077` | Add the gateway mechanism guide ahead of S-01 |
| 15:59 | `app-hub` | `6f74463` | Index learn/21 in the learn README |
| 16:15 | `n8n` | `51a7aab` | Switch both workflows from Gmail OAuth to SMTP |
| 16:17 | `app-hub` | `6b1efdb` | Resolve D-13 and record the SMTP switch |

## 2026-09-06

| Time (IST) | Repo | Commit | Change |
|---|---|---|---|
| 12:22 | `gateway` | `36feb40` | Setup gateway repo |

## 2026-09-07

| Time (IST) | Repo | Commit | Change |
|---|---|---|---|
| 11:27 | `gateway` | `7c52711` | Wrote async getLinks function |
| 13:27 | `gateway` | `1d5c088` | Add /links endpoint proxying to links-service with a shared async client |
| 18:35 | `gateway` | `261e5db` | Handle upstream failures with 502/503/504 and an explicit client timeout |

## 2026-09-08

| Time (IST) | Repo | Commit | Change |
|---|---|---|---|
| 12:05 | `app-hub` | `8841f54` | Correct documentation drift and fix a silent data loss in timeline.sh |
| 12:07 | `app-hub` | `bcf7915` | Refresh TIMELINE.md to include the drift-fix commit |

## 2026-09-09

| Time (IST) | Repo | Commit | Change |
|---|---|---|---|
| 12:45 | `app-hub` | `940d8a6` | Replace the work split: hand-build the learning, delegate the scaffolding |
| 12:45 | `app-hub` | `c5eeee6` | Refresh TIMELINE.md |
| 13:05 | `gateway` | `cb39f11` | Read links-service address from LINKS_SERVICE_URL, stop leaking it on errors |
| 13:06 | `app-hub` | `caf3ede` | Record S-01 step 4 and refresh the timeline |
| 13:39 | `gateway` | `e8b37fa` | Add Dockerfile and .dockerignore |
| 13:39 | `app-hub` | `6da7e8f` | Revise the learn/ rule to two tiers; record S-01 step 5 |
| 13:45 | `links-service` | `2c35edf` | Add .dockerignore |
| 13:46 | `app-hub` | `52e0523` | Make the ECR teardown cover every repository, not just links-service |
| 14:46 | `app-hub` | `d947e06` | Locate persistent/ in the infra repo; stop make status from lying |
| 17:03 | `infra` | `233d48b` | Commit .terraform.lock.hcl instead of ignoring it |
| 17:04 | `app-hub` | `c708aa4` | Close D-15 |

## 2026-09-10

| Time (IST) | Repo | Commit | Change |
|---|---|---|---|
| 11:15 | `app-hub` | `8a3039a` | Close D-12 -- the row was stale, not the defect |
| 12:57 | `links-service` | `fc753f8` | Add tests for the links CRUD endpoints; snake_case the handlers |
| 12:57 | `gateway` | `c921f03` | Rename getLinks to get_links |
| 12:59 | `app-hub` | `2eac25a` | Record C-02 and the closed defects; add learn/23 |
| 13:08 | `infra` | `6adda96` | Add the persistent Terraform stack with the DynamoDB table |
| 13:09 | `app-hub` | `afb0b54` | Record C-04 as written and committed, not applied |
| 13:10 | `app-hub` | `706353f` | Normalise escaped dollar signs in PROGRESS.md |
| 15:36 | `gateway` | `e76d2a5` | Add tests, write the README, describe the project |
| 15:36 | `links-service` | `8c11d8d` | Refresh the README -- three claims had gone stale |
| 15:37 | `manifests` | `c698344` | Add gateway manifests; move the namespace out of links-service/ |
| 15:37 | `infra` | `0b280cf` | Add the ECR repository for gateway |
| 15:38 | `app-hub` | `c2ab145` | Generalise the Makefile for two services; add make test; add learn/24 |
| 15:55 | `infra` | `5679306` | Write the README |
| 15:55 | `manifests` | `db87dff` | Write the README; make the links-service image tag an obvious placeholder |
| 15:56 | `gateway` | `951eedd` | Add app/__init__.py |
| 15:57 | `app-hub` | `716dbe8` | Add a doc-drift checker; fix ten stale documentation items |
| 16:23 | `gateway` | `42ec560` | Move to httpx2 (D-17) |
| 16:23 | `links-service` | `701a6fd` | POST /links returns 201 Created with a Location header (D-16) |
| 16:25 | `app-hub` | `21bb878` | Clear every no-cluster decision; prepare the scheduled teardown |
| 17:30 | `gateway` | `1d78307` | Correct the in-cluster address to links-service:80 |
| 17:30 | `manifests` | `94e7d55` | Fix gateway's LINKS_SERVICE_URL port, and pin both image tags |
| 17:35 | `app-hub` | `a478749` | Record the cluster session: S-01 complete, R-01..R-04 verified, port bug found |
| 18:03 | `app-hub` | `9f0f2b2` | Teardown clean; ECR needs multiple passes; correct the N-01b prerequisite |

## 2026-09-11

| Time (IST) | Repo | Commit | Change |
|---|---|---|---|
| 11:15 | `app-hub` | `f9bc157` | Refresh CONTEXT-BRIEF prose after the cluster session |

## 2026-09-12

| Time (IST) | Repo | Commit | Change |
|---|---|---|---|
| 21:18 | `links-service` | `1f7ce47` | Extract a repository layer and add the DynamoDB implementation |
| 21:22 | `app-hub` | `984aa79` | Record C-06's code half; log D-18; add learn/26 |

## 2026-09-13

| Time (IST) | Repo | Commit | Change |
|---|---|---|---|
| 00:01 | `gateway` | `c522956` | S-03: serve the dashboard from gateway; proxy the full links CRUD |
| 00:02 | `links-service` | `b20f10d` | README: the suite is 38 tests, not 15 |
| 00:03 | `app-hub` | `7f60008` | Record S-03; log D-19; add learn/27; correct a stale timing claim |
| 00:20 | `app-hub` | `fa8b51e` | C-04 was applied three days ago and the board never said so |
| 11:28 | `links-service` | `e69e797` | Add a repeatable check against the real DynamoDB table |
| 11:28 | `app-hub` | `d8bfb1b` | C-06 verified against the real table; add make verify-dynamo |
| 12:27 | `aggregator` | `83d4b1d` | aggregator: probe every catalogued link and report what is up |
| 12:39 | `gateway` | `922b3da` | Proxy /status to aggregator; show liveness dots on the dashboard |
| 12:39 | `infra` | `a661727` | Third ECR repository, for aggregator |
| 12:39 | `manifests` | `a83652f` | Add aggregator Deployment and Service |
| 12:39 | `app-hub` | `4f45bb9` | Record S-02; log D-20; add learn/28; seven repos now |
| 12:45 | `app-hub` | `2dc3854` | Summaries move to plain English |
| 12:59 | `app-hub` | `72734f7` | Close N-01b; the scheduled task was registered all along |
| 14:01 | `app-hub` | `8a4c59c` | Prove the scheduled task exists with a control query |
| 14:10 | `app-hub` | `041b517` | Guard was wrong: creating a task as yourself needs no admin |
| 14:24 | `app-hub` | `9dc59e6` | The nightly teardown would never have run on battery, silently |
| 14:42 | `app-hub` | `7f02341` | Nightly teardown proven end to end; tee the output into the log |
| 20:14 | `infra` | `edf5d71` | C-05: IRSA role, ServiceAccount, and D-18 made mechanical |
| 20:15 | `manifests` | `41c2e01` | C-05: IRSA role, ServiceAccount, and D-18 made mechanical |
| 20:15 | `app-hub` | `7f12203` | C-05: IRSA role, ServiceAccount, and D-18 made mechanical |
| 20:19 | `gateway` | `c35c456` | learn audit: learn/22 exists, and I had claimed it did not |
| 20:19 | `app-hub` | `a85e699` | learn audit: learn/22 exists, and I had claimed it did not |
| 20:41 | `manifests` | `d362f43` | D-02 closed on real EKS; AGGREGATOR_URL was missing from the manifest |
| 20:42 | `app-hub` | `9f5f367` | D-02 closed on real EKS; AGGREGATOR_URL was missing from the manifest |
| 23:48 | `app-hub` | `71eafde` | Log D-22: the cost watchdog has never fired, and structurally cannot |

## 2026-09-14

| Time (IST) | Repo | Commit | Change |
|---|---|---|---|
| 00:03 | `app-hub` | `0f64587` | Log D-23 (EKS 1.31 on extended support); close D-18 |
| 00:24 | `infra` | `581b817` | Fix D-22 and D-23: both cost controls now actually work |
| 00:24 | `app-hub` | `6d17286` | Fix D-22 and D-23: both cost controls now actually work |
| 10:03 | `app-hub` | `2548f4b` | Refresh the roadmap: items 1-3 and 5 are complete, R-05 is next |
| 10:11 | `manifests` | `801b6aa` | Two stale facts found while preparing R-05 |
| 10:11 | `app-hub` | `474474e` | Two stale facts found while preparing R-05 |
| 10:49 | `infra` | `ad739b7` | Stale-doc sweep; make the localhost-default bug a check |
| 10:49 | `app-hub` | `40d9f2b` | Stale-doc sweep; make the localhost-default bug a check |
| 14:37 | `manifests` | `4050407` | R-05 guided build: monitoring namespace and values.yaml |
| 14:37 | `app-hub` | `a71d1a7` | R-05 guided build: monitoring namespace and values.yaml |
| 17:40 | `links-service` | `ed8915a` | Expose /metrics for Prometheus (R-05) |
| 17:40 | `gateway` | `b389506` | Expose /metrics for Prometheus (R-05) |
| 17:40 | `aggregator` | `837f0f4` | Expose /metrics for Prometheus (R-05) |
| 17:59 | `manifests` | `01f388e` | R-05: ServiceMonitor scraping app-hub, and the silent failures it hid |
| 17:59 | `app-hub` | `3cbb441` | R-05: ServiceMonitor scraping app-hub, and the silent failures it hid |
| 18:14 | `app-hub` | `68962e1` | Record R-05 and the clean teardown; add learn/30 |

## 2026-09-16

| Time (IST) | Repo | Commit | Change |
|---|---|---|---|
| 15:57 | `app-hub` | `27c9ab3` | The validator was not validating the thing it was written for |
| 16:13 | `infra` | `344cb72` | E-06: an IRSA role for the AWS Load Balancer Controller |
| 16:13 | `manifests` | `8f4b0c1` | E-06: Ingress, a shared ALB, and links-service goes private |
| 16:13 | `app-hub` | `c948e54` | E-06 teardown ordering, and a false positive worth more than a true one |
| 16:43 | `gateway` | `3292226` | Links open in a new tab; fix a reload that silently killed /metrics |
| 16:43 | `aggregator` | `d155160` | checked_at was a monotonic reading published as a timestamp |
| 16:46 | `app-hub` | `06c4532` | Running the app for review found what 149 tests had not |
| 23:34 | `infra` | `2a8436e` | A daily spend guardrail that runs in AWS, not on the laptop |
| 23:34 | `manifests` | `802f698` | Point the E-06 runbook at learn/32, not learn/31 |
| 23:35 | `app-hub` | `8831c3b` | Record the daily spend guardrail; learn/31 |
| 23:51 | `app-hub` | `a25d4b1` | A public project page on Netlify, and what it deliberately is not |
| 23:51 | `manifests` | `57a391b` | Stop naming E-06 learn number in advance |

## 2026-09-17

| Time (IST) | Repo | Commit | Change |
|---|---|---|---|
| 11:23 | `app-hub` | `afd34dd` | Projects section: one source of truth, three readers |
| 12:35 | `app-hub` | `16d1ffd` | Projects: split by who the link actually works for |
| 12:39 | `app-hub` | `0479fcf` | Record the projects section; the log entry was late |
| 15:00 | `app-hub` | `3a3c15a` | Real blurbs, from each README rather than invented |
| 15:26 | `app-hub` | `58ebb37` | Stale-doc sweep: site/ existed nowhere in the entry-point docs |

## 2026-09-18

| Time (IST) | Repo | Commit | Change |
|---|---|---|---|
| 00:03 | `app-hub` | `1eadc94` | Correct D-25: the teardown does run at 23:30 when the laptop is awake |
| 00:14 | `app-hub` | `59dab1c` | Headers move to site/_headers; -WakeToRun added to the teardown task |
| 01:11 | `app-hub` | `5201600` | Add a 404 page; Procedo has a live URL |
| 01:17 | `app-hub` | `19b1904` | P-10 is live; D-25 fix applied, verification pending |
| 01:19 | `app-hub` | `215f04d` | P-10: the site is live but two commits stale |
| 13:12 | `manifests` | `919d3f7` | Runbook: the helm command was written for bash, pasted into PowerShell |
| 13:24 | `manifests` | `c96c95a` | E-06 verified end to end on a real cluster |
| 13:24 | `app-hub` | `2744da6` | E-06 done; make monitoring so R-05 is reproducible; learn/33 |
| 13:55 | `app-hub` | `95ee31f` | make down orphaned an ALB, because step 1 had never worked |
| 15:18 | `infra` | `6aad013` | R-06: a third IRSA role, for pushing images and nothing else |
| 15:19 | `manifests` | `43132d3` | R-06: Jenkins configured entirely as code |
| 15:19 | `links-service` | `1eabb8d` | R-06: the pipeline, which stops before deploying |
| 15:19 | `app-hub` | `b5c2abc` | R-06 written: make jenkins, and the record |
| 22:09 | `app-hub` | `25c7e69` | D-24 root cause fixed: restart n8n on every wake, not once |
| 22:31 | `compose` | `d50e33e` | The always-on deployment target |
| 22:31 | `app-hub` | `c1112ea` | Register compose/ as the seventh component; P-11 |
| 23:05 | `compose` | `02ef4ec` | Runbook: say how the files reach the host |
| 23:06 | `app-hub` | `86a7776` | compose has a remote, and the runbook gap it exposed |
| 23:11 | `app-hub` | `3bcdd07` | D-24: record why today is not evidence, before the gap is misread |
| 23:41 | `infra` | `b4d5b79` | ECR moves to the persistent stack; the always-on host depends on it |
| 23:41 | `compose` | `625379a` | Record that the registry is durable now |
| 23:42 | `app-hub` | `faf8c07` | make down no longer empties ECR, because destroy cannot reach it |
| 23:52 | `compose` | `cc1db59` | Tailscale Funnel replaces cloudflared; the deciding factor was the hostname |
| 23:52 | `app-hub` | `694669e` | learn/34, and the Tailscale decision recorded |
| 23:53 | `app-hub` | `1b2661b` | Regenerate TIMELINE.md |

## 2026-09-19

| Time (IST) | Repo | Commit | Change |
|---|---|---|---|
| 00:01 | `app-hub` | `a836331` | infra/persistent applied: ECR is durable now |
| 00:06 | `app-hub` | `653e6ab` | Correct two teardown docs my own ECR move made dangerous |
| 00:06 | `app-hub` | `01a9cb7` | CLAUDE.md section 2 said to empty ECR during teardown; it no longer should |
| 00:07 | `app-hub` | `6da01a9` | Regenerate TIMELINE.md |
| 00:26 | `manifests` | `c47478d` | R-07: ArgoCD, app-of-apps, written and never applied |
| 00:26 | `app-hub` | `74a5ac0` | make argocd, a teardown step 0, and a validator that would have skipped it |
| 00:26 | `app-hub` | `809b784` | Regenerate TIMELINE.md |
| 00:56 | `manifests` | `61b90cb` | Pin links-service to 1eabb8d, the image that actually exists |
| 01:10 | `manifests` | `28231a2` | applicationSet.enabled does nothing; the lever is replicas: 0 |
| 01:10 | `app-hub` | `c131ac3` | R-07 applied and verified on real EKS; three claims tested, one was false |
| 01:11 | `app-hub` | `2060e44` | Regenerate TIMELINE.md |
| 01:43 | `manifests` | `527384f` | D-29: sync waves, because deleting the IngressClass strands the Ingress |
| 01:44 | `app-hub` | `1f4f4bf` | D-29 recorded, and the teardown confirmed against AWS rather than the script |
| 01:44 | `app-hub` | `bc47a43` | Regenerate TIMELINE.md |
| 18:37 | `app-hub` | `e38931c` | Lock v1 finish line |
| 18:38 | `app-hub` | `dd46c70` | Record the v1 lock in PROGRESS |
| 18:51 | `app-hub` | `d033c9a` | UNFREEZE, then close G8-G11 |
| 21:34 | `app-hub` | `ba0f0df` | Add the main landmark; tokenise the type scale and radius |
| 21:43 | `app-hub` | `d69cbe2` | Record D-30: pushed commit has not reached the live site |
| 23:49 | `app-hub` | `5c9795c` | D-24 closed: the watchdog fired after a sleep, five days on |
| 23:52 | `app-hub` | `eff0e7d` | Remove three junk screenshots with $name literal in the filename |
| 23:57 | `app-hub` | `cb23941` | Deploy via CLI: production is current, continuous deployment is not |

## 2026-09-20

| Time (IST) | Repo | Commit | Change |
|---|---|---|---|
| 00:10 | `app-hub` | `7351e82` | The verify command I gave was bash-only and this machine runs PowerShell |
| 00:16 | `app-hub` | `e4aa7dd` | make run-local: the dashboard without a cluster |
| 00:23 | `app-hub` | `fb3aa93` | make deploy-site, because git push does not publish this site |
| 00:33 | `app-hub` | `a17a4ff` | D-30 root cause: every build setting is correct, the Git link is not |
| 00:33 | `app-hub` | `5c40fa2` | Repair the D-30 row a heredoc mangled |
| 00:36 | `app-hub` | `74e44a5` | Record the confirmed Pages root cause, and test the reconnect |
| 00:46 | `app-hub` | `f65f530` | D-30 root cause: app-hub is missing from the Pages GitHub App |
| 01:20 | `app-hub` | `59d5c80` | D-30 resolved: one repository, missing from one app's access list |
| 01:51 | `manifests` | `336dabd` | G4: a uv container so the pipeline can actually run tests |
| 01:51 | `links-service` | `e053a28` | G4: the Test stage runs the suite, so the pipeline is a real gate |
| 01:52 | `compose` | `1b81e4f` | G5: n8n moves here, not to EKS |
| 01:52 | `app-hub` | `adcfeea` | G4 done, G5 re-targeted and written, G3 blocked on a key |
| 02:20 | `manifests` | `3bfbfdf` | Document that app-hub-manifests needs TWO deploy keys |
| 02:20 | `app-hub` | `6dae5dc` | Both manifests deploy keys verified; G3 no longer blocked on a key |
| 02:22 | `app-hub` | `8e35016` | Regenerate TIMELINE.md |
| 02:36 | `manifests` | `a9246e1` | Jenkins runbook: replace the hand-typed secrets with make targets |
| 02:36 | `app-hub` | `b955054` | Jenkins secrets: split on whether the step needs a cluster |
| 02:38 | `app-hub` | `0c9a11e` | Regenerate TIMELINE.md |
| 02:47 | `app-hub` | `c23b601` | Point Procedo and Acharya Amit Puri at their Cloudflare Pages URLs |
| 02:49 | `app-hub` | `276d69f` | Record the live verification of the projects page |
| 10:16 | `app-hub` | `ad06f39` | G7 cannot close by waiting, and half of D-25 is already proven |
| 10:18 | `app-hub` | `57b62bd` | Add the commit -F rule to CLAUDE.md section 9 |
| 10:54 | `app-hub` | `5e9d5d5` | Clear the no-cluster work: two stale documents, and a compose check |
| 13:36 | `app-hub` | `1472cf5` | Correct which gaps actually need a cluster |

## 2026-09-22

| Time (IST) | Repo | Commit | Change |
|---|---|---|---|
| 12:13 | `app-hub` | `a553ce4` | D-25 and G7 closed by evidence; D-31 and D-32 opened |
| 12:20 | `app-hub` | `4a8b7f4` | D-32 root cause: the dead task belongs to the work domain account |
| 12:53 | `compose` | `01d6b6a` | Write the IAM policy and the Tailscale ACL for G2 |
