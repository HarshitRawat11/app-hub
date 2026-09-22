# FINISH-LINE.md — app-hub v1

| | |
|---|---|
| **Status** | 🔓 **UNFROZEN 2026-09-19** — the classification gate is lifted |
| **Version** | 1.0 (criteria unchanged) |
| **Locked** | 2026-09-19 18:34 IST |
| **Unfrozen** | 2026-09-19, at the owner's word |
| **Completion authority** | The owner, alone — personal work, no client |
| **Acceptance** | **SIGNED OFF** by the owner |

> **UNFROZEN 2026-09-19.** The owner lifted the freeze immediately after locking
> it — the DEFECT/EXTRA classification ritual on every request was not what they
> wanted, and they said so rather than living with it.
>
> **The criteria below are unchanged and still accurate.** What was switched off
> is the *gate*, not the *definition*. This document is now a **roadmap**: § 5 is
> the remaining work, § 4 records what was deliberately excluded and why, and
> § 0 still pins the eight repository HEADs from the moment of the lock.
>
> Nothing here needs permission to act on any more. To restore the gate, say
> **FREEZE**.

**The ruling this document is built on** (owner, 2026-09-19):

> *v1 is the platform complete. New apps are new projects.*

That resolves the tension in `CLAUDE.md § 1`, which says *"design for a hub that
grows, not for one service that ships."* The **platform** is the finishable
thing. Growth happens **on top of** a finished v1, as new projects — not inside
it as permanently unfinished scope.

**And the scope test the owner gave** (2026-09-19):

> *all of the phases should complete and fixed which is stated in status file*

So v1 is not a judgement call. It is: **every row on the `PROGRESS.md` status
board reads DONE, and the open defects are closed.**

---

## 0. Frozen state at lock time

`v1.0` was locked against these eight commits. A tag in the root repository
captures only the root, so the other seven are recorded here — this table, not
the tag, is what makes the freeze reconstructable.

| Repository | HEAD at lock |
|---|---|
| `.` (root / umbrella) | `bc47a434cf626a61893e6a4e7c68163c98a24dc8` |
| `infra/` | `b4d5b799b72615f5dd78ca216957053c1f68155b` |
| `links-service/` | `1eabb8d6532d2db026841f49cc8acd795e5a63a9` |
| `gateway/` | `32922261eee151bd567f61965514c8bb508e4f56` |
| `aggregator/` | `d1551607277e3c1a70799ae8de868b17a2dc423f` |
| `manifests/` | `527384f61ce5c88f2a6c8e6d40bcda4330afb6af` |
| `n8n/` | `51a7aaba5abc611ce75152cb3027df2276feda80` |
| `compose/` | `cc1db591abf56906100ecf88cf696cf1e6f83039` |

> **The lock freezes the SCOPE, not the completion.** Eleven gap items remain
> (§ 5). v1 is *defined*, not *reached*. The git tag is named accordingly.

---

## 1. Definition of Done

Every criterion below is answerable **yes/no in under a minute by someone with no
context**. Criteria are numbered so they can be named exactly.

### Content

This is a platform, not a website, so "pages" are **components**. A component not
on this list is out of scope.

**C1 — The status board is fully green.** All **43** rows in `PROGRESS.md §
Status board` read DONE. Check: no row's status column begins with `Not started`,
`WRITTEN`, `NEVER APPLIED`, or `Decided`.

The 43 rows: `P-01`–`P-11`, `C-01`–`C-06`, `E-00`–`E-06`, `R-01`–`R-07`,
`N-00`, `N-00b`, `N-01`, `N-01b`, `N-02`–`N-06`, `S-01`–`S-03`.

**C2 — The open defects are closed.** `D-24` (High) and `D-25` (Medium) are
struck through in `PROGRESS.md § Known Defects` with recorded evidence.

`D-19` and `D-20` are **already closed for v1 purposes** — both are tagged
Informational and deliberately retained (`mitigated by design`, `fixed same
day`). They are not gap items.

