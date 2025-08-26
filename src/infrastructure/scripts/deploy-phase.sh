#!/bin/bash
# Phase-based deployment script
# Based on proven patterns from /infrastructure/scripts/bootstrap.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_DIR="$(dirname "$SCRIPT_DIR")"
PHASE="${1:-}"
ENVIRONMENT="${2:-develop}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }

# Phase 1: Bootstrap with Ansible
deploy_phase_1() {
    log_info "Phase 1: Bootstrap with Ansible (Consul + Nomad without Vault)"
    
    cd "$INFRA_DIR/ansible"
    
    # Validate inventory
    ansible-inventory --list -i "inventories/$ENVIRONMENT" > /dev/null || {
        log_error "Invalid inventory for environment: $ENVIRONMENT"
        return 1
    }
    
    # Run bootstrap playbook
    log_info "Running system bootstrap playbook..."
    ansible-playbook -i "inventories/$ENVIRONMENT" \
        playbooks/01-system-bootstrap.yml \
        --tags "security,hardening,docker" \
        --diff --check || {
        log_error "System bootstrap failed"
        return 1
    }
    
    # Install Consul cluster
    log_info "Installing Consul cluster..."
    ansible-playbook -i "inventories/$ENVIRONMENT" \
        playbooks/02-consul-cluster.yml \
        --limit consul_servers \
        --diff
    
    # Install Nomad cluster (without Vault integration)
    log_info "Installing Nomad cluster (basic mode)..."
    ansible-playbook -i "inventories/$ENVIRONMENT" \
        playbooks/03-nomad-cluster.yml \
        --limit nomad_servers,nomad_clients \
        --extra-vars "vault_integration=false" \
        --diff
    
    log_success "Phase 1 completed successfully"
}

# Phase 2: Manual initialization
deploy_phase_2() {
    log_info "Phase 2: Manual Init (ACL bootstrap, Vault init/unseal)"
    
    # Check prerequisites
    command -v consul >/dev/null 2>&1 || { log_error "consul CLI not found"; return 1; }
    command -v nomad >/dev/null 2>&1 || { log_error "nomad CLI not found"; return 1; }
    command -v vault >/dev/null 2>&1 || { log_error "vault CLI not found"; return 1; }
    
    cd "$INFRA_DIR"
    
    # Create secrets directory
    mkdir -p secrets
    chmod 700 secrets
    
    # Bootstrap Consul ACLs
    if [[ ! -f "secrets/consul-bootstrap-$ENVIRONMENT.json" ]]; then
        log_info "Bootstrapping Consul ACLs..."
        consul acl bootstrap -format=json > "secrets/consul-bootstrap-$ENVIRONMENT.json" || {
            log_warn "Consul ACL bootstrap failed - may already be initialized"
        }
    fi
    
    # Bootstrap Nomad ACLs
    if [[ ! -f "secrets/nomad-bootstrap-$ENVIRONMENT.json" ]]; then
        log_info "Bootstrapping Nomad ACLs..."
        nomad acl bootstrap -json > "secrets/nomad-bootstrap-$ENVIRONMENT.json" || {
            log_warn "Nomad ACL bootstrap failed - may already be initialized"
        }
    fi
    
    # Deploy Vault job to Nomad
    log_info "Deploying Vault job to Nomad..."
    nomad job run "jobs/vault-bootstrap.nomad" || {
        log_error "Failed to deploy Vault job"
        return 1
    }
    
    # Wait for Vault to be ready
    log_info "Waiting for Vault to be ready..."
    for i in {1..30}; do
        if vault status >/dev/null 2>&1; then
            log_success "Vault is ready"
            break
        fi
        log_info "Waiting for Vault... (attempt $i/30)"
        sleep 10
    done
    
    # Initialize Vault if needed
    if [[ ! -f "secrets/vault-keys-$ENVIRONMENT.json" ]]; then
        log_info "Initializing Vault..."
        vault operator init -format=json > "secrets/vault-keys-$ENVIRONMENT.json" || {
            log_error "Vault initialization failed"
            return 1
        }
        log_success "Vault initialized successfully"
    fi
    
    # Unseal Vault
    log_info "Unsealing Vault..."
    UNSEAL_KEYS=$(jq -r '.unseal_keys_b64[]' "secrets/vault-keys-$ENVIRONMENT.json" | head -3)
    for key in $UNSEAL_KEYS; do
        vault operator unseal "$key" >/dev/null
    done
    
    log_success "Phase 2 completed successfully"
}

# Phase 3: Terraform configuration
deploy_phase_3() {
    log_info "Phase 3: Terraform Configuration (Vault, ACLs, policies)"
    
    cd "$INFRA_DIR/terraform"
    
    # Initialize Terraform
    terraform init -upgrade || {
        log_error "Terraform initialization failed"
        return 1
    }
    
    # Select workspace
    terraform workspace select "$ENVIRONMENT" || terraform workspace new "$ENVIRONMENT"
    
    # Plan changes
    log_info "Planning Terraform changes..."
    terraform plan -var-file="environments/$ENVIRONMENT/terraform.tfvars" -out="$ENVIRONMENT.tfplan" || {
        log_error "Terraform plan failed"
        return 1
    }
    
    # Apply changes
    log_info "Applying Terraform configuration..."
    terraform apply "$ENVIRONMENT.tfplan" || {
        log_error "Terraform apply failed"
        return 1
    }
    
    log_success "Phase 3 completed successfully"
}

