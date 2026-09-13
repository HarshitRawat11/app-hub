# 28 — aggregator, and the risk of fetching URLs you did not choose  ·  *delegated, short note*

> **Short note** (`CLAUDE.md § 2`). Claude wrote this. `learn/21` covers the
> service-to-service call pattern it reuses; `learn/27` covers the dashboard
> it feeds.

## What it does

Service #3. `aggregator` reads the link catalogue from `links-service` and **probes every URL**, so the dashboard shows which self-hosted apps are actually reachable rather than just listing them. Green dot, red dot, grey dot.

It runs on port 8002, is `ClusterIP` and **never publicly reachable**. The dashboard gets at it only because gateway proxies `GET /status` — which is the point, not a limitation.

47 tests. **Verified running against real targets**, not only mocks: a live n8n (`up`, 200, 4 ms), a stopped Grafana (`down`, `ConnectError`), example.com over the real internet (`up`, 78 ms), and `169.254.169.254` (`blocked`).

## Why it is this way

**It proves the thing `gateway` cannot.** gateway is the external entry point, so `gateway → links-service` is the outside talking in — which was always a slightly weak demonstration of service discovery. `browser → gateway → aggregator → links-service` has **neither end of the inner hop as the front door**. That is the claim the whole architecture rests on, and the reason Eureka was dropped in favour of Kubernetes DNS.

**Its workload genuinely differs, which is the honest test of whether something deserves to be its own service.** A CRUD API answers from memory in microseconds. This one sits waiting on dozens of slow third parties. Different timeouts, different concurrency, eventually a different replica count. If the answer to *"why is this separate?"* had only been "to prove services can talk", it would have been a demo rather than software.

**A down link is data; a down `links-service` is an error.** `/status` returns **200** with the link marked `down`. Only `links-service` itself being unreachable produces 5xx. Blur those two and the dashboard cannot tell *"your NAS is switched off"* from *"the hub is broken"* — which need completely different reactions from the person reading it.

**Anything under 500 counts as `up`, including 401 and 403.** The question is *"is the app running?"*, not *"may I in?"*. A Grafana behind auth answering 401 is working perfectly. Marking every protected app as down would make the dashboard cry wolf about most of the catalogue — and **a status page that cries wolf gets ignored, at which point it is worse than not having one.**

**Two HTTP clients, not one.** The call to `links-service` goes to a known, fast neighbour; the probes go to arbitrary third parties. Sharing a client would let a catalogue full of slow hosts exhaust the pool the `links-service` call also needs — so a few dead bookmarks would take out the endpoint entirely.

## The one thing to know

**This service fetches URLs that anyone who can `POST` to `links-service` chose, from inside the cluster. That is textbook SSRF, and the value of the attack is precisely the network position this service has.**

The reflex mitigation is *"block private address space"*. **Here that is wrong, and the reasoning is the transferable part.** app-hub exists to catalogue self-hosted apps — Grafana on `10.x`, n8n on `localhost`, a NAS on `192.168.x`. Blocking RFC1918 would block the product. **A guard that breaks the use case gets deleted within a day, which makes it worth less than a narrow guard that survives.**

So it refuses exactly three things:

- **Link-local addresses** (`169.254.0.0/16`, `fe80::/10`). `169.254.169.254` is the cloud instance metadata endpoint — the classic route from *"will fetch a URL you chose"* to *"hands over IAM credentials"*. IMDSv2 requires a `PUT` for a token so a plain `GET` is already weak, but **`C-05` is about to attach a real IAM role to this namespace, and "weak" is not a thing to build on top of.** The guard exists *before* the role rather than after.
- **Cloud metadata hostnames.**
- **Non-HTTP schemes** — `file://`, `gopher://`.

**Hostnames are resolved before the check**, because `http://metadata.example.com/` can point at `169.254.169.254` just as easily as the literal address can be typed.

**And it is not airtight — which is written down rather than hidden.** DNS can answer differently between our lookup and the HTTP client's own, so someone controlling a domain can still slip through; that is DNS rebinding. Closing it properly means resolving once and connecting to the pinned address through a custom transport. Worth doing if this ever probes URLs from an untrusted source. Today the only writer is the owner. **Stating the gap is what makes the guard maintainable; a control documented as complete when it is not is worse than no control.**

`blocked` is deliberately **not** folded into `down`. Down means we asked and got nothing; blocked means we refused to ask. **A security control nobody can see is one nobody maintains.**

### The bug the guard caused, which is its own small lesson

The concurrency test asserted probes run in parallel by measuring wall-clock time. It failed at **5.2 seconds** against a 1-second budget, apparently proving the probes were serial. They were not — the guard was doing a **real DNS lookup** for ten fake `.example` hostnames, and the test was measuring NXDOMAIN timeouts. Switching it to IP literals (which never reach a resolver) made it pass in milliseconds, and prompted a real improvement in the code: an address that is already an IP literal has been checked, so resolving it again is a wasted round trip.

**A test can fail for a reason that has nothing to do with what it claims to measure**, and the failure message will still be the claim.

## Verify it yourself

With all three services up, add a link pointing at the metadata endpoint and watch it get refused:

```bash
curl -s -X POST localhost:8001/links -H 'Content-Type: application/json' \
  -d '{"name":"EC2 metadata","url":"http://169.254.169.254/latest/meta-data/","category":"danger"}'
```

```bash
curl -s localhost:8001/status | python3 -m json.tool
```

That URL comes back `"status": "blocked"` with `"refusing link-local address"`, and the request was never made. Then stop aggregator and reload the dashboard: the links still render and stay clickable, the dots go grey, and **no error banner appears** — liveness is a decoration on the catalogue, not a dependency of it.
