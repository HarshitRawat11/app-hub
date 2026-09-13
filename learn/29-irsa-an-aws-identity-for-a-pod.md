# 29 — IRSA: giving a pod an AWS identity without giving it a secret

> **Written by Claude at the owner's request, 2026-09-13**, using the escape
> hatch in `CLAUDE.md § 2`. It is nonetheless a **full seven-section file**
> rather than the three-section note delegated work normally gets — because
> IRSA is exactly the kind of thing `C-05` existed to teach, and a short note
> would compound the skip rather than record it. **The concept to revisit is
> the trust policy's `sub` condition**: it is the first place in this project
> where a wrong Terraform detail *grants access* rather than breaking a
> deploy.

## What we did

Gave `links-service` an AWS identity, so its pod can read and write the
`app-hub-links` DynamoDB table — with **no access key stored anywhere.**

Three pieces:

- `infra/irsa.tf` — an IAM role whose trust policy accepts tokens from this
  cluster's OIDC provider, but only for one specific ServiceAccount, plus an
  inline policy granting exactly four DynamoDB actions on exactly one table.
- `manifests/links-service/00-serviceaccount.yaml` — a `ServiceAccount`
  annotated with that role's ARN.
- `manifests/links-service/deployment.yaml` — `serviceAccountName` and the
  `LINKS_TABLE_NAME` env var, added **in the same change** (see `D-18`).

**Status: written and validated offline. NOT applied.** `terraform validate`
passes and `validate-manifests.py` passes; nothing has run on a cluster.

## Why

Until now, every AWS credential in this project has been a secret sitting in a
file — `~/.aws/credentials` in WSL. That is fine on a laptop you control. It is
not fine inside a container image or a Kubernetes Secret, because:

- a Secret is base64, not encryption; anyone who can read the namespace reads it
- it does not rotate, so a leak is permanent until noticed
- it ends up in a `kubectl describe`, a log, a backup, a screenshot

IRSA removes the secret entirely. There is nothing to leak, because **no
credential exists at rest** — only a short-lived token the kubelet mints and
rotates, which is useless outside this cluster.

Without it, `C-06` cannot actually be used: the repository layer is written and
verified against the real table *from a laptop*, but the pod has no way to
authenticate. `D-18` exists precisely because wiring half of this up produces a
pod that looks perfectly healthy and fails every request.

## Key concepts

**OIDC (OpenID Connect)** — a standard way for one system to prove an identity
to another using a signed token. EKS runs an OIDC *provider*: a public endpoint
publishing the keys needed to verify tokens it issued.

**Projected ServiceAccount token** — a JWT the kubelet writes into the pod's
filesystem and refreshes automatically. It says "I am ServiceAccount X in
namespace Y of cluster Z", signed by the cluster.

**`sts:AssumeRoleWithWebIdentity`** — the AWS call that trades such a token for
temporary credentials. STS verifies the signature against the registered
provider, then checks your trust policy's conditions.

**Trust policy vs permission policy** — two different questions, and conflating
them is the usual source of confusion:

| | Answers |
|---|---|
| Trust policy (`assume_role_policy`) | **Who may become this role?** |
| Permission policy | **What may the role do once assumed?** |

A perfect permission policy with a sloppy trust policy is wide open.

**The `sub` claim** — the token's subject, always shaped
`system:serviceaccount:<namespace>:<name>`. Matching on it is what narrows the
role from "anything in the cluster" to "this one workload".

## Walkthrough

### The trust policy — the part that actually controls access

```hcl
principals {
  type        = "Federated"
  identifiers = [module.eks.oidc_provider_arn]
}

condition {
  test     = "StringEquals"
  variable = "${module.eks.oidc_provider}:sub"
  values   = ["system:serviceaccount:${var.namespace}:links-service"]
}

condition {
  test     = "StringEquals"
  variable = "${module.eks.oidc_provider}:aud"
  values   = ["sts.amazonaws.com"]
}
```

**Drop the `sub` condition and every ServiceAccount in the cluster can assume
this role.** Every pod, every namespace. Nothing breaks, no test fails, and
DynamoDB becomes readable and writable by anything running there. That is the
classic IRSA mistake, and it is classic *because* the symptom of getting it
wrong is that everything works.

Note the two different module outputs. `oidc_provider_arn` is the ARN, used as
the principal. `oidc_provider` is the **URL with `https://` stripped**, used to
prefix the condition keys. Swap them and you get a policy that is syntactically
valid and never matches — an `AccessDenied` with nothing obviously wrong.

### Crossing the stack boundary

The table is in `infra/persistent/`, a different stack with its own state file.
`irsa.tf` needs its ARN:

```hcl
data "aws_dynamodb_table" "links" {
  name = var.links_table_name
}
```

A data source, not `terraform_remote_state`, and not a hand-built ARN string:

- remote state works but couples this stack to another's internal shape for one string
- a constructed ARN is simplest, and silently wrong the day anything moves
- a data source **asks AWS**, and if the table is missing, `plan` fails clearly

That last point is the argument. A role granting access to a table that does
not exist is not something to apply quietly.

### Least privilege, meant literally

```hcl
actions = [
  "dynamodb:GetItem",
  "dynamodb:PutItem",
  "dynamodb:DeleteItem",
  "dynamodb:Scan",
]
resources = [data.aws_dynamodb_table.links.arn]
```

Exactly the four calls `DynamoDBLinkRepository` makes — nothing more. Not
`dynamodb:*`, not `Resource: "*"`. If a fifth call is added later it fails with
`AccessDenied`, which is a good failure: it says what changed.

### The Kubernetes side

```yaml
metadata:
  name: links-service
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::314146298861:role/app-hub-links-service
```

That annotation is **the entire link** between the two worlds. An admission
webhook watches for it and injects `AWS_ROLE_ARN`,
`AWS_WEB_IDENTITY_TOKEN_FILE` and a projected token volume into any pod using
this ServiceAccount. boto3's default credential chain does the rest — which is
why `repository.py` constructs a client with no credentials and simply works.

The filename is `00-serviceaccount.yaml` because `kubectl apply -f <dir>`
applies in **filename order**, and `deployment.yaml` sorts first. Same trick,
same reason, as `manifests/00-namespace.yaml`.

## Gotchas

- **A missing `sub` condition does not fail.** It silently widens the role to
  the whole cluster. This is the one to check twice.
- **`oidc_provider` and `oidc_provider_arn` are different outputs.** Using the
  ARN where the URL belongs gives a policy that never matches.
- **`LINKS_TABLE_NAME` without `serviceAccountName` is the worst failure mode
  in this project** (`D-18`): `build_repository()` only constructs a boto3
  resource, so **startup succeeds**; `/health` never touches storage, so
  **liveness and readiness both pass and the pod sits `Running` and `Ready`**;
  then every `/links` request fails with `NoCredentialsError`. A pod healthy by
  every probe and broken for every request. **`validate-manifests.py` now fails
  on this** rather than leaving it as prose.
- **`AWS_REGION` must be set too.** A container has no `~/.aws/config`, so
  boto3 raises `NoRegionError` — which reads like a credentials fault and is
  not.
- **The role lives in the ephemeral stack on purpose.** The OIDC provider is
  created with the cluster, so its URL changes on every rebuild and the trust
  policy must be regenerated with it. The role *name* is fixed, so the ARN is
  stable and the manifest never changes.
- **`replicas` stays at 1 in this change.** `C-06` removed the reason it had to
  be, but raising it in the same change as a brand-new credential path means a
  failure is indistinguishable from a replica problem. Raise it after one
  successful deploy; `D-02` closes then.

## Verify it yourself

Nothing here is proven until it runs. After `make up` and `make deploy`:

```bash
kubectl -n app-hub exec deploy/links-service -- env | grep AWS_
```

Expect `AWS_ROLE_ARN` and `AWS_WEB_IDENTITY_TOKEN_FILE`. **Empty output means
the webhook never fired** — check the annotation before suspecting IAM.

```bash
kubectl -n app-hub logs deploy/links-service | tail -20
```

Then the real test — a write that has to reach DynamoDB:

```bash
kubectl -n app-hub port-forward svc/links-service 8000:80
```

`POST` a link, then confirm it landed in the table itself rather than a dict:

```bash
aws dynamodb scan --table-name app-hub-links --region ap-south-1 --query Count
```

**That count going up is the proof.** A `201` from the API is not — the
in-memory repository returns `201` just as happily.

If it fails, the error names the layer: `NoCredentialsError` means the
annotation or ServiceAccount wiring; `AccessDenied` means the trust policy
matched but the permission policy is short; `NoRegionError` means `AWS_REGION`.

## Going deeper

- `learn/26` — the repository layer this exists to make usable in-cluster
- `learn/13` — why DynamoDB, and the ephemeral/persistent stack split
- AWS docs: *IAM roles for service accounts* — particularly the trust policy
  examples, where the `sub` condition is spelled out
- Worth reading next: **EKS Pod Identity**, a newer alternative that drops the
  OIDC trust policy in favour of an association API. IRSA is still the
  widely-deployed one and the one worth understanding first, because Pod
  Identity hides exactly the mechanism this file is about.
