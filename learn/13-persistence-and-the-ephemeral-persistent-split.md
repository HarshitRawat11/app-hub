# 13 — Persistence: DynamoDB, IRSA, and splitting Terraform into two stacks

## What we did

Decided how `links-service` will store data (`C-03`), and applied the immediate stopgap: **pinned the Deployment to a single replica**, with a comment explaining why and what has to land before it goes back up.

The full implementation — a second Terraform stack, a DynamoDB table, IRSA, and a repository layer in the service — is broken out as `C-04`, `C-05`, `C-06`. Those are new concepts, so per `CLAUDE.md § 2` the first implementation is written by hand.

## Why

Two separate problems, and it is worth keeping them apart.

**Problem 1: inconsistent reads, today.** `links_db` is an in-process dict and the Deployment ran `replicas: 2`. Two pods, two independent dicts, one Service load-balancing between them at random. Create a link — it lands on pod A. Read it back — you might hit pod B, which has never heard of it. That is not a slow degradation, it is a coin flip on every request.

**Problem 2: nothing survives a restart.** Even with one replica, the dict dies with the process. Pod restarts, node replacement, and every `terraform destroy` wipe the catalogue.

`replicas: 1` fixes problem 1 completely and problem 2 not at all. It is honest as a stopgap: the service stops being *randomly wrong*, and is still *ephemeral*.

## Key concepts

### 1. The constraint that decides everything: the cluster is destroyed nightly

This is the part that makes the obvious answer wrong.

The standing cost policy destroys the cluster at the end of every session. So:

- **Postgres in a pod** → dies with the cluster
- **Postgres on a PersistentVolume** → the PVC is in the destroyed stack; the underlying EBS volume may survive as an orphan, which is worse than either outcome
- **RDS inside `infra/`** → `terraform destroy` deletes it along with everything else

Add a database the naive way and you would pay for it, add complexity, and *still* lose your links every evening.

**The insight: if the cluster is ephemeral by policy, then anything that must persist has to live outside the thing being destroyed.** That is not a workaround, it is the actual architecture.

### 2. The ephemeral / persistent stack split

Terraform state is per-stack. Split the configuration into two directories with two state files:

```
infra/              # EPHEMERAL - destroyed every session
  vpc.tf            #   VPC, subnets, NAT, IGW
  eks.tf            #   cluster + node group
  ecr.tf            #   registry (images are rebuildable)

persistent/         # PERSISTENT - never destroyed
  dynamodb.tf       #   the links table
  iam.tf            #   the IRSA role the service assumes
```

`terraform destroy` in `infra/` cannot touch anything in `persistent/`, because it is not in that state file. Destroy safety becomes a property of *where a resource is declared*, not of remembering to be careful.

The two stacks connect through a **remote state data source** or by looking resources up by name — the persistent stack exports the table name and role ARN; the ephemeral stack (or the manifests) consume them.

**This pattern generalises well beyond this project.** Any environment that is torn down and rebuilt — ephemeral preview environments, spot-instance clusters, dev sandboxes — needs the same boundary between "cattle" and the data the cattle operate on.

### 3. Why DynamoDB rather than Postgres

| | DynamoDB | RDS Postgres |
|---|---|---|
| Cost at idle | **~$0** (on-demand; 25 GB free tier) | ~$15/mo minimum, billed continuously |
| Survives cluster destroy | Yes, trivially | Yes, if in the persistent stack |
| Ops burden | None — serverless | Patching, backups, connection limits |
| Data model | Key-value / document | Relational, SQL, joins |
| Teaches | IRSA, AWS SDK, NoSQL modelling | SQL, pooling, migrations |

For a personal link catalogue — a handful of items, single-key lookups, no joins — DynamoDB is a genuinely good fit rather than a compromise. The access patterns are exactly what it is designed for: get by id, scan a small table.

The decisive factor is cost shape. **RDS bills for existing; DynamoDB on-demand bills for use.** A database that costs nothing while you are not using it can stay up permanently, which is precisely what the persistent stack needs.

The honest counter-argument: it is NoSQL, and n8n-on-EKS (`N-06`) will need Postgres anyway. If you would rather learn one datastore deeply, put RDS Postgres in the persistent stack and share it. More transferable to typical org stacks, ~$15/month.

### 4. IRSA — how a pod gets AWS permissions without credentials

This is the highest-value thing in the whole task, and it is worth doing properly.

The naive approach is to create an IAM user, generate an access key, and put it in a Kubernetes Secret. That means a long-lived credential sitting in the cluster, needing rotation, and readable by anyone with Secret access.

**IRSA (IAM Roles for Service Accounts)** removes the credential entirely:

1. The cluster gets an **OIDC identity provider** — EKS issues signed tokens describing "this pod is running as ServiceAccount X in namespace Y"
2. An **IAM role** is created with a trust policy accepting tokens from that provider, for that specific ServiceAccount
3. The Kubernetes **ServiceAccount** is annotated with the role ARN
4. The AWS SDK inside the pod finds a projected token, exchanges it via STS for temporary credentials, and refreshes them automatically

