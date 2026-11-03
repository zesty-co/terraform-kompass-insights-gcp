MODULES := . examples/quick-start
TERRAFORM ?= terraform
TERRAFORM_DOCS ?= terraform-docs

.PHONY: all init validate fmt fmt-check test docs docs-check check

all: check

init:
	@set -eu; for module in $(MODULES); do \
		echo "Initializing $$module"; \
		$(TERRAFORM) -chdir="$$module" init -backend=false -input=false; \
	done

validate: init
	@set -eu; for module in $(MODULES); do \
		echo "Validating $$module"; \
		$(TERRAFORM) -chdir="$$module" validate; \
	done

fmt:
	@$(TERRAFORM) fmt -recursive

fmt-check:
	@$(TERRAFORM) fmt -check -recursive

test: init
	@$(TERRAFORM) test

docs:
	@set -eu; for module in $(MODULES); do \
		echo "Generating docs for $$module"; \
		$(TERRAFORM_DOCS) --config .terraform-docs.yml "$$module"; \
	done

docs-check:
	@set -eu; for module in $(MODULES); do \
		echo "Checking docs for $$module"; \
		$(TERRAFORM_DOCS) --config .terraform-docs.yml --output-check "$$module"; \
	done

check: fmt-check validate test docs-check
