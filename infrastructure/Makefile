# Enterprise Infrastructure Makefile
# Provides unified commands for managing the entire infrastructure stack

.PHONY: help init bootstrap deploy test clean status logs backup restore

# Default environment
ENVIRONMENT ?= develop

# Infrastructure directories
INFRA_DIR := $(shell pwd)
REPOS_DIR := $(INFRA_DIR)/repositories
SCRIPTS_DIR := $(INFRA_DIR)/scripts
TESTS_DIR := $(INFRA_DIR)/tests

# Colors for output
RED := \033[0;31m
GREEN := \033[0;32m
YELLOW := \033[1;33m
BLUE := \033[0;34m
NC := \033[0m

# Help target
help: ## Show this help message
	@echo "Enterprise Infrastructure Management"
	@echo "=================================="
	@echo ""
	@echo "Available targets:"
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  $(BLUE)%-20s$(NC) %s\n", $$1, $$2}' $(MAKEFILE_LIST)
	@echo ""
	@echo "Environment Variables:"
	@echo "  ENVIRONMENT    Target environment (develop|staging|production) [$(ENVIRONMENT)]"
	@echo ""
	@echo "Examples:"
	@echo "  make bootstrap ENVIRONMENT=develop"
	@echo "  make deploy ENVIRONMENT=staging"
	@echo "  make test ENVIRONMENT=production"

init: ## Initialize infrastructure directory structure and clone repositories
	@echo -e "$(BLUE)[INFO]$(NC) Initializing infrastructure for environment: $(ENVIRONMENT)"
	@mkdir -p {core,repositories,deployments,security,monitoring,tests,secrets,logs}
	@mkdir -p environments/{develop,staging,production}
	@if [ ! -d "$(REPOS_DIR)/nomad" ]; then \
		cd $(REPOS_DIR) && git clone https://github.com/rendermani/nomad.git; \
	fi
	@if [ ! -d "$(REPOS_DIR)/vault" ]; then \
		cd $(REPOS_DIR) && git clone https://github.com/rendermani/vault.git; \
	fi
	@if [ ! -d "$(REPOS_DIR)/traefik" ]; then \
		cd $(REPOS_DIR) && git clone https://github.com/rendermani/traefik.git; \
	fi
	@echo -e "$(GREEN)[SUCCESS]$(NC) Infrastructure initialized"

bootstrap: ## Bootstrap the entire infrastructure stack (Vault -> Nomad -> Traefik)
	@echo -e "$(BLUE)[INFO]$(NC) Bootstrapping infrastructure for environment: $(ENVIRONMENT)"
	@$(SCRIPTS_DIR)/bootstrap.sh $(ENVIRONMENT)
	@echo -e "$(GREEN)[SUCCESS]$(NC) Infrastructure bootstrap completed"

deploy: ## Deploy infrastructure components
	@echo -e "$(BLUE)[INFO]$(NC) Deploying infrastructure for environment: $(ENVIRONMENT)"
	@$(MAKE) deploy-vault ENVIRONMENT=$(ENVIRONMENT)
	@$(MAKE) deploy-nomad ENVIRONMENT=$(ENVIRONMENT)
	@$(MAKE) deploy-traefik ENVIRONMENT=$(ENVIRONMENT)
	@echo -e "$(GREEN)[SUCCESS]$(NC) Infrastructure deployment completed"

deploy-vault: ## Deploy Vault cluster
	@echo -e "$(BLUE)[INFO]$(NC) Deploying Vault for environment: $(ENVIRONMENT)"
	@cd $(REPOS_DIR)/vault && \
	if [ -f "deploy-$(ENVIRONMENT).sh" ]; then \
		./deploy-$(ENVIRONMENT).sh; \
	else \
		make deploy ENVIRONMENT=$(ENVIRONMENT); \
	fi
	@echo -e "$(GREEN)[SUCCESS]$(NC) Vault deployment completed"

deploy-nomad: ## Deploy Nomad cluster
	@echo -e "$(BLUE)[INFO]$(NC) Deploying Nomad for environment: $(ENVIRONMENT)"
	@cd $(REPOS_DIR)/nomad && \
	if [ -f "deploy-$(ENVIRONMENT).sh" ]; then \
		./deploy-$(ENVIRONMENT).sh; \
	else \
		make deploy ENVIRONMENT=$(ENVIRONMENT); \
	fi
	@echo -e "$(GREEN)[SUCCESS]$(NC) Nomad deployment completed"

deploy-traefik: ## Deploy Traefik load balancer
	@echo -e "$(BLUE)[INFO]$(NC) Deploying Traefik for environment: $(ENVIRONMENT)"
	@cd $(REPOS_DIR)/traefik && \
	if [ -f "deploy-$(ENVIRONMENT).sh" ]; then \
		./deploy-$(ENVIRONMENT).sh; \
	else \
		make deploy ENVIRONMENT=$(ENVIRONMENT); \
	fi
	@echo -e "$(GREEN)[SUCCESS]$(NC) Traefik deployment completed"

test: ## Run comprehensive integration tests
	@echo -e "$(BLUE)[INFO]$(NC) Running integration tests for environment: $(ENVIRONMENT)"
	@$(TESTS_DIR)/integration-test-suite.sh $(ENVIRONMENT)

test-vault: ## Run Vault-specific tests
	@echo -e "$(BLUE)[INFO]$(NC) Running Vault tests"
	@cd $(REPOS_DIR)/vault && make test ENVIRONMENT=$(ENVIRONMENT)

test-nomad: ## Run Nomad-specific tests
	@echo -e "$(BLUE)[INFO]$(NC) Running Nomad tests"
	@cd $(REPOS_DIR)/nomad && make test ENVIRONMENT=$(ENVIRONMENT)

test-traefik: ## Run Traefik-specific tests
	@echo -e "$(BLUE)[INFO]$(NC) Running Traefik tests"
	@cd $(REPOS_DIR)/traefik && make test ENVIRONMENT=$(ENVIRONMENT)

status: ## Check status of all infrastructure components
	@echo -e "$(BLUE)[INFO]$(NC) Checking infrastructure status for environment: $(ENVIRONMENT)"
	@echo -e "\n$(YELLOW)=== Vault Status ===$(NC)"
	@if command -v vault &> /dev/null; then \
		vault status || echo -e "$(RED)[ERROR]$(NC) Vault not available"; \
	else \
		echo -e "$(RED)[ERROR]$(NC) Vault CLI not installed"; \
	fi
	@echo -e "\n$(YELLOW)=== Nomad Status ===$(NC)"
	@if command -v nomad &> /dev/null; then \
		nomad status || echo -e "$(RED)[ERROR]$(NC) Nomad not available"; \
	else \
		echo -e "$(RED)[ERROR]$(NC) Nomad CLI not installed"; \
	fi
	@echo -e "\n$(YELLOW)=== Traefik Status ===$(NC)"
	@curl -sf http://localhost:8080/ping > /dev/null && \
		echo -e "$(GREEN)[OK]$(NC) Traefik is healthy" || \
		echo -e "$(RED)[ERROR]$(NC) Traefik not available"

health: ## Check health of all services
	@echo -e "$(BLUE)[INFO]$(NC) Performing health checks"
	@echo -e "\n$(YELLOW)=== Health Checks ===$(NC)"
	@echo -n "Vault: "
	@curl -sf http://localhost:8200/v1/sys/health > /dev/null && \
		echo -e "$(GREEN)Healthy$(NC)" || echo -e "$(RED)Unhealthy$(NC)"
	@echo -n "Nomad: "
	@curl -sf http://localhost:4646/v1/status/leader > /dev/null && \
		echo -e "$(GREEN)Healthy$(NC)" || echo -e "$(RED)Unhealthy$(NC)"
	@echo -n "Traefik: "
	@curl -sf http://localhost:8080/ping > /dev/null && \
		echo -e "$(GREEN)Healthy$(NC)" || echo -e "$(RED)Unhealthy$(NC)"

logs: ## Tail logs from all services
	@echo -e "$(BLUE)[INFO]$(NC) Tailing logs for environment: $(ENVIRONMENT)"
	@echo -e "$(YELLOW)Use Ctrl+C to stop$(NC)"
	@if [ -d "logs" ]; then \
		tail -f logs/*.log 2>/dev/null || echo "No log files found in logs/"; \
	else \
		echo "Logs directory not found. Run 'make bootstrap' first."; \
	fi

clean: ## Clean up infrastructure (stops all services and removes data)
	@echo -e "$(YELLOW)[WARN]$(NC) This will stop all services and remove data!"
	@read -p "Are you sure? [y/N] " -n 1 -r; \
	echo; \
	if [[ $$REPLY =~ ^[Yy]$$ ]]; then \
		echo -e "$(BLUE)[INFO]$(NC) Cleaning up infrastructure..."; \
		$(MAKE) stop; \
		rm -rf secrets/$(ENVIRONMENT)* logs/$(ENVIRONMENT)* || true; \
		echo -e "$(GREEN)[SUCCESS]$(NC) Cleanup completed"; \
	else \
		echo -e "$(YELLOW)[INFO]$(NC) Cleanup cancelled"; \
	fi

cleanup-dry-run: ## Preview what would be cleaned up in HashiCorp installations
	@echo -e "$(BLUE)[INFO]$(NC) Running HashiCorp cleanup dry-run"
	@sudo $(SCRIPTS_DIR)/cleanup-hashicorp.sh --dry-run

cleanup-hashicorp: ## Completely remove HashiCorp installations (Vault, Nomad, Consul)
	@echo -e "$(YELLOW)[WARN]$(NC) This will completely remove HashiCorp installations!"
	@echo "This includes:"
	@echo "  - All systemd services (vault, nomad, consul)"
	@echo "  - All binary files and configurations"
	@echo "  - All data directories and user accounts"
	@echo "  - Repository sources"
	@echo ""
	@echo "A comprehensive backup will be created before removal."
	@read -p "Are you sure you want to proceed? [y/N] " -n 1 -r; \
	echo; \
	if [[ $$REPLY =~ ^[Yy]$$ ]]; then \
		echo -e "$(BLUE)[INFO]$(NC) Running HashiCorp cleanup..."; \
		sudo $(SCRIPTS_DIR)/cleanup-hashicorp.sh --force; \
		echo -e "$(GREEN)[SUCCESS]$(NC) HashiCorp cleanup completed"; \
	else \
		echo -e "$(YELLOW)[INFO]$(NC) Cleanup cancelled"; \
	fi

cleanup-backup-only: ## Create backup of HashiCorp installations without removing anything
	@echo -e "$(BLUE)[INFO]$(NC) Creating backup of HashiCorp installations"
	@sudo $(SCRIPTS_DIR)/cleanup-hashicorp.sh --backup-only
	@echo -e "$(GREEN)[SUCCESS]$(NC) Backup completed"

restore-hashicorp: ## Restore HashiCorp installations from backup
	@echo -e "$(BLUE)[INFO]$(NC) Restoring HashiCorp installations from backup"
	@sudo $(SCRIPTS_DIR)/restore-hashicorp.sh

restore-list: ## List available HashiCorp backup directories
	@echo -e "$(BLUE)[INFO]$(NC) Available HashiCorp backup directories:"
	@$(SCRIPTS_DIR)/restore-hashicorp.sh --list

test-cleanup: ## Test cleanup and restoration scripts
	@echo -e "$(BLUE)[INFO]$(NC) Running cleanup script tests"
	@$(SCRIPTS_DIR)/test-cleanup.sh

stop: ## Stop all infrastructure services
	@echo -e "$(BLUE)[INFO]$(NC) Stopping all infrastructure services"
	@cd $(REPOS_DIR)/traefik && make stop ENVIRONMENT=$(ENVIRONMENT) || true
	@cd $(REPOS_DIR)/nomad && make stop ENVIRONMENT=$(ENVIRONMENT) || true
	@cd $(REPOS_DIR)/vault && make stop ENVIRONMENT=$(ENVIRONMENT) || true
	@echo -e "$(GREEN)[SUCCESS]$(NC) All services stopped"

backup: ## Create backup of infrastructure state
	@echo -e "$(BLUE)[INFO]$(NC) Creating backup for environment: $(ENVIRONMENT)"
	@mkdir -p backups/$(ENVIRONMENT)/$(shell date +%Y%m%d-%H%M%S)
	@BACKUP_DIR="backups/$(ENVIRONMENT)/$(shell date +%Y%m%d-%H%M%S)"; \
	if [ -d "secrets" ]; then cp -r secrets $$BACKUP_DIR/; fi; \
	if command -v vault &> /dev/null && vault status &> /dev/null; then \
		vault operator raft snapshot save $$BACKUP_DIR/vault-snapshot.snap || true; \
	fi; \
	if command -v nomad &> /dev/null && nomad status &> /dev/null; then \
		nomad operator snapshot save $$BACKUP_DIR/nomad-snapshot.snap || true; \
	fi
	@echo -e "$(GREEN)[SUCCESS]$(NC) Backup completed"

restore: ## Restore infrastructure from backup
	@echo -e "$(BLUE)[INFO]$(NC) Restore functionality - manual process required"
	@echo "Available backups:"
	@ls -la backups/$(ENVIRONMENT)/ 2>/dev/null || echo "No backups found"
	@echo "To restore, manually copy secrets and apply snapshots using:"
	@echo "  vault operator raft snapshot restore <snapshot-file>"
	@echo "  nomad operator snapshot restore <snapshot-file>"

secrets-setup: ## Setup initial secrets in Vault
	@echo -e "$(BLUE)[INFO]$(NC) Setting up initial secrets"
	@if command -v vault &> /dev/null && vault status &> /dev/null; then \
		$(SCRIPTS_DIR)/setup-initial-secrets.sh $(ENVIRONMENT); \
		echo -e "$(GREEN)[SUCCESS]$(NC) Secrets setup completed"; \
	else \
		echo -e "$(RED)[ERROR]$(NC) Vault is not available"; \
	fi

validate: ## Validate infrastructure configuration
	@echo -e "$(BLUE)[INFO]$(NC) Validating infrastructure configuration"
	@echo -e "\n$(YELLOW)=== Configuration Validation ===$(NC)"
	@if [ -f "core/bootstrap-config.yaml" ]; then \
		echo -e "$(GREEN)[OK]$(NC) Bootstrap configuration found"; \
	else \
		echo -e "$(RED)[ERROR]$(NC) Bootstrap configuration missing"; \
	fi
	@if [ -f "core/environment-config.yaml" ]; then \
		echo -e "$(GREEN)[OK]$(NC) Environment configuration found"; \
	else \
		echo -e "$(RED)[ERROR]$(NC) Environment configuration missing"; \
	fi
	@if [ -f "security/security-policies.yaml" ]; then \
		echo -e "$(GREEN)[OK]$(NC) Security policies found"; \
	else \
		echo -e "$(RED)[ERROR]$(NC) Security policies missing"; \
	fi

monitor: ## Start monitoring dashboard
	@echo -e "$(BLUE)[INFO]$(NC) Starting monitoring dashboard"
	@echo "Open the following URLs in your browser:"
	@echo "  Vault UI: http://localhost:8200/ui"
	@echo "  Nomad UI: http://localhost:4646/ui"
	@echo "  Traefik Dashboard: http://localhost:8080/dashboard/"

dev: ## Start development environment
	@echo -e "$(BLUE)[INFO]$(NC) Starting development environment"
	@$(MAKE) bootstrap ENVIRONMENT=develop
	@$(MAKE) monitor

# CI/CD Integration
ci-test: ## Run tests suitable for CI/CD pipeline
	@echo -e "$(BLUE)[INFO]$(NC) Running CI/CD tests"
	@$(MAKE) validate
	@$(MAKE) test ENVIRONMENT=develop

ci-deploy: ## Deploy using CI/CD pipeline
	@echo -e "$(BLUE)[INFO]$(NC) Running CI/CD deployment"
	@$(MAKE) bootstrap ENVIRONMENT=$(ENVIRONMENT)
	@$(MAKE) test ENVIRONMENT=$(ENVIRONMENT)

# Information targets
info: ## Display infrastructure information
	@echo "Enterprise Infrastructure Stack"
	@echo "=============================="
	@echo "Current Environment: $(ENVIRONMENT)"
	@echo "Infrastructure Directory: $(INFRA_DIR)"
	@echo "Repositories Directory: $(REPOS_DIR)"
	@echo ""
	@echo "Components:"
	@echo "  - HashiCorp Vault (Secret Management)"
	@echo "  - HashiCorp Nomad (Workload Orchestration)" 
	@echo "  - Traefik (Load Balancer & Reverse Proxy)"
	@echo ""
	@echo "Bootstrap Order: Vault -> Nomad -> Traefik"

version: ## Show version information
	@echo "Infrastructure Stack Versions:"
	@if command -v vault &> /dev/null; then \
		echo -n "Vault: "; vault version; \
	else \
		echo "Vault: Not installed"; \
	fi
	@if command -v nomad &> /dev/null; then \
		echo -n "Nomad: "; nomad version; \
	else \
		echo "Nomad: Not installed"; \
	fi
	@echo -n "Traefik: "
	@curl -s http://localhost:8080/api/version 2>/dev/null | jq -r '.Version' || echo "Not available"

# Default target
.DEFAULT_GOAL := help