# 03 — Terraform: providers, variables, and why state lives in S3

> **Backfilled.** Reconstructed from `infra/providers.tf`, `infra/variables.tf`, `infra/outputs.tf` and git history (`c8f6c12`, `009bd10`).

## What we did

Scaffolded the `infra` Terraform project: pinned Terraform and the AWS provider, configured an **S3 remote backend** for state with native locking, declared the `aws_region` variable, and defined outputs for the values other steps need.

## Why

The cluster, the network, and the registry all have to be created somehow. Doing it by clicking through the AWS console has three problems: it is not repeatable, it is not reviewable, and it leaves no record of what exists. Terraform makes infrastructure **code** — the same inputs produce the same infrastructure, changes show up in a diff, and teardown is one command.

That last point matters enormously here. The standing policy is to destroy the cluster at the end of every session (`CLAUDE.md § 4`). A reliable `terraform destroy` is what makes that policy survivable — and a reliable `terraform apply` is what makes it repeatable the next morning.

## Key concepts

### 1. State is Terraform's memory, and it is the whole ballgame

Terraform keeps a **state file** mapping the resources you declared to the real objects that exist in AWS. `module.vpc.aws_vpc.this[0]` ↔ `vpc-0a1b2c3d`.

Without state, Terraform cannot know whether it should create, update, or delete. It would have no idea that the VPC in your code is the VPC already running.

Consequences:

- **Losing state is much worse than losing code.** Code you can rewrite. Lose state and Terraform forgets it owns your infrastructure — the next `apply` tries to create everything again, and the real resources become orphans nothing manages.
- **State contains resource attributes, including sensitive ones.** This is why `*.tfstate` is in `.gitignore` and must stay there.

### 2. Remote state — why it is not on your laptop

```hcl
backend "s3" {
  bucket       = "app-hub-tfstate-314146298861"
  key          = "infra/terraform.tfstate"
  region       = "ap-south-1"
  use_lockfile = true
}
```

By default Terraform writes `terraform.tfstate` next to your code. That is fine for a tutorial and wrong for anything real: it lives on one machine, is not backed up, and cannot be shared.

The S3 backend puts state in a bucket instead. `bucket` is where, `key` is the path within it. The account id in the bucket name is a common convention — S3 bucket names are **globally unique across all AWS customers**, so appending an account id makes collisions essentially impossible.

**`use_lockfile = true` is the load-bearing line.** It enables S3-native state locking: while one `apply` is running, a lock object prevents a second from starting. Two concurrent applies against one state file can corrupt it — one writes over the other's view of reality.

Historically this required a separate **DynamoDB table**, and most tutorials still tell you to create one. S3 gained conditional writes, so the lock can live in S3 itself. **One less resource, one less thing to forget to destroy.** If you find a guide insisting on `dynamodb_table`, it predates this feature.

There is a chicken-and-egg problem worth noticing: the bucket holding the state cannot itself be created by the Terraform that uses it. It has to exist first, made by hand or by a separate bootstrap.

### 3. Version pinning, in two places

```hcl
terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}
```

`required_version` constrains the Terraform binary. `required_providers` constrains the plugin that talks to AWS.

`~> 5.0` is the **pessimistic constraint operator**: allow 5.1, 5.99 — reject 6.0. The convention is that a major-version bump may break things, so this accepts bug fixes and features while blocking breaking changes.

`.terraform.lock.hcl` then records the exact provider versions and their checksums — same idea as `uv.lock` for Python. Ordinarily you commit it; note that `infra/.gitignore` currently excludes it, which is a deliberate-looking but debatable choice.

### 4. Variables — declaration vs. assignment

```hcl
variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "ap-south-1"
}
```

This **declares** the variable. `terraform.tfvars` **assigns** it (`aws_region = "ap-south-1"`). The declaration says what may be set; the assignment says what it actually is.

