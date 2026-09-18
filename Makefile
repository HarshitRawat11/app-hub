# app-hub — session automation
#
# RUN THIS FROM WSL. terraform, aws, kubectl and make are WSL-native; Docker is
# reached via docker.exe through WSL interop. One shell drives the whole loop.
#
#   make status   what is running / what is billing me
#   make up       terraform apply + refresh kubeconfig + verify nodes
#   make deploy   build + push (git-SHA tag) + apply manifests + verify
#   make down     drain Kubernetes, terraform destroy, audit orphans
#   make ecr-prune  delete every image (opt-in; `down` no longer does this)
#   make test     run every service test suite (no cluster needed)
#
# TWO TERRAFORM STACKS, both in the app-hub-infra repo:
#   infra/             ephemeral -- destroyed every session. This is what up/down drive.
#   infra/persistent/  never destroyed -- the DynamoDB table (C-04), the budget
#                      guardrail, and ECR (moved 2026-09-18, because the
#                      always-on compose host pulls from it -- P-11).
#
# `cd infra && terraform destroy` does NOT recurse into subdirectories, so the
# persistent stack is safe from `make down` by construction, not by care. Its
# table also carries prevent_destroy as a second line of defence.
#
# Why a Makefile and not a Terraform local-exec provisioner: provisioners are a
# documented last resort, they do not re-run on refresh, and a failed one taints
# the resource -- so a trivial local command failing makes Terraform want to
# rebuild your EKS cluster. Orchestration belongs outside Terraform.

REGION    := ap-south-1
ACCOUNT   := 314146298861
CLUSTER   := app-hub-eks
NAMESPACE := app-hub
# Every deployable service. Each needs a directory of the same name at the
# repo root (the source) and under manifests/ (the Kubernetes objects).
# ADD A NEW SERVICE HERE and to ECR_REPOS below; nothing else changes.
SERVICES  := links-service gateway aggregator
# Every ECR repository. This list is what `ecr-prune` walks.
#
# IT IS NO LONGER WHAT `down` WALKS. ECR moved to infra/persistent/ on
# 2026-09-18, so destroy never touches it and there is nothing to empty on
# teardown -- emptying it nightly would delete the images the always-on host
# depends on (P-11).
#
# app-hub/gateway is listed BEFORE it exists (S-01 step 6 creates it). That is
# deliberate: `terraform destroy` fails once a repository holds images, and
# force_delete has been observed not to take effect here (CLAUDE.md 9). So the
# cleanup for a resource lands before the resource does -- otherwise the first
# time you find out is a failed destroy, with the cluster still billing.
#
# ADD EVERY NEW REPOSITORY HERE. A missing entry fails silently: destroy simply
# breaks later, on an error about the repository not being empty.
ECR_REPOS := app-hub/links-service app-hub/gateway app-hub/aggregator
ECR_HOST  := $(ACCOUNT).dkr.ecr.$(REGION).amazonaws.com
# The persistent stack's table (C-04). Lives in infra/persistent/, has its own
# state file, and is NEVER destroyed -- `make down` cannot reach it, because
# terraform does not recurse into subdirectories. Named here only so
# `verify-dynamo` does not hardcode it in two places.
LINKS_TABLE := app-hub-links
# Per-service image URL is derived in the recipes: $(ECR_HOST)/app-hub/<svc>
DOCKER    := docker.exe
# manifests/00-namespace.yaml is applied before any service directory.
# It lives at the top of manifests/ because every service shares it -- it used
# to sit inside manifests/links-service/, which made applying gateway alone
# into a fresh cluster fail with `namespaces "app-hub" not found`.
MANIFEST_ROOT := manifests
# Pinned to what R-05 was built and verified against on 2026-09-14. An
# unpinned `helm upgrade --install` takes whatever is newest, which is how a
# setup that worked yesterday breaks on a day you changed nothing.
MONITORING_CHART_VERSION := 91.2.3
# Same reasoning as the chart version above: pinned so a working setup does
# not break on a day you changed nothing.
JENKINS_CHART_VERSION := 5.8.18
# R-07. Chart 10.9.2 ships ArgoCD v3.5.3 -- read from `helm search repo
# argo/argo-cd --versions` on 2026-09-19 rather than guessed, because a
# chart version that does not exist fails at install time, not at review.
ARGOCD_CHART_VERSION := 10.9.2

# Tag every image with the links-service commit it was built from, because the
# ECR repo is IMMUTABLE (R-03) and a tag must never be reused. A dirty working
# tree gets a timestamp suffix so uncommitted experiments still push.
# Tag every image with the commit of ITS OWN repo -- the six repos move
# independently, so one shared SHA would label a gateway image with a
# links-service commit. ECR is IMMUTABLE (R-03), so a tag must never be
# reused; a dirty tree gets a timestamp suffix so experiments still push.
#
# $(call tag_of,<service>) -- evaluated lazily, so `=` not `:=`.
sha_of   = $(shell git -C $(1) rev-parse --short HEAD 2>/dev/null)
dirty_of = $(shell git -C $(1) status --porcelain 2>/dev/null | head -c1)
tag_of   = $(if $(call dirty_of,$(1)),$(call sha_of,$(1))-dirty-$(shell date +%s),$(call sha_of,$(1)))

