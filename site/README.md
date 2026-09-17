# site/ — the public project page

A static site deployed to Netlify. Two pages:

| Path | What it is |
|---|---|
| `/` | Project landing page — architecture, cost policy, the seven repos, the write-ups |
| `/demo.html` | **The real dashboard**, running against a stubbed API |

**This is not a deployment of app-hub.** Netlify Functions are JavaScript,
TypeScript and Go; all three services are Python/FastAPI, and two of them reach
DynamoDB with an identity that only exists inside the cluster. This is the
portfolio half of the project (`CLAUDE.md § 1`, purpose 3). See `learn/32`.

---

## Deploying it — the owner does this part

Claude wrote the site and `netlify.toml`, but **connecting the repo means
logging into Netlify and authorising it against a GitHub account.** That is not
something to hand to an agent, so these steps are yours.

### The one-time setup (recommended — gives continuous deploys)

1. Sign in at **[app.netlify.com](https://app.netlify.com)** with GitHub.
2. **Add new site → Import an existing project → GitHub**.
3. Pick **`HarshitRawat11/app-hub`** — the umbrella repo, not a component one.
4. **Leave every build setting blank.** `netlify.toml` at the repo root already
   sets `publish = "site"` and an empty build command. If Netlify pre-fills
   something, clear it; a build command here would fail, because there is
   nothing to build.
5. Deploy. Every push to `master` redeploys from then on.

Optionally rename the site under **Site configuration → Change site name** so
the URL reads `app-hub-<something>.netlify.app` rather than the random one.

### Or, from the CLI

```bash
npm install -g netlify-cli
netlify login          # opens a browser — your login, not Claude's
netlify deploy --prod --dir=site
```

---

## `_headers` — and why it has no comments in it

HTTP headers (CSP, `X-Frame-Options`, cache control) live in **`site/_headers`**,
not in `netlify.toml`. **Netlify and Cloudflare Pages both read that format**, so
the hosting choice is a dashboard change rather than a code change — and you can
run both at once if you want.

**It must sit in the published directory**, which is `site/`. At the repo root
both providers ignore it, with no warning from either. That failure is worth
naming: *headers silently absent looks exactly like headers applied.*

**There are deliberately no comments inside it.** Cloudflare documents `#`
comments for `_redirects` but says nothing about `_headers`, and an indented
`# …` inside a rule block would plausibly parse as a header *name*. The downside
of guessing wrong is losing the security headers without any error, so the
explanation lives here instead of in the file.

**Verify after deploying rather than assuming:**

```bash
curl -sI https://YOUR-SITE | grep -iE "content-security-policy|x-frame-options|referrer-policy"
```

If those three come back, the file is in the right place and being parsed. If
they do not, it is almost always the location — check it is inside `site/`.

**Do not re-add a `[[headers]]` block to `netlify.toml`.** Netlify merges the
two, so a stale rule there would quietly override the file everyone reads — two
sources of truth for one thing, which is the drift this project keeps paying for.

---

## Working on it locally

```bash
wsl -e bash -lc "cd /mnt/c/Users/harshit.rawat/Documents/Projects/app-hub/site && python3 -m http.server 8090 --bind 127.0.0.1"
```

Then open `http://localhost:8090`. No build step, so a refresh is the whole
edit loop.

---

## The two files you must not edit here

`static/style.css` and `static/app.js` are **vendored byte-for-byte from
`gateway/app/static/`**. They live here only because `gateway/` is a separate
git repository that the umbrella gitignores — a Netlify checkout of `app-hub`
has no `gateway/` in it at all, so the site cannot reference them across the
boundary.

Edit the originals in `gateway/`, then:

```bash
wsl -e bash -lc "cd /mnt/c/Users/harshit.rawat/Documents/Projects/app-hub && python3 scripts/check-doc-drift.py --fix"
```

`make validate` fails if the copies have drifted, so this cannot be forgotten
silently. It also checks that every element id `app.js` looks up still exists
in `demo.html` — that one is not a byte copy, because it adds the demo banner
and the stub, so the mechanical part is checked instead.

**`static/demo-api.js` is site-specific** and has no counterpart in gateway. It
replaces `window.fetch` with an in-memory catalogue so the unmodified `app.js`
runs with no backend.

> **Script order in `demo.html` is load-bearing.** `app.js` captures whatever
> `fetch` is when it runs, so `demo-api.js` must be parsed first. Swap the two
> and every request 404s against Netlify's static host, with nothing in the UI
> saying why.