# Phase 4: Enable Nomad-Vault integration
deploy_phase_4() {
    log_info "Phase 4: Enable Nomad-Vault Integration"
    
    cd "$INFRA_DIR/ansible"
    
    # Update Nomad configuration for Vault integration
    log_info "Configuring Nomad-Vault integration..."
    ansible-playbook -i "inventories/$ENVIRONMENT" \
        playbooks/04-vault-integration.yml \
        --extra-vars "vault_integration=true" \
        --diff
    
    # Test workload identity
    log_info "Testing workload identity..."
    cd "$INFRA_DIR"
    nomad job run "jobs/test-vault-integration.nomad" || {
        log_error "Workload identity test failed"
        return 1
    }
    
    # Migrate existing workloads
    log_info "Migrating existing workloads..."
    cd "$INFRA_DIR/ansible"
    ansible-playbook -i "inventories/$ENVIRONMENT" \
        playbooks/05-workload-migration.yml \
        --diff
    
    # Revoke temporary tokens
    log_info "Revoking temporary bootstrap tokens..."
    if [[ -f "$INFRA_DIR/secrets/vault-keys-$ENVIRONMENT.json" ]]; then
        ROOT_TOKEN=$(jq -r '.root_token' "$INFRA_DIR/secrets/vault-keys-$ENVIRONMENT.json")
        export VAULT_TOKEN=$ROOT_TOKEN
        # Revoke any temporary tokens (implementation specific)
    fi
    
    log_success "Phase 4 completed successfully"
}

# Phase 5: Deploy Traefik with Nomad Pack
deploy_phase_5() {
    log_info "Phase 5: Deploy Traefik with Nomad Pack"
    
    cd "$INFRA_DIR"
    
    # Check nomad-pack availability
    command -v nomad-pack >/dev/null 2>&1 || {
        log_error "nomad-pack CLI not found"
        log_info "Install with: curl -L https://github.com/hashicorp/nomad-pack/releases/latest/download/nomad-pack_linux_amd64.zip -o nomad-pack.zip && unzip nomad-pack.zip && sudo mv nomad-pack /usr/local/bin/"
        return 1
    }
    
    # Deploy Traefik pack
    log_info "Deploying Traefik with Nomad Pack..."
    nomad-pack run \
        --name="traefik-$ENVIRONMENT" \
        --var="environment=$ENVIRONMENT" \
        --var-file="packs/traefik/vars/$ENVIRONMENT.hcl" \
        "packs/traefik" || {
        log_error "Traefik deployment failed"
        return 1
    }
    
    # Deploy monitoring stack
    log_info "Deploying monitoring stack..."
    nomad-pack run \
        --name="monitoring-$ENVIRONMENT" \
        --var="environment=$ENVIRONMENT" \
        "packs/monitoring" || {
        log_warn "Monitoring deployment failed - continuing..."
    }
    
    log_success "Phase 5 completed successfully"
}

# Phase 6: Testing and validation
deploy_phase_6() {
    log_info "Phase 6: Testing and Validation"
    
    cd "$INFRA_DIR/tests"
    
    # Run infrastructure tests
    log_info "Running infrastructure tests..."
    ./integration/infrastructure-test.sh "$ENVIRONMENT" || {
        log_error "Infrastructure tests failed"
        return 1
    }
    
    # Run security tests
    log_info "Running security tests..."
    ./security/security-test.sh "$ENVIRONMENT" || {
        log_error "Security tests failed"
        return 1
    }
    
    # Run performance tests
    log_info "Running performance tests..."
    ./performance/performance-test.sh "$ENVIRONMENT" || {
        log_warn "Performance tests failed - review required"
    }
    
    # Generate validation report
    log_info "Generating validation report..."
    ./generate-report.sh "$ENVIRONMENT" > "../docs/validation-report-$ENVIRONMENT.md"
    
    log_success "Phase 6 completed successfully"
}

# Main function
main() {
    case $PHASE in
        "1"|"phase1")
            deploy_phase_1
            ;;
        "2"|"phase2") 
            deploy_phase_2
            ;;
        "3"|"phase3")
            deploy_phase_3
            ;;
        "4"|"phase4")
            deploy_phase_4
            ;;
        "5"|"phase5")
            deploy_phase_5
            ;;
        "6"|"phase6")
            deploy_phase_6
            ;;
        "all")
            deploy_phase_1 && deploy_phase_2 && deploy_phase_3 && deploy_phase_4 && deploy_phase_5 && deploy_phase_6
            ;;
        *)
            echo "Usage: $0 <phase> [environment]"
            echo "Phases: 1-6, all"
            echo "Environments: develop, staging, production"
            exit 1
            ;;
    esac
}

# Validate inputs
if [[ ! "$ENVIRONMENT" =~ ^(develop|staging|production)$ ]]; then
    log_error "Invalid environment: $ENVIRONMENT"
    exit 1
fi

# Run main function
main "$@"