.DEFAULT_GOAL := help
.PHONY: help guard status up deploy verify down destroy-only ecr-prune validate test verify-dynamo monitoring jenkins argocd

help:
	@echo "app-hub — run from WSL"
	@echo ""
	@echo "  make status   what is running right now, and what it costs"
	@echo "  make up       provision infra, refresh kubeconfig, verify nodes"
	@echo "  make deploy   build + push + apply manifests + verify (all services)"
	@echo "  make down     full teardown in the correct order, then audit"
	@echo "  make test     run every service test suite (no cluster needed)"
	@echo "  make validate offline manifest + terraform checks (no cluster needed)"
	@echo "  make monitoring  install Prometheus + Grafana (R-05) on a live cluster"
	@echo "  make jenkins     install Jenkins, configured entirely as code (R-06)"
	@echo "  make argocd      install ArgoCD + the root Application (R-07)"
	@echo ""
	@echo "  make ecr-prune       delete every image from ECR — opt-in, NOT part of down"
	@echo "                       the always-on compose host pulls these images (P-11)"
	@echo ""
	@echo "  make verify-dynamo   exercise the repository against the REAL table"
	@echo "                       WRITES to $(LINKS_TABLE) — needs approval, not part of 'test'"
	@echo ""
	@echo "  next image tags:"
	@$(foreach s,$(SERVICES),echo "    $(s): $(call tag_of,$(s))";)
# Fail early and clearly if this is run from the wrong shell. Without this the
# first error is "terraform: command not found" three commands into an apply.
guard:
	@command -v terraform >/dev/null || { echo "ERROR: terraform not found. Run this from WSL, not Windows."; exit 1; }
	@command -v $(DOCKER) >/dev/null || { echo "ERROR: $(DOCKER) not found. Is Docker Desktop running?"; exit 1; }

## status — the "am I being charged?" check
status:
	@echo "== EKS clusters ==";        aws eks list-clusters --region $(REGION) --query 'clusters' --output text
	@echo "== NAT gateways ==";        aws ec2 describe-nat-gateways --filter Name=state,Values=available,pending --region $(REGION) --query 'NatGateways[*].NatGatewayId' --output text
	@echo "== Load balancers ==";      aws elbv2 describe-load-balancers --region $(REGION) --query 'LoadBalancers[*].[LoadBalancerName,State.Code]' --output text
	@echo "== Running EC2 ==";         aws ec2 describe-instances --filters Name=instance-state-name,Values=running,pending --region $(REGION) --query 'length(Reservations[].Instances[])' --output text
	@echo "== Orphaned EBS ==";        aws ec2 describe-volumes --filters Name=status,Values=available --region $(REGION) --query 'Volumes[*].[VolumeId,Size]' --output text
	@echo "== Unassociated EIPs ==";   aws ec2 describe-addresses --region $(REGION) --query 'Addresses[?AssociationId==null].PublicIp' --output text
	@echo ""
	@echo "-- everything above is EPHEMERAL: all empty = nothing is billing you --"
	@echo ""
	@# Below the line: resources that are SUPPOSED to exist between sessions.
	@# Listed separately because "all empty" is the pass condition above and
	@# emphatically not down here -- an empty list after C-04 means the
	@# persistent stack was destroyed, which is a much worse problem than a bill.
	@echo "== DynamoDB tables (PERSISTENT — these are meant to survive) =="
	@aws dynamodb list-tables --region $(REGION) --query 'TableNames' --output text
	@echo ""
	@echo "-- on-demand DynamoDB costs ~\$$0 idle; storage is \$$0.25/GB-month --"

## up — provision, then make kubectl actually work
up: guard
	@# AUTO=1 skips the confirmation prompt, mirroring `down`. The asymmetry --
	@# down supporting it and up not -- was an oversight, and it matters because
	@# a non-interactive shell hangs on the prompt rather than failing.
	cd infra && terraform apply $(if $(AUTO),-auto-approve -input=false,)
	@echo ""
	@echo "== refreshing kubeconfig (EKS issues a NEW endpoint on every rebuild) =="
	aws eks update-kubeconfig --region $(REGION) --name $(CLUSTER)
	@echo ""
	@echo "== you are pointed at =="
	kubectl config current-context
	@echo ""
	kubectl get nodes

