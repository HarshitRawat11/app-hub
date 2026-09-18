# 35 — ArgoCD, and the half of GitOps that was missing

**Status: WRITTEN, NEVER APPLIED.** Nothing in this file has run on a cluster.
The runbook is `manifests/argocd/README.md`; this explains the reasoning.

## What we did

Added ArgoCD (`R-07`) to the cluster as a Helm release, plus five `Application`
objects arranged in the **app-of-apps** pattern: one root Application that
points at a directory of child Applications, one child per component. ArgoCD
now watches `app-hub-manifests` and makes the cluster match it, continuously.

`make argocd` installs the chart and applies the root Application. `make down`
gained a **step 0** that removes the Applications before anything else.

## Why

`PROGRESS.md` described the previous state exactly: **"GitOps-shaped, not
GitOps."** The manifests were declarative and versioned — but a human ran
`kubectl apply`, so the repository described what *should* be true rather than
what *was* true. Nothing detected drift, and nothing corrected it.

ArgoCD adds **reconciliation**: a controller that diffs live cluster state
against git every few minutes and fixes the difference.

On a cluster destroyed every night that is worth more than usual. Previously:
`make up`, then `make deploy` for each service in the right order, then the
Ingress, and remember the ALB controller first. Now: `make up`, `make argocd`,
and the application layer rebuilds itself from the repository.

## Key concepts

**Reconciliation, not deployment.** A deploy tool runs once and stops. A
reconciler never stops. `kubectl apply` is a deploy; ArgoCD is a thermostat.

**Desired state lives in git, not in your working tree.** This is the shift
that catches people. `make deploy` pins an image tag into
`manifests/<svc>/deployment.yaml`. ArgoCD reads **github.com**, not your
laptop. An uncommitted pin is invisible to it.

**`selfHeal` makes git the only write path.** With it on, `kubectl edit` is
undone in **seconds**. That feels hostile for a day and is the
entire value proposition: it is what makes the repository trustworthy.

**App-of-apps.** One Application whose job is to deploy other Applications.
Adding a service becomes committing a file rather than running a command. It is
indirection, and it earns its keep the moment there is more than one cluster or
more than a handful of components.

**Sync waves** order resources inside a sync. ArgoCD waits for a wave to report
Healthy before starting the next. Because the children here are themselves
`Application` objects, waves order whole components: namespace (-1), services
(0), Ingress (1).

**The bootstrap paradox.** ArgoCD applies Applications, so nothing can apply the
*first* Application except a human. Every GitOps setup has exactly one
imperative step at the bottom. Pretending otherwise just hides it.

## Walkthrough

**The root Application** points at `argocd/apps` — deliberately not at the
repository root, which also holds Helm `values.yaml` files for monitoring,
Jenkins and the ALB controller. Those are not Kubernetes objects, and a
recursive sync over the root would try to make sense of them.

It carries `resources-finalizer.argocd.argoproj.io`, which makes deletion
cascade. That finalizer is what `make down` step 0 depends on.

**The namespace gets its own Application**, and this is the subtle one. ArgoCD
can create a destination namespace for you with `CreateNamespace=true`. If it
did, the `app-hub` namespace would come up **with no labels** — losing
`pod-security.kubernetes.io/enforce: restricted`, which `R-04` verified on a
live cluster by watching admission control reject a busybox pod. Everything
would still deploy and nothing would error. The cluster would simply be quietly
less safe than the repository claims. So the namespace is synced from its real
manifest, with its real labels, in wave -1.

**Three chart components are turned off — but not by the same key, and assuming they were cost a wrong claim.** `dex` (SSO brokering for an identity provider that does not exist here) and `notifications` (n8n already owns that) both have an `enabled` key. **`applicationSet` does not** — in chart 10.9.2 the only `enabled` beneath it belongs to `applicationSet.pdb`.

So `applicationSet.enabled: false` was written, **Helm accepted it silently** — unknown values are not an error — and the controller ran anyway. The values file asserted one thing and the cluster did another, with nothing reporting the difference. It was caught by reading `kubectl get pods` after the install, not by reviewing the file.

