ENV            ?= prod
TOFU           ?= tofu
KUBECONFORM    ?= kubeconform
TOFU_DIR       := tofu
VAR_FILE       := environments/$(ENV).tfvars
PLAN_FILE      := $(ENV).tfplan
KUBECONFIG_OUT ?= $(HOME)/.kube/platform-$(ENV).yaml
CRD_SCHEMAS    := https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json

.PHONY: init fmt check validate lint plan apply kubeconfig

init:
	$(TOFU) -chdir=$(TOFU_DIR) init -var-file=$(VAR_FILE)

fmt:
	$(TOFU) -chdir=$(TOFU_DIR) fmt -recursive

validate:
	$(TOFU) -chdir=$(TOFU_DIR) init -backend=false -input=false
	$(TOFU) -chdir=$(TOFU_DIR) validate

lint:
	$(KUBECONFORM) -strict -summary -schema-location default -schema-location '$(CRD_SCHEMAS)' bootstrap/

check: validate lint
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
