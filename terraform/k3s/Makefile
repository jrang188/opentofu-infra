# OpenTofu wrapper for the k3s cluster.
#
# Secrets (Hetzner token, Tailscale auth key, SSH keys) are injected from
# 1Password via `op run --env-file=.env.tofu`. Requires the 1Password CLI
# authenticated and this machine on the Tailnet (Tailscale is the only node
# transport).
#
# Usage (from this directory):
#   make init        # tofu init
#   make plan        # tofu plan -out=k3s.tfplan
#   make apply       # apply the reviewed k3s.tfplan artifact
#   make kubeconfig  # write k3s_kubeconfig.yaml
#   make destroy     # plan-destroy + apply destroy.tfplan
#   make fmt validate

TOFU       ?= tofu
OP         ?= op
ENV_FILE   ?= .env.tofu
PLAN       ?= k3s.tfplan
DESTROY_PLAN ?= destroy.tfplan
KUBECONFIG ?= k3s_kubeconfig.yaml

OP_RUN := $(OP) run --env-file=$(ENV_FILE) -- $(TOFU)

.PHONY: init plan apply kubeconfig destroy fmt validate

init:
	$(OP_RUN) init

plan:
	$(OP_RUN) plan -out=$(PLAN)

apply:
	$(OP_RUN) apply $(PLAN)

kubeconfig:
	$(TOFU) output -raw kubeconfig > $(KUBECONFIG)

destroy:
	$(OP_RUN) plan -destroy -out=$(DESTROY_PLAN)
	@echo "Review $(DESTROY_PLAN), then run: make apply-destroy"
	@echo "  (make apply-destroy is intentionally not automatic)"

apply-destroy:
	$(OP_RUN) apply $(DESTROY_PLAN)

fmt:
	$(TOFU) fmt

validate:
	$(TOFU) validate
