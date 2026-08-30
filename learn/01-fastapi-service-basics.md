# 01 — The FastAPI service: uv, Pydantic models, and CRUD endpoints

> **Backfilled.** This step was performed by hand before `learn/` existed. It is reconstructed from the committed code and git history (`a048c10`, `5a21d5a`, `58e29cd`), so it describes *what the code does and why* rather than narrating the original session.

## What we did

Created `links-service`, the first service in app-hub: a Python project managed by `uv`, exposing a FastAPI HTTP API with a health check and CRUD operations over link records.

## Why

app-hub needs a catalogue of "which app lives where". That catalogue is the first thing to build, because everything downstream — the container, the cluster, the deployment — needs *something* to deploy. A CRUD API is the smallest thing that is genuinely useful and still exercises the whole path.

FastAPI was picked over Flask/Django for a specific reason: it derives request validation and OpenAPI documentation from Python type hints. You write the types once and get parsing, validation, error responses, and interactive docs for free. For a learning project that is a lot of leverage per line.

## Key concepts

### 1. `uv` — the package manager and what a lockfile buys you

`uv` is a Python package and project manager (written in Rust, from Astral). It replaces the `pip` + `venv` + `pip-tools` stack with one tool.

Three files define the project:

| File | Role |
|---|---|
| `pyproject.toml` | What you *want* — declared dependencies and constraints |
| `uv.lock` | What you *get* — every package pinned to an exact version, with hashes |
| `.python-version` | Which interpreter this project expects (`3.14`) |

`pyproject.toml` says `fastapi>=0.140.7`. That is a *range*. On its own, two installs a month apart could resolve to different versions and behave differently. `uv.lock` records the exact resolution — `fastapi 0.140.7`, `pydantic 2.13.4`, `starlette 1.3.1`, and so on, including transitive dependencies you never asked for directly.

**The mental model: `pyproject.toml` is the request, `uv.lock` is the receipt.** Commit both. The lockfile is what makes "it works on my machine" reproducible on someone else's.

### 2. Two models, not one — the request/response split

```python
class Link(BaseModel):
    id: int
    name: str
    url: str
    category: str
    icon: str | None = None

class LinkCreate(BaseModel):
    name: str
    url: str
    category: str
    icon: str | None = None
```

These look redundant. They are not, and the difference is the whole point: **`LinkCreate` has no `id`.**

`LinkCreate` is the *request* shape — what a client is permitted to send. `Link` is the *stored and returned* shape — what the server owns. The `id` is assigned by the server, so a client must not be able to supply one. If you used a single model with `id: int`, a client could POST `{"id": 999, ...}` and dictate its own primary key.

This request/response model split is one of the most transferable ideas in the codebase. It shows up in every API framework under different names (serializers, DTOs, schemas).

`icon: str | None = None` makes the field optional with a default of `None`. The `str | None` syntax is modern Python union syntax (3.10+), equivalent to `Optional[str]`.

### 3. Pydantic validates at the boundary

`BaseModel` comes from Pydantic. When FastAPI receives a POST body, it hands the JSON to `LinkCreate`, which:

- Checks every required field is present
- Coerces and checks types
- Returns a `422 Unprocessable Entity` with a precise error path if anything fails — before your function is ever called

So by the time `createLink(link: LinkCreate)` runs, `link` is guaranteed valid. **You never write validation code, and you never handle malformed input inside your handler.**

The important caveat, which bit this project later: **Pydantic validates at the boundary, not inside your function.** Assigning a `LinkCreate` into a `dict[int, Link]` is not checked by anything at runtime — Python type hints are documentation, not enforcement. That is exactly how the `POST /links` bug survived (see `learn/09`).

### 4. Path parameters and typed coercion

```python
@app.get("/links/{id}")
def getLink(id: int):
```

`{id}` in the path is a placeholder; the `id: int` annotation tells FastAPI to convert it. A request to `/links/abc` returns a 422 automatically — the handler is never entered. Free input validation from a type hint.

### 5. `HTTPException` is the way to return an error

```python
raise HTTPException(status_code=404, detail="Link not found")
```

You *raise* rather than *return*. FastAPI catches it and renders `{"detail": "Link not found"}` with status 404. Raising means you can bail out from anywhere in a call stack without threading error returns back up through every layer.

