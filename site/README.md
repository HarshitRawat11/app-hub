# site/ — the public project page

A static site deployed to **Cloudflare Pages**, live at
<https://app-hub-hr.pages.dev>. Two pages:

| Path | What it is |
|---|---|
| `/` | Project landing page — architecture, cost policy, the repos, the write-ups |
| `/demo` | **The real dashboard**, running against a stubbed API |

> **The demo is served at `/demo`, not `/demo.html`.** Cloudflare Pages strips
> the extension and 308-redirects, so both work — but `/demo` is the canonical
> URL and the one to link.

**This is not a deployment of app-hub.** Cloudflare Pages Functions are
JavaScript and TypeScript; all three services are Python/FastAPI, and two of them
reach DynamoDB with an identity that only exists inside the cluster. This is the
portfolio half of the project (`CLAUDE.md § 1`, purpose 3). See `learn/32`.

---

## Deploying it — the owner does this part

Claude wrote the site, but **connecting the repo means logging into Cloudflare
and authorising it against a GitHub account.** That is not something to hand to
an agent, so these steps are yours.

### One-time setup (gives continuous deploys)

1. Sign in at **[dash.cloudflare.com](https://dash.cloudflare.com)**.
2. **Workers & Pages → Create → Pages → Connect to Git**.
3. Pick **`HarshitRawat11/app-hub`** — the umbrella repo, not a component one.
4. Build settings: **framework preset `None`, build command blank, output
   directory `site`.** If Cloudflare pre-fills a build command, clear it — there
   is nothing to build, and a command here would fail.
5. Deploy. Every push to `master` redeploys from then on.

> **Check the Git connection is actually live, not just that the UI says so.**
> On 2026-09-18 the dashboard showed *"Automatic deployments enabled"* **and**
> *"This project is disconnected from your Git account"* at the same time, and
> the site sat three commits stale. It was caught with `curl`, not by reading the
> console. Verify by comparing the deployed content against the repo:
>
> **This machine's default shell is PowerShell, and PowerShell has no `<(...)`
> process substitution** — a `diff <(curl ...)` fails at the parser before it
> runs. Both forms below are given deliberately; pick the one matching the
> prompt you are at.
>
> **PowerShell** (hash comparison; `.gitattributes` is `eol=lf`, so the working
> tree and the deployed bytes are directly comparable):
>
> ```powershell
> curl.exe -s https://app-hub-hr.pages.dev/ -o "$env:TEMP\live.html"
> if ((Get-FileHash "$env:TEMP\live.html").Hash -eq (Get-FileHash .\site\index.html).Hash) { "MATCH - deploy is current" } else { "DIFFER - deploy is stale" }
> ```
>
> **WSL / bash**, where process substitution does work:
>
> ```bash
> wsl -e bash -lc "cd /mnt/c/Users/harshit.rawat/Documents/Projects/app-hub && diff <(curl -s https://app-hub-hr.pages.dev/) site/index.html && echo MATCH"
> ```
>
> Both were tested, **and both were tested against a file known to differ** — a
> check that has only ever printed MATCH has not been shown to detect anything.

### Or, from the CLI

```bash
npx wrangler pages deploy site --project-name=app-hub-hr
```

> Run it **from the repo root**, not from inside `site/`. Given `site` as a
> relative path from anywhere else it fails with `ENOENT ... scandir`, naming a
> directory that was never going to exist.

---

## `_headers` — and why it has no comments in it

HTTP headers (CSP, `X-Frame-Options`, cache control) live in **`site/_headers`**.
**Cloudflare Pages and Netlify both read that format**, so the hosting choice
stays a dashboard change rather than a code change — which is why the rules were
moved out of provider config in the first place.

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
curl -sI https://app-hub-hr.pages.dev/ | grep -iE "content-security-policy|x-frame-options|referrer-policy"
```

If those three come back, the file is in the right place and being parsed. If
they do not, it is almost always the location — check it is inside `site/`.

> **Do not move these rules into provider configuration.** `netlify.toml` used to
> carry a `[[headers]]` block and was removed on 2026-09-19 along with the rest
> of the Netlify config, because Netlify merged the two and a stale rule there
> would quietly override the file everyone reads — two sources of truth for one
> thing, which is the drift this project keeps paying for.

---

## A 404 must actually 404

`site/404.html` exists because without it **Cloudflare Pages serves `index.html`
with HTTP 200 for every nonexistent path** — SPA-fallback behaviour on a site
that is not an SPA. Check it:

```bash
curl -s -o /dev/null -w '%{http_code}\n' https://app-hub-hr.pages.dev/not-a-page
```

`404`, not `200`.

---

## Working on it locally

```bash
wsl -e bash -lc "cd /mnt/c/Users/harshit.rawat/Documents/Projects/app-hub/site && python3 -m http.server 8090 --bind 127.0.0.1"
```

Then open `http://localhost:8090`. No build step, so a refresh is the whole
edit loop.

> Locally `/demo.html` works and `/demo` does not — `http.server` does no
> extension stripping. That difference is the host's, not the site's.

---

## The two files you must not edit here

`static/style.css` and `static/app.js` are **vendored byte-for-byte from
`gateway/app/static/`**. They live here only because `gateway/` is a separate
git repository that the umbrella gitignores — a Cloudflare Pages checkout of
`app-hub` has no `gateway/` in it at all, so the site cannot reference them
across the boundary.

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
> and every request 404s against the static host, with nothing in the UI
> saying why.