`*.tfvars` is gitignored because it is the natural place for environment-specific and sensitive values. That does mean a fresh clone has no `.tfvars` — here the `default` covers it.

Note that Terraform reads **every `.tf` file** in the directory and merges them. Filenames are for humans; the parser does not care. That is why `vairables.tf` was a harmless typo for months, and why deleting an empty `main.tf` broke nothing.

### 5. Outputs — the seam between steps

```hcl
output "cluster_name"      { value = module.eks.cluster_name }
output "cluster_endpoint"  { value = module.eks.cluster_endpoint }
output "vpc_id"            { value = module.vpc.vpc_id }
output "private_subnet_ids"{ value = module.vpc.private_subnets }
```

Outputs surface values from inside the configuration so humans and other tools can read them, via `terraform output`. They are how you answer "what is the cluster called?" without digging through state.

## Walkthrough

The workflow, in the order you actually use it:

```bash
terraform init
```

Reads the `terraform` block, downloads the providers into `.terraform/`, and configures the backend. **Run it after any change to provider versions or backend config.** This is what created the ~800 MB `.terraform/` directory — vendored provider binaries, gitignored, never to be read.

```bash
terraform plan
```

Refreshes state against reality, compares it to your code, and prints what it *would* do. Free, read-only, and safe to run any time. `+` create, `-` destroy, `~` update in place, `-/+` replace.

**Read the plan.** A `-/+` on the cluster means it will be destroyed and rebuilt — very different from `~`.

```bash
terraform apply
```

Plans again, shows it, waits for `yes`. **Costs money here** — needs explicit approval per session (`CLAUDE.md § 4`).

```bash
terraform destroy
```

Removes everything in state. Routine in this project, not exceptional.

Two free commands worth habit-forming:

```bash
terraform fmt -recursive
terraform validate
```

`fmt` normalises formatting; `validate` checks syntax and internal consistency without touching AWS.

## Gotchas

- **Terraform only runs in WSL here.** Not on the Windows PATH. The vendored providers under `.terraform/providers/` are `linux_amd64` — proof it has only ever run from Linux.
- **The local `infra/terraform.tfstate` is a decoy.** It is a pre-migration stub with `"serial": 1` and zero resources, left over from before the S3 backend. It proves nothing about what is deployed. Reading it is exactly the mistake that produced a wrong entry in `PROGRESS.md` (see `learn/09`).
- **`terraform plan` needs valid credentials** even though it changes nothing — it refreshes state against the live API. With no working profile it fails immediately (currently `E-00`).
- **Never hand-edit state.** If it drifts, use `terraform import`, `terraform state mv`, or `terraform state rm`.
- **`.terraform/` is not code.** It is regenerated by `init`, and it is 800 MB. Never read it, never commit it.

## Verify it yourself

Everything below is read-only and safe:

```bash
wsl -e bash -lc "cd /mnt/c/Users/harshit.rawat/Documents/Projects/app-hub/infra && terraform validate && terraform fmt -check -recursive ."
```

Check formatting and validity without touching AWS. Then, once credentials exist (`E-00`):

```bash
wsl -e bash -lc "cd /mnt/c/Users/harshit.rawat/Documents/Projects/app-hub/infra && terraform state list"
```

An empty result means nothing is deployed — the expected resting state here. A populated list means the cluster is up and **billing**.

See where state actually lives:

```bash
aws s3 ls s3://app-hub-tfstate-314146298861/infra/
```

## Going deeper

- [Terraform state](https://developer.hashicorp.com/terraform/language/state) — why it exists and what it holds
- [S3 backend](https://developer.hashicorp.com/terraform/language/backend/s3) — including `use_lockfile` and the DynamoDB history
- [Version constraints](https://developer.hashicorp.com/terraform/language/expressions/version-constraints) — the `~>` operator
- [Terraform outputs](https://developer.hashicorp.com/terraform/language/values/outputs)

---

**Next:** `learn/04` — the VPC the cluster lives in.
