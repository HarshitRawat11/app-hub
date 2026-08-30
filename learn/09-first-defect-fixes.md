# 02 — Fixing the first defects: a storage bug, a lying base image, and two file-hygiene items

## What we did

Cleared six tasks: fixed the `POST /links` storage bug (`C-01`), rewrote the Dockerfile to fix both its Python version mismatch and its container-start install (`P-03`, `D-11`), wrote the service README (`P-06`), renamed `vairables.tf` (`P-04`), removed the empty `main.tf` (`P-05`), and committed the Dockerfile that had been sitting untracked (`P-02`).

Four commits across two repos. `n8n/` was deliberately left uncommitted.

## Why

These were the tasks with no blocker and no decision attached — the ones where the answer was already known and only the doing was left. Clearing them matters because two of them (`P-03`, `D-11`) sat directly in the path of the next image build, and one (`C-01`) meant the service returned wrong data to anything that read from it.

## Key concepts

### 1. A write bug that hides behind a correct-looking response

The bug was one word:

```python
new_link = Link(id=next_id, **link.model_dump())
links_db[next_id] = link          # stored the input, not the constructed object
return new_link                   # returned the constructed object
```

Two Pydantic models exist for a reason. `LinkCreate` is the **request shape** — what a client is allowed to send. `Link` is the **stored/response shape** — what the server owns. The difference is `id`: the client must not choose it, the server assigns it. This split is standard and correct.

The bug stored the request object and returned the server object. So:

- `POST /links` → looked perfect. Response had an `id`.
- `GET /links` → returned records with **no `id`**, because that's what was actually in the dict.

**The lesson generalises well beyond this bug: verifying a write by reading its response only tests the response.** The response was built from a different variable than the one that got stored. To actually verify a write, you have to read it back through a separate path — which is why the check we ran was `POST` followed by `GET`, not `POST` alone.

There's a second reason this stayed invisible: `links_db` is typed `dict[int, Link]`, and a `LinkCreate` was being put in it. Python type hints are **not enforced at runtime** — they're documentation for humans and static checkers. Nothing objected. A type checker like `mypy` or `pyright` would have caught this instantly, at zero runtime cost. That's an argument for adding one later.

### 2. `uv` will paper over a wrong base image

The Dockerfile said `FROM python:3.12-slim`, but `pyproject.toml` says `requires-python = ">=3.14"`.

You'd expect a hard failure. You don't get one — `uv` downloads and uses its own managed Python 3.14 by default when the available interpreter doesn't satisfy the requirement. So the image *built* and *ran*. The damage was subtler:

- The `FROM` tag became a lie — the image says 3.12, the app runs on 3.14.
- The image carried **two Python installations**, one unused.
- The behaviour depended on `uv`'s download policy, which is configuration, not a guarantee.

Fixed by moving the base to `python:3.14-slim` (verified to exist — currently 3.14.7). **The principle: the base image should satisfy the project's own constraints, so the tag tells the truth about what runs.**

### 3. Build-time work vs. container-start work

The old final line was:

```dockerfile
CMD ["uv", "run", "uvicorn", "app.main:app", ...]
```

`uv run` is not just "run this command". It first ensures the environment is in sync — resolving and installing as needed. At `CMD`, that means it happens **every time a container starts**, which:

- Undoes the build-time `uv sync` the image already paid for.
- Adds latency to every pod start, delaying readiness-probe success.
- Converts a *build* failure into a *runtime* failure. A missing dependency should break your build, where you're watching. Not your 3 a.m. pod restart.

The fix puts the virtualenv on `PATH` and calls `uvicorn` directly:

```dockerfile
ENV PATH="/app/.venv/bin:$PATH"
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
```

**Mental model: a container image should be finished at build time. Starting it should start the app, not build it.**

### 4. Why dependencies are copied before source

This ordering is deliberate and is the main reason Docker builds stay fast:

```dockerfile
COPY pyproject.toml uv.lock ./     # rarely changes
RUN uv sync --frozen --no-install-project
COPY app/ ./app/                   # changes constantly
```

