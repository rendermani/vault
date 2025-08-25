#!/bin/bash
# Master deployment script - orchestrates the complete infrastructure deployment
# Runs all deployment scripts in the correct order with proper error handling
set -euo pipefail

# Configuration variables - can be overridden by environment
ENVIRONMENT="${ENVIRONMENT:-production}"
DOMAIN_NAME="${DOMAIN_NAME:-cloudya.net}"
ACME_EMAIL="${ACME_EMAIL:-admin@cloudya.net}"
AUTO_APPROVE="${AUTO_APPROVE:-false}"
DRY_RUN="${DRY_RUN:-false}"
SKIP_CONSUL="${SKIP_CONSUL:-false}"
SKIP_NOMAD="${SKIP_NOMAD:-false}"
SKIP_VAULT="${SKIP_VAULT:-false}"
SKIP_TRAEFIK="${SKIP_TRAEFIK:-false}"
SKIP_VERIFY="${SKIP_VERIFY:-false}"
PARALLEL_DEPLOY="${PARALLEL_DEPLOY:-false}"

# Paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Source common functions
source "$SCRIPT_DIR/common.sh"

# Track deployment status
declare -A DEPLOYMENT_STATUS
declare -a DEPLOYMENT_ORDER
declare -i DEPLOYMENTS_SUCCEEDED=0
declare -i DEPLOYMENTS_FAILED=0

# Usage information
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Complete infrastructure deployment orchestrator"
    echo ""
    echo "Options:"
    echo "  -e, --environment ENV     Environment (develop|staging|production) [default: production]"
    echo "  -d, --domain DOMAIN       Domain name [default: cloudya.net]"
    echo "  --email EMAIL            ACME email for certificates [default: admin@cloudya.net]"
    echo "  -y, --yes                Auto-approve all deployments"
    echo "  --dry-run                Show what would be deployed without executing"
    echo "  --skip-consul            Skip Consul installation"
    echo "  --skip-nomad             Skip Nomad installation"  
    echo "  --skip-vault             Skip Vault deployment"
    echo "  --skip-traefik           Skip Traefik deployment"
    echo "  --skip-verify            Skip deployment verification"
    echo "  --parallel               Deploy services in parallel (experimental)"
    echo "  -h, --help               Show this help message"
    echo ""
    echo "Environment Variables:"
    echo "  CONSUL_VERSION           Consul version to install [default: 1.17.0]"
    echo "  NOMAD_VERSION            Nomad version to install [default: 1.7.2]"
    echo "  VAULT_VERSION            Vault version to deploy [default: 1.17.6]"
    echo "  TRAEFIK_VERSION          Traefik version to deploy [default: v3.2.3]"
    echo "  NOMAD_NAMESPACE          Nomad namespace [default: default]"
    echo "  NOMAD_REGION             Nomad region [default: global]"
    echo ""
    echo "Examples:"
    echo "  $0 --environment production --yes"
    echo "  $0 --environment staging --dry-run"
    echo "  $0 --skip-consul --skip-nomad --environment develop"
    echo "  VAULT_VERSION=1.17.5 $0 --environment production"
    echo ""
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -e|--environment)
                ENVIRONMENT="$2"
                shift 2
                ;;
            -d|--domain)
                DOMAIN_NAME="$2"
                shift 2
                ;;
            --email)
                ACME_EMAIL="$2"
                shift 2
                ;;
            -y|--yes)
                AUTO_APPROVE=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --skip-consul)
                SKIP_CONSUL=true
                shift
                ;;
            --skip-nomad)
                SKIP_NOMAD=true
                shift
                ;;
            --skip-vault)
                SKIP_VAULT=true
                shift
                ;;
            --skip-traefik)
                SKIP_TRAEFIK=true
                shift
                ;;
            --skip-verify)
                SKIP_VERIFY=true
                shift
                ;;
            --parallel)
                PARALLEL_DEPLOY=true
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
}

# Record deployment result
record_deployment() {
    local component="$1"
    local status="$2"
    local message="$3"
    
    DEPLOYMENT_STATUS["$component"]="$status:$message"
    
    if [[ "$status" == "SUCCESS" ]]; then
        ((DEPLOYMENTS_SUCCEEDED++))
        log_success "✓ $component: $message"
    else
        ((DEPLOYMENTS_FAILED++))
        log_error "✗ $component: $message"
    fi
}