## deploy — build, push, roll out
## deploy — build, push and roll out every service
deploy: guard
	@echo "== ECR login =="
	aws ecr get-login-password --region $(REGION) | $(DOCKER) login --username AWS --password-stdin $(ECR_HOST)
	@echo ""
	@# One loop over SERVICES rather than a block per service, so adding
	@# aggregator later is a one-word change to the SERVICES variable.
	@for svc in $(SERVICES); do \
	  sha=$$(git -C $$svc rev-parse --short HEAD 2>/dev/null); \
	  if [ -z "$$sha" ]; then echo "ERROR: no git HEAD in $$svc"; exit 1; fi; \
	  if [ -n "$$(git -C $$svc status --porcelain 2>/dev/null | head -c1)" ]; then \
	    tag="$$sha-dirty-$$(date +%s)"; \
	    echo "   NOTE: $$svc tree is dirty; tag carries a timestamp so the push is unique"; \
	  else tag="$$sha"; fi; \
	  image="$(ECR_HOST)/app-hub/$$svc"; \
	  echo "== $$svc -> $$image:$$tag =="; \
	  $(DOCKER) build -t "$$image:$$tag" "./$$svc" || exit 1; \
	  $(DOCKER) push "$$image:$$tag" || exit 1; \
	  echo "   pinning manifests/$$svc/deployment.yaml"; \
	  sed -i "s|image: $$image:.*|image: $$image:$$tag|" "manifests/$$svc/deployment.yaml" || exit 1; \
	  grep -q "image: $$image:$$tag" "manifests/$$svc/deployment.yaml" || { echo "   ERROR: pin did not take"; exit 1; }; \
	done
	@echo ""
	@echo "   manifests/*/deployment.yaml updated — COMMIT THESE."
	@# The manifest holds the real tag on purpose: ArgoCD (R-07) applies that
	@# repo verbatim, so the desired state must be in git, not injected at
	@# deploy time. This is exactly the step Jenkins (R-06) will automate.
	@echo ""
	@echo "== namespace first (nothing else can be applied without it) =="
	kubectl apply -f $(MANIFEST_ROOT)/00-namespace.yaml
	@for svc in $(SERVICES); do \
	  echo "== applying manifests/$$svc =="; \
	  kubectl apply -f "manifests/$$svc/" || exit 1; \
	  kubectl -n $(NAMESPACE) rollout status "deployment/$$svc" --timeout=180s || exit 1; \
	done
	@# E-06. Applied last, because the Ingress routes to gateway's Service and
	@# there is no reason to ask AWS for a load balancer in front of pods that
	@# are not up yet.
	@#
	@# The controller is installed by HELM, not by this target -- it is a
	@# one-line `helm upgrade --install` documented in
	@# manifests/alb-controller/values.yaml. Checking for it here rather than
	@# silently applying an Ingress nothing will act on: that combination gives
	@# you an Ingress with a permanently empty ADDRESS and no error anywhere.
	@if kubectl -n kube-system get deploy aws-load-balancer-controller >/dev/null 2>&1; then \
	  echo "== applying manifests/ingress =="; \
	  kubectl apply -f "$(MANIFEST_ROOT)/ingress/" || exit 1; \
	else \
	  echo "== SKIPPING manifests/ingress — aws-load-balancer-controller is not installed =="; \
	  echo "   install it first (see manifests/alb-controller/values.yaml), or the"; \
	  echo "   Ingress would sit with no ADDRESS and nothing would say why."; \
	fi
	@$(MAKE) --no-print-directory verify

verify:
	@echo ""
	@echo "== pods =="
	kubectl -n $(NAMESPACE) get pods -o wide
	@echo ""
	@# Endpoints, not pods, is the "is this Service actually wired up" check.
	@# Empty endpoints with Running pods means the selector does not match the
	@# pod labels, or readiness is failing -- neither looks like a network fault.
	@echo "== endpoints (empty here means selector/readiness, not networking) =="
	kubectl -n $(NAMESPACE) get endpoints
	@echo ""
	@echo "== service discovery by DNS name, from inside the cluster =="
	@# Was: `kubectl run` a throwaway curlimages/curl pod. That is rejected by
	@# the restricted Pod Security Standard the namespace enforces (R-04) --
	@# the throwaway pod sets none of runAsNonRoot, allowPrivilegeEscalation,
	@# capabilities.drop or seccompProfile. Verified live 2026-09-10: the
	@# policy is real, and it broke the verification rather than the workload.
	@#
	@# Exec into gateway instead. It is already running, already compliant, and
	@# it is a BETTER test: it proves the real pod can resolve the name, not
	@# that a freshly-created one can.
	kubectl -n $(NAMESPACE) exec deploy/gateway -- python -c \
	  "import httpx2, os; u=os.environ['LINKS_SERVICE_URL']; \
	   print('links-service by DNS name ->', httpx2.get(u+'/health', timeout=5).text); \
	   print('gateway by DNS name       ->', httpx2.get('http://gateway:8001/health', timeout=5).text)" || true
	@echo ""
	@# The claim gateway exists to prove: one pod reaching another by name,
	@# through the gateway's own configured URL rather than a hand-typed one.
	@echo "== a real request through gateway, end to end =="
	kubectl -n $(NAMESPACE) exec deploy/gateway -- python -c \
	  "import httpx2; print(httpx2.get('http://gateway:8001/links', timeout=5).text)" || true
	@echo ""
	@echo "== external endpoint for links-service (blank until the NLB provisions, ~2 min) =="
	@kubectl -n $(NAMESPACE) get svc links-service -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'; echo
	@echo "   gateway is ClusterIP by design (E-06) — reach it with:"
	@echo "   kubectl -n $(NAMESPACE) port-forward svc/gateway 8001:8001"

