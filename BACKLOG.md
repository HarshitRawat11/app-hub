# BACKLOG.md

Everything classified **EXTRA** under the locked finish line (`FINISH-LINE.md`).

**Format — one line each, nothing more:** `YYYY-MM-DD · description · source`

No estimates, no priorities, no grouping. This is a capture log, not a plan. An
item here is **not** scheduled work; it is a thing that was suggested and
deliberately not done.

Nothing leaves this file and enters scope except by **UNFREEZE** and a new
version of `FINISH-LINE.md`.

---

## Captured

- 2026-09-19 · Add an `aws_ecr_lifecycle_policy` so ECR storage cannot grow unbounded — IMMUTABLE tags plus a git-SHA per build means images only accumulate, and the $3/day budget will not notice cents · Claude
- 2026-09-19 · Restrict the ArgoCD `AppProject` — everything currently uses `default`, which permits any source and any destination · Claude
- 2026-09-19 · Bring the monitoring and Jenkins Helm releases under ArgoCD, which supports Helm sources directly · Claude
- 2026-09-19 · Add `strict-transport-security` to the public page's response headers · Claude
- 2026-09-19 · Register a custom domain (~$10/yr), which would also unblock the ACM certificate that HTTPS on the ALB has been waiting on · Claude
- 2026-09-19 · Prometheus persistence via the EBS CSI addon and a fourth IRSA role · Claude
- 2026-09-19 · A 15-minute recurring reminder while the cluster is up · owner
- 2026-09-19 · Tighten the `argocd` namespace from `baseline` to `restricted` once the first install's admission warnings are read · Claude