# Deploy Consul
deploy_consul() {
    if [[ "$SKIP_CONSUL" == "true" ]]; then
        log_info "Skipping Consul deployment"
        record_deployment "consul" "SKIPPED" "Explicitly skipped"
        return 0
    fi
    
    log_info "Deploying Consul..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        record_deployment "consul" "SUCCESS" "Dry run - would install Consul"
        return 0
    fi
    
    local consul_script="$SCRIPT_DIR/install-consul.sh"
    if [[ ! -f "$consul_script" ]]; then
        record_deployment "consul" "FAILED" "Install script not found"
        return 1
    fi
    
    # Export environment variables for Consul
    export CONSUL_VERSION="${CONSUL_VERSION:-1.17.0}"
    export CONSUL_DATACENTER="${CONSUL_DATACENTER:-dc1}"
    export CONSUL_NODE_ROLE="${CONSUL_NODE_ROLE:-server}"
    export CONSUL_BOOTSTRAP_EXPECT="${CONSUL_BOOTSTRAP_EXPECT:-1}"
    export CONSUL_UI="${CONSUL_UI:-true}"
    
    if bash "$consul_script"; then
        record_deployment "consul" "SUCCESS" "Consul installed and running"
    else
        record_deployment "consul" "FAILED" "Consul installation failed"
        return 1
    fi
}

# Deploy Nomad
deploy_nomad() {
    if [[ "$SKIP_NOMAD" == "true" ]]; then
        log_info "Skipping Nomad deployment"
        record_deployment "nomad" "SKIPPED" "Explicitly skipped"
        return 0
    fi
    
    log_info "Deploying Nomad..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        record_deployment "nomad" "SUCCESS" "Dry run - would install Nomad"
        return 0
    fi
    
    local nomad_script="$SCRIPT_DIR/install-nomad.sh"
    if [[ ! -f "$nomad_script" ]]; then
        record_deployment "nomad" "FAILED" "Install script not found"
        return 1
    fi
    
    # Export environment variables for Nomad
    export NOMAD_VERSION="${NOMAD_VERSION:-1.7.2}"
    export NOMAD_DATACENTER="${NOMAD_DATACENTER:-dc1}"
    export NOMAD_REGION="${NOMAD_REGION:-global}"
    export NOMAD_NODE_ROLE="${NOMAD_NODE_ROLE:-both}"
    export NOMAD_BOOTSTRAP_EXPECT="${NOMAD_BOOTSTRAP_EXPECT:-1}"
    export NOMAD_UI="${NOMAD_UI:-true}"
    export CONSUL_ENABLED="${CONSUL_ENABLED:-$([ "$SKIP_CONSUL" == "true" ] && echo "false" || echo "true")}"
    
    if bash "$nomad_script"; then
        record_deployment "nomad" "SUCCESS" "Nomad installed and running"
    else
        record_deployment "nomad" "FAILED" "Nomad installation failed"
        return 1
    fi
}

# Deploy Vault
deploy_vault() {
    if [[ "$SKIP_VAULT" == "true" ]]; then
        log_info "Skipping Vault deployment"
        record_deployment "vault" "SKIPPED" "Explicitly skipped"
        return 0
    fi
    
    log_info "Deploying Vault..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        record_deployment "vault" "SUCCESS" "Dry run - would deploy Vault job"
        return 0
    fi
    
    local vault_script="$SCRIPT_DIR/deploy-vault-job.sh"
    if [[ ! -f "$vault_script" ]]; then
        record_deployment "vault" "FAILED" "Deploy script not found"
        return 1
    fi
    
    # Export environment variables for Vault
    export VAULT_VERSION="${VAULT_VERSION:-1.17.6}"
    export NOMAD_NAMESPACE="${NOMAD_NAMESPACE:-default}"
    export NOMAD_REGION="${NOMAD_REGION:-global}"
    
    local vault_args=("--environment" "$ENVIRONMENT")
    
    if [[ "$AUTO_APPROVE" == "true" ]]; then
        vault_args+=("--auto-init")
    fi
    
    if bash "$vault_script" "${vault_args[@]}"; then
        record_deployment "vault" "SUCCESS" "Vault job deployed"
    else
        record_deployment "vault" "FAILED" "Vault deployment failed"
        return 1
    fi
}

