# app-hub — session automation
#
# RUN THIS FROM WSL. terraform, aws, kubectl and make are WSL-native; Docker is
# reached via docker.exe through WSL interop. One shell drives the whole loop.
#
#   make status   what is running / what is billing me
#   make up       terraform apply + refresh kubeconfig + verify nodes
#   make deploy   build + push (git-SHA tag) + apply manifests + verify
#   make down     drain Kubernetes, empty ECR, terraform destroy, audit orphans
#   make test     run every service test suite (no cluster needed)
#
# TWO TERRAFORM STACKS, both in the app-hub-infra repo:
#   infra/             ephemeral -- destroyed every session. This is what up/down drive.
#   infra/persistent/  never destroyed -- the DynamoDB table (C-04).
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
SERVICES  := links-service gateway
# Every ECR repository the teardown must empty. ECR_REPO above is only the one
# `deploy` builds today; this list is what `down` walks.
#
# app-hub/gateway is listed BEFORE it exists (S-01 step 6 creates it). That is
# deliberate: `terraform destroy` fails once a repository holds images, and
# force_delete has been observed not to take effect here (CLAUDE.md 9). So the
# cleanup for a resource lands before the resource does -- otherwise the first
# time you find out is a failed destroy, with the cluster still billing.
#
# ADD EVERY NEW REPOSITORY HERE. A missing entry fails silently: destroy simply
# breaks later, on an error about the repository not being empty.
ECR_REPOS := app-hub/links-service app-hub/gateway
ECR_HOST  := $(ACCOUNT).dkr.ecr.$(REGION).amazonaws.com
# Per-service image URL is derived in the recipes: $(ECR_HOST)/app-hub/<svc>
DOCKER    := docker.exe
# manifests/00-namespace.yaml is applied before any service directory.
# It lives at the top of manifests/ because both services share it -- it used
# to sit inside manifests/links-service/, which made applying gateway alone
# into a fresh cluster fail with `namespaces "app-hub" not found`.
MANIFEST_ROOT := manifests

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
.PHONY: help guard status up deploy verify down destroy-only validate test

help:
	@echo "app-hub — run from WSL"
	@echo ""
	@echo "  make status   what is running right now, and what it costs"
	@echo "  make up       provision infra, refresh kubeconfig, verify nodes"
	@echo "  make deploy   build + push + apply manifests + verify (all services)"
	@echo "  make down     full teardown in the correct order, then audit"
	@echo "  make test     run every service test suite (no cluster needed)"
	@echo "  make validate offline manifest + terraform checks (no cluster needed)"
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
	@echo "== 1/5 deleting LoadBalancer Services (releases NLB + its ENIs) =="
	-kubectl delete svc --all-namespaces --field-selector spec.type=LoadBalancer --ignore-not-found
	@echo "   waiting for AWS to actually remove them..."
	@for i in $$(seq 1 30); do \
	  n=$$(aws elbv2 describe-load-balancers --region $(REGION) --query 'length(LoadBalancers)' --output text 2>/dev/null || echo 0); \
	  [ "$$n" = "0" ] && { echo "   load balancers gone"; break; }; \
	  printf '.'; sleep 10; \
	done
	@echo "== 2/5 deleting PVCs (their EBS volumes are invisible to Terraform) =="
	-kubectl delete pvc --all --all-namespaces --ignore-not-found
	@echo "== 3/5 emptying ECR — tagStatus=ANY, because the default hides untagged digests =="
	@# Walk ECR_REPOS, not just the one `deploy` builds. A repository holding
	@# images blocks `terraform destroy`, and force_delete has been observed not
	@# to help (CLAUDE.md 9).
	@#
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
	    echo "   $$repo: does not exist yet — nothing to empty"; continue; \
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
	    echo "   ERROR: $$repo still holds $$left image(s) after 5 passes — destroy would fail."; \
	    echo "   Stopping rather than proceeding blindly. Inspect with:"; \
	    echo "     aws ecr describe-images --repository-name $$repo --region $(REGION)"; \
	    exit 1; \
	  fi; \
	  echo "   $$repo: empty (confirmed, $$total deleted)"; \
	done
	@echo "== 4/5 terraform destroy =="
	@# AUTO=1 skips the confirmation prompt. Only for the scheduled unattended
	@# destroy (scripts/scheduled-destroy.sh) -- interactively you want the prompt.
	cd infra && terraform destroy $(if $(AUTO),-auto-approve -input=false,)
	@echo "== 5/5 orphan audit =="
	@$(MAKE) --no-print-directory status

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

## validate — offline checks, useful when everything is torn down
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
	@for d in $(MANIFEST_ROOT) $(foreach s,$(SERVICES),$(MANIFEST_ROOT)/$(s)); do \
	  python3 scripts/validate-manifests.py "$$d" || exit 1; \
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