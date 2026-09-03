# app-hub — session automation
#
# RUN THIS FROM WSL. terraform, aws, kubectl and make are WSL-native; Docker is
# reached via docker.exe through WSL interop. One shell drives the whole loop.
#
#   make status   what is running / what is billing me
#   make up       terraform apply + refresh kubeconfig + verify nodes
#   make deploy   build + push (git-SHA tag) + apply manifests + verify
#   make down     drain Kubernetes, empty ECR, terraform destroy, audit orphans
#
# Why a Makefile and not a Terraform local-exec provisioner: provisioners are a
# documented last resort, they do not re-run on refresh, and a failed one taints
# the resource -- so a trivial local command failing makes Terraform want to
# rebuild your EKS cluster. Orchestration belongs outside Terraform.

REGION    := ap-south-1
ACCOUNT   := 314146298861
CLUSTER   := app-hub-eks
NAMESPACE := app-hub
ECR_REPO  := app-hub/links-service
ECR_HOST  := $(ACCOUNT).dkr.ecr.$(REGION).amazonaws.com
IMAGE     := $(ECR_HOST)/$(ECR_REPO)
DOCKER    := docker.exe
MANIFESTS := manifests/links-service

# Tag every image with the links-service commit it was built from, because the
# ECR repo is IMMUTABLE (R-03) and a tag must never be reused. A dirty working
# tree gets a timestamp suffix so uncommitted experiments still push.
GIT_SHA := $(shell git -C links-service rev-parse --short HEAD 2>/dev/null)
DIRTY   := $(shell git -C links-service status --porcelain 2>/dev/null | head -c1)
TAG     := $(if $(DIRTY),$(GIT_SHA)-dirty-$(shell date +%s),$(GIT_SHA))

.DEFAULT_GOAL := help
.PHONY: help guard status up deploy verify down destroy-only validate

help:
	@echo "app-hub — run from WSL"
	@echo ""
	@echo "  make status   what is running right now, and what it costs"
	@echo "  make up       provision infra, refresh kubeconfig, verify nodes"
	@echo "  make deploy   build + push + apply manifests + verify"
	@echo "  make down     full teardown in the correct order, then audit"
	@echo "  make validate offline manifest checks (no cluster needed)"
	@echo ""
	@echo "  image tag for the next deploy: $(TAG)"

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
	@echo "All empty = nothing is billing you."

## up — provision, then make kubectl actually work
up: guard
	cd infra && terraform apply
	@echo ""
	@echo "== refreshing kubeconfig (EKS issues a NEW endpoint on every rebuild) =="
	aws eks update-kubeconfig --region $(REGION) --name $(CLUSTER)
	@echo ""
	@echo "== you are pointed at =="
	kubectl config current-context
	@echo ""
	kubectl get nodes

## deploy — build, push, roll out
deploy: guard
	@echo "== building $(IMAGE):$(TAG) =="
	@if [ -n "$(DIRTY)" ]; then echo "   NOTE: links-service working tree is dirty; tag carries a timestamp so the push is unique."; fi
	aws ecr get-login-password --region $(REGION) | $(DOCKER) login --username AWS --password-stdin $(ECR_HOST)
	$(DOCKER) build -t $(IMAGE):$(TAG) ./links-service
	$(DOCKER) push $(IMAGE):$(TAG)
	@echo ""
	@echo "== pinning the manifest to $(TAG) =="
	@# The manifest holds the real tag on purpose: ArgoCD (R-07) applies this repo
	@# verbatim, so the desired state must be in git, not injected at deploy time.
	@# This is exactly the step Jenkins (R-06) will automate.
	sed -i 's|image: $(IMAGE):.*|image: $(IMAGE):$(TAG)|' $(MANIFESTS)/deployment.yaml
	@echo "   manifests/links-service/deployment.yaml updated — COMMIT THIS."
	@echo ""
	kubectl apply -f $(MANIFESTS)/
	kubectl -n $(NAMESPACE) rollout status deployment/links-service --timeout=180s
	@$(MAKE) --no-print-directory verify

## verify — prove it actually works, rather than that it applied
verify:
	@echo ""
	@echo "== pods =="
	kubectl -n $(NAMESPACE) get pods -l app=links-service -o wide
	@echo "== endpoints (empty here means selector/readiness problem, not networking) =="
	kubectl -n $(NAMESPACE) get endpoints links-service
	@echo "== service discovery by DNS name =="
	kubectl -n $(NAMESPACE) run verify-$$$$ --image=curlimages/curl --restart=Never --rm -i --quiet -- \
	  curl -sS --max-time 10 http://links-service:8000/health || true
	@echo ""
	@echo "== external endpoint (blank until the NLB finishes provisioning, ~2 min) =="
	@kubectl -n $(NAMESPACE) get svc links-service -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'; echo

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
	-@IDS=$$(aws ecr list-images --repository-name $(ECR_REPO) --region $(REGION) --filter tagStatus=ANY --query 'imageIds[*]' --output json 2>/dev/null); \
	  if [ -n "$$IDS" ] && [ "$$IDS" != "[]" ]; then \
	    aws ecr batch-delete-image --repository-name $(ECR_REPO) --region $(REGION) --image-ids "$$IDS" --query 'length(imageIds)' --output text; \
	  else echo "   already empty"; fi
	@echo "== 4/5 terraform destroy =="
	cd infra && terraform destroy
	@echo "== 5/5 orphan audit =="
	@$(MAKE) --no-print-directory status

## destroy-only — skip the Kubernetes drain. Only safe when no cluster exists.
destroy-only: guard
	cd infra && terraform destroy

## validate — offline checks, useful when everything is torn down
validate:
	python3 scripts/validate-manifests.py $(MANIFESTS)
	cd infra && terraform fmt -check -recursive . && terraform validate
