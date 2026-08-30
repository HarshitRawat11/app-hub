# 05 — The EKS cluster: control plane, node groups, and the access trap

> **Backfilled.** Reconstructed from `infra/eks.tf` and git history (`838d446`).

## What we did

Created the Kubernetes cluster `app-hub-eks` (version 1.31) with the `terraform-aws-modules/eks/aws` module: a managed control plane, one managed node group of two `t3.medium` instances in the private subnets, a public API endpoint, and — critically — admin access granted to the IAM user that created it.

## Why

Kubernetes is the thing that actually runs containers: scheduling them onto machines, restarting them when they die, and giving them stable network identities. EKS is AWS's managed Kubernetes — you get the control plane as a service and supply the worker nodes.

The alternative would be running Kubernetes on raw EC2 yourself. That is a genuinely educational exercise and completely the wrong use of time here, because the organisation this is preparing for uses EKS.

## Key concepts

### 1. Control plane vs data plane — the split that defines EKS

A Kubernetes cluster has two halves:

- **Control plane** — the API server, scheduler, controller manager, and etcd. The brain. It decides *what should run where*.
- **Data plane** — the worker nodes. The muscle. It *actually runs* the containers.

**EKS manages the control plane for you.** You never see those machines. AWS runs them across multiple AZs, patches them, and backs up etcd. You pay a flat hourly fee for it (roughly $0.10/hour — about $73/month if left running).

**You own the data plane.** Worker nodes are EC2 instances in your account, in your VPC, billed as EC2.

This split explains the cost structure: the control plane bills as long as the cluster *exists*, even with zero workloads. That, plus the NAT gateway from `learn/04`, is why an idle cluster is not free.

### 2. Managed node groups

```hcl
eks_managed_node_groups = {
  default = {
    instance_types = ["t3.medium"]
    min_size       = 1
    max_size       = 2
    desired_size   = 2
  }
}
```

A **managed node group** is EKS-operated EC2: AWS handles the auto-scaling group, uses an EKS-optimised AMI, registers nodes with the cluster automatically, and coordinates graceful draining during updates.

The three sizes:

- `desired_size = 2` — how many to run now
- `min_size = 1` / `max_size = 2` — the bounds an autoscaler may move within

**These bounds do not cause scaling by themselves.** Without a Cluster Autoscaler or Karpenter installed, the node count just sits at `desired_size`. The bounds define what *would* be permitted.

`t3.medium` is 2 vCPU / 4 GiB. Not big — but note that a chunk of each node is consumed by system pods (`kube-proxy`, `aws-node`, CoreDNS) before your workloads get anything.

### 3. Nodes go in private subnets

```hcl
subnet_ids = module.vpc.private_subnets
```

Worker nodes have no public IPs and cannot be reached from the internet. They reach *out* through the NAT gateway (to pull images from ECR, call AWS APIs).

This is the standard production posture, and it is why `learn/04` bothered with the NAT gateway at all. Nodes in public subnets would be cheaper — no NAT — and meaningfully worse.

### 4. `cluster_endpoint_public_access` — how *you* reach the API

```hcl
cluster_endpoint_public_access = true
```

Separate question from where the nodes live. This governs whether the **Kubernetes API server** is reachable from the internet.

With `true`, you can run `kubectl` from your laptop. With `false`, the API is VPC-only and you would need a VPN, bastion host, or Direct Connect.

For a personal cluster driven from a laptop, `true` is the pragmatic choice. It is not wide open — access still requires valid AWS credentials plus Kubernetes RBAC. But the endpoint is internet-reachable, and a production setup would usually restrict it by CIDR or turn it off entirely.

### 5. `enable_cluster_creator_admin_permissions` — the trap

```hcl
enable_cluster_creator_admin_permissions = true
```

**This is the single least obvious line in the whole infra directory, and omitting it produces a genuinely baffling failure.**

Here is the problem it solves. AWS IAM and Kubernetes RBAC are **two separate authorisation systems**. Your IAM user having `AdministratorAccess` in AWS means you can create and delete the EKS cluster — it says *nothing* about your permissions **inside** Kubernetes.

Without this flag, you create a cluster and then:

```
error: You must be logged in to the server (Unauthorized)
```

You own the cluster. You are an AWS administrator. And you cannot list a single pod. The error looks like a credentials or networking problem — people spend hours on it.