# Deploy Traefik  
deploy_traefik() {
    if [[ "$SKIP_TRAEFIK" == "true" ]]; then
        log_info "Skipping Traefik deployment"
        record_deployment "traefik" "SKIPPED" "Explicitly skipped"
        return 0
    fi
    
    log_info "Deploying Traefik..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        record_deployment "traefik" "SUCCESS" "Dry run - would deploy Traefik job"
        return 0
    fi
    
    local traefik_script="$SCRIPT_DIR/deploy-traefik-job.sh"
    if [[ ! -f "$traefik_script" ]]; then
        record_deployment "traefik" "FAILED" "Deploy script not found"
        return 1
    fi
    
    # Export environment variables for Traefik
    export TRAEFIK_VERSION="${TRAEFIK_VERSION:-v3.2.3}"
    export NOMAD_NAMESPACE="${NOMAD_NAMESPACE:-default}"
    export NOMAD_REGION="${NOMAD_REGION:-global}"
    
    local traefik_args=("--environment" "$ENVIRONMENT" "--domain" "$DOMAIN_NAME" "--email" "$ACME_EMAIL")
    
    # Use staging for non-production environments
    if [[ "$ENVIRONMENT" != "production" ]]; then
        traefik_args+=("--staging")
    fi
    
    if bash "$traefik_script" "${traefik_args[@]}"; then
        record_deployment "traefik" "SUCCESS" "Traefik job deployed"
    else
        record_deployment "traefik" "FAILED" "Traefik deployment failed"
        return 1
    fi
}

# Verify deployment
verify_deployment() {
    if [[ "$SKIP_VERIFY" == "true" ]]; then
        log_info "Skipping deployment verification"
        record_deployment "verify" "SKIPPED" "Explicitly skipped"
        return 0
    fi
    
    log_info "Verifying deployment..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        record_deployment "verify" "SUCCESS" "Dry run - would verify deployment"
        return 0
    fi
    
    local verify_script="$SCRIPT_DIR/verify-deployment.sh"
    if [[ ! -f "$verify_script" ]]; then
        record_deployment "verify" "FAILED" "Verify script not found"
        return 1
    fi
    
    local verify_args=("--environment" "$ENVIRONMENT" "--domain" "$DOMAIN_NAME")
    
    # Skip external tests in development
    if [[ "$ENVIRONMENT" == "develop" ]]; then
        verify_args+=("--skip-external")
    fi
    
    if bash "$verify_script" "${verify_args[@]}"; then
        record_deployment "verify" "SUCCESS" "All verification tests passed"
    else
        record_deployment "verify" "FAILED" "Some verification tests failed"
        return 1
    fi
}

# Wait for dependencies to be ready
wait_for_dependencies() {
    log_info "Waiting for dependencies to be ready..."
    
    # Wait for Consul if installed
    if [[ "$SKIP_CONSUL" != "true" ]] && [[ "$DRY_RUN" != "true" ]]; then
        if ! wait_for_service "Consul" "consul members" 120 5; then
            log_warning "Consul may not be fully ready, continuing anyway"
        fi
    fi
    
    # Wait for Nomad if installed
    if [[ "$SKIP_NOMAD" != "true" ]] && [[ "$DRY_RUN" != "true" ]]; then
        if ! wait_for_service "Nomad" "nomad node status" 120 5; then
            log_error "Nomad is not ready, cannot proceed with job deployments"
            return 1
        fi
    fi
    
    log_success "Dependencies are ready"
}

# Deploy infrastructure services in parallel
deploy_parallel() {
    log_info "Starting parallel deployment of services..."
    
    local pids=()
    
    # Deploy Vault and Traefik in parallel
    if [[ "$SKIP_VAULT" != "true" ]]; then
        deploy_vault &
        pids+=($!)
        DEPLOYMENT_ORDER+=("vault")
    fi
    
    if [[ "$SKIP_TRAEFIK" != "true" ]]; then
        deploy_traefik &
        pids+=($!)
        DEPLOYMENT_ORDER+=("traefik")
    fi
    
    # Wait for all parallel deployments to complete
    local all_success=true
    for pid in "${pids[@]}"; do
        if ! wait $pid; then
            all_success=false
        fi
    done
    
    if [[ "$all_success" == "true" ]]; then
        log_success "Parallel deployment completed successfully"
    else
        log_error "Some parallel deployments failed"
        return 1
    fi
}

# Deploy infrastructure services sequentially
deploy_sequential() {
    log_info "Starting sequential deployment of services..."
    
    # Deploy in order: Vault, then Traefik
    DEPLOYMENT_ORDER=("vault" "traefik")
    
    deploy_vault || return 1
    deploy_traefik || return 1
    
    log_success "Sequential deployment completed successfully"
}

