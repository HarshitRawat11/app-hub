# 21 — `gateway`: when your service becomes a client

> **This is a guide, not a record.** `S-01` is the owner's to build by hand (`CLAUDE.md § 2`).
> It explains the mechanism *before* implementation, so the concepts are met head-on rather
> than reverse-engineered from finished code. Written 2026-09-05, before any code exists.

## What you are building

`gateway` — a service that receives external requests and forwards them to `links-service`
over the network. It is the next core-app task in the roadmap (phase 0b).

## Why

**The product reason:** right now `links-service` is exposed directly. Add `aggregator` and a
`frontend` and you would have three public endpoints, three places to add authentication,
three CORS configurations. A gateway is **one front door** — external traffic arrives at one
place, internal services stop being publicly reachable at all.

**The reason it earns its place here:** every service in this project must teach something
distinct. `gateway` proves that **one pod can reach another by Kubernetes DNS name.** That
claim underpins the whole architecture and is currently only demonstrated by a disposable
`curl` pod (`learn/16`). `gateway` turns it into a real, running dependency.

## Key concepts

### 1. Server *and* client

`links-service` is purely a **server**: a request arrives, it answers from an in-memory dict,
done. It waits on nothing.

`gateway` is both. It receives a request, then **makes its own outbound HTTP request**, waits
for the answer, and shapes that into its response.

That is the genuinely new idea. Not "routing" — **outbound calls from inside a handler.**
Everything else below follows from it.

### 2. `async def` vs `def`, and the trap between them

FastAPI accepts both handler styles, and they are not interchangeable once the network is
involved.

```python
def handler():        # sync -- FastAPI runs it in a threadpool
async def handler():  # async -- runs directly on the event loop
```

`links-service` uses plain `def`. Correct, because it never waits: reading a dict is
instant, and the threadpool is never under pressure.

`gateway` waits on the network, so the combination matters:

| Handler | HTTP library | What happens |
|---|---|---|
| `def` | `requests` | Works. Each in-flight request holds a thread while waiting. Threadpool is finite. |
| `async def` | `httpx.AsyncClient` | **Correct.** While awaiting, the event loop serves other requests. |
| `async def` | `requests` | **Disaster.** A blocking call inside a coroutine freezes the entire event loop — *every* request stalls, not just this one. |

The third row is the trap. It looks reasonable, works in a single-request test, and collapses
the moment two people use it at once. The symptom is baffling: the service appears to hang
under trivial load.

**Mental model:** the event loop is a single worker handling many conversations by switching
whenever one is waiting. `await` is how you say "I am waiting, go serve someone else." A
blocking library never says it, so the worker sits idle holding everyone up.

Use `async def` with `httpx.AsyncClient`. You already have `httpx` in `links-service` as a
test dependency, so it is familiar.

### 3. The HTTP client should outlive the request

The instinct is to create the client inside the handler:

```python
async def get_links():
    async with httpx.AsyncClient() as client:   # a fresh TCP connection every request
        ...
```

That works and is wasteful. Every request pays for a new TCP handshake — plus TLS
negotiation once anything is encrypted.

**Create one client at application startup and reuse it**, so connections are pooled and
kept alive. FastAPI's `lifespan` is the mechanism: "run this on startup, run that on
shutdown." Look up `contextlib.asynccontextmanager` and FastAPI's `lifespan=` parameter when
you reach this step.

The general principle: **anything expensive to create and safe to share belongs at
application scope, not request scope.** Database connection pools follow the same rule.

### 4. The address is configuration, not code

```python
LINKS_SERVICE_URL = os.getenv("LINKS_SERVICE_URL", "http://localhost:8000")
```

Locally `links-service` is at `http://localhost:8000`. In the cluster it is
`http://links-service:8000` (same namespace) or
`http://links-service.app-hub.svc.cluster.local:8000` (fully qualified).

**Hardcode either one and the other becomes impossible.** Hardcode the DNS name and you
cannot run gateway on your laptop at all.

The default matters as much as the variable: with it, local development needs zero
configuration; in the cluster the Deployment's `env:` block overrides it. **Same image, same
code, different environment** — which is the whole point of building a container once and
promoting it.

