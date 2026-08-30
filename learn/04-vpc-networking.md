# 04 — The VPC: subnets, gateways, and the thing that costs money

> **Backfilled.** Reconstructed from `infra/vpc.tf` and git history (`66f8f16`).

## What we did

Created the network the cluster lives in, using the community `terraform-aws-modules/vpc/aws` module: a `10.0.0.0/16` VPC across two availability zones, with public and private subnets, an internet gateway, a single NAT gateway, and the tags EKS requires to discover the subnets.

## Why

Every EC2 instance, every EKS node, every load balancer has to live inside a network. AWS will not let you skip this. More importantly, the *shape* of the network decides what can reach your workloads and what they can reach — so getting it right early avoids painful re-plumbing later.

The specific shape here — private subnets for workloads, public subnets for load balancers, NAT for outbound — is the standard production pattern, which is precisely why it is worth learning rather than dropping everything in a public subnet.

## Key concepts

### 1. CIDR blocks — how big is `/16`?

```hcl
cidr = "10.0.0.0/16"
```

A CIDR block is an IP range. The number after the slash is how many bits are **fixed**; the rest are free for addresses.

- `/16` fixes the first 16 bits (`10.0.`), leaving 16 free → **65,536 addresses** (`10.0.0.0`–`10.0.255.255`)
- `/24` fixes 24 bits (`10.0.1.`), leaving 8 → **256 addresses**

So this VPC is a `/16` carved into `/24` subnets. Small number after the slash = big network. `10.x.x.x` is private address space (RFC 1918) — not routable on the public internet, which is what you want internally.

**Sizing matters more on EKS than you would expect.** The AWS VPC CNI gives every *pod* a real IP from the subnet. Pods, not just nodes. A `/24` with 256 addresses can run out faster than you would guess on a busy cluster.

### 2. Availability zones — why two

```hcl
azs = ["ap-south-1a", "ap-south-1b"]
```

An AZ is a physically separate datacentre within a region. A workload in one AZ survives a fire, flood, or power failure in another.

Two is the minimum for a highly-available setup and the minimum EKS accepts — the control plane requires subnets in at least two AZs. Two is also the cheap choice: cross-AZ data transfer is billed, so more AZs means more resilience and more cost.

### 3. Public vs private subnets — the difference is one route

```hcl
private_subnets = ["10.0.1.0/24",   "10.0.2.0/24"]
public_subnets  = ["10.0.101.0/24", "10.0.102.0/24"]
```

There is no `is_public` flag in AWS. **The distinction is entirely about routing:**

- A **public** subnet has a route to an **internet gateway (IGW)**. Resources with public IPs are reachable from the internet, and can reach out.
- A **private** subnet has no such route. Nothing on the internet can initiate a connection to it.

The `10.0.1.x` / `10.0.101.x` split is just a readable convention — low numbers private, 100+ public. Nothing enforces it.

**Worker nodes go in private subnets** (see `learn/05`), so a misconfigured pod is not directly exposed. Load balancers go in public subnets and forward inward.

### 4. Internet gateway vs NAT gateway — the one that costs money

Two different things, easy to confuse:

| | Internet Gateway (IGW) | NAT Gateway |
|---|---|---|
| Direction | Both ways | **Outbound only** |
| Sits in | The VPC itself | A public subnet |
| Serves | Public subnets | Private subnets |
| Cost | Free | **Hourly + per-GB** |

An IGW is the VPC's door to the internet. Free, and traffic flows both ways for anything with a public IP.

A **NAT gateway** solves a specific problem: your private nodes need *outbound* access — to pull container images from ECR, fetch OS updates, call AWS APIs — but must not be reachable *inbound*. NAT sits in a public subnet, and private subnets route their outbound traffic through it. Replies come back; unsolicited inbound connections cannot get in.

```hcl
enable_nat_gateway = true
single_nat_gateway = true
```

`single_nat_gateway = true` creates **one** NAT shared by both AZs, instead of one per AZ.

- **Cost:** one NAT instead of two — roughly half the NAT bill
- **Risk:** if that AZ fails, private subnets in the *other* AZ lose outbound access

For a personal learning cluster that trade is obviously right. In production you would pay for one per AZ.

**This is the single most important cost line in the project.** A NAT gateway bills per hour *whether or not any traffic flows through it* — an idle cluster still runs up a NAT bill. That is the reason for the destroy-every-session policy (`CLAUDE.md § 4`), and the reason `terraform destroy` is routine here rather than exceptional.

### 5. Subnet tags — how EKS finds where to put load balancers

