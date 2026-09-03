# 19 — Hardening the deployment, and automating the session loop

## What we did

Five things, all without a cluster running:

- **`R-04`** — everything moved into an `app-hub` namespace that enforces the restricted Pod Security Standard
- **`R-01`** — resource requests and limits on the container
- **`R-02`** — non-root user in the image, plus a locked-down `securityContext` in the Deployment
- **`R-03`** — ECR tags made immutable, with image tags now derived from the git commit SHA
- **`P-09`** — a `Makefile` wrapping the whole session loop, plus an offline manifest validator

## Why

Two separate motivations.

**The hardening items (`R-01`–`R-04`) are the difference between "it runs" and "it runs the way you'd defend in review."** None of them were urgent — the service worked fine without them — but all four are things a reviewer would ask about immediately, and three of them get *harder* to add later once more services exist.

**The automation (`P-09`) exists because of a specific failure shape.** Two steps in the session loop are load-bearing and silent when skipped: `aws eks update-kubeconfig` after a rebuild, and deleting LoadBalancer Services before `terraform destroy`. Neither announces "you forgot me" — one produces confusing auth errors, the other fails a destroy partway and leaves the NAT gateway billing. **A step you cannot forget beats a step you remember.**

## Key concepts

### 1. Namespaces, and why the file is called `00-namespace.yaml`

A namespace is a scope for names — two services can both be called `api` in different namespaces. It's also the unit that quotas, network policies and RBAC attach to.

The naming matters mechanically: **`kubectl apply -f <dir>/` processes files in filename order.** Every other object here declares `namespace: app-hub`, so applying them before the namespace exists fails with `namespaces "app-hub" not found`. The `00-` prefix guarantees it goes first. Alphabetically `deployment` < `namespace` < `service`, so without the prefix it would have been applied *second*.

The namespace also carries Pod Security Standard labels:

```yaml
pod-security.kubernetes.io/enforce: restricted
```

That turns "our pods happen to be secure" into "the cluster **refuses** anything that isn't". A future manifest that forgets `runAsNonRoot` gets rejected at admission rather than quietly running as root. `warn` and `audit` are also set, which surface violations without blocking — useful while adding services.

### 2. Requests vs limits, and the QoS class you get

```yaml
resources:
  requests: {cpu: 50m, memory: 64Mi}
  limits:   {cpu: 500m, memory: 256Mi}
```

These do genuinely different jobs:

- **`requests`** is what the **scheduler reserves**. It's how Kubernetes decides whether a node has room. It is *not* a cap.
- **`limits`** is the **hard ceiling**, enforced at runtime.

`m` means millicores — `50m` is 0.05 of a CPU core, `500m` is half a core.

The two behave asymmetrically when exceeded, and this catches people:

| Resource | Over the limit |
|---|---|
| CPU | **Throttled** — slowed down, stays alive |
| Memory | **OOM-killed** — the container dies |

Memory is incompressible; you can't give a process 90% of a byte. CPU is compressible, so the kernel just gives it fewer time slices.

**The QoS class falls out of what you set:**

| | Condition | Evicted |
|---|---|---|
| `Guaranteed` | requests == limits, both set | last |
| `Burstable` | requests set, less than limits | middle |
| `BestEffort` | nothing set | **first** |

Before this change the pod was **BestEffort** — the first thing killed when a node runs short. That's the real cost of omitting resources, and it's invisible until a node is under pressure.

We chose Burstable: guaranteed 50m, free to burst to 500m when the node is idle. Guaranteed would reserve the full 500m permanently, wasting capacity on a service this small.

**These numbers are starting points, not measurements.** That's an honest limitation — the right values come from observing real usage, which is what `R-05` (Prometheus) will provide.

### 3. Non-root, and why it's nearly free here

By default a container runs as root. If something escapes the container, **it escapes as root**.

```dockerfile
RUN groupadd --system --gid 10001 appuser \
 && useradd --system --uid 10001 --gid appuser --no-create-home appuser \
 && chown -R appuser:appuser /app
USER appuser
```