## down — teardown in the ONLY order that works
##
## The cluster's own controllers are what delete the NLB and any EBS volumes.
## Destroy the cluster first and those controllers die, orphaning the AWS
## resources permanently. See learn/15.
down: guard
	@# ================= STEP 0, AND IT IS NEW AS OF R-07 =================
	@#
	@# THE CONSTRAINT, STATED BEFORE IT IS ENCODED (CLAUDE.md section 2):
	@#
	@# ArgoCD runs with selfHeal. If it is alive when step 1 deletes the
	@# Ingress, it notices the drift and RECREATES it -- the ALB controller
	@# then provisions a SECOND load balancer, and teardown proceeds around
	@# it. That is D-28 again (an orphaned, billing ALB), except this time
	@# something is actively undoing the fix.
	@#
	@# Deleting the ROOT Application cascades through the resources-finalizer
	@# to the child Applications and their objects, Ingress included -- and
	@# the ALB controller is still installed at this moment, so the load
	@# balancer is deprovisioned properly rather than stranded.
	@#
	@# --ignore-not-found so this is a clean no-op on a cluster that never
	@# had ArgoCD. --wait so the cascade finishes before step 1 starts.
	@echo "== 0/4 removing ArgoCD Applications (selfHeal would recreate the Ingress) =="
	-kubectl delete application app-hub-root -n argocd --ignore-not-found --wait --timeout=5m
	-kubectl delete applications --all -n argocd --ignore-not-found --wait --timeout=5m
	@# Assert rather than assume. An Application stuck on its finalizer here
	@# means something still reconciles, and step 1 would be a fight.
	@APPS=$$(kubectl get applications -A --no-headers 2>/dev/null | wc -l | tr -d ' '); \
	  if [ "$$APPS" != "0" ]; then \
	    echo "ABORTING: $$APPS ArgoCD Application(s) still exist."; \
	    echo "Deleting the Ingress now would be undone by selfHeal, and the"; \
	    echo "ALB it creates would be orphaned. Investigate:"; \
	    echo "  kubectl get applications -A"; \
	    exit 1; \
	  fi
	-helm uninstall argocd -n argocd --ignore-not-found
	@echo ""
	@echo "== 1/4 deleting Ingresses, then LoadBalancer Services (releases the ALB/NLB and their ENIs) =="
	@# THE INGRESS COMES FIRST, AND THE ORDER IS LOAD-BEARING (added with E-06).
	@#
	@# An ALB created from an Ingress is not tracked by Terraform AND is not a
	@# `Service type: LoadBalancer`, so the svc delete below does not match it.
	@# Before E-06 this step would have left the ALB and its ENIs in place, and
	@# `terraform destroy` would then fail on the VPC.
	@#
	@# The ALB is deleted by the CONTROLLER reacting to the Ingress going away.
	@# So the controller has to still be running when that happens. Uninstall it
	@# first and the Ingress disappears from Kubernetes while the ALB survives in
	@# AWS -- an orphan no kubectl command can reach, billing quietly, findable
	@# only in the console. Hence: Ingress, wait, THEN uninstall.
	@# `--all -A`, NOT `--all-namespaces` on its own. THIS LINE WAS WRONG FROM
	@# the day it was written and it orphaned an ALB on 2026-09-18.
	@#
	@#   kubectl delete ingress --all-namespaces
	@#     -> error: resource(s) were provided, but no name was specified
	@#
	@# `--all-namespaces` chooses which NAMESPACES to look in; `--all` chooses
	@# which OBJECTS. Without the latter kubectl has a kind and no names, so it
	@# refuses. The `-` prefix then made make swallow the error, so the step
	@# whose entire purpose is preventing an orphaned load balancer failed
	@# silently and the teardown carried on to uninstall the controller.
	@#
	@# The svc line below was always fine: --field-selector selects the objects,
	@# so --all-namespaces alone is enough there. That asymmetry is why this went
	@# unnoticed -- the two lines look like the same idiom and are not.
	-kubectl delete ingress --all -A --ignore-not-found
	-kubectl delete svc --all-namespaces --field-selector spec.type=LoadBalancer --ignore-not-found
	@echo "   waiting for AWS to actually remove them..."
	@for i in $$(seq 1 30); do \
	  n=$$(aws elbv2 describe-load-balancers --region $(REGION) --query 'length(LoadBalancers)' --output text 2>/dev/null || echo 0); \
	  [ "$$n" = "0" ] && { echo "   load balancers gone"; break; }; \
	  printf '.'; sleep 10; \
	done
	@# The loop above used to fall through SILENTLY after five minutes, so a
	@# load balancer that never went away produced a confusing `terraform
	@# destroy` failure several minutes later instead of a reason here.
	@n=$$(aws elbv2 describe-load-balancers --region $(REGION) --query 'length(LoadBalancers)' --output text 2>/dev/null || echo 0); \
	  [ "$$n" = "0" ] || echo "   WARNING: $$n load balancer(s) still present after 5 min — destroy will likely fail on the VPC"
	@# ASSERT BEFORE UNINSTALLING, rather than trusting the delete above.
	@#
	@# This is the check that would have caught 2026-09-18. The ordering was
	@# correct on paper -- delete the Ingress, then remove the controller -- but
	@# the first half silently did nothing, and nothing verified it before the
	@# second half ran. Sequencing two steps is not the same as enforcing that
	@# the first one worked.
	@#
	@# An Ingress carries the finalizer `ingress.k8s.aws/resources`, which ONLY
	@# this controller removes. Uninstall it while an Ingress survives and you
	@# get a deadlock on top of an orphan: the ALB stays in AWS billing, and the
	@# Ingress can never finish deleting because the thing that owns its
	@# finalizer is gone. Recovery means reinstalling the controller.
	@ING=$$(kubectl get ingress -A --no-headers 2>/dev/null | wc -l | tr -d ' '); \
	  if [ "$$ING" != "0" ]; then \
	    echo ""; \
	    echo "ABORTING: $$ING ingress(es) still exist."; \
	    echo "Uninstalling the controller now would strand its ALB in AWS, billing,"; \
	    echo "with no kubectl route to it and the Ingress deadlocked on a finalizer"; \
	    echo "only this controller can clear. Delete them first:"; \
	    echo "  kubectl delete ingress --all -A"; \
	    exit 1; \
	  fi
	@# Only now is it safe to remove the controller: the ALB it manages is gone.
	-helm uninstall aws-load-balancer-controller -n kube-system --ignore-not-found
	@echo "== 2/4 deleting PVCs (their EBS volumes are invisible to Terraform) =="
	-kubectl delete pvc --all --all-namespaces --ignore-not-found
	@echo "== 3/4 terraform destroy =="
	@# AUTO=1 skips the confirmation prompt. Only for the scheduled unattended
	@# destroy (scripts/scheduled-destroy.sh) -- interactively you want the prompt.
	cd infra && terraform destroy $(if $(AUTO),-auto-approve -input=false,)
	@echo "== 4/4 orphan audit =="
	@$(MAKE) --no-print-directory status

