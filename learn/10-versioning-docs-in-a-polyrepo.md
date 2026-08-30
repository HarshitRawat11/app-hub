# 10 — Versioning shared docs when there is no root repo

## What we did

Turned the `app-hub/` root — previously a plain folder holding four independent git repos — into a fifth **umbrella repository** that tracks only the cross-cutting docs (`CLAUDE.md`, `README.md`, `PROGRESS.md`, `CONTEXT-BRIEF.md`, `learn/`) and deliberately ignores the four component directories. Then wired up remotes and pushed both it and `app-hub-n8n` to GitHub.

## Why

This project is a **polyrepo**: `infra`, `links-service`, `manifests`, and `n8n` are four separate repositories with four separate GitHub remotes. That is a deliberate choice — each component is independently cloneable and independently deployable, and the separate `manifests` repo is what makes GitOps possible later (`R-06`).

The gap it left: **some documents belong to the project, not to any one component.** The operating manual, the status board, the learning folder. They had nowhere to live, so they lived nowhere — sitting in a plain directory, untracked by anything, with no history and no backup.

That was fine when it was three files. It stopped being fine once `learn/` existed. Those files are the most irreplaceable content in the project — the code can be rewritten from the docs far more easily than the explanations can be rewritten from the code. Losing the folder to an accidental `rm -rf` would have been unrecoverable.

## Key concepts

### 1. Polyrepo vs monorepo, and the seam between them

- **Monorepo** — everything in one repository. One commit can change a service and its manifests atomically. One history, one CI config, simple cross-cutting changes.
- **Polyrepo** — one repository per component. Independent versioning, independent access control, independent deploys. Cross-cutting changes take multiple commits in multiple places.

Neither is correct in general. This project is polyrepo, and the cost shows up exactly where you would expect: a change touching `links-service` and `manifests` is **two commits in two repos**, and there is no single revision that represents "the state of app-hub".

The umbrella repo does not fix that — nothing does, short of merging everything. What it fixes is narrower and real: **it gives the project-level documents a home.**

### 2. A repository can ignore directories that are themselves repositories

This is the mechanism that makes the umbrella work:

```gitignore
infra/
links-service/
manifests/
n8n/
```

Git already treats a nested `.git` directory as a boundary — it will not descend into a subdirectory that is its own repo, it would record it as a *gitlink* instead. Explicitly gitignoring them makes the intent unambiguous and keeps `git status` clean.

The result is four component repos that are completely unaware the umbrella exists, and an umbrella that tracks nothing but docs. Verified:

```
infra          ignored by umbrella: YES | own repo intact: true
links-service  ignored by umbrella: YES | own repo intact: true
manifests      ignored by umbrella: YES | own repo intact: true
n8n            ignored by umbrella: YES | own repo intact: true
```

### 3. Why not git submodules

Submodules are the textbook polyrepo answer, and they were rejected. Worth understanding the trade rather than taking it on faith.

A submodule embeds a **pointer to a specific commit** of another repository. `git clone --recursive` then fetches everything at once.

What that buys: one clone gets the whole project, and the umbrella records exactly which commit of each component was current.

What it costs:

- **Every component change becomes two commits.** Change `links-service`, commit there, then commit the updated pointer in the umbrella. Forget the second and the umbrella silently references stale code.
- **Detached HEAD by default.** A freshly-initialised submodule checks out a commit, not a branch. Edit and commit inside it without noticing, and your work is on no branch at all — easy to lose.
- **It fights the model you already have.** The components are meant to be independent. Pinning them to umbrella-blessed commits reintroduces the coupling the polyrepo was avoiding.

Since the alternative is four `git clone` commands, the ceremony is not worth it. **The rule of thumb: reach for submodules when you need reproducible pinning of component versions — a release artifact, a vendored dependency. Not for "I would like these in one folder".**

### 4. Remote, branch, upstream — three different things

```bash
git remote add origin git@github.com:HarshitRawat11/app-hub.git
git push -u origin master
```

