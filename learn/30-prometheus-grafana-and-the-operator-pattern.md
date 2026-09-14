# 30 — Prometheus, Grafana, and the operator pattern

> **Guided build** (`CLAUDE.md § 2`, added 2026-09-14). Claude wrote the
> `values.yaml` and the `ServiceMonitor`; the owner ran every command and hit
> every failure. That tier exists because "explain, then you write" assumes a
> baseline that a *first* Helm chart does not have — a blank `values.yaml` with
> a thousand keys is a stall, not a lesson. This is a **full seven-section
> file** rather than a delegated short note, because the material is exactly
> what `R-05` existed to teach.

## What we did

Installed `kube-prometheus-stack` on EKS via Helm, then made Prometheus scrape
app-hub's own three services — by creating one Kubernetes object, not by
editing any configuration file.

End state: **22 scrape targets, all UP**, of which five are app-hub pods.
Grafana queries them. `149` tests across the three services, up from 138.

## Why

`R-01`–`R-04` hardened the cluster and `D-02` made it correct, but nothing
could answer *"is it healthy right now, and was it healthy an hour ago?"*.
Every check so far has been a human running a command.

There is also a work reason, which is the real one: this is the stack the
owner has to own at their organisation, and the Nagios experience they already
have transfers — but only after the model shift in **Key concepts** below.

## Key concepts

**`kube-prometheus-stack` is six things, not one.** prometheus-operator,
Prometheus, Alertmanager, Grafana, node-exporter (a **DaemonSet**), and
kube-state-metrics. The DaemonSet is why this cluster uses EC2 node groups and
not Fargate — Fargate has no nodes for one to land on.

**node-exporter and kube-state-metrics answer different questions**, and they
get confused constantly. node-exporter: *"how is the machine?"* — CPU, memory,
disk, read from the host's `/proc` and `/sys`. kube-state-metrics: *"what does
Kubernetes think?"* — desired vs ready replicas, pod phase, read from the API
server. *"The pod is Pending because the node is out of memory"* needs both.

**The operator pattern — the concept that transfers.** Classic Prometheus
means writing `prometheus.yml` with a list of targets. That model breaks in
Kubernetes: pods are ephemeral, IPs change on every rollout, a static list is
wrong within minutes.

So you never write `prometheus.yml`. You create a **`ServiceMonitor`** — *"scrape
Services matching these labels, on this named port, at this path"* — and a
controller watches for it, regenerates the config, and reloads Prometheus.
**Scrape configuration becomes declarative Kubernetes state**, versioned in git
next to the service it describes. ArgoCD's `Application` (`R-07`) is the same
idea with a different noun.

**A CRD is how that noun exists.** `apiVersion: monitoring.coreos.com/v1` is not
a Kubernetes API; the operator's CustomResourceDefinitions added it. Before the
chart installed them, `kubectl get servicemonitor` said *"the server doesn't
have a resource type"*. Afterwards it is as real to the API server as a
Deployment.

**PromQL asks a different shape of question than Nagios.** Nagios asks *"is this
host above 80% now?"*. PromQL asks *"what is the rate across this label set over
this window?"*:

```
100 - (avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)
```

`node_cpu_seconds_total` is a **counter** — only ever increasing. `rate(...[5m])`
turns it into seconds-per-second, which for `mode="idle"` is the fraction of
time idle. `avg by (instance)` collapses per-core series into one per node.
**The labels are what let one expression answer for two nodes, or two hundred.**

## Walkthrough

**Storage: `emptyDir`, and this reversed the original plan.** The first draft of
this guide said to use a PersistentVolumeClaim, so the EBS-orphan lesson would
land. Checking rather than assuming killed that:

```
aws eks describe-addon-versions  ->  aws-ebs-csi-driver is a SEPARATE addon,
                                     NOT installed by default
```

**With no CSI driver there is no provisioner**, so the PVC would sit `Pending`
forever and Prometheus would never start — with nothing anywhere saying *"you
need a CSI driver"*. Installing it needs the addon **and** its own IRSA role,
which is a task of its own. Persistence is now a deliberate follow-up that
teaches the CSI addon and a *second* IRSA role, building on `C-05`.

**A separate `monitoring` namespace with no PSS labels.** `app-hub` enforces the
`restricted` Pod Security Standard. node-exporter needs `hostNetwork`,
`hostPID` and `hostPath` to read the node's own metrics and **cannot run under
it** — it would be refused at admission and the DaemonSet would sit at zero
pods. Pod Security Standards are **per-namespace** admission control, so an
unlabelled namespace is unrestricted, and `app-hub` stays strict. That is a
real trade, written down rather than hidden.

