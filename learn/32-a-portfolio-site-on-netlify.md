# 32 — A portfolio site on Netlify  ·  *delegated, short note*

> Written by Claude at the owner's request, 2026-09-16. Netlify is a **new
> cloud provider**, which `CLAUDE.md § 4` says must be flagged rather than
> silently added — so the flag, and the scoping that followed, are most of this
> note.

## What it does

`site/` is a static two-page site deployed by Netlify from the umbrella repo:
a project landing page (architecture, cost policy, the seven repos, the
write-ups) and **the real dashboard running with no backend** at `/demo.html`.

`netlify.toml` sets `publish = "site"` with **no build command** — the files
are hand-written, so there is no bundler to break a deploy a year from now.

## Why it is this way

**app-hub cannot run on Netlify, and that had to be said before building
anything.** Netlify Functions are JavaScript, TypeScript and Go; all three
services are Python/FastAPI, and two of them reach DynamoDB with an
IRSA-derived identity that only exists inside the cluster. So this deploys the
**portfolio purpose** (`CLAUDE.md § 1`, purpose 3), not the system.

**Pointing the page at the live cluster was considered and rejected.** EKS
issues a new API endpoint hostname on every creation, and the cluster is
destroyed nightly by policy — so a permanent link to the real thing would be
dead most of the time and aimed at a stale host the rest of it. That is
`learn/16`'s lesson arriving somewhere new.

**The demo runs the real `app.js`, not a re-implementation.** Every call it
makes goes through one `api()` helper that calls `fetch(path, …)`, so
`site/static/demo-api.js` replaces `window.fetch` before `app.js` loads and
serves an in-memory catalogue. Adding and deleting genuinely work; nothing
persists, deliberately — `localStorage` would have been easy and would have
made the demo lie in a subtler way, showing a returning visitor their own
edits as though a backend were answering.

**The polyrepo forced a copy, so the copy is checked.** `gateway/` is a
separate git repository that the umbrella **gitignores**, so a Netlify
checkout of `app-hub` contains no `gateway/` at all and cannot reference the
dashboard across the boundary. `style.css` and `app.js` are therefore vendored
into `site/static/`, and `scripts/check-doc-drift.py` gained a `COPIES` check
that byte-compares them — with `--fix` to re-copy. A portfolio page claiming to
show the real dashboard while showing a three-month-old one is worse than a
screenshot that admits what it is.

`site/demo.html` cannot be a byte copy — it adds the banner and the stub script
tag. So the **mechanical part of it** is checked instead: every id `app.js`
looks up via `getElementById` must exist in `demo.html`. Both checks were
verified by breaking them on purpose and watching them fail.

## The one thing to know

**Script order in `demo.html` is load-bearing, and getting it wrong fails
quietly.** `app.js` captures whatever `window.fetch` is when it runs. If the
two `<script>` tags are swapped, every request goes to Netlify's static host,
404s, and the page renders empty with the error banner showing a generic
failure — no hint that the cause is two lines being in the wrong order.

There is a second thing worth carrying, because it was found by measuring
rather than by looking: **the stack table overflowed the page at a 293px
viewport**, giving the whole document a horizontal scrollbar and pushing every
section below it off-centre. It was invisible at desktop width and would have
been the first thing anyone opening the link on a phone saw. The fix is a
`.table-wrap { overflow-x: auto }` so the table scrolls inside its own box, and
a `min-width` so the columns do not crush instead.

> A page that is only ever checked at the width you built it at has only ever
> been checked at one width.

**Deploying needs an account and a login, which is the owner's to do.** Claude
can write the site and the config; connecting the repo and authorising Netlify
is not something to hand to an agent. See `site/README.md` for the steps.