The usual objection is "but my app needs root." Two things actually require it: writing to root-owned paths, and binding a port below 1024. This app does neither — it binds 8000 and writes nothing. So the trade-off is genuinely zero.

`--system` creates a user with no login shell and no password. The UID `10001` is arbitrary but **explicit**, so the Kubernetes `securityContext` can assert the same number.

### 4. Pod-level vs container-level `securityContext`

Both exist and they're not interchangeable:

```yaml
spec:
  securityContext:              # POD level -- applies to every container
    runAsNonRoot: true
    runAsUser: 10001
    seccompProfile: {type: RuntimeDefault}
  containers:
    - securityContext:          # CONTAINER level -- narrower
        allowPrivilegeEscalation: false
        readOnlyRootFilesystem: true
        capabilities: {drop: ["ALL"]}
```

What each buys:

- **`runAsNonRoot: true`** — the kubelet *refuses to start the pod* if the image's user resolves to UID 0. A guard against someone rebuilding without `USER`.
- **`allowPrivilegeEscalation: false`** — blocks a setuid binary from gaining more privilege than its parent.
- **`capabilities: drop: ["ALL"]`** — Linux splits root's powers into ~40 capabilities. A web app needs none.
- **`seccompProfile: RuntimeDefault`** — restricts syscalls to the runtime's default allowlist.
- **`readOnlyRootFilesystem: true`** — the whole filesystem is mounted read-only.

### 5. Verify read-only before you claim it

`readOnlyRootFilesystem` is the one most likely to break an app, because anything writing to disk fails at runtime rather than at deploy time. So it was tested locally rather than assumed:

```bash
docker run --rm --read-only links-service:nonroot
```

It worked **with no writable mount at all** — no tmpfs, nothing. Two reasons: the app stores state in memory, and `PYTHONDONTWRITEBYTECODE=1` stops Python creating `__pycache__` under `/app`.

That's why the Deployment mounts no volume. The manifest records what to do if that changes:

```yaml
#   volumes: [{name: tmp, emptyDir: {}}]
#   volumeMounts: [{name: tmp, mountPath: /tmp}]
```

**The general point: a security control you have not tested is a deployment failure scheduled for later.** Docker's `--read-only` reproduces the Kubernetes behaviour closely enough to catch it in seconds, with no cluster.

### 6. Immutable tags force a real versioning scheme

```hcl
image_tag_mutability = "IMMUTABLE"
```

With `MUTABLE` you can push a rebuilt image over `:v1`. Two pods started at different times then run **different code under the same tag**, and rollback stops being reliable.

Immutability makes that impossible — and forces the useful consequence: **every build needs a unique tag.** The Makefile derives one from the git SHA:

```make
GIT_SHA := $(shell git -C links-service rev-parse --short HEAD)
DIRTY   := $(shell git -C links-service status --porcelain | head -c1)
TAG     := $(if $(DIRTY),$(GIT_SHA)-dirty-$(shell date +%s),$(GIT_SHA))
```

So a tag *names the code it was built from*. `98f355b` is answerable: `git show 98f355b`.

The dirty case matters in practice — you often build before committing. A timestamp suffix keeps the tag unique (immutability demands it) while flagging that it doesn't correspond to a commit.

### 7. Make is a dependency engine used here as a task runner

Make's real job is "rebuild X when its inputs change." We use it as a task runner, where nothing is a file. That's common and fine, but it explains two gotchas:

- **`.PHONY: up deploy down`** tells Make these aren't filenames. Without it, a file named `deploy` would make `make deploy` do nothing.
- **Recipe lines must begin with a literal TAB.** Spaces produce `*** missing separator. Stop.` — Make's most infamous error. Verified: 77 tab-indented lines, 0 space-indented.
- **Each recipe line runs in its own shell**, so `cd infra` on one line does not affect the next. Hence `cd infra && terraform apply` on one line.

### 8. The manifest holds the tag on purpose

`make deploy` rewrites the image tag *in* `deployment.yaml`:

```make
sed -i 's|image: $(IMAGE):.*|image: $(IMAGE):$(TAG)|' $(MANIFESTS)/deployment.yaml
```