## ecr-prune — delete every image from every repository. NOT part of `down`.
ecr-prune:
	@# THE CONSTRAINT, STATED BEFORE IT IS ENCODED (CLAUDE.md section 2):
	@#
	@# This was step 3 of `down` and ran on EVERY teardown. It existed for
	@# exactly one reason: `terraform destroy` fails on a non-empty repository.
	@# ECR now lives in infra/persistent/, which destroy never reaches -- so that
	@# reason is gone, and running it nightly would delete the very images the
	@# always-on compose host pulls (P-11). A 24/7 host whose registry is emptied
	@# every night is not a 24/7 host.
	@#
	@# So it is opt-in. Run it to reclaim storage; never as part of a teardown.
	@# It deletes images that cannot be rebuilt if their source commit is gone.
	@if [ -z "$(AUTO)" ]; then \
	  echo "This deletes EVERY image in: $(ECR_REPOS)"; \
	  echo "The always-on compose host (P-11) pulls from these."; \
	  printf "Type 'yes' to continue: "; read ans; \
	  [ "$$ans" = "yes" ] || { echo "aborted"; exit 1; }; \
	fi
	@# ONE PASS IS NOT ENOUGH. buildkit pushes a manifest INDEX plus the child
	@# manifests it points at (the image itself, and an attestation). Deleting
	@# the index makes its children visible to list-images as newly-untagged
	@# digests that were not in the first listing. Observed live 2026-09-10:
	@# one pass deleted 1 image and left 2 behind. So loop until the repository
	@# actually reports empty, rather than deleting once and hoping.
	@#
	@# "does not exist" is reported separately from "already empty" on purpose.
	@# Swallowing the RepositoryNotFoundException would make a typo'd repo name
	@# look like a clean one -- a check that passes because it never checked.
	@for repo in $(ECR_REPOS); do \
	  if ! aws ecr describe-repositories --repository-names $$repo --region $(REGION) >/dev/null 2>&1; then \
	    echo "   $$repo: does not exist — nothing to empty"; continue; \
	  fi; \
	  total=0; \
	  for pass in 1 2 3 4 5; do \
	    IDS=$$(aws ecr list-images --repository-name $$repo --region $(REGION) --filter tagStatus=ANY --query 'imageIds[*]' --output json); \
	    if [ -z "$$IDS" ] || [ "$$IDS" = "[]" ]; then break; fi; \
	    n=$$(aws ecr batch-delete-image --repository-name $$repo --region $(REGION) --image-ids "$$IDS" --query 'length(imageIds)' --output text); \
	    total=$$((total + n)); \
	    echo "   $$repo: pass $$pass deleted $$n"; \
	  done; \
	  if [ "$$total" = "0" ]; then echo "   $$repo: already empty"; fi; \
	  left=$$(aws ecr describe-images --repository-name $$repo --region $(REGION) --query 'length(imageDetails)' --output text 2>/dev/null || echo 0); \
	  if [ "$$left" != "0" ]; then \
	    echo "   ERROR: $$repo still holds $$left image(s) after 5 passes."; \
	    echo "   Inspect with:"; \
	    echo "     aws ecr describe-images --repository-name $$repo --region $(REGION)"; \
	    exit 1; \
	  fi; \
	  echo "   $$repo: empty (confirmed, $$total deleted)"; \
	done

