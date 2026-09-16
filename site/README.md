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