That looks odd — a build step editing a tracked file. It's deliberate: **ArgoCD (`R-07`) applies this repo verbatim**, so the desired state must live in git, not be injected at deploy time. Injecting with `kubectl set image` would make the cluster diverge from the repo, and ArgoCD would revert it.

This is exactly the step Jenkins (`R-06`) will automate: build, push, bump the tag in the manifests repo, commit. ArgoCD notices and reconciles.

## Walkthrough — the Makefile targets

| Target | Does |
|---|---|
| `make status` | The "am I being charged?" audit — clusters, NAT, LBs, EC2, orphaned EBS, unassociated EIPs |
| `make up` | `terraform apply`, **then `update-kubeconfig`**, then print the context and nodes |
| `make deploy` | ECR login, build, push, pin the manifest tag, apply, wait for rollout, verify |
| `make down` | Delete LoadBalancer Services → wait for the NLB → delete PVCs → empty ECR with `tagStatus=ANY` → `terraform destroy` → audit |
| `make validate` | Offline: manifest checks + `terraform fmt -check` + `validate` |

`guard` runs first on the cluster-touching targets and fails immediately with a clear message if `terraform` or `docker.exe` is missing — i.e. if you're in a Windows shell instead of WSL. Without it, the first error arrives three commands into an apply.

## Gotchas

- **`00-` prefix on the namespace is load-bearing.** Rename it and `kubectl apply -f dir/` breaks.
- **`runAsUser` in the manifest must match `USER` in the Dockerfile.** They're set independently and nothing checks they agree — a mismatch means files owned by 10001 and a process running as something else.
- **`readOnlyRootFilesystem` fails at runtime, not deploy time.** Test with `docker run --read-only`.
- **Immutable tags mean re-pushing the same SHA fails.** Correct, but surprising the first time.
- **`make deploy` modifies a tracked file.** Commit it, or the next apply silently reverts the tag.
- **Recipe lines need TABs.** Editors love converting them.
- **The restricted PSS will reject non-compliant manifests** at admission. Good, but the rejection message is verbose — read it for the specific field.

## Verify it yourself

Everything below works with no cluster:

```bash
wsl -e bash -lc "cd /mnt/c/Users/harshit.rawat/Documents/Projects/app-hub && make validate"
```

Confirm the image really runs as non-root and needs no writable filesystem:

```bash
wsl -e bash -lc "cd /mnt/c/Users/harshit.rawat/Documents/Projects/app-hub/links-service && docker.exe build -q -t ls:check . && docker.exe run --rm ls:check id && docker.exe run --rm --read-only -d -p 8099:8000 --name lschk ls:check && sleep 6 && curl -s localhost:8099/health && docker.exe stop lschk"
```

Expect `uid=10001(appuser)` and `{"status":"ok"}`.

See what tag the next deploy would use:

```bash
wsl -e bash -lc "cd /mnt/c/Users/harshit.rawat/Documents/Projects/app-hub && make help | tail -1"
```

Check the Makefile's tabs are intact:

```bash
grep -cP '^\t' Makefile
```

## Going deeper

- [Resource requests and limits](https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/) and [QoS classes](https://kubernetes.io/docs/concepts/workloads/pods/pod-qos/)
- [Pod Security Standards](https://kubernetes.io/docs/concepts/security/pod-security-standards/) — what `restricted` actually requires
- [securityContext reference](https://kubernetes.io/docs/tasks/configure-pod-container/security-context/)
- [Linux capabilities](https://man7.org/linux/man-pages/man7/capabilities.7.html) — the ~40 pieces root splits into
- [ECR tag mutability](https://docs.aws.amazon.com/AmazonECR/latest/userguide/image-tag-mutability.html)
- [GNU Make manual](https://www.gnu.org/software/make/manual/make.html) — `.PHONY`, and why each line is its own shell

---

**Not yet verified on a cluster.** All of this was validated offline and with local Docker. The `securityContext` and the restricted PSS enforcement need a real `make up && make deploy` to confirm — that is the first thing to check next time the cluster comes up.
