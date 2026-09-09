# 22 — `gateway`: config boundary and container · *delegated, short note*

> **Short note, not a full walkthrough** (`CLAUDE.md § 2`). Steps 4 and 5 of the
> `gateway` build order were written by Claude. Steps 1–3 were hand-written — the
> `async`/`await` and error-handling concepts live in `learn/21`.

## What it does

Two changes to `gateway`, plus one test fixture.

**Step 4 — the address became configuration.** `gateway` had `http://localhost:8000` hardcoded in the handler. It now reads:

```python
LINKS_SERVICE_URL = os.getenv("LINKS_SERVICE_URL", "http://localhost:8000").rstrip("/")
```

and builds the URL as `f"{LINKS_SERVICE_URL}/links"`. Same change also removed `detail=str(e)` from the `503`/`504` handlers — those now return fixed strings and log the real exception instead.

**Step 5 — the Dockerfile.** Near-identical to `links-service/Dockerfile`, with port `8001`, plus a `.dockerignore` that neither service had.

## Why it is this way

**The default matters as much as the variable.** Locally `links-service` is at `http://localhost:8000`; in the cluster it is `http://links-service:8000`. Hardcode either and the other becomes impossible — hardcode the DNS name and `gateway` will not start on a laptop at all. With the default present, local development needs zero configuration, and the Deployment's `env:` block supplies the cluster value. **Same image, same bytes, different behaviour** — which is the entire reason to build a container once and promote it rather than rebuilding per environment. This is [twelve-factor config](https://12factor.net/config): what varies between environments is config, what does not is code.

**Read once at module scope, not per request.** The obvious reason is efficiency, but the real one is debuggability: read at import time, the value is fixed for the life of the process, so *"which URL is this pod using?"* has exactly one answer, decided before any traffic arrives. Read per request, two concurrent requests could legitimately disagree.

**`.rstrip("/")` removes a whole class of bug.** If anyone ever sets `LINKS_SERVICE_URL=http://links-service:8000/`, the f-string yields `...8000//links`. Some servers tolerate it, some `404`, and it is miserable to debug because the URL *looks* right in every log line.

**`str(e)` was an information leak.** httpx includes the attempted URL in its message. Locally that is `http://localhost:8000/links` — harmless. In the cluster it becomes `http://links-service:8000/links`, which means anyone curling the public endpoint gets handed the internal service topology. The caller needs to know *that* the upstream failed, not *where* it lives.

**The Dockerfile is a deliberate copy.** Those concepts were learned once in `learn/02` and `learn/19` — base image satisfying `requires-python`, `uv sync --frozen`, layer ordering, non-root uid 10001, `PYTHONDONTWRITEBYTECODE` as what makes `readOnlyRootFilesystem` viable. Rewriting them from scratch here would teach nothing and only risk a fresh mistake. **Only the port differs.**

One line does earn extra weight in this service specifically: `PYTHONUNBUFFERED=1`. `gateway` deliberately logs the upstream errors that the caller never sees, so a buffered log would be a debugging dead end.

## The one thing to know

**Inside the container, `localhost:8000` is the container's own localhost — not your machine's.** So a containerised `gateway` with the default config cannot reach a `links-service` running on the host. It returns `503`, correctly, and that is *not* a bug in either service.

This is why step 5's verification has to be done in two parts. `--read-only` proves the container runs under the constraint the Deployment will enforce:

```bash
docker.exe run --rm --read-only -p 8001:8001 gateway:local
```

But proving the two services actually talk needs them on a shared network, addressed **by name** — which also happens to rehearse step 6's whole claim, locally and for free:

```bash
docker.exe network create app-hub-test
docker.exe run -d --name ls-test --network app-hub-test --network-alias links-service --read-only links-service:local
docker.exe run -d --name gw-test --network app-hub-test --read-only -p 8001:8001 \
  -e LINKS_SERVICE_URL=http://links-service:8000 gateway:local
curl -s localhost:8001/links
```

That returned the seeded record through `gateway`, both containers read-only and non-root. **The Kubernetes version differs only in who provides the DNS name** — a Service instead of a Docker network alias. Worth knowing that you can de-risk an EKS deploy on a laptop before paying for the cluster.

Second thing, smaller: **a `.dockerignore` is about the build context, not the image.** The `COPY` lines here are specific, so `.venv` could never reach the image anyway — but the whole directory is tar'd and shipped to the Docker daemon before the build starts regardless. That was 17 MB of `.venv` on every build. It is also a safety net for the day someone writes `COPY . .`. `links-service` had none either; it got the same file the same day (`D-14`, resolved).

## Verify it yourself

Config boundary, both directions — the second is the one that proves anything:

```bash
cd gateway && uv run uvicorn app.main:app --port 8001          # expect 200 against a live links-service
LINKS_SERVICE_URL=http://localhost:9999 uv run uvicorn app.main:app --port 8001   # expect 503
```

A `200` in the second case means the variable is being *declared* but not *read*, and you would next discover that in the cluster as a DNS failure that reads like a network fault.

The `502` and `504` paths need a misbehaving upstream — `gateway/tests/fake_upstream.py` provides one:

```bash
python3 tests/fake_upstream.py 8002 404     # then point LINKS_SERVICE_URL at :8002, expect 502
python3 tests/fake_upstream.py 8003 slow    # expect 504 at ~3s
```

Note that this got easier *because* of step 4: with a configurable address you no longer have to stop the real `links-service` to test its failure modes. **The config boundary made its own tests simpler** — a small illustration of why the seam is worth having.