Docker caches each instruction as a layer and reuses it while its inputs are unchanged. Dependencies change rarely; app code changes every commit. With this order, editing `main.py` invalidates only the last layers — the dependency install is reused. Reverse the two and every one-character code edit re-resolves the whole dependency tree.

`--frozen` is the reproducibility guarantee: fail if `uv.lock` is stale rather than silently resolving something new. A build that quietly picks different versions than the lockfile isn't reproducible.

`--no-install-project` installs dependencies but not the project itself. That's correct here because `pyproject.toml` has no `[build-system]` section, so this isn't an installable package — it runs from source, which is why `app/` is simply copied in.

### 5. Terraform loads every `.tf` file — names are for humans

`vairables.tf` was a typo, and it changed nothing functionally. Terraform reads **all** `.tf` files in the directory and merges them; the filenames and their order are irrelevant to the parser. `main.tf` isn't special either — it's a convention, not a requirement, which is why deleting an empty one is safe.

So this was purely a readability fix. `terraform validate` before and after confirms it.

### 6. `git mv` preserves rename detection

Using `git mv` rather than a filesystem rename plus `git add` gives:

```
R  vairables.tf -> variables.tf
```

`R` for rename, not `D` + `A` for delete-and-add. Git actually detects renames by content similarity at diff time, so both approaches usually produce the same result — but staging it as a rename makes the history unambiguous and keeps `git log --follow` working cleanly.

## Gotchas

- **Three of the four repos had no git identity set.** `links-service` had a name but no email; `manifests` and `n8n` had neither; global was unset. The first commit in any of them would have failed with `fatal: empty ident name`. Because this is a work-managed laptop, identity is deliberately set **per repo** rather than globally, so a personal commit can never pick up a work identity by accident. Set both `user.name` and `user.email` locally *before* the first commit in any new repo.
- **`git status` warns about CRLF in `links-service`.** That repo has no `.gitattributes`. It's harmless for Python and for exec-form `CMD`, but it's the same trap that would break a shell script — see `learn/08` for the failure mode. Logged as `D-12`.
- **Fixing `C-01` does not make the service correct.** Data still lives in an in-process dict while the Deployment runs 2 replicas (`C-03` / `D-02`). The record now has its `id`; it's still lost on restart and still invisible to the other pod.

## Verify it yourself

Run the service (from WSL, where `uv` lives) and check that a written record reads back **with** its id:

```bash
wsl -e bash -lc "cd /mnt/c/Users/harshit.rawat/Documents/Projects/app-hub/links-service && uv run uvicorn app.main:app --port 8021"
```

Then, in another shell:

```bash
curl -s -X POST localhost:8021/links -H "Content-Type: application/json" -d '{"name":"Grafana","url":"https://grafana.local","category":"ops"}' && echo && curl -s localhost:8021/links
```

Both responses should contain `"id":1`. Before the fix, the second one did not.

Confirm the Terraform rename broke nothing:

```bash
wsl -e bash -lc "cd /mnt/c/Users/harshit.rawat/Documents/Projects/app-hub/infra && terraform fmt -check -recursive . && terraform validate"
```

Check the commits landed where you expect:

```bash
git -C links-service log --oneline -3 && git -C infra log --oneline -1
```

## Going deeper

- [Pydantic models for request vs. response](https://fastapi.tiangolo.com/tutorial/response-model/) — FastAPI's `response_model`, which would enforce the shape and catch this class of bug at the framework level
- [uv Docker integration guide](https://docs.astral.sh/uv/guides/integration/docker/) — the recommended image patterns, including multi-stage builds
- [uv Python version resolution](https://docs.astral.sh/uv/concepts/python-versions/) — how and when uv downloads a managed interpreter
- [Docker layer caching](https://docs.docker.com/build/cache/) — what invalidates a layer and why ordering matters
- [gitattributes: end-of-line conversion](https://git-scm.com/docs/gitattributes#_end_of_line_conversion)

---

**Next step:** `C-02` (tests) is the natural follow-on, and it is a **new concept for this project — no tests exist anywhere yet**. Per `CLAUDE.md § 2`, that first test file is yours to write by hand. See the handover notes in `PROGRESS.md`.