## destroy-only — skip the Kubernetes drain. Only safe when no cluster exists.
destroy-only: guard
	cd infra && terraform destroy

## test — every service suite. No cluster, no AWS, no cost.
test:
	@# Each service owns its own venv and its own pytest config, so this is a
	@# loop of independent runs rather than one pytest invocation. A failure in
	@# one service must not stop the others from reporting, so the exit status
	@# is collected and re-raised at the end.
	@fail=0; \
	for svc in $(SERVICES); do \
	  if [ ! -d "$$svc/tests" ]; then echo "== $$svc: no tests/ — skipping =="; continue; fi; \
	  echo "== $$svc =="; \
	  (cd "$$svc" && uv run pytest -q) || fail=1; \
	  echo ""; \
	done; \
	exit $$fail

## verify-dynamo — exercise the repository against the REAL table (WRITES; needs approval)
verify-dynamo:
	@# THE CONSTRAINT, STATED BEFORE IT IS ENCODED (CLAUDE.md § 2):
	@#
	@# This target WRITES to app-hub-links -- the table in the persistent stack,
	@# the one thing here deliberately never destroyed. So it is NOT part of
	@# `make test` and never will be: `make test` must stay offline, free, and
	@# runnable without asking anyone. Per CLAUDE.md § 4 this needs the owner's
	@# approval in the session it is run.
	@#
	@# It earns its place because tests/test_repository.py runs against moto,
	@# and moto is a reimplementation. The gaps are where the expensive
	@# surprises live -- most importantly that real reads are EVENTUALLY
	@# CONSISTENT by default while moto's are immediate (learn/26).
	@#
	@# The before/after scan is the actual safety property. The script cleans up
	@# in a finally block, but "it cleans up" is a claim, and an unverified
	@# claim is what this project keeps getting burned by.
	@command -v aws >/dev/null || { echo "aws CLI not found — run this from WSL"; exit 1; }
	@echo "== baseline =="
	@aws dynamodb scan --table-name $(LINKS_TABLE) --region $(REGION) --output json > /tmp/dynamo-before.json
	@python3 -c "import json;d=json.load(open('/tmp/dynamo-before.json'));print('  %d item(s) before' % d['Count'])"
	@echo "== verifying =="
	@cd links-service && PYTHONPATH=. uv run python scripts/verify_real_table.py; \
	  rc=$$?; \
	  echo "== confirming the table was left as found =="; \
	  aws dynamodb scan --table-name $(LINKS_TABLE) --region $(REGION) --output json > /tmp/dynamo-after.json; \
	  python3 -c "import json,sys; a=json.load(open('/tmp/dynamo-before.json')); b=json.load(open('/tmp/dynamo-after.json')); same = a['Items']==b['Items']; print('  %d item(s) after — %s' % (b['Count'], 'identical to baseline' if same else 'CHANGED — leftovers below')); [print('   LEFTOVER:', i) for i in b['Items'] if i not in a['Items']]; sys.exit(0 if same else 1)" || rc=1; \
	  exit $$rc

## validate — offline checks, useful when everything is torn down
## jenkins -- R-06, and it refuses to run without its two Secrets
#
# Jenkins here is CONFIGURED ENTIRELY AS CODE. Persistence is off, because
# the cluster is destroyed nightly and a PVC would create an EBS volume that
# `terraform destroy` takes anyway. Everything -- the job, the agent pod
# template, the credential bindings, the plugin list -- rebuilds from
# manifests/jenkins/values.yaml on every install.
#
# THE TWO SECRETS ARE YOURS TO CREATE, and this target checks for them
# rather than installing a Jenkins that comes up broken. See
# manifests/jenkins/README.md. They are not in git and never will be.
#
# NOT part of `make deploy`: Jenkins wants ~1Gi on a two-node cluster that
# already runs Prometheus and three services, so it is opt-in.
jenkins: guard
	@command -v helm >/dev/null || { echo "ERROR: helm not found. Run this from WSL."; exit 1; }
	kubectl apply -f $(MANIFEST_ROOT)/jenkins/namespace.yaml
	@echo ""
	@# CHECK BEFORE INSTALLING, not after. Without these the chart installs
	@# happily and Jenkins starts with no admin password and a JCasC block
	@# that cannot resolve ${manifests-deploy-key} -- so the UI is reachable,
	@# the job exists, and every build fails at the git push. Failing here is
	@# a worse-looking but far cheaper outcome.
	@for sec in jenkins-admin jenkins-deploy-key; do \
	  kubectl -n jenkins get secret $$sec >/dev/null 2>&1 || { \
	    echo ""; \
	    echo "MISSING SECRET: $$sec"; \
	    echo "Jenkins would install and then fail at runtime. Create both first:"; \
	    echo "  see manifests/jenkins/README.md"; \
	    exit 1; }; \
	done
	@echo "   both secrets present"
	@echo ""
	helm repo add jenkins https://charts.jenkins.io >/dev/null
	helm repo update jenkins >/dev/null
	@echo ""
	@echo "== installing jenkins $(JENKINS_CHART_VERSION) =="
	@# --wait with a long timeout: the controller downloads and installs the
	@# plugin list on first boot, which is slow and is the usual reason a
	@# first install looks hung when it is only working.
	helm upgrade --install jenkins jenkins/jenkins \
	  --version $(JENKINS_CHART_VERSION) \
	  -n jenkins \
	  -f $(MANIFEST_ROOT)/jenkins/values.yaml \
	  --wait --timeout 15m
	@echo ""
	kubectl -n jenkins get pods
	@echo ""
	@echo "   UI:  kubectl -n jenkins port-forward svc/jenkins 8080:8080  ->  http://localhost:8080"
	@echo ""
	@echo "   The job 'links-service' should already exist. If it does not, JCasC"
	@echo "   did not apply -- check:  kubectl -n jenkins logs sts/jenkins -c jenkins | grep -i casc"