This is [twelve-factor config](https://12factor.net/config): anything that varies between
environments is config; anything that does not is code.

### 5. Failure modes — the part that makes this harder than `links-service`

`links-service` has no dependencies. It is up or it is down.

`gateway` can be perfectly healthy while the thing it depends on is broken. Three decisions
follow, and skipping them is how a gateway becomes worse than no gateway.

**Set an explicit timeout.** `httpx` does not always default to a short one. Without it a
hung upstream hangs your handler indefinitely, holding a connection. Enough of those and
your readiness probe fails, Kubernetes restarts the pod, and the incident looks like
*gateway* is broken — sending you to debug the wrong service.

**Return the right status code.** If `links-service` fails, returning `500` claims *you*
failed. These codes exist specifically for proxies:

| Situation | Code | Means |
|---|---|---|
| Upstream returned an error | `502 Bad Gateway` | I am fine; what I depend on is not |
| Upstream unreachable | `503 Service Unavailable` | Cannot reach it at all |
| Upstream too slow | `504 Gateway Timeout` | Gave up waiting |

Using them correctly means the status code alone tells you which service to look at.

**`/health` must not check the upstream.** It is tempting to make gateway's health endpoint
verify `links-service`. Do not. If `links-service` goes down, gateway's **liveness** probe
would fail and Kubernetes would kill gateway too — one broken service becomes two, and the
restarts obscure the real cause.

`/health` answers *"am I alive?"* — not *"is everything alive?"* If you later want a
dependency-aware check, that belongs on a **readiness** probe, or a separate `/ready`
endpoint, precisely because readiness removes a pod from load balancing without killing it.

### 6. Namespaces and DNS names

From `learn/07`: a Service gets a DNS name. The short form works **within a namespace**:

```
http://links-service:8000                            # same namespace only
http://links-service.app-hub.svc.cluster.local:8000  # from anywhere in the cluster
```

`links-service` now lives in the `app-hub` namespace (`R-04`). If `gateway` deploys into the
same namespace, the short name resolves. If it lands in `default`, it will not — and the
error is a DNS resolution failure that reads like a network problem.

## Suggested build order

Six steps, each teaching one thing. **Do not collapse them** — the whole value is meeting one
new idea at a time.

| Step | Do | What it teaches |
|---|---|---|
| 1 | `uv init gateway`, a single `/health`, run on **8001** | project skeleton; two services side by side |
| 2 | Add `httpx`, one endpoint that calls `links-service` on 8000 | outbound calls, `async def` |
| 3 | **Stop `links-service`**, hit gateway again | the real failure; then add timeout + 502/503 |
| 4 | Move the URL into `LINKS_SERVICE_URL` | the config boundary |
| 5 | Dockerfile — copy the `links-service` one | nothing new, deliberately |
| 6 | Manifests + deploy to EKS | the `env:` block; DNS discovery proven |

**Step 3 is the one not to skip.** Breaking it deliberately, while calm, is the only way to
find out what your error handling actually does. If you first discover it during a real
outage you are debugging two things at once.

Steps 1–5 need **no cluster and no AWS**. Only step 6 costs money.

## Gotchas

- **`async def` + a blocking HTTP library freezes the whole event loop.** The single worst
  mistake available here, and it passes a casual test.
- **No timeout means an indefinite hang**, which surfaces as gateway being restarted rather
  than the upstream being down.
- **A hardcoded URL makes one of the two environments impossible.**
- **`/health` that checks the upstream turns one outage into two.**
- **The short DNS name only resolves within the same namespace.**
- **Creating an `AsyncClient` per request** silently discards connection pooling.
- **Two local services need two ports.** `links-service` owns 8000; give gateway 8001.

## Verify it yourself

With both running locally — `links-service` on 8000, `gateway` on 8001:

```bash
curl -s localhost:8001/health
curl -s localhost:8001/links
```

The second should return what `links-service` returns. Then the important test — stop
`links-service` and repeat:

```bash
curl -s -o /dev/null -w "%{http_code}\n" localhost:8001/links
```

Expect `502` or `503`, **quickly**. If it hangs, your timeout is missing. If it returns
`500`, gateway is claiming a failure that is not its own.

Later, in the cluster, the claim this service exists to prove:

```bash
kubectl -n app-hub exec deploy/gateway -- curl -sS http://links-service:8000/health
```

## Going deeper

- [FastAPI async](https://fastapi.tiangolo.com/async/) — when `def` beats `async def`
- [FastAPI lifespan events](https://fastapi.tiangolo.com/advanced/events/) — for the shared client
- [httpx async client](https://www.python-httpx.org/async/) and
  [timeouts](https://www.python-httpx.org/advanced/timeouts/)
- [Twelve-factor config](https://12factor.net/config)
- [Kubernetes DNS for Services](https://kubernetes.io/docs/concepts/services-networking/dns-pod-service/)

---

**Ask before writing** if any of the above is unclear — particularly `async`/`await` and the
lifespan client. That conversation is the point, not the file that results from it.