```hcl
public_subnet_tags  = { "kubernetes.io/role/elb"          = "1" }
private_subnet_tags = { "kubernetes.io/role/internal-elb" = "1" }
tags                = { "kubernetes.io/cluster/app-hub-eks" = "shared" }
```

These look like bookkeeping. They are **functional**.

When you create a Kubernetes `Service` of type `LoadBalancer`, or an Ingress, the AWS controller has to decide which subnets to place the load balancer in. It finds out by **searching for these tags**.

- `kubernetes.io/role/elb = 1` → "put internet-facing load balancers here"
- `kubernetes.io/role/internal-elb = 1` → "put internal load balancers here"
- `kubernetes.io/cluster/app-hub-eks = shared` → "this subnet belongs to that cluster"

Omit them and load balancer creation fails with an error about not finding suitable subnets — which reads like a permissions or networking problem, not a missing tag. **This will matter directly at `E-05`**, when the ClusterIP service needs to become externally reachable.

### 6. Using a module instead of raw resources

```hcl
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"
  ...
}
```

Written out by hand, this network is a VPC, 4 subnets, an IGW, a NAT gateway, an Elastic IP, 3+ route tables, and a set of route-table associations — well over a hundred lines, with several easy mistakes.

The module is a community-maintained package of exactly that, driven by a handful of inputs. `version = "~> 5.0"` pins it the same way providers are pinned.

**The trade:** far less code and far fewer mistakes, at the cost of some indirection — when something breaks you may need to read the module's source to understand what it built. For learning, a reasonable middle path is to use the module and then inspect what it actually created.

## Walkthrough

What those ~25 lines produce:

1. A VPC `app-hub-vpc`, `10.0.0.0/16`
2. Two private subnets, one per AZ (`10.0.1.0/24`, `10.0.2.0/24`)
3. Two public subnets, one per AZ (`10.0.101.0/24`, `10.0.102.0/24`)
4. An internet gateway attached to the VPC
5. An Elastic IP (a static public IP) for the NAT
6. One NAT gateway in a public subnet
7. A public route table: `0.0.0.0/0` → IGW
8. A private route table: `0.0.0.0/0` → NAT
9. Associations binding each subnet to the right route table
10. Tags on everything

Reading rule for route tables: `0.0.0.0/0` means "everything not matched by a more specific route" — the default route. Public subnets send it to the IGW; private subnets send it to the NAT.

## Gotchas

- **The NAT gateway is the cost driver.** It bills hourly while it exists. This is *the* reason to destroy between sessions.
- **`single_nat_gateway = true` is a deliberate availability trade.** Know that you made it.
- **Subnet tags are load-bearing.** Missing tags produce confusing load-balancer failures at `E-05`.
- **Pods consume subnet IPs, not just nodes.** With the AWS VPC CNI, subnet sizing constrains pod count.
- **Destroy can fail on leftovers.** If Kubernetes created a load balancer or ENI that Terraform does not know about, `terraform destroy` may fail to delete the VPC because something still occupies it. Delete Kubernetes `Service`s of type `LoadBalancer` *before* destroying.
- **CIDR ranges are painful to change later.** Resizing a VPC in place is largely not a thing; you rebuild.

## Verify it yourself

Read the config without touching AWS:

```bash
wsl -e bash -lc "cd /mnt/c/Users/harshit.rawat/Documents/Projects/app-hub/infra && terraform validate"
```

Once the cluster exists, inspect what was actually built:

```bash
aws ec2 describe-vpcs --filters "Name=tag:Name,Values=app-hub-vpc" --query "Vpcs[*].[VpcId,CidrBlock]" --output table --region ap-south-1
```

List the subnets and which AZ each landed in:

```bash
aws ec2 describe-subnets --filters "Name=tag:Name,Values=app-hub-vpc-*" --query "Subnets[*].[Tags[?Key=='Name']|[0].Value,CidrBlock,AvailabilityZone]" --output table --region ap-south-1
```

Confirm the NAT gateway exists — this is the thing costing money:

```bash
aws ec2 describe-nat-gateways --filter "Name=state,Values=available" --query "NatGateways[*].[NatGatewayId,SubnetId]" --output table --region ap-south-1
```

## Going deeper

- [AWS VPC user guide](https://docs.aws.amazon.com/vpc/latest/userguide/what-is-amazon-vpc.html)
- [NAT gateway pricing](https://aws.amazon.com/vpc/pricing/) — worth reading once, properly
- [EKS subnet requirements and tags](https://docs.aws.amazon.com/eks/latest/userguide/network-reqs.html)
- [terraform-aws-modules/vpc](https://github.com/terraform-aws-modules/terraform-aws-vpc) — the module's own docs

---

**Next:** `learn/05` — the EKS cluster that sits in this network.
