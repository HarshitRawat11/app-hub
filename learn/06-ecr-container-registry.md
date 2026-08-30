# 06 — ECR: the registry, and the flag that makes teardown work

> **Backfilled.** Reconstructed from `infra/ecr.tf` and git history (`19f7a5e`, `cdfa2d5`).

## What we did

Created an ECR (Elastic Container Registry) repository at `app-hub/links-service`, with vulnerability scanning on push, mutable tags, and `force_delete = true`.

## Why

The image built in `learn/02` exists only on your laptop. Kubernetes nodes cannot see it — they are EC2 instances in a private subnet in AWS. The image has to live somewhere both you and the cluster can reach.

That is a **container registry**. Docker Hub is the public one; ECR is AWS's, and it is the natural choice here for two reasons: it lives in the same account and region as the cluster (so pulls do not traverse the internet or incur egress), and node IAM roles can authenticate to it without any credentials stored in the cluster.

## Key concepts

### 1. Registry, repository, image, tag

Four nested things, easy to blur:

| Term | Here |
|---|---|
| **Registry** | `314146298861.dkr.ecr.ap-south-1.amazonaws.com` — one per account per region |
| **Repository** | `app-hub/links-service` — holds all versions of one image |
| **Image** | A specific build, identified by a content digest (`sha256:...`) |
| **Tag** | A human label pointing at a digest — `v1`, `latest` |

The full reference the Deployment uses:

```
314146298861.dkr.ecr.ap-south-1.amazonaws.com/app-hub/links-service:v1
└──────────── registry ─────────────────────┘└─── repository ───┘└tag┘
```

The `app-hub/` prefix is just part of the repository name — ECR allows slashes, so it reads like a namespace. Each additional service gets its own repository (`app-hub/gateway`, etc.).

### 2. Tag mutability — the one to change later

```hcl
image_tag_mutability = "MUTABLE"
```

**Mutable** means you can push a *different* image to the same tag. Push `v1` today, push a rebuilt `v1` tomorrow, and `v1` now points somewhere else.

This is convenient during development and genuinely dangerous in a cluster:

- Two pods started at different times from `:v1` can be running **different code**
- A rollback to `:v1` does not necessarily get you back what you had
- "Which build is in production?" stops having a reliable answer

**Immutable** rejects a second push to an existing tag. The standard fix is to tag by git commit SHA — every build gets a unique, meaningful, unrepeatable tag.

This is tracked as `R-03`. `MUTABLE` is a reasonable starting point; it should not survive to a real workflow.

### 3. `scan_on_push` — free vulnerability scanning

```hcl
image_scanning_configuration {
  scan_on_push = true
}
```

ECR scans each pushed image against the CVE database and reports vulnerabilities by severity. Basic scanning is free.

It scans the OS packages in your base image, which is a good argument for `-slim` variants — fewer packages, fewer CVEs, smaller attack surface. It does not scan your application code.

### 4. `force_delete = true` — the hard-won one

```hcl
force_delete = true
```

**This one cost real time to discover.**

By default, AWS refuses to delete an ECR repository that still contains images. It is a safety measure against destroying artefacts you might need.

In this project it is a trap. The workflow is: apply infra → push an image → deploy → `terraform destroy`. At destroy time the repository contains the image you just pushed, AWS refuses to delete it, and **`terraform destroy` fails partway through** — leaving a half-destroyed stack and, importantly, a NAT gateway still billing.

`force_delete = true` tells Terraform to delete the repository and its contents. It was added in a follow-up commit (`cdfa2d5`, "Add force_delete to ECR repo for easier teardown") — the sequencing tells you it was found the hard way.

**Do not remove it.** It is recorded in `CLAUDE.md § 9` for exactly that reason.

The general lesson generalises past ECR: **resources that accumulate content — S3 buckets, ECR repositories, CloudWatch log groups — often refuse deletion while non-empty.** In a create-and-destroy-repeatedly workflow, that turns into failed teardowns and lingering costs.

### 5. Authentication is a token, not a stored password

```bash
aws ecr get-login-password --region ap-south-1 \
  | docker login --username AWS --password-stdin 314146298861.dkr.ecr.ap-south-1.amazonaws.com
```

`get-login-password` uses your AWS credentials to mint a **temporary token** (valid ~12 hours). The username is literally `AWS`; the token is the password.

