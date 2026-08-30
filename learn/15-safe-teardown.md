# 15 — Safe teardown: what `terraform destroy` does not know about

> Assembled from hard-won experience in the manual sessions. This is the single most cost-relevant file in the folder, because teardown happens **every session** and its failures are quiet.

## What this covers

`terraform destroy` removes what is in Terraform state. It does **not** remove things Kubernetes created on AWS's side while the cluster was running. Those leftovers either block the destroy outright or, worse, survive it and keep billing.

Three categories, in increasing order of nastiness:

1. **ECR images** — block the destroy loudly
2. **Load balancers and ENIs** — block VPC deletion, with a confusing error
3. **EBS volumes behind PVCs** — do not block anything, and quietly cost money forever

## Why this matters more here than in most projects

The standing policy destroys the cluster at the end of every session (`CLAUDE.md § 4`). So teardown is not a rare event you can afford to do carefully-and-slowly once — it happens constantly, and every leftover compounds.

The failure mode that actually hurts is **a destroy that fails halfway**. Terraform deletes what it can, hits the blocker, and stops. You are left with a partially-destroyed stack — and critically, **the NAT gateway is usually still standing**, billing hourly, while you debug. A failed teardown costs more than no teardown, because you think you are done.

## Key concepts

### 1. Terraform's state is its entire worldview

From `learn/03`: Terraform manages what is in its state file, and nothing else. It has no ambient knowledge of your AWS account.

So when the EBS CSI driver creates a volume in response to a PersistentVolumeClaim, that volume is **real, billable, and completely invisible to Terraform**. Same for an AWS load balancer created by a `Service type: LoadBalancer`.

**The general rule: anything created by a controller *inside* the cluster is outside Terraform's world.** Kubernetes and Terraform are both control loops managing AWS resources, and they do not talk to each other.

### 2. ECR images — the loud one

Covered in `learn/06`. `force_delete = true` is set in `ecr.tf` and should stay, but **it has been observed not to take effect**, with destroy failing anyway.

Reliable fix — empty the repository first:

```bash
aws ecr batch-delete-image --repository-name app-hub/links-service --region ap-south-1 --image-ids imageTag=v1
```

Repeat for untagged digests. Safe, because Terraform tracks the repository, never its contents.

### 3. Load balancers and ENIs — the confusing one

A `Service` of `type: LoadBalancer` or an Ingress makes the AWS Load Balancer Controller create a real ELB/ALB, which attaches **Elastic Network Interfaces** to your subnets.

Terraform then tries to delete the VPC, and AWS refuses: you cannot delete a VPC while network interfaces are attached. The error names a dependency violation, not a load balancer, so it reads like a Terraform bug rather than a leftover Kubernetes object.

This is why `E-05` (exposing the service) makes teardown harder, and why it is worth knowing *before* doing it rather than after.

### 4. EBS volumes — the expensive quiet one

This is the trap that costs real money.

When a pod needs durable storage, it declares a **PersistentVolumeClaim (PVC)**. The EBS CSI driver provisions an EBS volume to satisfy it. Delete the cluster without deleting the PVC, and:

- The pod is gone
- The PVC object is gone with the cluster
- **The EBS volume is still there, still billing, forever**

Nothing fails. Nothing warns you. `terraform destroy` reports success. The bill arrives later.

**This becomes live the moment any stateful workload lands** — `kube-prometheus-stack` (`R-05`), Jenkins (`R-06`), or n8n-on-EKS (`N-06`) all want persistent storage. Right now `links-service` has none, which is the only reason it has not bitten yet.

### 5. Order matters: drain Kubernetes, then destroy Terraform

The rule that follows from all three:

> **Delete Kubernetes-created AWS resources from inside Kubernetes, before asking Terraform to delete the cluster.**

Kubernetes knows how to clean up what it made. Once the cluster is gone, that knowledge is gone with it, and you are reduced to hunting orphans in the console.

## The teardown checklist

