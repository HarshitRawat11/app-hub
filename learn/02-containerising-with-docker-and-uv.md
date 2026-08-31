# 02 — Containerising the service with Docker and uv

> **Backfilled.** Written from the committed `Dockerfile`. It describes the file **as it stands now**, after the two defects found in the 2026-08-30 audit were fixed (`learn/09`). Where the original differed, that is called out.

## What we did

Wrote a `Dockerfile` that packages `links-service` into an image: a Python 3.14 base, `uv` copied in from its official image, dependencies installed in a cached layer, application code copied on top, and `uvicorn` as the entrypoint.

## Why

Kubernetes does not run Python projects. It runs **containers**. So before anything can reach EKS, the service has to become an image: a self-contained filesystem with the interpreter, the dependencies, and the code, that starts the same way every time on any machine.

This is also the step that makes "works on my machine" go away for real. The image carries its own Python — the host's Python version becomes irrelevant.

## Key concepts

### 1. An image is a stack of layers, and layers are cached

Each instruction in a Dockerfile produces a **layer** — a filesystem diff. Docker caches layers and reuses them as long as their inputs are unchanged. Change one instruction and that layer plus **every layer after it** is rebuilt.

This single fact drives the entire structure of the file:

```dockerfile
COPY pyproject.toml uv.lock ./     # changes rarely
RUN uv sync --frozen --no-install-project
COPY app/ ./app/                   # changes every commit
```

Dependencies are copied and installed *before* the application code. Editing `main.py` invalidates only the last layers, so the dependency install is reused and the rebuild takes seconds.

Reverse those two blocks and every one-character code change re-downloads and reinstalls every dependency. **Order your Dockerfile from least-frequently-changed to most-frequently-changed.** That is the whole trick.

### 2. Copying a binary out of another image

```dockerfile
COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /bin/
```

`COPY --from=<image>` pulls files directly out of another image without running it. Here it lifts the `uv` binaries out of Astral's published image.

Why not `pip install uv`? Because that would put `uv` **inside the application's Python environment**, mixing a build tool into the runtime dependency tree. Copying the binary keeps them completely separate — `uv` is a tool that happens to be present, not a dependency of your app.

> **Improvement worth making:** `:latest` is not reproducible. Two builds a month apart could get different `uv` versions. Pinning to a specific tag would be strictly better.

### 3. The base image must satisfy your own constraints

```dockerfile
FROM python:3.14-slim
```

`pyproject.toml` declares `requires-python = ">=3.14"`, so the base must provide 3.14.

**The original said `python:3.12-slim`, and it still worked — which is the interesting part.** `uv` noticed the interpreter did not satisfy the requirement and quietly downloaded its own managed Python 3.14. The build succeeded and the app ran. The damage was subtle:

- The `FROM` tag was a lie — the image claimed 3.12, the app ran on 3.14
- The image shipped **two Python installations**, one unused
- Behaviour depended on `uv`'s download policy, which is configuration and could change

**The principle: the base image should satisfy the project's declared constraints, so the tag tells the truth about what runs.**

`-slim` is a Debian-based variant with docs, man pages, and build toolchain stripped out — a few hundred MB smaller than the default tag, without the sharp edges of `alpine` (which uses musl libc and can break Python wheels that expect glibc).

### 4. `--frozen` is the reproducibility guarantee

```dockerfile
RUN uv sync --frozen --no-install-project
```

`--frozen` means: install exactly what `uv.lock` says, and **fail if the lockfile is out of date** rather than silently re-resolving. Without it, a build could quietly pick versions the lockfile never blessed, and your image would not match what you tested.

`--no-install-project` installs the dependencies but not the project itself. That is correct here because `pyproject.toml` has no `[build-system]` section, so this is not an installable package — it runs from source, which is why `app/` is simply copied in.

### 5. A container should *start* the app, not *build* it

```dockerfile
ENV PATH="/app/.venv/bin:$PATH"
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
```

`uv sync` creates a virtualenv at `/app/.venv`. Putting its `bin/` first on `PATH` means a bare `uvicorn` resolves to the venv's copy.

**The original `CMD` was `["uv", "run", "uvicorn", ...]`, and that was a real defect.** `uv run` does not just run a command — it first ensures the environment is in sync, resolving and installing as needed. At `CMD` that happens **every time a container starts**, which:

- Undoes the build-time `uv sync` the image already paid for
- Adds latency to every pod start, delaying readiness-probe success
- **Converts a build failure into a runtime failure.** A missing dependency should break your build, where you are watching — not a pod restart at 3 a.m.

**Mental model: the image should be finished at build time. Starting it should start the app.**

### 6. `0.0.0.0` is a bind address, not a destination

```dockerfile
CMD [..., "--host", "0.0.0.0", ...]
```

This means "listen on all network interfaces". By default uvicorn binds `127.0.0.1` — loopback only — which inside a container means *nothing outside the container can reach it*, including Docker's port forwarding. Binding `0.0.0.0` is what makes `-p 8000:8000` work.

It is **not** an address you browse to. Reach the container at `localhost:8000`.

### 7. `EXPOSE` is documentation

```dockerfile
EXPOSE 8000
```

This does not publish anything or open a port. It records the port as image metadata, for humans and for tools like `docker run -P`. Actual publishing is `-p 8000:8000` at run time. Leaving `EXPOSE` out changes nothing functionally — but it is how the image tells you where to look.

## Walkthrough

Reading the finished file top to bottom, in dependency order:

1. `FROM python:3.14-slim` — the base filesystem, with an interpreter matching `requires-python`
2. `COPY --from=...uv...` — build tooling, kept out of the app's environment
3. `WORKDIR /app` — every later relative path resolves against this, and it becomes the container's starting directory
4. `COPY pyproject.toml uv.lock ./` — the two files that decide the dependency set
5. `RUN uv sync --frozen --no-install-project` — the expensive step, in its own cacheable layer
6. `COPY app/ ./app/` — the volatile part, deliberately last
7. `ENV PATH=...` — makes the venv's binaries the default
8. `EXPOSE 8000` — metadata
9. `CMD [...]` — the process that runs, in exec form

**Exec form vs shell form:** `CMD ["uvicorn", ...]` (a JSON array) runs the binary directly as PID 1. `CMD uvicorn ...` (a bare string) wraps it in `/bin/sh -c`, which makes the shell PID 1 and can swallow signals — so `docker stop` and Kubernetes pod termination may not reach your app, and you wait for the 10-second kill timeout on every shutdown. **Always use exec form.**

## Gotchas

- **Docker runs on Windows, but you can drive it from WSL.** WSL's native `/usr/bin/docker` fails with `Input/output error` — there is no Linux daemon. Use **`docker.exe`**, which WSL interop resolves to the Docker Desktop binary; `/mnt/c/...` build contexts work fine. This means one WSL shell can run `uv`, `terraform`, `kubectl` *and* `docker.exe`, instead of hopping between two shells. Verified 2026-08-30 with a full build of this image.
- **`.dockerignore` does not exist here.** The build context is the whole `links-service/` directory, so `.git`, `.venv`, and `__pycache__` all get sent to the daemon. Harmless at this size, wasteful later. Worth adding.
- **The image runs as root.** No `USER` instruction. Tracked as `R-02`.
- **`:latest` on the uv image is unpinned** — a reproducibility hole in an otherwise carefully pinned build.
- **A stale `uv.lock` fails the build, by design.** If you edit `pyproject.toml` and forget `uv lock`, `--frozen` stops you. That error is the feature working.

## Verify it yourself

Build (from Windows, where Docker lives):

```bash
docker build -t links-service:dev ./links-service
```

Run it:

```bash
docker run --rm -p 8000:8000 links-service:dev
```

```bash
curl -s localhost:8000/health
```

Prove the layer cache works — touch a source file and rebuild; the dependency layers should say `CACHED`:

```bash
touch links-service/app/main.py && docker build -t links-service:dev ./links-service
```

Confirm the interpreter matches what `pyproject.toml` asked for:

```bash
docker run --rm links-service:dev python --version
```

Inspect the layers and their sizes:

```bash
docker history links-service:dev
```

## Going deeper

- [uv Docker integration guide](https://docs.astral.sh/uv/guides/integration/docker/) — including multi-stage builds, the next refinement
- [Docker build cache](https://docs.docker.com/build/cache/) — what invalidates a layer
- [Dockerfile reference: CMD](https://docs.docker.com/reference/dockerfile/#cmd) — exec vs shell form and PID 1 signal handling
- [`.dockerignore`](https://docs.docker.com/build/concepts/context/#dockerignore-files)

---

**Next:** `learn/03` — Terraform, and where the cluster's state lives.