Piping into `--password-stdin` matters: passing `--password <value>` on the command line would put the token in your shell history and in the process list, where other users on the machine can see it.

**Nodes do not need this.** The EKS node IAM role includes `AmazonEC2ContainerRegistryReadOnly`, so nodes pull from ECR using their instance role — no secret stored in the cluster, nothing to rotate. This is a real advantage of same-account ECR over an external registry, where you would need an `imagePullSecret`.

### 6. The output that ties the steps together

```hcl
output "links_service_ecr_url" {
  value = aws_ecr_repository.links_service.repository_url
}
```

Rather than hand-assembling the registry URL from the account id and region, ask Terraform:

```bash
terraform output links_service_ecr_url
```

Note this output lives in `ecr.tf` alongside its resource, while other outputs live in `outputs.tf`. Terraform merges all `.tf` files, so both work — but keeping outputs in one place is the more consistent convention.

## Walkthrough

The full path from source to a running pod:

```bash
docker build -t links-service:dev ./links-service
```

Build locally, and confirm it runs before pushing anything.

```bash
aws ecr get-login-password --region ap-south-1 | docker login --username AWS --password-stdin 314146298861.dkr.ecr.ap-south-1.amazonaws.com
```

Authenticate. Expect `Login Succeeded`.

```bash
docker tag links-service:dev 314146298861.dkr.ecr.ap-south-1.amazonaws.com/app-hub/links-service:v1
```

A tag is a *label on an existing image*, not a copy — this is instant and consumes no extra space. Pushing requires the full registry-qualified name, which is how Docker knows where to send it.

```bash
docker push 314146298861.dkr.ecr.ap-south-1.amazonaws.com/app-hub/links-service:v1
```

Uploads layer by layer, skipping any the registry already has.

The Deployment then references that exact string, and nodes pull it using their instance role.

## Gotchas

- **`force_delete = true` must stay.** Without it, `terraform destroy` fails once an image exists — and the NAT gateway keeps billing.
- **The login token expires (~12h).** A `denied` or `no basic auth credentials` error after a while usually just means re-authenticate.
- **The repository must exist before you push.** ECR does not create repositories on demand the way Docker Hub does. `E-02` (apply) precedes `E-03` (push).
- **Region must match everywhere.** Login region, repository region, cluster region. A mismatch produces a confusing auth failure rather than a clear "wrong region".
- **Architecture matters.** An image built on an ARM Mac will not run on `t3.medium` (x86_64) without `--platform linux/amd64`. Not an issue on this Windows/x86 machine, but the failure mode — `exec format error` in the pod — is worth recognising.
- **Untagged images still cost storage.** Re-pushing a mutable tag orphans the previous image; it lingers until deleted. A lifecycle policy would clean these up automatically.

## Verify it yourself

Once credentials exist and the repository is applied:

```bash
aws ecr describe-repositories --repository-names app-hub/links-service --region ap-south-1 --query "repositories[*].[repositoryName,repositoryUri,imageTagMutability]" --output table
```

Ask Terraform for the URL rather than assembling it by hand:

```bash
wsl -e bash -lc "cd /mnt/c/Users/harshit.rawat/Documents/Projects/app-hub/infra && terraform output links_service_ecr_url"
```

List what is actually stored, with digests and sizes:

```bash
aws ecr describe-images --repository-name app-hub/links-service --region ap-south-1 --query "imageDetails[*].[imageTags[0],imagePushedAt,imageSizeInBytes]" --output table
```

Check the scan findings for a pushed image:

```bash
aws ecr describe-image-scan-findings --repository-name app-hub/links-service --image-id imageTag=v1 --region ap-south-1 --query "imageScanFindings.findingSeverityCounts"
```

## Going deeper

- [ECR user guide](https://docs.aws.amazon.com/AmazonECR/latest/userguide/what-is-ecr.html)
- [Image tag mutability](https://docs.aws.amazon.com/AmazonECR/latest/userguide/image-tag-mutability.html) — the case for immutable tags
- [ECR lifecycle policies](https://docs.aws.amazon.com/AmazonECR/latest/userguide/LifecyclePolicies.html) — automatic cleanup of untagged images
- [Private registry authentication](https://docs.aws.amazon.com/AmazonECR/latest/userguide/registry_auth.html)

---

**Next:** `learn/07` — the Kubernetes manifests that turn this image into running pods.