**C3 — Three services, each complete.** For `links-service`, `gateway` and
`aggregator`: own git repo with a pushed remote, a `Dockerfile`, a passing test
suite, Kubernetes manifests under `manifests/<service>/`, and an image in ECR.

**C4 — Both Terraform stacks apply from clean.** `infra/` (VPC, EKS, three IRSA
roles) and `infra/persistent/` (DynamoDB, budget guardrail, three ECR
repositories). Check: `terraform validate` passes in both.

**C5 — The platform layers exist as code.** Ingress + ALB (`E-06`), observability
(`R-05`), CI (`R-06`), CD (`R-07`), always-on target (`P-11`), n8n (`N-06`).

**C6 — Documentation reflects reality.** `README.md`, `CLAUDE.md`, `PROGRESS.md`,
`TIMELINE.md` and `CONTEXT-BRIEF.md` contain no statement contradicted by the
repo. Check: `python3 scripts/check-doc-drift.py` exits 0 **and**
`README.md`'s status line names the true current phase.

**C7 — The learning record is complete.** Every `learn/NN-*.md` appears in
`learn/README.md`. Check: file count equals index row count. *(VERIFIED 36 = 36.)*

**C8 — The public page exists and describes the platform.** `site/` publishes
`index.html`, `demo.html`, `404.html`, `projects.json` and its four static assets.

#### Owed content

| Item | Owner | Status |
|---|---|---|
| `links-service/Jenkinsfile:72` — placeholder test stage | **Owner** | **IN SCOPE.** CI must genuinely run the test suite. Needs a container with Python in the agent pod template. Tracked as `G4`. |
| `compose/.env.example` — 6 × `CHANGEME` | — | **DONE.** A `.example` file's job is to carry placeholders; the real `.env` is gitignored and absent. Not owed content. |

#### Explicit exclusions — Content

- **A fourth service.** Per the ruling: a new app is a new project.
- `netlify.toml` — **removed 2026-09-19** (`G9` closed). No Netlify deploy
  existed; the site is on Cloudflare Pages, and two deploy configs for one site
  read as drift. `site/README.md` was rewritten for Cloudflare Pages in the same
  change — it had been substantially a Netlify runbook, which `G9` understated.
- `CONTEXT-BRIEF.md` is a working aid for chat sessions without filesystem access.
  It is drift-checked so it cannot rot silently, but it is **not** held to v1
  content criteria beyond `C6`.

### Design / Creativity

**The visual system as it exists now is the v1 visual system.** Observed, not
invented:

| | |
|---|---|
| **Palette** | 7 tokens — `--bg --surface --border --text --muted --accent --danger` |
| Light | `#fbfbfa` `#ffffff` `#e3e1dd` `#1f1e1c` `#6f6c67` `#2f6f4f` `#a13b2d` |
| Dark | `#17171a` `#1f1f23` `#33333a` `#eceaE6` `#9a968e` `#6fc79a` `#e0806f` |
| **Typography** | **two families**: a system sans for prose, a mono for code and chips |
| **Type scale** | **6 steps** — `--fs-xs .78` `--fs-sm .85` `--fs-base .9` `--fs-md .95` `--fs-lg 1.28` `--fs-xl 1.5` — plus 2 fluid `clamp()` heads |
| **Radius** | 3 named tokens — `--radius 8px`, `--radius-sm 4px`, `--radius-pill 999px` |
| **Theming** | `@media (prefers-color-scheme: dark)` |

**D1 — No page introduces a colour outside the seven tokens.** Check: no literal
hex in `site/*.html` or `site/static/*.css` other than the token definitions.

**D2 — Two type families, and a scale with six steps.** One system sans for
prose, one mono for code and chips. Every fixed size in a site-owned file
resolves to a `--fs-*` token; the only exceptions are `code` at `0.87em`
(relative by design) and the two `clamp()` heads (fluid, not steps).

> **CORRECTED 2026-09-19. This criterion previously read *"One type family. No
> second `font-family` declaration anywhere in `site/`."* Both halves were
> false** — there are two families and four declarations. I wrote it after
> grepping `font-family:` in `style.css` alone, which matched neither the
> `font:` shorthand that actually sets the body type nor anything in
> `index.html`. The site did not fail a gate; **I wrote a gate that did not
> describe the site.**