**Four components turned off because EKS does not expose them.**
`kubeControllerManager`, `kubeScheduler`, `kubeEtcd`, `kubeProxy` — the control
plane is managed by AWS and those endpoints are unreachable. Left on, you get
four permanently-down targets from minute one. **A monitoring system that is red
on day one for reasons you are told to ignore is one you stop reading**, which
is the same failure as the pinned-data watchdog in `learn/20`.

**`/metrics` on the services, and the reason it is a library.** The hard part is
not counting requests, it is **label cardinality**. A naive counter labels by
request path, so `/links/<uuid>` creates a new time series per id — and ids are
server-generated UUIDs, so that set is unbounded. Prometheus holds series in
memory; this is the classic way to OOM it. `prometheus-fastapi-instrumentator`
groups by **route template** (`/links/{id}`), bounding the series count by the
number of routes. That claim is a test, not a comment: `test_metrics.py`
requests a fresh UUID and asserts it never appears in `/metrics`.

**The `ServiceMonitor` itself** selects Services by label, references the
Service's port by **name**, and names the namespace to look in.

## Gotchas

- **A ServiceMonitor that matches nothing says nothing.** All three Services
  were unlabelled with unnamed ports, so the monitor matched nothing and no
  target appeared — no error from the operator, the monitor, or Prometheus.
  **This is the most common reason a ServiceMonitor "does not work".**
  `validate-manifests.py` now cross-checks every ServiceMonitor's labels and
  port names against the real Services and fails if they do not exist.
- **`endpoints[].port` is a port NAME, never a number.** An unnamed Service port
  cannot be referenced at all.
- **There are TWO reload delays, not one.** operator → config secret, then
  config-reloader → Prometheus. Checking 46 seconds after `kubectl apply` showed
  17 targets and produced a confident *"it matched nothing"* — while the
  generated config already contained the new job. **Confirm against the
  generated config before concluding the operator failed.**
- **Grafana under this chart is not a bare Grafana.** A 256Mi limit OOMKilled it
  twice. It provisions ~25 dashboards from ConfigMaps with two sidecars.
- **Where a failure is loud and where you are looking are different questions.**
  That OOMKill appeared in the browser as *"Error loading: timeseries — make
  sure it was compiled"*, which sends you into plugin documentation. Only
  `kubectl get pod -o json` said `reason=OOMKilled exitCode=137`. **When a
  Grafana panel misbehaves, check the pod before believing the browser.**
- **Turning a component off means turning off what points at it.** Disabling
  Alertmanager still left a Grafana datasource aimed at a Service that does not
  exist — a permanently broken panel you learn to scroll past.
- **Grafana persists datasources in its own database once created.** Removing
  one from provisioning does not delete it; the `helm upgrade` was not enough
  and a pod restart was needed.
- **Helm is installed on both Windows and WSL at different MAJOR versions** here
  (v4 vs v3). Only WSL's kubeconfig points at EKS. Use WSL's.

## Verify it yourself

```bash
wsl -e bash -lc "kubectl -n monitoring get pods"
```

All Running, **nothing `Pending`** — Pending means the resource requests need
lowering for a 2-node cluster.

```bash
wsl -e bash -lc "kubectl -n monitoring port-forward svc/monitoring-kube-prometheus-prometheus 9090:9090"
```

**Status → Targets** should be all UP. Then the one that proves the operator
pattern — apply the ServiceMonitor and watch targets appear **without
restarting anything**:

```bash
wsl -e bash -lc "kubectl apply -f manifests/monitoring/servicemonitor-app-hub.yaml"
```

```
17 targets  ->  22 targets, five new ones, one per POD
```

Then in Grafana → Explore:

```
sum by (service) (rate(http_requests_total{namespace="app-hub"}[5m]))
```

Swap `service` for `status` to get error rates — the question `gateway` was
built to answer, now answerable without reading logs.

## Going deeper

- `learn/26` — the repository layer these services now expose metrics for
- `learn/20` — the silently dead monitor, the same disease in n8n
- **Next, in order:** persistence via the EBS CSI addon and a second IRSA role
  (building directly on `C-05`); then alert rules, where the Nagios checks the
  owner already runs at work translate most directly; then Alertmanager, routed
  into the n8n webhook that already works.
- The `kube-prometheus-stack` chart's own `values.yaml` — `helm show values
  prometheus-community/kube-prometheus-stack --version 91.2.3` — is the
  authoritative reference for everything this file deliberately left at default.
