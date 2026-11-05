ENV               ?= prod
TOFU              ?= tofu
TOFU_DIR          := tofu
VAR_FILE          := environments/$(ENV).tfvars
PLAN_FILE         := $(ENV).tfplan
KUBECONFIG_OUT    ?= $(HOME)/.kube/platform-$(ENV).yaml
CRD_CATALOG       := c86448cbf1a840ca62d119259864863897c8748a
CRD_SCHEMAS       := https://raw.githubusercontent.com/datreeio/CRDs-catalog/$(CRD_CATALOG)/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json
KUBECONFORM_IMAGE := ghcr.io/yannh/kubeconform:v0.8.0@sha256:faffaf43f95aa6425306e1ab8d6fcad72acb9049158f38e574c085ea1ec0f64e

# KUBECONFORM_DOCKER=1 runs kubeconform from the pinned image instead of a local binary.
ifeq ($(KUBECONFORM_DOCKER),1)
KUBECONFORM := docker run --rm -v "$(CURDIR)":/work -w /work $(KUBECONFORM_IMAGE)
else
KUBECONFORM ?= kubeconform
endif

.PHONY: init fmt check validate lint verify-k3s plan apply kubeconfig

init:
	$(TOFU) -chdir=$(TOFU_DIR) init -var-file=$(VAR_FILE)

fmt:
	$(TOFU) -chdir=$(TOFU_DIR) fmt -recursive

validate:
	$(TOFU) -chdir=$(TOFU_DIR) init -backend=false -input=false
	$(TOFU) -chdir=$(TOFU_DIR) validate

lint:
	$(KUBECONFORM) -strict -summary -schema-location default -schema-location '$(CRD_SCHEMAS)' bootstrap/

verify-k3s:
	sh scripts/verify-k3s-pin.sh $(TOFU_DIR)/$(VAR_FILE)

check: validate lint verify-k3s
	$(TOFU) -chdir=$(TOFU_DIR) fmt -check -recursive

plan:
	$(TOFU) -chdir=$(TOFU_DIR) plan -var-file=$(VAR_FILE) -out=$(PLAN_FILE)

# Only run by a human after reviewing `make plan`.
apply:
	$(TOFU) -chdir=$(TOFU_DIR) apply $(PLAN_FILE)

kubeconfig:
	@mkdir -p $(dir $(KUBECONFIG_OUT))
	@ip=$$($(TOFU) -chdir=$(TOFU_DIR) output -raw server_ipv4) && \
	  ssh root@$$ip cat /etc/rancher/k3s/k3s.yaml | sed "s/127.0.0.1/$$ip/" > $(KUBECONFIG_OUT) && \
	  chmod 600 $(KUBECONFIG_OUT) && \
	  echo "kubeconfig written to $(KUBECONFIG_OUT)"
