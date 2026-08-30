# 12 — Reading a Terraform plan before you spend money on it

## What we did

Ran `terraform plan` against the app-hub infrastructure for the first time with working credentials. Result: **55 to add, 0 to change, 0 to destroy**. Nothing was applied — the plan is the review step, and applying needs a separate, explicit decision.

## Why

`terraform apply` on this configuration starts billing an EKS control plane, two EC2 instances, and a NAT gateway — roughly $150–200/month if left running. It also creates 55 AWS resources that you then have to be able to destroy cleanly.

A plan is how you find out what is about to happen while it is still free to change your mind. It is the single most useful safety habit in Terraform, and it costs nothing: `plan` only reads.

There is a second reason it matters here specifically. Because the cluster is destroyed at the end of every session (`CLAUDE.md § 4`), `apply` runs *often*. A step you repeat constantly is exactly the step worth understanding properly rather than muscle-memorying past.

## Key concepts

### 1. What a plan actually is

Terraform compares three things:

1. **Your configuration** — what the `.tf` files declare
2. **State** — what Terraform believes exists (here, in S3)
3. **Reality** — what the AWS API reports right now

The plan is the diff that would bring reality in line with configuration. It runs a *refresh* first — querying AWS for each resource in state — which is why `plan` needs valid credentials even though it changes nothing.

With empty state, as here, there is nothing to refresh and everything is a create.

### 2. The four symbols, and which one should worry you

| Symbol | Meaning | Concern |
|---|---|---|
| `+` | create | Low |
| `~` | update in place | Low — no downtime |
| `-` | destroy | Read carefully |
| `-/+` | **destroy then recreate** | **Read very carefully** |

`-/+` is the one that catches people. Some attributes cannot be changed on a live resource, so Terraform deletes and recreates instead. On an EKS cluster or an RDS instance that means a full outage and, without care, data loss. The plan tells you *why*, in a line like:

```
# forces replacement
```

**Always search a plan for `forces replacement` before applying.** On this project, an unexpected `-/+` on the cluster would mean a rebuild, a new API endpoint, and a stale kubeconfig.

### 3. `(known after apply)` is normal, not vague

```hcl
+ arn = (known after apply)
+ id  = (known after apply)
```

AWS assigns these — ARNs, IDs, IP addresses — at creation time. Terraform cannot know them in advance, and it does not need to. It knows the *dependency graph*: the node group needs the cluster's name, so the cluster is created first and the value flows through.

This is also why outputs read `(known after apply)`.

### 4. The summary line is the headline

```
Plan: 55 to add, 0 to change, 0 to destroy.
```

For this project, from a clean slate, that shape is exactly right. Deviations to notice:

- **anything to destroy**, when you expected only creates — state and reality have diverged
- **far fewer resources than expected** — something is already applied
- **`0 to add, 0 to change, 0 to destroy`** — infrastructure already matches your config; nothing to do

### 5. What the 55 resources actually are

Broken down by module:

| Module | Count | What |
|---|---|---|
| `module.eks` | 37 | Cluster, node group, IAM roles and policy attachments, security groups, KMS key, access entries, add-ons |
| `module.vpc` | 19 | VPC, 4 subnets, IGW, NAT gateway, EIP, route tables and associations |
| root | 3 | ECR repository and its supporting resources |

Fifty-five resources from roughly 60 lines of Terraform — that is what the community modules are doing for you (`learn/04`, `learn/05`).

The ones worth recognising by name:

```
module.vpc.aws_vpc.this[0]                      # the network
module.vpc.aws_subnet.private[0], private[1]    # where nodes run
module.vpc.aws_subnet.public[0],  public[1]     # where load balancers go
module.vpc.aws_internet_gateway.this[0]         # free
module.vpc.aws_nat_gateway.this[0]              # BILLS HOURLY
module.vpc.aws_eip.nat[0]                       # static IP for the NAT
module.eks.aws_eks_cluster.this[0]              # BILLS HOURLY (control plane)
module.eks.module.eks_managed_node_group[...]   # BILLS HOURLY (2x t3.medium)
module.eks.aws_eks_access_entry.this["cluster_creator"]   # the kubectl-access flag
aws_ecr_repository.links_service                # free at this scale
```