- **Remote** (`origin`) — a named URL. Just a bookmark; adding one contacts nothing.
- **Branch** (`master`) — a local pointer to a commit.
- **Upstream** — the link between a local branch and a remote one, which is what `-u` establishes.

Without an upstream, bare `git push` and `git status`'s "ahead/behind" reporting have nothing to compare against. That is exactly the state both repos were in: commits existed locally, GitHub repos existed remotely, and **nothing connected them**. `git remote -v` printed nothing, and it looked like the work had not been done.

**Diagnostic worth remembering:** `git log --oneline @{u}..` lists commits you have that the upstream does not. It errors if no upstream is set — which is itself the answer.

## Walkthrough

```bash
git init -q
git symbolic-ref HEAD refs/heads/master
```

`git init` defaults to `main` on modern git. This project uses `master` everywhere, deliberately, so the branch is set explicitly. On a fresh repo with no commits, `git symbolic-ref` is the way to do it — `git branch -m` needs a commit to rename.

```bash
git config user.name  "Harshit Rawat"
git config user.email "harshitrawat2011@gmail.com"
```

Per-repo, never global. This is a work-managed laptop; global identity stays unset so a personal commit can never silently pick up a work identity (`CLAUDE.md § 3`).

Then `.gitignore` excluding the four component directories, `.gitattributes` with `eol=lf`, and the commit.

Before pushing, two checks that should be habit:

```bash
git ls-remote git@github.com:HarshitRawat11/app-hub.git
```

Confirms the remote repository exists and is reachable, before you configure anything against it. `--exit-code` additionally distinguishes "exists with commits" from "exists but empty".

```bash
git diff --cached | grep -iE '(api[-_]?key|token|secret|password)[^a-z]*[:=]'
```

Scan staged content for secrets **before** the first push. Once something is pushed, deleting it in a later commit does not remove it from history — it has to be rewritten, and if the repo is public you must assume it was scraped.

## Gotchas

- **Creating the GitHub repo is not the same as connecting to it.** Both repos existed and were empty; locally neither had a remote and `n8n` had zero commits. "Done" on the GitHub side and "done" locally are separate states — check `git remote -v` and `git log @{u}..`.
- **`git init` gives you `main`.** Set `master` explicitly here, or the branch names diverge from the rest of the project.
- **Set identity before the first commit in a new repo.** With global identity unset, the commit fails with `fatal: empty ident name`.
- **The umbrella is not a source of truth for component state.** It records docs, not which commit of `infra` is deployed. If you ever need that, submodules become worth reconsidering.
- **Secrets in pushed history are effectively permanent.** Scan before, not after.

## Verify it yourself

Confirm the umbrella tracks only docs, and that the component repos are untouched:

```bash
git -C /c/Users/harshit.rawat/Documents/Projects/app-hub ls-files
```

```bash
for d in infra links-service manifests n8n; do echo "$d: ignored=$(git check-ignore -q $d && echo yes || echo no) ownrepo=$(git -C $d rev-parse --is-inside-work-tree)"; done
```

Check every repo is fully pushed — each should report `0`:

```bash
for d in . infra links-service manifests n8n; do printf "%-14s %s unpushed\n" "$d" "$(git -C $d log --oneline @{u}.. 2>/dev/null | wc -l)"; done
```

Confirm SSH auth to GitHub works at all:

```bash
ssh -T git@github.com
```

Expect `Hi HarshitRawat11! You've successfully authenticated` — GitHub denying shell access is the normal, correct response.

## Going deeper

- [Git submodules](https://git-scm.com/book/en/v2/Git-Tools-Submodules) — read the "Issues with Submodules" section particularly
- [gitignore pattern format](https://git-scm.com/docs/gitignore)
- [Remote branches and upstreams](https://git-scm.com/book/en/v2/Git-Branching-Remote-Branches)
- [Removing sensitive data from a repository](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/removing-sensitive-data-from-a-repository) — the painful process you are avoiding by scanning first

---

**Next:** `learn/11` — configuring AWS credentials, and the two-kubeconfig trap.