Net effect: **the pod assumes an IAM role, scoped to one table, with no stored secret and automatic rotation.** Nothing to leak, nothing to rotate.

Recall the credential chain from `learn/11` — step 5 was "IAM role attached to the instance". IRSA is the pod-level version, and it is why the application code needs no credential configuration at all: `boto3.resource("dynamodb")` just works.

### 5. The repository pattern — keeping the swap contained

The service currently does this, inline in the handlers:

```python
links_db[next_id] = new_link
```

Swapping storage means touching every handler. The fix is to put a thin layer between the handlers and the storage:

```python
# app/repository.py
class LinkRepository:
    def list(self) -> list[Link]: ...
    def get(self, id: int) -> Link | None: ...
    def create(self, data: LinkCreate) -> Link: ...
    def delete(self, id: int) -> bool: ...
```

Two implementations — `InMemoryLinkRepository` and `DynamoDBLinkRepository` — behind one interface. Handlers depend on the interface, so switching backends is a configuration change, not a rewrite.

This also solves the testing problem from `C-02`: tests use the in-memory implementation and never touch AWS.

**The general principle: isolate the thing you expect to change behind an interface, and the change stops rippling.**

### 6. Id generation has to move

`next_id` as a module-level counter with `global` cannot survive multiple processes — two pods would both hand out id 5.

Options, in rough order of preference here:

- **A UUID or ULID generated by the service** — no coordination needed at all, works with any number of replicas. ULIDs sort by creation time, which is a nice property.
- **A DynamoDB atomic counter** — a dedicated item incremented with `UpdateExpression: SET n = n + :one`, returning the new value. Keeps integer ids; costs an extra write.

UUIDs are the simpler answer. It changes `Link.id` from `int` to `str`, which touches the models and the path parameters.

## Walkthrough — what changed now

Only the stopgap. In `manifests/links-service/deployment.yaml`:

```yaml
spec:
  # Pinned to 1 deliberately. links-service holds state in an in-process dict,
  # so two replicas would each hold independent data and the Service would
  # load-balance between them at random -- a link created on one pod would be
  # invisible on the other. Raise this only after the DynamoDB persistence
  # work lands (C-04..C-06 in PROGRESS.md).
  replicas: 1
```

The comment matters as much as the value. A bare `replicas: 1` invites a future reader — including you — to "fix" the availability by raising it, silently reintroducing the bug. Recording *why*, and *what has to be true before changing it*, is the difference between a decision and an accident.

Verified the manifest still parses and the selector/label invariant holds:

```
links-service/deployment.yaml -> Deployment OK
   replicas: 1
   selector matches template labels: True
```

## Gotchas

- **`replicas: 1` means no redundancy.** During a rolling update or a node failure there is a window with zero pods. That is an acceptable trade for a service whose data is wrong with two replicas, but know that you made it.
- **Do not raise replicas before persistence lands.** The comment in the manifest exists for exactly this.
- **IRSA requires the OIDC provider to be enabled on the cluster.** The EKS module can do it, but it is a cluster-level setting that must exist before any role trust policy references it.
- **DynamoDB free tier is per-account, not per-table.** Fine here; worth knowing if you add more tables.
- **On-demand vs provisioned capacity.** On-demand is right for spiky, low, unpredictable traffic. Provisioned is cheaper at sustained high throughput and can throttle you if you underprovision.
- **A shared table across services is a coupling trap.** Give each service its own table.
- **The persistent stack needs its own state key**, e.g. `persistent/terraform.tfstate` in the same bucket — not the same key as `infra/`, or they overwrite each other.

## Verify it yourself

Confirm the replica pin and that the manifest is still structurally valid:

```bash
wsl -e bash -lc "cd /mnt/c/Users/harshit.rawat/Documents/Projects/app-hub/manifests && python3 -c \"import yaml; d=yaml.safe_load(open('links-service/deployment.yaml')); print('replicas:', d['spec']['replicas']); print('selector ok:', d['spec']['selector']['matchLabels']==d['spec']['template']['metadata']['labels'])\""
```

Once deployed, demonstrate the bug the pin prevents — scale to 2, then create and read repeatedly. Results will vary by which pod answers:

```bash
kubectl scale deployment/links-service --replicas=2
```

Scale back down afterwards. Do not leave it at 2.

## Going deeper

- [IAM Roles for Service Accounts (IRSA)](https://docs.aws.amazon.com/eks/latest/userguide/iam-roles-for-service-accounts.html)
- [DynamoDB core components](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/HowItWorks.CoreComponents.html)
- [DynamoDB on-demand vs provisioned](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/HowItWorks.ReadWriteCapacityMode.html)
- [Terraform `terraform_remote_state` data source](https://developer.hashicorp.com/terraform/language/state/remote-state-data) — how the ephemeral stack reads the persistent one
- [The repository pattern](https://martinfowler.com/eaaCatalog/repository.html)

---

**Next:** `learn/14` — testing the service, which is the prerequisite for changing its storage safely.