# Generate deployment summary
generate_summary() {
    local summary_file="${LOGS_DIR}/deployment-summary-${ENVIRONMENT}-$(date +%Y%m%d_%H%M%S).md"
    
    log_info "Generating deployment summary..."
    
    cat > "$summary_file" <<EOF
# Infrastructure Deployment Summary - $ENVIRONMENT

**Generated:** $(date)  
**Environment:** $ENVIRONMENT  
**Domain:** $DOMAIN_NAME  
**ACME Email:** $ACME_EMAIL  
**Deployment Mode:** $([ "$PARALLEL_DEPLOY" == "true" ] && echo "Parallel" || echo "Sequential")

## Overview

- **Total Deployments:** ${#DEPLOYMENT_ORDER[@]}
- **Succeeded:** $DEPLOYMENTS_SUCCEEDED
- **Failed:** $DEPLOYMENTS_FAILED
- **Overall Status:** $([ $DEPLOYMENTS_FAILED -eq 0 ] && echo "✅ SUCCESS" || echo "❌ FAILED")

## Component Status

EOF
    
    for component in consul nomad vault traefik verify; do
        if [[ -n "${DEPLOYMENT_STATUS[$component]:-}" ]]; then
            local status="${DEPLOYMENT_STATUS[$component]%%:*}"
            local message="${DEPLOYMENT_STATUS[$component]#*:}"
            
            case "$status" in
                "SUCCESS")
                    echo "- **$component**: ✅ $message" >> "$summary_file"
                    ;;
                "FAILED")
                    echo "- **$component**: ❌ $message" >> "$summary_file"
                    ;;
                "SKIPPED")
                    echo "- **$component**: ⏭️ $message" >> "$summary_file"
                    ;;
            esac
        fi
    done
    
    cat >> "$summary_file" <<EOF

## Next Steps

EOF
    
    if [[ $DEPLOYMENTS_FAILED -eq 0 ]]; then
        cat >> "$summary_file" <<EOF
✅ **Deployment completed successfully!**

### Immediate Actions:
1. Verify all services are accessible
2. Complete initial configuration if needed
3. Set up monitoring and alerting
4. Configure backup procedures

### Service Access:
- **Traefik Dashboard**: https://traefik.$DOMAIN_NAME
- **Vault**: https://vault.$DOMAIN_NAME
- **Nomad**: https://nomad.$DOMAIN_NAME

### Security Checklist:
EOF
        
        case "$ENVIRONMENT" in
            production)
                cat >> "$summary_file" <<EOF
- [ ] Change default passwords
- [ ] Configure TLS certificates
- [ ] Enable audit logging
- [ ] Set up backup automation
- [ ] Configure monitoring alerts
- [ ] Review security policies
- [ ] Complete compliance audit
EOF
                ;;
            staging)
                cat >> "$summary_file" <<EOF
- [ ] Configure staging-specific settings
- [ ] Test certificate provisioning
- [ ] Validate service discovery
- [ ] Test backup/restore procedures
EOF
                ;;
            develop)
                cat >> "$summary_file" <<EOF
- [ ] Verify development environment
- [ ] Test basic functionality
- [ ] Configure development tools
EOF
                ;;
        esac
    else
        cat >> "$summary_file" <<EOF
❌ **Deployment failed!**

### Failed Components:
EOF
        
        for component in consul nomad vault traefik verify; do
            if [[ -n "${DEPLOYMENT_STATUS[$component]:-}" ]]; then
                local status="${DEPLOYMENT_STATUS[$component]%%:*}"
                local message="${DEPLOYMENT_STATUS[$component]#*:}"
                
                if [[ "$status" == "FAILED" ]]; then
                    echo "- **$component**: $message" >> "$summary_file"
                fi
            fi
        done
        
        cat >> "$summary_file" <<EOF