Run these in order, from **WSL**. Steps 1–2 only matter once stateful workloads exist, but running them when there is nothing to delete is harmless.

**1. Remove Helm releases** (Prometheus, Jenkins, anything installed by chart):

```bash
helm list --all-namespaces
```

```bash
helm uninstall <release> -n <namespace>
```

**2. Delete PVCs and LoadBalancer Services** — the two things that create AWS resources:

```bash
kubectl delete pvc --all --all-namespaces
```

```bash
kubectl get svc --all-namespaces --field-selector spec.type=LoadBalancer
```

Delete any that appear, and **wait** — the controller needs a moment to remove the ELB and detach its ENIs. Destroying immediately can still hit the dependency error.

**3. Empty the ECR repository:**

```bash
aws ecr batch-delete-image --repository-name app-hub/links-service --region ap-south-1 --image-ids imageTag=v1
```

**4. Destroy:**

```bash
wsl -e bash -lc "cd /mnt/c/Users/harshit.rawat/Documents/Projects/app-hub/infra && terraform destroy"
```

**5. Verify — this is the step people skip.** A successful destroy is not proof that nothing is billing.

```bash
aws ec2 describe-vpcs --filters "Name=tag:Name,Values=app-hub-vpc" --query "Vpcs[*].VpcId" --output table
```

```bash
aws ec2 describe-volumes --filters Name=status,Values=available --region ap-south-1 --query "Volumes[*].[VolumeId,Size,CreateTime]" --output table
```

```bash
aws ec2 describe-nat-gateways --filter Name=state,Values=available --region ap-south-1 --query "NatGateways[*].NatGatewayId" --output text
```

All three should be **empty**. An `available` EBS volume means "attached to nothing" — that is an orphan, and it is costing you money for zero benefit.

## Gotchas

- **A successful `terraform destroy` does not mean nothing is billing.** Orphaned EBS volumes survive it silently. Always run the verify step.
- **A *failed* destroy is worse than none**, because the NAT gateway usually survives and you may believe you are done. Re-run destroy until it reports success, then verify.
- **`force_delete = true` on ECR is necessary but not always sufficient.** Keep it; keep the manual fallback too.
- **Deleting a LoadBalancer Service is not instant.** Wait for the ENIs to detach before destroying the VPC.
- **The `persistent/` stack (`C-04`) must never be destroyed.** That is the entire point of splitting it out (`learn/13`). Run destroy in `infra/` only — never a blanket destroy from a parent directory.
- **`terraform destroy` deletes everything in state, with one confirmation.** There is no per-resource prompt. Read what it lists.

## Verify it yourself

Right now, with nothing deployed, all of these should come back empty — this is what a clean resting state looks like:

```bash
wsl -e bash -lc "aws ec2 describe-volumes --filters Name=status,Values=available --region ap-south-1 --query 'Volumes[*].VolumeId' --output text; aws ec2 describe-nat-gateways --filter Name=state,Values=available --region ap-south-1 --query 'NatGateways[*].NatGatewayId' --output text; aws eks list-clusters --region ap-south-1 --output text"
```

Make that your end-of-session habit. It takes two seconds and it is the difference between a $0 night and a surprise at the end of the month.

## Going deeper

- [EBS CSI driver](https://docs.aws.amazon.com/eks/latest/userguide/ebs-csi.html) — what provisions the volumes
- [PersistentVolume reclaim policies](https://kubernetes.io/docs/concepts/storage/persistent-volumes/#reclaiming) — `Delete` vs `Retain`, and why the default still leaves orphans when the cluster dies first
- [Deleting a VPC](https://docs.aws.amazon.com/vpc/latest/userguide/delete-vpc.html) — the dependency rules that produce the confusing error
- [AWS Cost Explorer](https://docs.aws.amazon.com/cost-management/latest/userguide/ce-what-is.html) — set a budget alert; it is the backstop for everything above

---

**Applies from `R-05` onward.** `kube-prometheus-stack` is the first workload here that wants persistent storage, so this checklist stops being theoretical the moment it lands.
