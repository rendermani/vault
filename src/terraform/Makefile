# Terraform Infrastructure Makefile

.PHONY: help init plan apply destroy validate format lint clean docs

# Default environment
ENV ?= dev

# Terraform directories
TERRAFORM_DIR = .
MODULE_DIRS = modules/*/

help: ## Show this help message
	@echo "Vault Infrastructure Terraform Commands"
	@echo "======================================"
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n"} /^[a-zA-Z_-]+:.*?##/ { printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)

##@ Terraform Commands

init: ## Initialize Terraform
	@echo "Initializing Terraform..."
	terraform init
	@if [ -d "environments/$(ENV)" ]; then \
		cd environments/$(ENV) && terraform init; \
	fi

validate: ## Validate Terraform configuration
	@echo "Validating Terraform configuration..."
	terraform validate
	@for dir in $(MODULE_DIRS); do \
		echo "Validating $$dir..."; \
		cd $$dir && terraform validate && cd -; \
	done

format: ## Format Terraform files
	@echo "Formatting Terraform files..."
	terraform fmt -recursive

plan: ## Create Terraform execution plan
	@echo "Creating Terraform execution plan for $(ENV)..."
	@if [ -d "environments/$(ENV)" ]; then \
		cd environments/$(ENV) && terraform plan -var-file="terraform.tfvars"; \
	else \
		terraform plan; \
	fi

plan-destroy: ## Create Terraform destroy plan
	@echo "Creating Terraform destroy plan for $(ENV)..."
	@if [ -d "environments/$(ENV)" ]; then \
		cd environments/$(ENV) && terraform plan -destroy -var-file="terraform.tfvars"; \
	else \
		terraform plan -destroy; \
	fi

apply: ## Apply Terraform configuration
	@echo "Applying Terraform configuration for $(ENV)..."
	@if [ -d "environments/$(ENV)" ]; then \
		cd environments/$(ENV) && terraform apply -var-file="terraform.tfvars"; \
	else \
		terraform apply; \
	fi

apply-auto: ## Apply Terraform configuration without confirmation
	@echo "Auto-applying Terraform configuration for $(ENV)..."
	@if [ -d "environments/$(ENV)" ]; then \
		cd environments/$(ENV) && terraform apply -auto-approve -var-file="terraform.tfvars"; \
	else \
		terraform apply -auto-approve; \
	fi

destroy: ## Destroy Terraform-managed infrastructure
	@echo "Destroying Terraform-managed infrastructure for $(ENV)..."
	@if [ -d "environments/$(ENV)" ]; then \
		cd environments/$(ENV) && terraform destroy -var-file="terraform.tfvars"; \
	else \
		terraform destroy; \
	fi

output: ## Show Terraform outputs
	@echo "Showing Terraform outputs for $(ENV)..."
	@if [ -d "environments/$(ENV)" ]; then \
		cd environments/$(ENV) && terraform output; \
	else \
		terraform output; \
	fi

##@ Development Commands

lint: ## Lint Terraform files
	@echo "Linting Terraform files..."
	@if command -v tflint >/dev/null 2>&1; then \
		tflint --recursive; \
	else \
		echo "tflint not installed. Install with: brew install tflint"; \
	fi

security-scan: ## Run security scan on Terraform files
	@echo "Running security scan..."
	@if command -v tfsec >/dev/null 2>&1; then \
		tfsec .; \
	else \
		echo "tfsec not installed. Install with: brew install tfsec"; \
	fi

docs: ## Generate documentation
	@echo "Generating documentation..."
	@if command -v terraform-docs >/dev/null 2>&1; then \
		terraform-docs markdown table . > TERRAFORM.md; \
		for dir in $(MODULE_DIRS); do \
			terraform-docs markdown table $$dir > $$dir/README.md; \
		done; \
	else \
		echo "terraform-docs not installed. Install with: brew install terraform-docs"; \
	fi

##@ Environment Commands

dev: ## Switch to development environment
	$(MAKE) ENV=dev plan

staging: ## Switch to staging environment  
	$(MAKE) ENV=staging plan

prod: ## Switch to production environment
	$(MAKE) ENV=prod plan

##@ Utility Commands

clean: ## Clean Terraform files
	@echo "Cleaning Terraform files..."
	find . -name ".terraform" -type d -exec rm -rf {} + 2>/dev/null || true
	find . -name "terraform.tfstate*" -type f -delete 2>/dev/null || true
	find . -name ".terraform.lock.hcl" -type f -delete 2>/dev/null || true

upgrade: ## Upgrade Terraform providers
	@echo "Upgrading Terraform providers..."
	terraform init -upgrade
	@for dir in $(MODULE_DIRS); do \
		echo "Upgrading providers in $$dir..."; \
		cd $$dir && terraform init -upgrade && cd -; \
	done

graph: ## Generate Terraform dependency graph
	@echo "Generating Terraform dependency graph..."
	terraform graph | dot -Tsvg > terraform-graph.svg
	@echo "Graph saved to terraform-graph.svg"

state-list: ## List Terraform state resources
	@echo "Listing Terraform state resources for $(ENV)..."
	@if [ -d "environments/$(ENV)" ]; then \
		cd environments/$(ENV) && terraform state list; \
	else \
		terraform state list; \
	fi

refresh: ## Refresh Terraform state
	@echo "Refreshing Terraform state for $(ENV)..."
	@if [ -d "environments/$(ENV)" ]; then \
		cd environments/$(ENV) && terraform refresh -var-file="terraform.tfvars"; \
	else \
		terraform refresh; \
	fi

##@ Testing Commands

test: validate lint security-scan ## Run all tests

smoke-test: ## Run smoke tests
	@echo "Running smoke tests..."
	@echo "Checking Terraform syntax..."
	terraform fmt -check -diff -recursive
	@echo "Validating configurations..."
	$(MAKE) validate
	@echo "All smoke tests passed!"

##@ CI/CD Commands

ci-init: ## Initialize for CI/CD
	terraform init -input=false -backend=true

ci-plan: ## Plan for CI/CD
	terraform plan -input=false -out=tfplan

ci-apply: ## Apply for CI/CD
	terraform apply -input=false tfplan

ci-destroy: ## Destroy for CI/CD
	terraform destroy -input=false -auto-approve

# Environment variables
export TF_IN_AUTOMATION=true
export TF_INPUT=false