## argocd — R-07, GitOps. Refuses to run without its repository Secret.
argocd: guard
	@command -v helm >/dev/null || { echo "ERROR: helm not found. Run this from WSL."; exit 1; }
	kubectl apply -f $(MANIFEST_ROOT)/argocd/namespace.yaml
	@echo ""
	@# CHECK BEFORE INSTALLING, same as `jenkins` above and for the same reason.
	@# app-hub-manifests is a PRIVATE repository. Without this Secret the chart
	@# installs cleanly, the UI comes up, and every Application sits in Unknown
	@# with an authentication error -- which reads as a broken install rather
	@# than a missing credential.
	@#
	@# ArgoCD finds repository credentials BY LABEL, not by name, so a Secret
	@# that exists without argocd.argoproj.io/secret-type=repository is inert.
	@# Both are checked.
	@kubectl -n argocd get secret app-hub-manifests-repo >/dev/null 2>&1 || { \
	  echo ""; \
	  echo "MISSING SECRET: app-hub-manifests-repo"; \
	  echo "ArgoCD would install and then fail to clone a private repo."; \
	  echo "Create it first: see manifests/argocd/README.md"; \
	  exit 1; }
	@lbl=$$(kubectl -n argocd get secret app-hub-manifests-repo \
	         -o jsonpath='{.metadata.labels.argocd\.argoproj\.io/secret-type}' 2>/dev/null); \
	  if [ "$$lbl" != "repository" ]; then \
	    echo ""; \
	    echo "SECRET EXISTS BUT IS NOT LABELLED: app-hub-manifests-repo"; \
	    echo "ArgoCD discovers repo credentials by label. Without it the Secret"; \
	    echo "is ignored and the failure looks identical to having no Secret."; \
	    echo "  kubectl -n argocd label secret app-hub-manifests-repo argocd.argoproj.io/secret-type=repository"; \
	    exit 1; \
	  fi
	@echo "   repository Secret present and labelled"
	@echo ""
	helm repo add argo https://argoproj.github.io/argo-helm >/dev/null
	helm repo update argo >/dev/null
	@echo ""
	@echo "== installing argo-cd $(ARGOCD_CHART_VERSION) =="
	helm upgrade --install argocd argo/argo-cd \
	  --version $(ARGOCD_CHART_VERSION) \
	  -n argocd \
	  -f $(MANIFEST_ROOT)/argocd/values.yaml \
	  --wait --timeout 10m
	@echo ""
	@# THE ONE IMPERATIVE STEP GITOPS ALWAYS NEEDS. Nothing can apply the first
	@# Application except a human, because ArgoCD is what applies Applications.
	@echo "== applying the root Application (app-of-apps) =="
	kubectl apply -f $(MANIFEST_ROOT)/argocd/root-app.yaml
	@echo ""
	kubectl -n argocd get applications
	@echo ""
	@echo "   Children appear within a minute or so; the root syncs them."
	@echo ""
	@echo "   UI:  kubectl -n argocd port-forward svc/argocd-server 8080:80  ->  http://localhost:8080"
	@echo "   Password:  kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
	@echo ""
	@echo "   selfHeal is ON. kubectl changes are reverted in SECONDS -- commit instead."