**D5 — Radius is tokenised.** Three named tokens, no raw values in site-owned
files. *(`style.css` additionally uses `50%` for a circular control — vendored
from `gateway`, and a legitimately distinct idiom.)*

**D3 — Both pages support light and dark** via `prefers-color-scheme`.

**D4 — Responsive floor: `360px`, `768px`, `1280px`.** Each renders with **no
horizontal page scroll**.

> **Stated honestly:** the stylesheet contains **no width-based media queries** —
> the layout is fluid, not breakpoint-driven. So `D4` tests the *outcome*, not the
> mechanism. This was called the criterion most likely to fail, because a table
> already overflowed at 293px once (`learn/32`).
>
> **VERIFIED 2026-09-19 — it passes, and the mechanism is now known.** Both pages
> report `documentElement.scrollWidth == window.innerWidth` at all three widths.
> At 360px the landing page's table really is **480px wide and does overflow** —
> but it sits inside `div.table-wrap` with `overflow-x: auto` (`clientWidth` 320,
> `scrollWidth` 480). **The table scrolls; the page does not.** Containment, not
> breakpoints, is what satisfies this criterion — which is exactly the fix
> `learn/32` describes.

#### Explicit exclusions — Design

- No redesign, no CSS framework, no component library, no build step for `site/`.
- No additional pages beyond `index`, `demo`, `404`.
- `site/static/style.css` and `app.js` are **vendored from `gateway`** and
  drift-checked. Editing them in `site/` is a defect, not a design change.
- No animation or motion system. There is none today; none is owed.

### Optimization

Thresholds tuned to what this project actually is: a learning platform with a
small static shopfront, not a marketing site.

| # | Criterion | State at lock |
|---|---|---|
| **O1** | `make test` — all pass, zero failures | **VERIFIED 152/152, exit 0** |
| **O2** | `make validate` — exit 0 (manifests + both Terraform stacks) | **VERIFIED** |
| **O3** | `scripts/check-doc-drift.py` — exit 0 | **VERIFIED** |
| **O4** | Total `site/` weight ≤ **100 KB** | **VERIFIED 63,816 B** |
| **O5** | Live response headers carry CSP, `X-Frame-Options`, `X-Content-Type-Options`, `Referrer-Policy` | **VERIFIED — all four** |
| **O6** | Every page: `<html lang>`, a unique `<title>`, a unique `<meta name="description">` | **VERIFIED both pages** |
| **O7** | A nonexistent path returns **404**, not 200 | **VERIFIED (2,194 B custom page)** |
| **O8** | **Zero console errors** on load of `/` and `/demo` | **VERIFIED 2026-09-19** — zero console messages of any level on both |
| **O9** | `make down` leaves **zero** orphaned AWS resources — no cluster, NAT gateway, load balancer, unattached EBS or unassociated EIP | **VERIFIED 2026-09-19** |
| **O10** | Resting cost is **$0/hour** apart from the persistent stack (DynamoDB on-demand + ECR storage) | **VERIFIED** |
| **O11** | No secret committed in any of the 8 repos — no AWS keys, kubeconfigs, `*.tfvars`, `.env` | **VERIFIED by gitignore + inspection** |

**Deliberately NOT criteria, and why:**

- **`strict-transport-security`** is absent from the live response. Cloudflare
  Pages terminates TLS and serves HTTPS regardless. Not required for v1.
- **Lighthouse.** The site is 62 KB of static HTML with no images, no fonts and
  no third-party scripts; a Lighthouse number would measure Cloudflare's CDN, not
  this project's work. `O4`–`O8` cover the same ground with checks that can
  actually fail for a reason we control.

---

## 2. Deployment Criterion

**DEP1 — The public page responds 200** at **`https://app-hub-hr.pages.dev/`**.
*(VERIFIED. A custom domain is explicitly NOT required for v1 — owner's ruling,
2026-09-19.)*

