# 33 — Ingress, a shared ALB, and the back door that was propped open

> **Guided build** (`CLAUDE.md § 2`). Claude wrote `infra/alb-controller-irsa.tf`,
> `manifests/alb-controller/values.yaml` and `manifests/ingress/`; the owner ran
> the Helm install and hit the failures. **Full seven-section file** rather than
> a delegated short note, because `Ingress` and `IngressClass` are object types
> this project had never used, and because the teardown constraint that arrived
> with them is the expensive kind.

## What we did

Replaced `links-service`'s own network load balancer with **one shared
application load balancer in front of `gateway`**, created from an `Ingress`
object by the AWS Load Balancer Controller.

```
BEFORE   links-service  LoadBalancer  ->  its own NLB, public
         gateway        ClusterIP     ->  port-forward only

AFTER    links-service  ClusterIP     ->  unreachable from outside
         gateway        ClusterIP     ->  public, via one ALB
```

Verified on a real cluster 2026-09-18: one internet-facing ALB, all three
Services `ClusterIP` with `external=<none>`, the dashboard and the API both
served through it, and the seeded catalogue coming back from DynamoDB.

## Why

`gateway` exists to be the single entry point. Until this landed it was **a
front door with the back door propped open beside it** — `links-service` had its
own public NLB from `E-05`, so anything the gateway was supposed to mediate
could be reached directly.

Be honest about the money, because the obvious claim is wrong: **this is roughly
cost-neutral today.** One NLB at ~$16/month is replaced by one ALB at ~$16–18.
The saving arrives at services four and five, which become *routing rules on the
same ALB* rather than two more load balancers. The win right now is the shape,
not the bill.

## Key concepts

**An `Ingress` is inert on its own.** It is a row in the Kubernetes API saying
"route `/` to this Service". Nothing about creating it makes a load balancer.
A **controller** watches for Ingress objects and calls the AWS API on your
behalf — so the controller is an AWS API client in a pod, and needs an identity
exactly as `links-service` does. This is the project's **second IRSA role**;
`learn/29` explains the mechanism.

**`IngressClass` is how an Ingress says which controller owns it.** A cluster can
run several. Historically this was the `kubernetes.io/ingress.class` *annotation*,
deprecated in 1.18 because an annotation is untyped and unvalidated. Note the
failure mode either way: name a class that does not exist and **nothing errors**
— the Ingress is created, valid, and simply never claimed.

**`target-type: ip` versus `instance` is the most consequential line in the
file**, and it decides things elsewhere:

| | `instance` | `ip` |
|---|---|---|
| Targets | nodes, on a NodePort | **pod IPs directly** |
| Service type required | `NodePort` | `ClusterIP` works |
| Extra hop | kube-proxy | none |
| Client IP | lost without proxy protocol | preserved |

`ip` mode is only possible because EKS uses the AWS VPC CNI, which gives every
pod a real routable VPC address. **That annotation and the Service type are one
decision, not two.**

**Most real configuration travels as annotations**, because the Ingress spec is
deliberately generic — hosts, paths, backends — and says nothing about schemes,
health checks or listeners. So every controller invents its own vocabulary,
untyped and unvalidated, where a typo in a *key* is silently ignored. This is the
main reason the Gateway API exists as the intended successor.

## Walkthrough

**The IRSA role uses a module, and `irsa.tf` does not.** The difference is the
permission policy, not the trust policy. `links-service` needs four DynamoDB
actions on one table — small enough to write out, and worth writing out. The
controller's policy is ~200 lines spanning `elasticloadbalancing`, `ec2`, `acm`,
`wafv2`, `shield` and `cognito-idp`, revised by AWS as the controller gains
features. Copying it here would mean holding **a stale fork of someone else's
security policy** and never noticing it drift.

**The role name is fixed, so the ARN survives nightly rebuilds** — which is what
lets `values.yaml` hardcode it. Proven this session: after a full destroy and
recreate, the Terraform output and the committed YAML still matched.

**`vpcId` is NOT in the values file**, and that contrast is the lesson. The role
name is stable, so hardcode it. The VPC id is destroyed and recreated every
night, so deriving it is the only correct answer:

```bash
--set vpcId="$(cd infra && terraform output -raw vpc_id)"
```

> A value the nightly teardown changes cannot live in a committed file.

**The `ServiceMonitor` ordering has a cousin here.** `manifests/ingress/` uses a
`00-` filename prefix because `kubectl` applies a directory in filename order,
and an `Ingress` naming an `IngressClass` that does not exist yet is rejected.

## Gotchas

- **The command in the runbook was written for bash and pasted into
  PowerShell.** Windows PowerShell 5.1 has **no `&&` operator**, and `\"` does
  not escape a quote there — it *ends the string*, which exposed the inner `&&`
  to PowerShell's parser. Confusingly, an earlier step with `&&` worked fine,
  because its `&&` stayed inside a string PowerShell never had to reopen. The
  runbook now shows a WSL-native form and a PowerShell-safe alternative.
- **`Running` is not `Ready`, and `Ready` is not `working`.** The controller can
  be `1/1 Ready` and still fail every AWS call. The only tell is the Ingress
  never getting an `ADDRESS`, and the only place the reason appears is the
  controller's own log:
  ```bash
  kubectl -n kube-system logs deploy/aws-load-balancer-controller --tail=50
  ```
  Check for the injected environment instead — it is a positive signal rather
  than an absence:
  ```bash
  kubectl -n kube-system get pod <pod> -o jsonpath='{.spec.containers[0].env[*].name}'
  # expect AWS_ROLE_ARN and AWS_WEB_IDENTITY_TOKEN_FILE
  ```
- **The ALB takes 2–4 minutes**, and targets go `unknown` before `up`.
  "Discovered" is not "scraped"; "created" is not "healthy". Concluding failure
  early is the same mistake `learn/30` records at 46 seconds.
- **The controller writes AWS state Terraform cannot see** — not just the load
  balancer but a **security group rule** (`authorized securityGroup ingress` on
  port 8001). That is why the teardown order below is not optional.

## Verify it yourself

```bash
wsl -e bash -lc "kubectl -n app-hub get ingress app-hub"
```

Then the three checks that actually prove `E-06`, rather than proving the ALB
exists:

```bash
wsl -e bash -lc "kubectl -n app-hub get svc"
```
All three `ClusterIP`, `EXTERNAL-IP` `<none>`.

```bash
wsl -e bash -lc "aws elbv2 describe-load-balancers --region ap-south-1 --query 'LoadBalancers[*].[LoadBalancerName,Type,Scheme]' --output table"
```
**Exactly one row**, `application`, `internet-facing`. A second row means the
old NLB was orphaned.

```bash
ADDR=$(kubectl -n app-hub get ingress app-hub -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
curl -sS "http://$ADDR/health" && curl -sS "http://$ADDR/links"
```

## Going deeper

- `learn/29` — IRSA, and why the `sub` condition is the whole access control
- `learn/15` — the teardown ordering this extends

### The teardown constraint, which is the expensive part

**An ALB created from an Ingress is neither Terraform-tracked nor a
`Service type: LoadBalancer`**, so the sweep that has protected every previous
teardown does not match it. And the order looks reversible and is not:

```
1. delete the Ingress        -> the CONTROLLER deletes the ALB
2. wait for the ALB to go
3. THEN uninstall the controller
4. THEN terraform destroy
```

Uninstall the controller first and nothing remains to act on the deletion. The
Ingress vanishes from Kubernetes while **the ALB survives in AWS** — an orphan
no `kubectl` command can reach, billing quietly, findable only in the console.

`make down` encodes exactly this, and warns rather than failing silently if load
balancers are still present after five minutes.

### What was deliberately not done

**HTTP only, no TLS.** HTTPS needs an ACM certificate, which needs a domain this
project does not own. Written into the Ingress and the runbook so the day
something sensitive is hosted here is a decision rather than a discovery.

**No `host:` rule**, because the only address is the ALB's AWS-generated name —
which, like every other AWS-generated hostname here, changes on every rebuild.
A real domain would need `external-dns` to keep a record pointing at it.