## monitoring -- put R-05 back on the cluster
#
# WHY THIS TARGET EXISTS. R-05 was finished on 2026-09-14 and verified with 22
# scrape targets all UP. On 2026-09-18 the cluster came back and the monitoring
# namespace did not exist at all: a Helm release lives IN the cluster, so
# `terraform destroy` takes it with everything else.
#
# Nothing re-installed it. `make deploy` covers the three services and stops
# there, so the one piece of R-05 that is not a committed manifest -- the Helm
# release itself -- had to be retyped from learn/30 every session. A step that
# only exists in a walkthrough is a step that gets skipped, and the project's
# own standard is 'reproducibly, from code committed to git'.
#
# NOT folded into `make deploy` on purpose. Prometheus and Grafana are a real
# chunk of a two-node cluster, and most sessions do not need them. Making it
# opt-in keeps a plain deploy fast and keeps the memory for the services.
#
# THE CHART VERSION IS PINNED. 91.2.3 is what R-05 was actually built and
# verified against; `helm upgrade --install` with no --version silently takes
# whatever is newest, which is how a working setup breaks on a day you changed
# nothing.
#
# TEARDOWN: this installs with emptyDir storage (see values.yaml), so there are
# no PVCs and therefore no EBS volumes for `terraform destroy` to leave behind.
# THAT CHANGES the day persistence is added -- `make down` already deletes PVCs,
# but the CLAUDE.md section 9 orphan audit becomes mandatory rather than
# precautionary.
monitoring: guard
	@command -v helm >/dev/null || { echo "ERROR: helm not found. Run this from WSL -- the Windows helm is v4 and points at minikube."; exit 1; }
	@echo "== namespace first (deliberately NOT labelled with a Pod Security Standard) =="
	@# node-exporter needs hostNetwork, hostPID and hostPath. Under the
	@# `restricted` PSS that app-hub enforces it would be refused at admission and
	@# the DaemonSet would sit at zero pods. PSS is per-namespace, so an
	@# unlabelled monitoring namespace leaves app-hub strict. See learn/30.
	kubectl apply -f $(MANIFEST_ROOT)/monitoring/namespace.yaml
	@echo ""
	@echo "== chart repo =="
	helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null
	helm repo update prometheus-community >/dev/null
	@echo ""
	@echo "== installing kube-prometheus-stack $(MONITORING_CHART_VERSION) =="
	helm upgrade --install monitoring prometheus-community/kube-prometheus-stack \
	  --version $(MONITORING_CHART_VERSION) \
	  -n monitoring \
	  -f $(MANIFEST_ROOT)/monitoring/values.yaml \
	  --wait --timeout 10m
	@echo ""
	@echo "== ServiceMonitor -- this is the whole point of the operator pattern =="
	@# Applied AFTER the chart, because it is a CRD instance and the CRD does not
	@# exist until the operator installs it. Applied first, kubectl fails with
	@# 'no matches for kind ServiceMonitor'.
	kubectl apply -f $(MANIFEST_ROOT)/monitoring/servicemonitor-app-hub.yaml
	@echo ""
	kubectl -n monitoring get pods
	@echo ""
	@echo "   Prometheus:  kubectl -n monitoring port-forward svc/monitoring-kube-prometheus-prometheus 9090:9090"
	@echo "   Grafana:     kubectl -n monitoring port-forward svc/monitoring-grafana 3000:80   (admin / prom-operator)"
	@echo ""
	@echo "   TARGETS TAKE A MINUTE. There are TWO reload delays, not one:"
	@echo "   operator -> config secret, then config-reloader -> Prometheus."
	@echo "   Checking 46 seconds in once produced a confident wrong answer (learn/30)."

validate:
	@echo "== documentation drift =="
	@# CONTEXT-BRIEF.md reproduces source files verbatim so a Claude chat with
	@# no filesystem access can still see them. That duplication went stale on
	@# 2026-09-10 -- the brief shipped handler names that had been renamed the
	@# day before, and nothing noticed because nothing was looking. Now it is
	@# checked. Run with --fix to rewrite the blocks from source.
	python3 scripts/check-doc-drift.py
	@echo "== manifests =="
	@# Validated per directory, because the checker globs *.yaml in one level.
	@#
	@# The directory list is a SHELL GLOB, not $(SERVICES). It was $(SERVICES)
	@# until 2026-09-16, and that silently excluded manifests/monitoring/ --
	@# the one directory holding the ServiceMonitor that the validator's
	@# newest check was written FOR. `make validate` printed "all checks
	@# passed" without ever opening it.
	@#
	@# Same shape as a service missing from ECR_REPOS, or a repo missing from
	@# the root .gitignore: a hand-maintained list that nothing reconciles
	@# against the filesystem, so it fails by OMISSION rather than by error.
	@# Deriving the list removes the thing there was to forget.
	@#
	@# SERVICES cannot simply be extended -- it also drives build/push/deploy,
	@# which would then try to `docker build` a monitoring/ directory that has
	@# no source tree at all.
	@# TWO levels of glob, not one. manifests/argocd/apps/ holds the child
	@# Applications and sits a level deeper than anything before it -- with
	@# a single-level glob it would be skipped SILENTLY, which is precisely
	@# how manifests/monitoring/ went unchecked until 2026-09-16.
	@for d in $(MANIFEST_ROOT) $(MANIFEST_ROOT)/*/ $(MANIFEST_ROOT)/*/*/; do \
	  [ -d "$$d" ] || continue; \
	  echo "-- $${d%/}"; \
	  python3 scripts/validate-manifests.py "$${d%/}" || exit 1; \
	done
	@echo "== terraform: ephemeral stack =="
	cd infra && terraform fmt -check -recursive . && terraform validate
	@# The persistent stack (C-04) lives in the infra REPO but is a separate
	@# Terraform stack -- its own directory, its own state file. `terraform
	@# validate` above only covers infra/ itself; it does not recurse.
	@#
	@# -backend=false initialises providers WITHOUT touching S3, so this stays
	@# offline and needs no credentials.
	@if [ -d infra/persistent ]; then \
	  echo "== terraform: persistent stack =="; \
	  cd infra/persistent && terraform fmt -check . && terraform init -backend=false -input=false >/dev/null && terraform validate; \
	else \
	  echo "== infra/persistent/ does not exist yet (C-04) — skipping =="; \
	fi