# 27 — The dashboard, and what a proxy owes its caller  ·  *delegated, short note*

> **Short note** (`CLAUDE.md § 2`). Claude wrote this. `learn/21` covers
> gateway's design rationale and the `async`/`await` and shared-client
> concepts this builds on.

## What it does

app-hub has a face. `GET /` on gateway serves a dashboard: link records grouped by category, a filter box bound to `/`, an add form, and delete. It is about 400 lines of dependency-free HTML, CSS and JavaScript in `gateway/app/static/`.

Making it useful meant gateway had to become a real proxy rather than a demonstration of one. It now forwards `GET /links`, `GET /links/{id}`, `POST /links` and `DELETE /links/{id}` instead of only the first, through one `_proxy` helper that holds the error mapping the owner wrote in `S-01` steps 1–3 — moved, not rewritten.

47 tests, up from 15. **Verified running, not merely written:** both services live on a laptop, driven through a real browser.

## Why it is this way

**The dashboard is served BY gateway, and is not a service of its own.** `PROGRESS.md` had `S-03` down as a fourth service. That would have bought three problems and no benefit:

- a second origin, so every gateway response needs CORS headers, and the page needs a build-time or runtime answer to *"where is the API?"*
- a second public endpoint — meaning a second ELB, on a cluster destroyed nightly, while `E-06` is explicitly deferring exactly that decision
- a third GitHub repository, which only the owner can create, so the work would have been blocked before it started

Served from gateway, every URL in the page is a bare path and none of that exists. It also matches what gateway already claims to be: the external entry point. A front door that serves an API but not the page you actually open is a strange front door.

This is reversible. If `E-06` ever wants the static files behind their own nginx pod, moving a directory is a small change; the expensive thing would have been standing up a service to find out.

**Some upstream 4xx responses are the caller's answer, not a gateway fault — and that distinction had never come up before.** With only `GET /links`, every 4xx from links-service genuinely was a fault: the collection always exists, so a 404 means something upstream is wrong, and `502` is honest. The moment `GET /links/{id}` exists, a 404 is the *correct* answer to a question about an id that is not there.

Flattening it to `502` would tell the caller the server is broken when in fact they asked for something that does not exist — sending them to read gateway's logs instead of checking their id. Same in reverse for `POST`: a `422` is about what the **caller** sent, and reporting that as `502` points them at the wrong machine entirely.

So `_proxy` takes an explicit `passthrough` set per route. `GET /links` passes nothing through, and that asymmetry is the point rather than an oversight.

**gateway does not own the link schema, so it must not restate it.** `POST` takes a bare `dict` and forwards it. Copying `LinkCreate` over from links-service would give the project two definitions of a link, and the day a field is added, gateway starts silently stripping it — which looks exactly like a client that never sent it. Validation stays where the data lives, and its `422` comes back through `passthrough`.

**Two security properties the page has to hold, because link records are attacker-controllable.** Anything that can `POST` to the API decides what `name`, `icon` and `url` contain:

- Every value is written with `textContent`, never `innerHTML`. One makes it data, the other makes it markup.
- `href` is assigned only from a scheme-checked value. `textContent` does nothing for an `href` — a stored `javascript:...` URL is inert as text and executes on click. Both halves are needed; neither is sufficient.

Verified with a real payload rather than asserted: a record whose name was `<img src=x onerror=alert(1)>` and whose URL was `javascript:alert(document.domain)` rendered zero injected elements and produced a plain `<span>` reading "unsupported URL".

## The one thing to know

**Every test passed, and the page was visibly wrong the first time it was opened.**

The add form is marked `hidden` and rendered anyway. `hidden` is not a behaviour — it is one rule in the browser's default stylesheet, `[hidden] { display: none }`, and **any author rule that sets `display` outranks it**. `#add-form { display: flex }` did. So the form sat open on load, and the JavaScript toggling `.hidden` did nothing at all, silently.

Nothing could have caught it from the server side. `test_dashboard.py` asserts the file is served, has the right content type, does not shadow `/health`, and references only assets that exist — all true, all passing, all blind to the actual rendered result. The fix is one line (`[hidden] { display: none !important; }`); the lesson is that **"the tests pass" and "it works" are different claims about a user interface**, and only one of them was checked.

Second thing, found immediately after: fixing the CSS changed nothing in the browser, because it was reusing a cached `style.css` without revalidating. That is the same bug shape with a deploy in the middle — new HTML, old stylesheet, no error anywhere, page just wrong. `/` and `/static/*` now send `Cache-Control: no-cache`, which does **not** mean "do not cache" but "cache, then revalidate every time" — so the browser still sends `If-None-Match` and still gets a `304`. Right trade for three small files with stable names; a large bundle would want content-hashed filenames instead.

## Verify it yourself

With `links-service` on 8000 and gateway on 8001, open <http://localhost:8001> and then break it on purpose:

```bash
python3 gateway/tests/fake_upstream.py 8000 slow
```

The banner should read *"links-service did not answer within 3 seconds — HTTP 504"*, not a generic failure. Distinguishing that from `503` and `502` is the entire reason gateway exists, and the dashboard is the first thing in this project that actually shows it to a human.