This flag tells EKS to create an access entry mapping the creating IAM principal to Kubernetes `cluster-admin`. Set it once at creation and `kubectl` works.

**The mental model to keep: IAM controls the cluster from the outside; RBAC controls what happens inside it. Being an admin in one grants nothing in the other.**

### 6. Kubernetes version

```hcl
cluster_version = "1.31"
```

Kubernetes releases roughly three minor versions a year, and EKS supports each for a limited window before forcing an upgrade. Pinning is right; the version is a thing you will periodically have to bump deliberately.

Control plane and nodes can differ by a version or so, and the control plane is upgraded first. Skipping minor versions is not allowed — 1.31 → 1.33 means going through 1.32.

## Walkthrough

What this module call produces:

1. The EKS control plane (`app-hub-eks`), managed by AWS across AZs
2. IAM roles — one for the cluster, one for the nodes — with the required AWS-managed policies
3. Security groups for control-plane ↔ node communication
4. A managed node group: launch template, auto-scaling group, 2× `t3.medium`
5. An EKS access entry mapping your IAM user to `cluster-admin`
6. Core add-ons (`kube-proxy`, `aws-node` / VPC CNI, CoreDNS)

Connecting to it afterwards:

```bash
aws eks update-kubeconfig --region ap-south-1 --name app-hub-eks
```

This writes a context into `~/.kube/config` telling `kubectl` where the API server is and how to authenticate — using the AWS CLI to fetch a token, which is why valid AWS credentials are a prerequisite for `kubectl` here.

**Re-run it after every destroy + apply cycle.** EKS issues a *new endpoint hostname* each time, even with an identical cluster name. A stale kubeconfig points at a hostname that no longer exists, and the resulting errors look like network or auth failures rather than staleness. Given the destroy-every-session policy, this applies nearly every time the cluster comes back — it is the #1 source of confusing `kubectl` failures in this project (`CLAUDE.md § 9`).

Then, always:

```bash
kubectl config current-context
```

The default context on this machine is `minikube`. Applying manifests to the wrong cluster is a quiet, easy mistake.

## Gotchas

- **`enable_cluster_creator_admin_permissions = true` must be set at creation.** Adding it later means managing access entries after the fact. Do not remove it.
- **Re-run `update-kubeconfig` after every rebuild.** New endpoint every time.
- **Check `current-context` before every `kubectl apply`.** `minikube` is the default here.
- **Cluster creation is slow.** 10–15 minutes for the control plane, several more for nodes. `terraform apply` has not hung; EKS is just like that.
- **Destroy can fail on Kubernetes-created resources.** A `Service` of type `LoadBalancer` creates an AWS load balancer that Terraform does not track, and it can block VPC deletion. Delete such Services first.
- **The control plane bills while it exists**, regardless of workload. Together with NAT, that is the whole cost case for tearing down.
- **Node capacity is smaller than it looks.** System pods take a slice of every node before your workloads schedule.

## Verify it yourself

Once credentials exist (`E-00`) and the cluster is up:

```bash
aws eks describe-cluster --name app-hub-eks --region ap-south-1 --query "cluster.[name,status,version,endpoint]" --output table
```

Point kubectl at it, then confirm you are actually talking to EKS and not minikube:

```bash
aws eks update-kubeconfig --region ap-south-1 --name app-hub-eks && kubectl config current-context
```

Prove the access-entry flag did its job — this is what fails with `Unauthorized` if it was omitted:

```bash
kubectl get nodes -o wide
```

Two nodes, `Ready`, with private IPs from `10.0.1.x` / `10.0.2.x` — confirming they landed in the private subnets.

See the system pods that consume node capacity:

```bash
kubectl get pods -n kube-system
```

## Going deeper

- [EKS user guide](https://docs.aws.amazon.com/eks/latest/userguide/what-is-eks.html)
- [EKS cluster access management](https://docs.aws.amazon.com/eks/latest/userguide/grant-k8s-access.html) — the IAM/RBAC boundary in detail
- [Managed node groups](https://docs.aws.amazon.com/eks/latest/userguide/managed-node-groups.html)
- [EKS Kubernetes version support](https://docs.aws.amazon.com/eks/latest/userguide/kubernetes-versions.html)
- [terraform-aws-modules/eks](https://github.com/terraform-aws-modules/terraform-aws-eks)

---

**Next:** `learn/06` — the registry the cluster pulls images from.
