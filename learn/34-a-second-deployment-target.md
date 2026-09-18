# 34 — A second deployment target, and a tunnel that needs no domain  ·  *guided build, short note*

**Status: WRITTEN, NEVER DEPLOYED.** Nothing here has run on a host. The runbook
is `compose/README.md`; this file is the reasoning behind it.

## What it does

`compose/` runs the same three services — `links-service`, `aggregator`,
`gateway` — on **one machine that stays up**, reached over a **Tailscale Funnel**.
It is a second deployment target alongside EKS, not a replacement for it.

The split is deliberate and the two must not converge:

| | purpose | lifecycle |
|---|---|---|
| `infra/` + `manifests/` | learning Terraform, Kubernetes, observability, CI/CD | destroyed every session |
| `compose/` | the dashboard actually used every day | always on |

EKS run 24/7 is roughly **$200/month** for a bookmark page. The EKS path is never
simplified to save money, and this path never acquires Kubernetes. What they
share is **the image** — same registry, same tag, same bytes.

## Why it is this way

**One host, no orchestrator.** Compose is the smallest thing that runs four
containers with a dependency order and restart policy. Reaching for Kubernetes
here would teach nothing new and cost the thing being avoided.

**No `ports:` anywhere in the file.** Nothing listens on the host. The tunnel
client dials *out* and traffic returns down that connection, so there is no
inbound port, no router forwarding, and no dynamic DNS. This mirrors what `E-06`
settled on EKS: gateway public, the other two internal.

**Tailscale rather than Cloudflare Tunnel, and the reason is the hostname.** A
named Cloudflare Tunnel's public hostname must sit on a **domain in your
Cloudflare account**. This project owns none — `manifests/ingress/README.md` has
been waiting on one for its ACM certificate since `E-06`. Cloudflare has no free
equivalent of the `*.pages.dev` name Pages hands out; its free option is a Quick
Tunnel, whose **URL changes on every restart**, which is useless for the one
thing this host exists to be. Tailscale gives a stable HTTPS hostname on the
free plan with no domain purchase.

**The same DynamoDB table as EKS, not a local store.** A local one would give
two divergent catalogues of the thing used daily. It is also the cheaper
direction to reverse: shared now with a local cache added later is additive;
local now and merged later means reconciling conflicting ids.

**ECR had to move first.** The repositories were in the ephemeral Terraform
stack, so the nightly destroy **deleted** them — see the postscript on
`learn/06`. An always-on host pulling from a registry that is deleted nightly is
not always-on. That was found before deploying, not after.

## The things to know

**The same variable needs a different value per target.**

```
EKS       LINKS_SERVICE_URL=http://links-service:80     Service maps 80 -> 8000
Compose   LINKS_SERVICE_URL=http://links-service:8000   no Service; direct
```

That is worse than a variable that is merely unset, and it is the third costume
of a bug this project has already paid for twice — the 8000-vs-80 mix-up, and
`AGGREGATOR_URL` missing entirely (`D-21`). `AGGREGATOR_URL` is `8002` in
**both**, because aggregator's Service maps 8002 → 8002. Do not make them match
out of symmetry.

**There is no IRSA outside EKS.** On the cluster a pod gets a short-lived,
automatically rotated identity with no stored secret (`learn/29`). Here it is a
real long-lived AWS key in a file on a host you patch yourself. Contained by
scoping the IAM user to four DynamoDB actions on one table plus read-only ECR
pull — so the worst case is someone reading and writing a list of bookmarks.

**`docker compose down -v` changes your URL.** The Tailscale node identity lives
in a named volume. Destroy it and the container re-registers as a *new* node —
and because the old `app-hub` node still exists, Tailscale does not reuse the
name, it appends a suffix. The URL silently becomes `app-hub-1.…` and every
bookmark breaks with nothing reporting an error. Plain `docker compose down` is
safe.

**Funnel is off by default per tailnet, and the failure looks like networking.**
It is granted in the ACL policy file via `nodeAttrs`. Without it the container
starts, authenticates, reports healthy, and is simply unreachable from outside.

**Node keys expire after 180 days.** When one does the node drops off and the
dashboard goes dark — half a year later, with no local cause and nothing
connecting it to setup. Disable key expiry on the node for an always-on host.

**Funnel is public and the hostname is not a secret.** It serves a real Let's
Encrypt certificate, and issued certificates are published to **Certificate
Transparency logs**, which are public and searchable. This matters here because
**the gateway dashboard does not filter on the `public` flag** — that flag only
governs `site/projects.json`. Setting `"AllowFunnel": false` makes it
tailnet-only on the same hostname, which is arguably what a personal dashboard
wants; the public face of this project is already `site/` on Cloudflare Pages.
