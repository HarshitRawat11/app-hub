# 24 — Testing a proxy, and writing step 6 before the cluster exists · *delegated, short note*

> **Short note** (`CLAUDE.md § 2`). Claude wrote all of this. It covers the free
> half of `S-01` step 6 plus the gateway test suite.

## What it does

**`gateway` got 15 tests** (`gateway/tests/test_gateway.py`). `links-service` is never started — every upstream response is faked. `make test` now runs both suites, 29 tests total, from the repo root.

**Step 6's artifacts were written and validated without a cluster:**

- `infra/ecr.tf` — a second ECR repository, `app-hub/gateway`
- `manifests/gateway/deployment.yaml` and `service.yaml`
- `manifests/00-namespace.yaml` moved up out of `manifests/links-service/`
- the `Makefile` generalised from one service to a `SERVICES` list

Nothing was applied. No cluster, no ECR repository, no cost.

Also filled two gaps the new repo had inherited: `gateway/README.md` was empty and `pyproject.toml` still said `"Add your description here"` — the same defects as `D-08` and `D-09`, which were fixed for `links-service` and never re-checked for `gateway`.

## Why it is this way

**`httpx.MockTransport` rather than a running upstream.** It replaces the transport layer *underneath* the real `AsyncClient`, so the client, the `await`, the timeout configuration and the exception handling are all the genuine article while nothing touches a socket. That is what makes the `502` and `504` branches testable at all — previously they needed `tests/fake_upstream.py` on a spare port, which is fine for a one-off check and useless in CI.

Four of the tests are worth knowing about individually:

- **The `504` test also proves the `except` clauses are ordered correctly.** `httpx.TimeoutException` subclasses `httpx.RequestError`, so putting the general one first silently swallows timeouts — you get a `503` and never see a `504`, in tests or in production.
- **The non-JSON-body test guards an ordering, not a value.** An upstream `500` with an HTML body once produced a `500` from gateway — not from the error handling but from `.json()` raising `JSONDecodeError` on `<html>`. Right answer, wrong reason, and it hid the missing `502` completely. If the status check ever moves below `.json()`, that test fails.
- **The leak test asserts on absence.** No error body may contain `localhost`, `links-service:8000`, `http://` or `8000`. httpx puts the attempted URL in its exception message, and passing `str(e)` through as `detail` handed internal topology to anyone curling the public endpoint.
- **`test_health_does_not_depend_on_the_upstream` is the most important one.** It holds the upstream hard down, confirms `/links` really returns `503`, then requires `/health` to still be `200`. That is a design decision made executable: `/health` backs the liveness probe, so if it checked `links-service` then `links-service` going down would get *gateway* killed and restarted too.

**`replicas: 2` for gateway, where `links-service` is pinned to 1.** The difference is **state, not importance**. `links-service` holds records in an in-process dict, so a second replica would hold independent data and the Service would load-balance between them at random. `gateway` holds nothing — every request is answered from upstream — so a second replica is free redundancy. The `AsyncClient` on `app.state` is a connection pool, not shared state; each pod having its own is the point.

**`gateway`'s Service is `ClusterIP`, which looks wrong.** It is the front door, so surely it should have the load balancer? Eventually. But `links-service` already has a `LoadBalancer` from `E-05`, and giving gateway one too means **two ELBs and two bills** on a cluster that is destroyed nightly. The correct end state inverts today's setup — gateway public via a shared ALB, `links-service` `ClusterIP` and not externally reachable at all — which is precisely what `E-06` is for. Flipping `links-service` now would also remove the public endpoint `E-05` verified. So this commit adds no cost and leaves the decision deliberate. Until then, `kubectl port-forward` reaches gateway for free.

**The namespace moved because it was owned by the wrong thing.** `00-namespace.yaml` sat inside `manifests/links-service/`, where the `00-` prefix made `kubectl apply -f manifests/links-service/` apply it first. Fine with one service; with two it meant applying `gateway` alone into a fresh cluster fails with `namespaces "app-hub" not found`. It is shared, so it lives at the top of `manifests/`.

## The one thing to know

**`kubectl apply -f <dir>` sorts by filename *within* a directory. It gives you nothing across directories.**

That is why the `00-` prefix was enough before and is not now. `make deploy` applies `manifests/00-namespace.yaml` **explicitly**, as its own step, before touching any service directory — rather than moving the file to the top of `manifests/` and hoping a recursive apply happens to reach it first. Ordering you rely on should be ordering you state.

The same instinct applies to the `Makefile`'s `SERVICES` list. Adding `aggregator` later is a one-word change, and the build, push, manifest-pin and rollout all follow — but **the ECR teardown list is separate** (`ECR_REPOS`) and a service missing from it does not fail loudly. It breaks a later `terraform destroy` with an error about a repository not being empty, long after the change that caused it.

Second thing, smaller: `pytest` needs `pythonpath = ["."]` in `pyproject.toml`. Without it pytest puts only `tests/` on `sys.path`, and `from app.main import app` fails with `ModuleNotFoundError: No module named 'app'` — which reads like a broken install and sends you to `uv sync` rather than to your path configuration. Both services now set it.

## Verify it yourself

```bash
make test        # 29 tests, both services, no cluster
make validate    # manifests + both Terraform stacks, offline
```

To see the `504` ordering trap the tests catch, swap the two `except` clauses in `gateway/app/main.py` so `httpx.RequestError` comes first, then run `make test`. `test_slow_upstream_maps_to_504` fails with `503` — because the general handler caught the timeout. Swap them back.