## Walkthrough

The complete service:

```python
from fastapi import FastAPI, HTTPException
from app.models import Link, LinkCreate

app = FastAPI()
links_db: dict[int, Link] = {}
next_id = 1
```

`app` is the ASGI application object — the thing uvicorn looks for. `links_db` is a plain dict standing in for a database. `next_id` is a hand-rolled auto-increment counter.

```python
@app.get("/health")
def health():
    return {"status": "ok"}
```

Trivial, and load-bearing. Kubernetes calls this endpoint to decide whether the pod is alive and whether it should receive traffic. It has no dependencies deliberately — a health check that queries a database tells you about the database, not about your process.

Returning a plain dict is enough; FastAPI serialises it to JSON and sets the content type.

```python
@app.post("/links")
def createLink(link: LinkCreate):
    global next_id
    new_link = Link(id=next_id, **link.model_dump())
    links_db[next_id] = new_link
    next_id += 1
    return new_link
```

The load-bearing line is the third one. `link.model_dump()` converts the Pydantic model to a plain dict; `**` unpacks it as keyword arguments; and `id=next_id` supplies the field the client was not allowed to send. The result is a fully-formed `Link`.

`global next_id` is required because assigning to a name inside a function makes it local by default. Without `global`, `next_id += 1` would raise `UnboundLocalError`.

> This function is shown **as fixed**. As originally written it stored `link` (the `LinkCreate`) instead of `new_link`, so reads came back without an `id`. See `learn/09`.

```python
@app.delete("/links/{id}")
def removeLink(id: int):
    if id not in links_db:
        raise HTTPException(status_code=404, detail="Link not found")
    del links_db[id]
    return {"deleted": id}
```

Check-then-act. Note that ids are never reused: `next_id` only increases, so deleting link 3 does not free up 3.

## Gotchas

- **`links_db` is in-process memory.** Every restart wipes it, and every replica has its own copy. This is fine for a prototype and actively wrong once the Deployment runs 2 replicas — tracked as `C-03`.
- **`global` is a smell that will need replacing.** With a real datastore, id generation moves to the database and both `global next_id` and the counter disappear.
- **Function names are camelCase** (`getLinks`, `createLink`), which is against PEP 8 — Python convention is `get_links`. Cosmetic, tracked as `D-10`.
- **`getLinks` builds a list with an explicit loop** where `list(links_db.values())` would do. Harmless, but worth noticing.
- **The interactive docs at `/docs` are free.** FastAPI generates an OpenAPI schema from your type hints and serves a Swagger UI. Use it instead of hand-writing `curl` commands while exploring.

## Verify it yourself

`uv` lives in WSL, not on Windows (`CLAUDE.md § 5`):

```bash
wsl -e bash -lc "cd /mnt/c/Users/harshit.rawat/Documents/Projects/app-hub/links-service && uv sync && uv run uvicorn app.main:app --reload --port 8000"
```

`uv sync` reads `uv.lock` and builds `.venv` to match it exactly. `--reload` restarts on file changes.

Health check:

```bash
curl -s localhost:8000/health
```

Full round-trip — create, then read back:

```bash
curl -s -X POST localhost:8000/links -H "Content-Type: application/json" -d '{"name":"Grafana","url":"https://grafana.local","category":"ops"}' && echo && curl -s localhost:8000/links
```

Watch validation reject bad input with a 422 and a precise error path:

```bash
curl -s -X POST localhost:8000/links -H "Content-Type: application/json" -d '{"name":"missing other fields"}'
```

Then open <http://localhost:8000/docs> in a browser — every endpoint, with its schema, generated from the type hints.

## Going deeper

- [FastAPI first steps](https://fastapi.tiangolo.com/tutorial/first-steps/)
- [FastAPI response models](https://fastapi.tiangolo.com/tutorial/response-model/) — `response_model=` would enforce the return shape at the framework level and would have caught the `C-01` bug
- [Pydantic models](https://docs.pydantic.dev/latest/concepts/models/)
- [uv project concepts](https://docs.astral.sh/uv/concepts/projects/) — `pyproject.toml` vs `uv.lock`

---

**Next:** `learn/02` — putting this service in a container.
