# 11 — AWS credentials, and why WSL and Windows never share them

## What we did

Configured AWS credentials for the app-hub account (`314146298861`, IAM user `terraform-learning`) **inside WSL**, and verified that the Windows-side AWS config — which holds unrelated work profiles — was completely unaffected. While verifying, discovered that `kubectl` has the same split: two separate `~/.kube/config` files pointing at two different clusters.

## Why

Nothing that touches AWS could run. `terraform plan`, `terraform apply`, `aws eks update-kubeconfig`, ECR login — every one of them needs credentials, and there were none for this account. It was the single blocker holding up all of Phase 2.

The complication is that this is a **work-managed laptop**. The Windows side already has work AWS profiles on it. Putting personal credentials in the wrong place risks two bad outcomes: a personal `terraform apply` landing in a work account, or work tooling suddenly authenticating as a personal user. Both are the kind of mistake that is embarrassing at best.

## Key concepts

### 1. WSL and Windows have different home directories — this is the whole idea

WSL is a real Linux environment with its own filesystem and its own `$HOME`:

| | Windows | WSL |
|---|---|---|
| Home | `C:\Users\harshit.rawat\` | `/home/harshitrawat/` |
| AWS config | `C:\Users\harshit.rawat\.aws\` | `/home/harshitrawat/.aws/` |
| Kube config | `C:\Users\harshit.rawat\.kube\config` | `/home/harshitrawat/.kube/config` |

These are **different files on different filesystems**. Not synced, not linked, and never will be automatically.

WSL can *see* the Windows drive at `/mnt/c/`, which is why the project files are shared. But `~` inside WSL is the Linux home, not the Windows one. That single fact explains the entire toolchain split in `CLAUDE.md § 5`.

### 2. Two `default` profiles that are not the same profile

Here is the part that looks like a conflict and is not:

- Windows `~/.aws/credentials` → `[default]`, `[uzio-nonprod-audit]`, `[scripttest]` — **work**, and `default` there is intentionally broken
- WSL `~/.aws/credentials` → `[default]` — **app-hub**, `terraform-learning`, account `314146298861`

Both are named `default`. They are different files, read by different binaries, resolving to different AWS accounts. There is no collision, because the two environments never share a home directory.

This is why the original plan — "use a *named* profile like `AWS_PROFILE=app-hub`, don't touch `default`" — turned out to be unnecessary. That advice is correct when two accounts share one config file. Here they do not. Configuring WSL's `default` overwrote nothing, and Terraform picks it up with zero extra configuration.

**The general principle: before worrying about profile collisions, work out whether the configs are even the same file.**

### 3. Credential resolution order

The AWS CLI and SDKs look in a fixed order, first match wins:

1. Explicit `--profile` flag
2. `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` environment variables
3. `AWS_PROFILE` environment variable
4. `~/.aws/credentials` → `[default]`
5. IAM role attached to the instance (EC2/ECS/EKS)

Terraform's AWS provider uses the same chain, which is why `provider "aws" { region = var.aws_region }` needs no credential configuration — it inherits from the environment.

Step 5 matters later: **inside the cluster**, pods get credentials from an IAM role rather than a file. That is the mechanism behind IRSA (see `learn/13`).

### 4. `sts get-caller-identity` is the ground-truth check

```bash
aws sts get-caller-identity
```

```json
{
  "UserId": "AIDAUSJEUDPW7HF6N5G2C",
  "Account": "314146298861",
  "Arn": "arn:aws:iam::314146298861:user/terraform-learning"
}
```

This is the "who am I actually?" command. It requires no permissions beyond being authenticated, so it works even with a heavily restricted user, and it answers three questions at once: are the credentials valid, which account, which principal.

**Run it before anything expensive.** The failure modes are distinguishable:

| Error | Meaning |
|---|---|
| `InvalidClientTokenId` | The access key does not exist or was deleted |
| `SignatureDoesNotMatch` | Key exists, secret is wrong |
| `ExpiredToken` | Temporary/SSO credentials need refreshing |
| `Unable to locate credentials` | Nothing configured at all |

### 5. The two kubeconfigs — the trap this uncovered

Checking the credential split revealed the same pattern in `kubectl`, and this one is sharper:

```
Windows kubectl  → context: minikube
WSL kubectl      → context: arn:aws:eks:ap-south-1:314146298861:cluster/app-hub-eks
```

Two installs, two config files, two different clusters. WSL's already carried an `app-hub-eks` context left over from the earlier proven deploy — confirming EKS work has always happened from WSL, which is consistent with Terraform and the AWS credentials both living there.

**Why this is dangerous:** `kubectl config current-context` returns a confident, plausible answer on *both* sides. Neither errors. So the standard "check your context before applying" advice silently fails if you check on the wrong side of the split.

**The rule that follows:** run `aws eks update-kubeconfig` and every EKS-facing `kubectl` command from WSL. Reserve Windows `kubectl` for minikube. Remember that `update-kubeconfig` writes to *whichever side ran it* — running it on Windows would configure the wrong file and leave WSL untouched.

The deploy path therefore genuinely straddles both environments, because Docker Desktop's WSL integration is not enabled here:

- `docker build` / `docker push` → **Windows**
- `terraform`, `aws`, `kubectl` → **WSL**

## Walkthrough

Configuring, from inside WSL:

```bash
wsl -e bash -lc "aws configure"
```

Four prompts: access key id, secret access key, default region (`ap-south-1`), output format (`json`). This writes `~/.aws/credentials` (the keys) and `~/.aws/config` (region and output).

Verifying — the sequence that actually proves it works:

```bash
wsl -e bash -lc "aws sts get-caller-identity && aws configure get region"
```

Account must be `314146298861`, region must be `ap-south-1`. A wrong region does not error, it just quietly operates in the wrong place.

Confirming the Windows side is untouched:

```bash
aws sts get-caller-identity
```

Should still fail with `InvalidClientTokenId`. **That failure is the correct result** — it is the work profile, and it is supposed to stay broken.

Then confirming Terraform can use it:

```bash
wsl -e bash -lc "cd /mnt/c/Users/harshit.rawat/Documents/Projects/app-hub/infra && terraform init"
```

`init` contacts the S3 backend, so success proves both credentials and backend access.

## Gotchas

- **`aws configure` writes to whichever environment ran it.** Running it on Windows would have configured the wrong side entirely.
- **So does `aws eks update-kubeconfig`.** Same trap, worse consequences — you would end up with a working credential in one place and a kubeconfig in another.
- **Both sides answer `kubectl config current-context` confidently.** Only one is the cluster you mean.
- **Region is silent when wrong.** `ap-south-1` vs `us-east-1` produces "resource not found", not "wrong region".
- **Access keys are long-lived and do not expire.** Unlike SSO sessions, an IAM access key works until deleted — convenient, and a reason to rotate it periodically and never commit it.
- **`~/.aws/credentials` is plaintext.** Permissions are `-rw-------` (owner only), which is the protection you get. Anyone with your user account can read it.

## Verify it yourself

Prove the two AWS configs are genuinely different files:

```bash
wsl -e bash -lc "readlink -f ~/.aws/credentials" && ls -la /c/Users/harshit.rawat/.aws/credentials
```

Different paths, different sizes, different modification times.

Confirm the app-hub identity:

```bash
wsl -e bash -lc "aws sts get-caller-identity --output table"
```

Demonstrate the kubeconfig split — these should disagree:

```bash
echo "windows: $(kubectl config current-context)" && wsl -e bash -lc "echo \"wsl:     \$(kubectl config current-context)\""
```

Check what is actually running right now (both should be empty at rest):

```bash
wsl -e bash -lc "cd /mnt/c/Users/harshit.rawat/Documents/Projects/app-hub/infra && terraform state list; aws eks list-clusters --region ap-south-1"
```

## Going deeper

- [AWS CLI configuration and credential precedence](https://docs.aws.amazon.com/cli/latest/userguide/cli-chap-configure.html)
- [Terraform AWS provider authentication](https://registry.terraform.io/providers/hashicorp/aws/latest/docs#authentication-and-configuration)
- [WSL file system access](https://learn.microsoft.com/en-us/windows/wsl/filesystems) — why `/mnt/c` is shared and `~` is not
- [Organizing kubeconfig files](https://kubernetes.io/docs/concepts/configuration/organize-cluster-access-kubeconfig/) — including `KUBECONFIG` for merging multiple files

---

**Next:** `learn/12` — reading a Terraform plan before spending money on it.