### Recovery Actions:
1. Check component logs for detailed error messages
2. Verify system requirements and dependencies
3. Fix identified issues
4. Re-run deployment with: \`$0 --environment $ENVIRONMENT\`

### Troubleshooting:
- Check systemd service status: \`systemctl status <service>\`
- View service logs: \`journalctl -u <service> -f\`
- Verify network connectivity and DNS resolution
- Check disk space and system resources
EOF
    fi
    
    cat >> "$summary_file" <<EOF

## Configuration Details

- **Consul Version:** ${CONSUL_VERSION:-1.17.0}
- **Nomad Version:** ${NOMAD_VERSION:-1.7.2}  
- **Vault Version:** ${VAULT_VERSION:-1.17.6}
- **Traefik Version:** ${TRAEFIK_VERSION:-v3.2.3}
- **Namespace:** ${NOMAD_NAMESPACE:-default}
- **Region:** ${NOMAD_REGION:-global}

## Logs and Documentation

- **Deployment Logs:** ${LOGS_DIR}/deployment.log
- **Individual Service Logs:** Check respective service log files
- **Configuration Files:** Located in /etc/<service>/ directories

---
*Generated by infrastructure deployment script*
EOF
    
    log_success "Deployment summary written to: $summary_file"
    
    # Display summary on console
    if [[ "$DRY_RUN" != "true" ]]; then
        echo ""
        log_info "=== DEPLOYMENT SUMMARY ==="
        cat "$summary_file"
    fi
}

# Pre-flight checks
preflight_checks() {
    log_info "Running pre-flight checks..."
    
    # Check if running as root
    if ! check_root; then
        return 1
    fi
    
    # Validate environment
    if ! validate_environment "$ENVIRONMENT"; then
        return 1
    fi
    
    # Validate email format
    if ! validate_email "$ACME_EMAIL"; then
        log_error "Invalid email format: $ACME_EMAIL"
        return 1
    fi
    
    # Check required scripts exist
    local required_scripts=()
    if [[ "$SKIP_CONSUL" != "true" ]]; then
        required_scripts+=("$SCRIPT_DIR/install-consul.sh")
    fi
    if [[ "$SKIP_NOMAD" != "true" ]]; then
        required_scripts+=("$SCRIPT_DIR/install-nomad.sh")
    fi
    if [[ "$SKIP_VAULT" != "true" ]]; then
        required_scripts+=("$SCRIPT_DIR/deploy-vault-job.sh")
    fi
    if [[ "$SKIP_TRAEFIK" != "true" ]]; then
        required_scripts+=("$SCRIPT_DIR/deploy-traefik-job.sh")
    fi
    if [[ "$SKIP_VERIFY" != "true" ]]; then
        required_scripts+=("$SCRIPT_DIR/verify-deployment.sh")
    fi
    
    for script in "${required_scripts[@]}"; do
        if [[ ! -f "$script" ]]; then
            log_error "Required script not found: $script"
            return 1
        fi
        
        if [[ ! -x "$script" ]]; then
            log_warning "Making script executable: $script"
            chmod +x "$script"
        fi
    done
    
    log_success "Pre-flight checks passed"
}

# Main deployment orchestration
main() {
    log_info "=== Infrastructure Deployment Orchestrator ==="
    log_info "Environment: $ENVIRONMENT"
    log_info "Domain: $DOMAIN_NAME"
    log_info "ACME Email: $ACME_EMAIL"
    log_info "Auto Approve: $AUTO_APPROVE"
    log_info "Dry Run: $DRY_RUN"
    log_info "Parallel Deploy: $PARALLEL_DEPLOY"
    
    # Initialize
    init_common_environment
    setup_exit_trap
    
    # Confirm deployment
    if [[ "$DRY_RUN" != "true" ]] && ! confirm_action "This will deploy infrastructure to $ENVIRONMENT environment" "$AUTO_APPROVE"; then
        log_info "Deployment cancelled"
        exit 0
    fi
    
    # Pre-flight checks
    preflight_checks || exit 1
    
    # Phase 1: Install base services (Consul, Nomad)
    log_info "=== Phase 1: Installing Base Services ==="
    deploy_consul || true  # Continue on failure
    deploy_nomad || true   # Continue on failure
    
    # Wait for dependencies
    wait_for_dependencies || exit 1
    
    # Phase 2: Deploy application services
    log_info "=== Phase 2: Deploying Application Services ==="
    if [[ "$PARALLEL_DEPLOY" == "true" ]]; then
        deploy_parallel || true
    else
        deploy_sequential || true
    fi
    
    # Phase 3: Verify deployment
    log_info "=== Phase 3: Verifying Deployment ==="
    verify_deployment || true
    
    # Generate summary
    generate_summary
    
    # Final status
    if [[ $DEPLOYMENTS_FAILED -eq 0 ]]; then
        log_success "=== Infrastructure deployment completed successfully! ==="
        exit 0
    else
        log_error "=== Infrastructure deployment completed with failures ==="
        log_error "Failed deployments: $DEPLOYMENTS_FAILED/$((DEPLOYMENTS_SUCCEEDED + DEPLOYMENTS_FAILED))"
        exit 1
    fi
}

# Initialize deployment status tracking
DEPLOYMENT_STATUS["consul"]=""
DEPLOYMENT_STATUS["nomad"]=""
DEPLOYMENT_STATUS["vault"]=""
DEPLOYMENT_STATUS["traefik"]=""
DEPLOYMENT_STATUS["verify"]=""

# Parse arguments and run
parse_args "$@"
main "$@"