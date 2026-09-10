# 25 — Documentation that rots, and checking the part that can be checked · *delegated, short note*

> **Short note** (`CLAUDE.md § 2`). Claude wrote this. It came out of being asked
> three times whether any no-cluster work remained, saying "no" twice, and being
> wrong twice.

## What it does

A sweep of every repo for documentation that had drifted from reality, plus one new tool.

**`scripts/check-doc-drift.py`** — `CONTEXT-BRIEF.md` reproduces source files verbatim so a Claude chat session with no filesystem access can still see them. The script compares each embedded block against the real file, fails `make validate` on a mismatch, and rewrites the blocks from source with `--fix`.

**Two READMEs written from nothing:** `infra/` and `manifests/` had none at all.

**Fixed, having been verified stale:**

| Where | Was |
|---|---|
| `CONTEXT-BRIEF.md` | embedded `links-service/app/main.py` with `getLinks` / `createLink` — **renamed the day before**; also "no tests are written yet" (14 exist), `destroy-notifier` "🚧 needs the IF node" (done and verified), `manifests/` described as three files in one directory |
| root `README.md` line 196 | *"The Service is `ClusterIP`, so nothing is reachable from outside"* — `LoadBalancer` since `E-05`. **Line 75 of the same file said `LoadBalancer`.** |
| root `README.md` | two `kubectl` commands with no `-n app-hub`; the apply sequence no longer created the namespace; layout tree and Makefile table both behind |
| `links-service/README.md` | `replicas: 2` "live today" (pinned to 1 for eleven days); `C-03` "needs a decision" (decided the same day) |
| `manifests/links-service/deployment.yaml` | image tag `:v1` — predates immutable SHA tags and was deleted from ECR at teardown |
| `gateway/` | empty `README.md`, scaffold `description`, no `app/__init__.py` |

## Why it is this way

**The pattern, which is the actual lesson:** documentation that *describes* something rots every time the something changes, and nothing notices. This project has now hit it five times — `timeline.sh` silently dropping every repo's root commit, `D-12` sitting closed-but-open for a fortnight, `links-service/README.md` claiming a replica count that changed eleven days earlier, and `CONTEXT-BRIEF.md` shipping code renamed the previous day.

Every one of those failed **silently and optimistically**: the doc looked fine, the numbers looked plausible, and the only way to find out was to compare two things that were supposed to agree.

**So the fix has two halves, and the split matters:**

- **Where the duplication is mechanical, check it mechanically.** A verbatim copy of a file either matches or it does not. That is what the new script does, and `--fix` means the correct response to a failure is one command rather than a manual re-copy.
- **Where the fact is prose, delete the fact instead of checking it.** `CONTEXT-BRIEF.md` used to say *"There are 22 files"* in `learn/`. There were 24. The right fix is not a file-counting test — it is to stop asserting a number that has to be maintained. **Prefer removing a rotting fact over building a checker for it.**

**Why the image tags became `:PLACEHOLDER`.** `links-service` carried `:v1`, which looked like a real tag and was not — `R-03` moved to immutable SHA tags, and `:v1` was deleted from ECR at the last teardown. So a direct `kubectl apply` would fail either way; the question was only whether it failed *understandably*. An obviously-invalid tag does. This also surfaced a real prerequisite for `R-07`: **ArgoCD applies the manifests repo verbatim** — no build, no `sed` — so GitOps cannot work until `make deploy` has run and committed real tags.

## The one thing to know

**A validation tool is only worth what it is wired into.**

`scripts/validate-manifests.py` has existed since 2026-09-03 and was genuinely useful. The `links-service` test suite existed for a day before anything ran it. Both were one `make` target away from being automatic and neither was, so both depended on someone remembering.

`make validate` now runs the drift check, the manifest checks and both Terraform stacks; `make test` runs both suites. The rule worth keeping: **when you write a check, wire it into the thing that runs checks in the same commit** — otherwise you have written documentation of an intention.

Second thing: the drift checker deliberately ignores anything without an `<!-- embed: path -->` marker, so illustrative snippets and prose are untouched. Scope a checker to what it can be certain about; a checker that produces false positives gets switched off.

## Verify it yourself

```bash
make validate
```

To watch it work, break an embedded block on purpose — edit any line inside the fenced block after `<!-- embed: links-service/app/main.py -->` in `CONTEXT-BRIEF.md` and run:

```bash
python3 scripts/check-doc-drift.py
```

It names the file, the first differing line, and both versions of it. Then:

```bash
python3 scripts/check-doc-drift.py --fix
```