Settled with `helm template` rather than another guess: `--set applicationSet.enabled=false` renders `replicas: 1`; `--set applicationSet.replicas=0` renders `replicas: 0`. The working lever is `replicas: 0`, and note what it does not do — the Deployment object still exists, it just runs no pods.

**The transferable part: a Helm value you invented is indistinguishable from one you got right, because the failure is silence.** Check the rendered output, or check the cluster.

**`server.insecure: true`, and why that is not careless.** ArgoCD is reached by
`kubectl port-forward`, not through the shared ALB. The ALB is HTTP-only,
because HTTPS needs an ACM certificate which needs a domain this project does
not own — so putting the ArgoCD login behind it would send the admin password
across the public internet in cleartext. A port-forward tunnels over the
authenticated Kubernetes API and lands on localhost. The transport security is
the port-forward; a self-signed certificate on top would add a warning to click
through and nothing else.

**A read-only deploy key.** `app-hub-manifests` is private — verified rather
than assumed, by running `git ls-remote` with the credential helper explicitly
disabled and watching it ask for a username, while the same query against
`app-hub-compose` succeeded. Jenkins already holds a **write** key on that
repository because it commits image tags back. ArgoCD only reads, so it gets a
separate key with **write access unticked**. A compromised ArgoCD should not be
able to rewrite the manifests it deploys from.

ArgoCD discovers repository credentials **by label**, not by name. A correct
Secret without `argocd.argoproj.io/secret-type=repository` is inert, and the
resulting failure is indistinguishable from having no Secret at all — so
`make argocd` checks for the label, not just the Secret.

## Gotchas

**`make down` had to change, and getting it wrong recreates `D-28`.** With
`selfHeal`, deleting the Ingress makes ArgoCD put it back. The ALB controller
then provisions a *second* load balancer, teardown continues around it, and it
is orphaned — billing, with no cluster left to manage it. Step 0 now deletes
the root Application first (cascading, while the controller is still alive), and
**asserts zero Applications remain** before continuing.

**An uncommitted image pin silently rolls back.** `make deploy` pins the tag
locally and applies it. The pods come up on the new image, ArgoCD notices the
cluster disagrees with git, and reverts — almost immediately. It looks like a
flaky deployment. It is the system working.

**The validator would not have seen these files.** `make validate` globbed one
directory level, and `manifests/argocd/apps/` is two deep. That is exactly how
`manifests/monitoring/` went unchecked until 2026-09-16 — failure by omission,
which reports success. The glob now walks two levels, and **that was proven by
deleting a namespace from a child Application and watching validate fail**,
rather than by reading the change and believing it.

**It may not all fit.** kube-prometheus-stack wants roughly 3 GiB of requests,
Jenkins 1–2 GiB, ArgoCD another 1.5–2 GiB, on 2× `t3.medium`. Expect to run one
or two of the three at a time. The resource numbers in `values.yaml` are honest
requests, not numbers shrunk until the arithmetic worked.

## Verify it yourself

**Nothing below has been run.** These are the checks to run on the first
install, and they are chosen to test claims rather than to look reassuring.

```bash
kubectl -n argocd get applications
```

Six, all `Synced` / `Healthy`.

```bash
kubectl get ns app-hub -o jsonpath='{.metadata.labels}'; echo
```

`enforce: restricted` must still be there — this is the check that catches
ArgoCD having created the namespace itself.

```bash
kubectl -n app-hub scale deployment/gateway --replicas=0
```

Then watch it come back. **Measured 2026-09-19: it was already back to 2 by the
time the next command ran** — ArgoCD watches resources rather than only
polling, so the documented 3-minute reconciliation interval is the worst case
when an event is missed, not the expected latency. **If it does not revert,
`selfHeal` is not doing what this file claims.**

## Going deeper

- [Declarative setup](https://argo-cd.readthedocs.io/en/stable/operator-manual/declarative-setup/) — Applications, repositories, projects
- [App of apps](https://argo-cd.readthedocs.io/en/stable/operator-manual/cluster-bootstrapping/)
- [Sync waves and hooks](https://argo-cd.readthedocs.io/en/stable/user-guide/sync-waves/)
- [AppProject](https://argo-cd.readthedocs.io/en/stable/user-guide/projects/) — everything here uses `default`, which permits any source and any destination. Restricting it is the obvious next hardening step.