**DEP2 — The platform is reproducible from a clean clone.** `make up` → `make
deploy` → `make argocd` brings the full stack live on EKS, and `make down`
returns to `DEP3`. *(VERIFIED end to end 2026-09-19.)*

**DEP3 — Nothing is deployed at rest.** A destroyed cluster is the **normal**
state of this project, not an incomplete one. v1 does **not** require a running
cluster.

> **DEP3 is the criterion most likely to be misread** by someone new to the repo,
> so it is stated positively: "nothing running" is success, not an unfinished v1.

---

## 3. Completion Authority

**Personal work. v1 is complete on the owner's sign-off alone.** No client, no
acceptance checklist, no provisional freeze.

---

## 4. Explicitly Out of Scope

Named, so that none of it can later be mistaken for unfinished v1 work. Every
item is a legitimate idea; none is part of v1.

**Platform capability**
- A fourth service, or any new app — **new project**, per the ruling
- Prometheus persistence (EBS CSI addon + a fourth IRSA role)
- Grafana dashboards beyond the chart defaults
- Prometheus alert rules / PromQL — including Nagios translations
- `NetworkPolicy`, `HorizontalPodAutoscaler`, `PodDisruptionBudget`
- Multi-architecture (`arm64`) images
- Migration to Oracle Cloud Always Free

**Hardening**
- ACM certificate / HTTPS on the ALB — needs a domain that is out of scope
- A custom domain
- `aws_ecr_lifecycle_policy` to cap ECR storage growth
- An ArgoCD `AppProject` restricting sources and destinations
- Bringing the monitoring and Jenkins Helm releases under ArgoCD
- `strict-transport-security` on the public page

**Operational**
- The 15-minute "cluster is up" reminder
- Any monitor that survives the laptop sleeping — that is the AWS budget
  guardrail's job, and its ~1-day lag is accepted
- minikube as a supported deploy path — documented as a sandbox only
- Netlify as a deploy target — `netlify.toml` was removed 2026-09-19

**Tooling**
- GitHub Actions or any CI outside the cluster — CI is Jenkins (`R-06`)
- `gh` CLI installation
- Consolidating the 8 repositories into a monorepo

---

## 5. Gap to Finish Line

**This is the only remaining in-scope work.** Anything not on this list is EXTRA.