Seeing `aws_eks_access_entry.this["cluster_creator"]` in the plan is confirmation that `enable_cluster_creator_admin_permissions = true` is doing its job — that is the resource which prevents the `Unauthorized` trap from `learn/05`.

### 6. Three billable things, and they bill on existence not use

- **EKS control plane** — flat hourly rate, charged while the cluster exists, even with zero pods
- **2× `t3.medium`** — standard EC2 pricing
- **NAT gateway** — hourly *plus* per-GB processed

None of these care whether you are using them. An idle cluster costs the same as a busy one at this scale. **That is the entire justification for the destroy-every-session policy** — and the reason the plan is worth reading rather than skimming.

### 7. `plan` and `apply` can disagree

```
Note: You didn't use the -out option to save this plan, so Terraform can't
guarantee to take exactly these actions if you run "terraform apply" now.
```

Between plan and apply, reality can move — someone changes something in the console, or a data source resolves differently. Saving the plan closes that gap:

```bash
terraform plan -out=tfplan
terraform apply tfplan
```

Applying a saved plan skips the confirmation prompt, because you already reviewed exactly those actions. This is the right pattern in CI. Interactively, the default `apply` re-plans and shows it again before asking — which is fine.

## Walkthrough

Terraform lives in WSL only:

```bash
wsl -e bash -lc "cd /mnt/c/Users/harshit.rawat/Documents/Projects/app-hub/infra && terraform plan -input=false -no-color"
```

- `-input=false` — fail rather than prompt for missing variables. Correct for non-interactive runs; here every variable has a default.
- `-no-color` — strip ANSI escape codes, so the output is readable when captured or piped.

Getting a summary rather than 2,000 lines of attributes:

```bash
terraform plan -no-color 2>&1 | grep -E '^  # '
```

Every resource line in a plan starts with `  # `, so this lists what will change without the detail. Good first pass; read the full output before an apply that matters.

Checking specifically for replacements:

```bash
terraform plan -no-color 2>&1 | grep -B5 'forces replacement'
```

## Gotchas

- **`plan` needs credentials** even though it changes nothing — it refreshes against the live API.
- **`plan` is not a lock.** Someone else applying between your plan and your apply invalidates it. `-out` is the fix.
- **A clean plan is not a guarantee of a clean apply.** Terraform validates configuration, not AWS service quotas, capacity, or IAM conditions. EIP limits and vCPU quotas are common surprises in a fresh account.
- **EKS creation is slow.** 10–15 minutes for the control plane, several more for nodes. `apply` has not hung.
- **Destroy is the mirror image and can fail.** A `LoadBalancer` Service creates an AWS load balancer Terraform does not track, which then blocks VPC deletion. Delete such Services before destroying (`learn/07`).
- **The billing starts at `apply`, not at first use.** There is no grace period.

## Verify it yourself

The plan itself, free and read-only:

```bash
wsl -e bash -lc "cd /mnt/c/Users/harshit.rawat/Documents/Projects/app-hub/infra && terraform plan -input=false -no-color | tail -20"
```

Just the resource list:

```bash
wsl -e bash -lc "cd /mnt/c/Users/harshit.rawat/Documents/Projects/app-hub/infra && terraform plan -no-color 2>&1 | grep -E '^  # ' | wc -l"
```

Confirm nothing is currently deployed — empty output means nothing is billing:

```bash
wsl -e bash -lc "cd /mnt/c/Users/harshit.rawat/Documents/Projects/app-hub/infra && terraform state list"
```

Cross-check against AWS directly, rather than trusting state:

```bash
wsl -e bash -lc "aws eks list-clusters --region ap-south-1 && aws ec2 describe-nat-gateways --filter Name=state,Values=available --region ap-south-1 --query 'NatGateways[*].NatGatewayId' --output text"
```

Those two commands are the honest answer to "am I being charged right now?".

## Going deeper

- [The `terraform plan` command](https://developer.hashicorp.com/terraform/cli/commands/plan)
- [Resource behaviour and replacement](https://developer.hashicorp.com/terraform/language/resources/behavior)
- [`create_before_destroy` and lifecycle rules](https://developer.hashicorp.com/terraform/language/meta-arguments/lifecycle) — how to soften a `-/+`
- [AWS pricing calculator](https://calculator.aws/) — worth pricing this stack once, properly

---

**Next:** `learn/13` — where the data goes, and why a nightly-destroyed cluster cannot hold it.