| # | Gap | Makes it VERIFIED |
|---|---|---|
| **G1** | `P-11` — deploy the always-on host | `docker compose ps` shows **5** services up — `links-service`, `gateway`, `aggregator`, `n8n`, `tailscale` — and the Tailscale hostname serves the dashboard from a non-home network. **Was "4 services" until 2026-09-20**; `G5` added `n8n` to the stack and this criterion was not updated with it, so it would have passed while a service was missing. <br><br>**Offline checks done 2026-09-20** (no cluster, no deploy): the file **parses** under `docker compose config`, resolves to exactly those five services, publishes **no ports at all**, and `n8n_data` resolves to `external: true` — the one property that, if wrong, would start n8n blank and make every stored credential permanently undecryptable. The live `n8n_data` volume exists. *Still not deployed.* |
| **G2** | `P-11` owner prerequisites — scoped IAM user + access key, Tailscale account/ACL/key/expiry, `.env` | The above, working |
| **G3** | `R-06` — apply Jenkins to a live cluster | A build runs green and pushes an image to ECR. **Credentials are no longer a blocker** (2026-09-20): both deploy keys verified at the access level (Jenkins write, ArgoCD read-only), and the admin password is generated and stored outside the cluster at `~/.app-hub/jenkins-admin.env`. `make jenkins-secrets` installs both Secrets and must be re-run after every `make up`. **Only a cluster remains.** |
| **G4** | `R-06` — a **real** test stage (owner's ruling) | The pipeline executes the service's pytest suite and fails the build when a test fails. ***Written 2026-09-20, never executed*** — the `uv` agent container is in `values.yaml` and the Test stage runs `uv sync --frozen && uv run pytest` with `junit allowEmptyResults: false`, but no pipeline has run it. **Same blocker as `G3`: a cluster.** |
| **G5** | `N-06` — n8n on the **always-on host**, re-targeted from EKS 2026-09-20 | The existing instance runs under Compose with its `n8n_data` volume attached, workflows intact and **credentials still decrypting**, reachable tailnet-only on `:8443`. *Written; not yet migrated.* |
| ~~**G6**~~ | ~~`D-24` — cost watchdog proven alive~~ | **DONE 2026-09-19** — `mode=trigger` at 21:00:05 IST after a 06:48→12:19 sleep. Closing condition met. **Residual, recorded not hidden**: the 17:00 trigger was still missed because the restart landed at 17:50/18:32, so firings between a sleep and the next restart are still lost |
| ~~**G7**~~ | ~~`D-25` — teardown notification proven~~ | **DONE 2026-09-22.** Laptop slept `09-20 22:02:32`, Windows woke it at **23:30:38**, Task Scheduler logged the time trigger at **23:30:34**, the teardown ran **23:31→23:32 success** and reported `HTTP 200`. Three independent sources agree, and the ~27-second wake-to-run gap distinguishes a **wake timer** from a catch-up (the `09-17` catch-up took 6 minutes). <br><br>**A separate fault was found in the same evidence and is tracked as `D-31`, not as this gap reopening**: the `09-21` 23:30 trigger never fired while the machine was awake, caught up at `09-22 03:37`, and failed. <br><br>*(was: A ~23:30 teardown log from a night the laptop slept, plus a Power-Troubleshooter wake event at ~23:30 — the log alone is not enough, because Task Scheduler catches up a missed trigger on wake and that looks identical. <br><br>**Half of `D-25` is now PROVEN (2026-09-20)**: both recent 23:30 runs reported `HTTP 200`, including the 09-18 one that **failed with exit 2** — the exact failed-teardown/failed-notification pair the defect was opened for. <br><br>**But this will NOT close by waiting.** Windows' event log shows the laptop was awake at 23:30 on both nights, and every recorded sleep begins between 05:21 and 06:49 — so it is never asleep at the trigger time. **Needs a deliberate test**: shut the lid before 23:30 one evening with the cluster down (free), then check for both signals next morning. |
| ~~**G8**~~ | ~~`README.md:7` three phases stale~~ | **DONE 2026-09-19** — now reads *Phases 1, 2 and 5 complete; 40 of 43 tasks done*, and names the three open tasks |
| ~~**G9**~~ | ~~Remove `netlify.toml` and its `README.md` reference~~ | **DONE 2026-09-19** — file deleted; `README.md`, `CLAUDE.md § 3` and `site/README.md` all corrected to Cloudflare Pages. **Scope was larger than this row claimed**: `site/README.md` was mostly a Netlify runbook and needed rewriting, not a reference swap |
| ~~**G10**~~ | ~~`O8` — console errors unmeasured~~ | **DONE 2026-09-19** — both pages load with **zero console messages of any level** |
| ~~**G11**~~ | ~~`D4` — responsive floor unmeasured~~ | **DONE 2026-09-19** — no page-level horizontal scroll at 360 / 768 / 1280 on either page. The 480px table is contained by `div.table-wrap` (`overflow-x: auto`) |

**Gap size: 5 items** — down from 11. `G8`–`G11` closed on 2026-09-19 after the
unfreeze; **`G6` closed the same evening** when `D-24`'s evidence finally
appeared; **`G7` closed 2026-09-22** when the wake timer fired on its own and
three independent logs agreed.

**What remains, sorted by what actually blocks it.** This line previously read
*"`G1` and `G3`–`G5` are real work needing a cluster"*, and that was wrong about
two of them — corrected 2026-09-20. **Only `G3` and `G4` need EKS.**

| gap | needs a cluster? | blocked on |
|---|---|---|
| `G1` | **no** — Docker Compose on the always-on host | `G2`'s credentials |
| `G2` | **no** | owner-only: IAM user + access key, Tailscale account/ACL/key |
| `G3` | **yes** | a cluster, and nothing else — credentials done 2026-09-20 |
| `G4` | **yes** | a cluster; written, never executed |
| `G5` | **no** — n8n under Compose, re-targeted off EKS | owner's go-ahead: it stops a running n8n and moves a volume holding live credentials |
| ~~`G7`~~ | — | **CLOSED 2026-09-22** — no test needed in the end; the conditions occurred on their own on the night of 09-20 |

**`G1` needing no cluster is not an assumption — its preconditions were checked
on 2026-09-20 and all of them live in the PERSISTENT stack**, which is precisely
why ECR was moved there: three images in each of the three ECR repositories, and
`app-hub-links` `ACTIVE`. Both survive every teardown. The ephemeral stack
contributes nothing to `G1`.

**So three of the five open gaps are reachable with no cluster and no spend** —
`G1`, `G2` and `G5`. All three converge on the same bottleneck: **`G2`'s
credentials**, which only the owner can create. `G5` additionally needs their
go-ahead, because it stops a running n8n and moves a volume holding live
credentials.

**`G7` closed on 2026-09-22 without the deliberate test this document called
for.** The laptop happened to sleep at 22:02 on 09-20 and the wake timer fired at
23:30:38 — so the evidence arrived on its own. **The recommendation was still
right**: it could not have closed by *waiting passively and checking one signal*,
which is what the document said before 2026-09-20. It closed because the check
was defined as **two** signals, and the second one — a wake event at the trigger
minute — is what separates a wake timer from Task Scheduler catching up.

**The same evidence opened two new defects**, `D-31` (a 23:30 trigger silently
skipped while the machine was awake, then caught up four hours late into a
suspend, then failed on WSL DNS) and `D-32` (a stale duplicate task registration
emitting failure-shaped events). **Neither is part of the v1 test**, which names
`D-24` and `D-25` specifically and both of which are now closed. Whether they
should gate v1 is the owner's decision, not something to settle by editing the
test.

**`G7` was described here as closing "by observation", and that was wrong.**
Measured 2026-09-20: the laptop is awake at 23:30 every night in the record, and
every sleep begins between 05:21 and 06:49. Waiting cannot produce the evidence.
It needs **one deliberate test** — lid shut before 23:30, cluster down so it costs
nothing — and the check is two signals, not one: the teardown log *and* a wake
event at ~23:30, because Task Scheduler catching up on wake looks the same in the
log alone.

**`D-30` is RESOLVED (2026-09-20) and `DEP1` now holds on its own.** The cause
was one repository missing from the Cloudflare Pages GitHub App's access list —
not the account OAuth, and not the build configuration, both of which were
correct throughout. Granting access and reconnecting restored Git-triggered
deployments.

**`make deploy-site` is kept anyway**, and not as dead weight: it publishes on
demand and then **asserts against the live bytes**, the 404 behaviour and the
four security headers. Those three assertions are the only reason this was
caught at all — the dashboard reported *"Automatic deployments enabled"* for two
days while nothing deployed.

---

## 6. Recording Mechanism

1. **`FINISH-LINE.md`** — this file, in the root repo. The single source of truth.
2. **`BACKLOG.md`** — root repo. One line per EXTRA: date, description, source.
3. **`CLAUDE.md § 0`** — the post-freeze operating rule, so every future session
   inherits the freeze without being told.
4. **Annotated git tag `v1-scope-locked`** on the freeze commit in the root repo.

**Why this combination:** the root repo is the only place that sees the whole
project, so the line and the backlog belong there; `CLAUDE.md` is the only
artifact every session reads unprompted, which is what makes the rule survive a
fresh session.

**Why the tag is named `v1-scope-locked` and not `v1.0`:** v1 is *defined* here,
not *reached* — eleven gap items remain. A tag reading `v1.0` on this commit
would tell a portfolio reader the project had shipped v1, which is false. The
release tag, if there is one, belongs on the commit that closes `G11`.

**The polyrepo caveat:** a tag in the root captures only the root. § 0 records all
eight HEADs, and that table — not the tag — is what makes the freeze
reconstructable.

---

*Locked 2026-09-19 18:34 IST. v1.0. Signed off by the owner.*
