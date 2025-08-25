#!/bin/bash
# Idempotent script to deploy Vault job to Nomad
# Can be run multiple times safely
set -euo pipefail

# Configuration variables - can be overridden by environment
ENVIRONMENT="${ENVIRONMENT:-develop}"
NOMAD_NAMESPACE="${NOMAD_NAMESPACE:-default}"
NOMAD_REGION="${NOMAD_REGION:-global}"
VAULT_VERSION="${VAULT_VERSION:-1.17.6}"
DRY_RUN="${DRY_RUN:-false}"
AUTO_INIT="${AUTO_INIT:-false}"
FORCE_DEPLOY="${FORCE_DEPLOY:-false}"
JOB_FILE="${JOB_FILE:-}"
VAULT_TOKEN="${VAULT_TOKEN:-}"

# Paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
JOBS_DIR="${PROJECT_ROOT}/nomad/jobs"
LOGS_DIR="${PROJECT_ROOT}/logs"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "${LOGS_DIR}/vault-deploy.log"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "${LOGS_DIR}/vault-deploy.log"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "${LOGS_DIR}/vault-deploy.log"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "${LOGS_DIR}/vault-deploy.log"
}

# Usage information
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Deploy Vault job to Nomad cluster"
    echo ""
    echo "Options:"
    echo "  -e, --environment ENV     Environment (develop|staging|production) [default: develop]"
    echo "  -n, --namespace NS        Nomad namespace [default: default]"
    echo "  -r, --region REGION       Nomad region [default: global]"
    echo "  -v, --version VERSION     Vault version [default: 1.17.6]"
    echo "  -f, --file FILE          Custom job file path"
    echo "  -t, --token TOKEN        Vault token for post-deployment operations"
    echo "  -d, --dry-run            Show what would be deployed without executing"
    echo "  -i, --auto-init          Automatically initialize Vault after deployment"
    echo "  --force                  Force deployment even if job is running"
    echo "  -h, --help               Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 --environment develop"
    echo "  $0 --environment staging --dry-run"
    echo "  $0 --environment production --auto-init --token s.xyz123"
    echo "  $0 --file /path/to/custom/vault.nomad"
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
            -n|--namespace)
                NOMAD_NAMESPACE="$2"
                shift 2
                ;;
            -r|--region)
                NOMAD_REGION="$2"
                shift 2
                ;;
            -v|--version)
                VAULT_VERSION="$2"
                shift 2
                ;;
            -f|--file)
                JOB_FILE="$2"
                shift 2
                ;;
            -t|--token)
                VAULT_TOKEN="$2"
                shift 2
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -i|--auto-init)
                AUTO_INIT=true
                shift
                ;;
            --force)
                FORCE_DEPLOY=true
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

# Validate environment
validate_environment() {
    case $ENVIRONMENT in
        develop|staging|production)
            ;;
        *)
            log_error "Invalid environment: $ENVIRONMENT"
            log_error "Valid environments: develop, staging, production"
            exit 1
            ;;
    esac
}

# Setup directories
setup_directories() {
    mkdir -p "$LOGS_DIR"
    mkdir -p "${PROJECT_ROOT}/tmp"
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if Nomad CLI is available
    if ! command -v nomad &> /dev/null; then
        log_error "Nomad CLI not found. Please install Nomad."
        exit 1
    fi
    
    # Check Nomad connection
    if ! nomad node status &> /dev/null; then
        log_error "Cannot connect to Nomad cluster. Is Nomad agent running?"
        log_error "Make sure NOMAD_ADDR is set correctly or Nomad agent is accessible"
        exit 1
    fi
    
    # Check Vault CLI if auto-init is requested
    if [[ "$AUTO_INIT" == "true" ]] && ! command -v vault &> /dev/null; then
        log_error "Vault CLI not found but auto-init is requested. Please install Vault CLI."
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# Determine job file path
determine_job_file() {
    if [[ -n "$JOB_FILE" ]]; then
        if [[ ! -f "$JOB_FILE" ]]; then
            log_error "Custom job file not found: $JOB_FILE"
            exit 1
        fi
        log_info "Using custom job file: $JOB_FILE"
    else
        JOB_FILE="${JOBS_DIR}/${ENVIRONMENT}/vault.nomad"
        if [[ ! -f "$JOB_FILE" ]]; then
            log_error "Default job file not found: $JOB_FILE"
            log_error "Available job files:"
            find "$JOBS_DIR" -name "*.nomad" | sort
            exit 1
        fi
        log_info "Using default job file: $JOB_FILE"
    fi
}

# Get current job status
get_job_status() {
    local job_name="vault-${ENVIRONMENT}"
    local job_status
    
    if nomad job status "$job_name" &> /dev/null; then
        job_status=$(nomad job status -short "$job_name" | grep "Status" | awk '{print $3}' || echo "unknown")
        echo "$job_status"
    else
        echo "not_found"
    fi
}

# Check if deployment should proceed
should_deploy() {
    local current_status
    current_status=$(get_job_status)
    
    log_info "Current job status: $current_status"
    
    case "$current_status" in
        "not_found")
            log_info "Job not found, proceeding with deployment"
            return 0
            ;;
        "running")
            if [[ "$FORCE_DEPLOY" == "true" ]]; then
                log_warning "Job is running but force deployment requested"
                return 0
            else
                log_warning "Job is already running. Use --force to redeploy"
                return 1
            fi
            ;;
        "pending"|"dead"|"failed")
            log_info "Job is in $current_status state, proceeding with deployment"
            return 0
            ;;
        *)
            if [[ "$FORCE_DEPLOY" == "true" ]]; then
                log_info "Forcing deployment despite status: $current_status"
                return 0
            else
                log_warning "Job status is $current_status. Use --force to override"
                return 1
            fi
            ;;
    esac
}

# Validate job file
validate_job() {
    log_info "Validating job file..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would validate: $JOB_FILE"
        return 0
    fi
    
    # Create temporary file with substituted variables
    local temp_job="${PROJECT_ROOT}/tmp/vault-${ENVIRONMENT}-$(date +%s).nomad"
    
    # Substitute environment variables in job file
    envsubst < "$JOB_FILE" > "$temp_job"
    
    if ! nomad job validate "$temp_job"; then
        log_error "Job validation failed for $JOB_FILE"
        rm -f "$temp_job"
        exit 1
    fi
    
    rm -f "$temp_job"
    log_success "Job validation passed"
}

# Plan deployment
plan_deployment() {
    log_info "Planning deployment..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would plan deployment of: $JOB_FILE"
        return 0
    fi
    
    # Create temporary file with substituted variables
    local temp_job="${PROJECT_ROOT}/tmp/vault-${ENVIRONMENT}-plan-$(date +%s).nomad"
    
    # Substitute environment variables in job file
    envsubst < "$JOB_FILE" > "$temp_job"
    
    log_info "Planning with namespace: $NOMAD_NAMESPACE, region: $NOMAD_REGION"
    
    if ! nomad job plan -namespace="$NOMAD_NAMESPACE" -region="$NOMAD_REGION" "$temp_job"; then
        log_error "Deployment planning failed"
        rm -f "$temp_job"
        exit 1
    fi
    
    rm -f "$temp_job"
    log_success "Deployment planning completed"
}

# Deploy Vault job
deploy_vault() {
    log_info "Deploying Vault to $ENVIRONMENT environment..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would deploy: $JOB_FILE"
        return 0
    fi
    
    # Create temporary file with substituted variables
    local temp_job="${PROJECT_ROOT}/tmp/vault-${ENVIRONMENT}-deploy-$(date +%s).nomad"
    
    # Export environment variables for job template substitution
    export ENVIRONMENT
    export VAULT_VERSION
    export NOMAD_NAMESPACE
    export NOMAD_REGION
    
    # Substitute environment variables in job file
    envsubst < "$JOB_FILE" > "$temp_job"
    
    log_info "Deploying with namespace: $NOMAD_NAMESPACE, region: $NOMAD_REGION"
    
    if ! nomad job run -namespace="$NOMAD_NAMESPACE" -region="$NOMAD_REGION" "$temp_job"; then
        log_error "Deployment failed"
        rm -f "$temp_job"
        exit 1
    fi
    
    rm -f "$temp_job"
    log_success "Vault deployed successfully"
}

# Wait for deployment to be healthy
wait_for_healthy() {
    local job_name="vault-${ENVIRONMENT}"
    local timeout=600  # 10 minutes
    local interval=15
    local elapsed=0
    
    log_info "Waiting for deployment to be healthy..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would wait for deployment to be healthy"
        return 0
    fi
    
    while [ $elapsed -lt $timeout ]; do
        local status
        status=$(nomad job status -namespace="$NOMAD_NAMESPACE" "$job_name" | grep "Status" | awk '{print $3}' || echo "unknown")
        
        if [ "$status" = "running" ]; then
            # Check if all allocations are healthy
            local healthy_allocs failed_allocs
            healthy_allocs=$(nomad job status -namespace="$NOMAD_NAMESPACE" "$job_name" | grep -c "running" || echo "0")
            failed_allocs=$(nomad job status -namespace="$NOMAD_NAMESPACE" "$job_name" | grep -c "failed" || echo "0")
            
            if [ "$healthy_allocs" -gt 0 ] && [ "$failed_allocs" -eq 0 ]; then
                log_success "Deployment is healthy ($healthy_allocs running allocations)"
                return 0
            fi
            
            log_info "Deployment status: $status ($healthy_allocs running, $failed_allocs failed)"
        else
            log_info "Deployment status: $status (waiting... ${elapsed}s/${timeout}s)"
        fi
        
        sleep $interval
        elapsed=$((elapsed + interval))
    done
    
    log_error "Deployment did not become healthy within $timeout seconds"
    
    # Show detailed status for troubleshooting
    log_info "Current job status:"
    nomad job status -namespace="$NOMAD_NAMESPACE" "$job_name" || true
    
    exit 1
}

# Get Vault service endpoint
get_vault_endpoint() {
    local service_name="vault-${ENVIRONMENT}"
    local vault_addr
    
    # Try to get service from Consul if available
    if command -v consul &> /dev/null && consul catalog services | grep -q "^$service_name$"; then
        local service_info
        service_info=$(consul catalog service "$service_name" -format=json)
        local service_ip service_port
        service_ip=$(echo "$service_info" | jq -r '.[0].ServiceAddress // .[0].Address')
        service_port=$(echo "$service_info" | jq -r '.[0].ServicePort')
        
        if [[ "$service_ip" != "null" && "$service_port" != "null" ]]; then
            case $ENVIRONMENT in
                develop)
                    vault_addr="http://${service_ip}:${service_port}"
                    ;;
                *)
                    vault_addr="https://${service_ip}:${service_port}"
                    ;;
            esac
        fi
    fi
    
    # Fallback to standard endpoints
    if [[ -z "$vault_addr" ]]; then
        case $ENVIRONMENT in
            develop)
                vault_addr="http://localhost:8200"
                ;;
            staging)
                vault_addr="https://localhost:8210"
                ;;
            production)
                vault_addr="https://localhost:8220"
                ;;
        esac
    fi
    
    echo "$vault_addr"
}

# Wait for Vault to be available
wait_for_vault() {
    local vault_addr
    vault_addr=$(get_vault_endpoint)
    local timeout=300  # 5 minutes
    local interval=10
    local elapsed=0
    
    log_info "Waiting for Vault to be available at $vault_addr..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would wait for Vault to be available"
        return 0
    fi
    
    # Set environment for Vault commands
    export VAULT_ADDR="$vault_addr"
    
    if [[ "$ENVIRONMENT" != "develop" ]]; then
        export VAULT_SKIP_VERIFY=true  # For self-signed certs in staging/production
    fi
    
    while [ $elapsed -lt $timeout ]; do
        if command -v vault &> /dev/null && vault status &> /dev/null; then
            log_success "Vault is available at $vault_addr"
            vault status
            return 0
        fi
        
        log_info "Waiting for Vault... (${elapsed}s/${timeout}s)"
        sleep $interval
        elapsed=$((elapsed + interval))
    done
    
    log_warning "Vault did not become available within $timeout seconds"
    log_warning "This might be expected if Vault needs initialization"
    return 0
}

# Initialize Vault if requested
initialize_vault() {
    if [[ "$AUTO_INIT" != "true" ]]; then
        return 0
    fi
    
    log_info "Checking if Vault initialization is needed..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would initialize Vault if needed"
        return 0
    fi
    
    if ! command -v vault &> /dev/null; then
        log_error "Vault CLI not available for auto-initialization"
        return 1
    fi
    
    # Check if already initialized
    if vault status | grep -q "Initialized.*true"; then
        log_info "Vault is already initialized"
        return 0
    fi
    
    local init_file="${LOGS_DIR}/vault-init-${ENVIRONMENT}-$(date +%Y%m%d_%H%M%S).json"
    
    log_warning "Initializing Vault for $ENVIRONMENT environment"
    log_warning "This should only be done once per cluster!"
    
    case $ENVIRONMENT in
        develop)
            # Development with simple setup
            vault operator init -key-shares=1 -key-threshold=1 -format=json > "$init_file"
            ;;
        staging|production)
            # Production-like with recovery keys
            vault operator init -recovery-shares=5 -recovery-threshold=3 -format=json > "$init_file"
            ;;
    esac
    
    chmod 600 "$init_file"
    
    log_success "Vault initialized successfully"
    log_warning "CRITICAL: Initialization keys and root token stored in: $init_file"
    log_warning "This file contains extremely sensitive information!"
    log_warning "For production, immediately:"
    log_warning "1. Backup keys securely"
    log_warning "2. Distribute to key holders"
    log_warning "3. Remove from this system"
    
    # If in development mode, auto-unseal and show token
    if [[ "$ENVIRONMENT" == "develop" ]]; then
        local unseal_key root_token
        unseal_key=$(jq -r '.unseal_keys_b64[0]' "$init_file")
        root_token=$(jq -r '.root_token' "$init_file")
        
        if [[ -n "$unseal_key" && "$unseal_key" != "null" ]]; then
            log_info "Auto-unsealing development Vault..."
            vault operator unseal "$unseal_key"
            
            log_info "Development root token: $root_token"
            log_warning "Save this token for development use"
        fi
    fi
}

# Post-deployment verification
verify_deployment() {
    log_info "Verifying deployment..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would verify deployment"
        return 0
    fi
    
    local job_name="vault-${ENVIRONMENT}"
    local vault_addr
    vault_addr=$(get_vault_endpoint)
    
    # Check job status
    if ! nomad job status -namespace="$NOMAD_NAMESPACE" "$job_name" &> /dev/null; then
        log_error "Job $job_name not found in namespace $NOMAD_NAMESPACE"
        return 1
    fi
    
    log_success "Job is deployed and running"
    
    # Check Vault health endpoint
    log_info "Checking Vault health endpoint..."
    
    local health_check_url
    if [[ "$ENVIRONMENT" == "develop" ]]; then
        health_check_url="${vault_addr}/v1/sys/health"
    else
        health_check_url="${vault_addr}/v1/sys/health"
    fi
    
    if curl -k -s "$health_check_url" | jq -e '.initialized' &> /dev/null; then
        log_success "Vault health check passed"
    else
        log_warning "Vault health check failed or Vault not yet initialized"
        log_info "This is normal for a fresh deployment"
    fi
    
    # Show service information
    log_info "Vault service information:"
    log_info "  Environment: $ENVIRONMENT"
    log_info "  Endpoint: $vault_addr"
    log_info "  Namespace: $NOMAD_NAMESPACE"
    log_info "  Region: $NOMAD_REGION"
    
    log_success "Deployment verification completed"
}

# Generate post-deployment instructions
generate_instructions() {
    local instructions_file="${LOGS_DIR}/post-deployment-${ENVIRONMENT}-$(date +%Y%m%d_%H%M%S).md"
    local vault_addr
    vault_addr=$(get_vault_endpoint)
    
    log_info "Generating post-deployment instructions..."
    
    cat > "$instructions_file" <<EOF
# Vault Deployment Instructions - $ENVIRONMENT

**Generated:** $(date)  
**Environment:** $ENVIRONMENT  
**Vault Address:** $vault_addr  
**Nomad Namespace:** $NOMAD_NAMESPACE  
**Nomad Region:** $NOMAD_REGION  

## Quick Status Check

\`\`\`bash
# Check job status
nomad job status -namespace=$NOMAD_NAMESPACE vault-$ENVIRONMENT

# Check Vault status
export VAULT_ADDR="$vault_addr"
EOF
    
    if [[ "$ENVIRONMENT" != "develop" ]]; then
        echo "export VAULT_SKIP_VERIFY=true  # For self-signed certs" >> "$instructions_file"
    fi
    
    cat >> "$instructions_file" <<EOF
vault status
\`\`\`

## Next Steps

### If Vault needs initialization:
EOF
    
    case $ENVIRONMENT in
        develop)
            cat >> "$instructions_file" <<EOF

\`\`\`bash
# Development initialization (simple)
vault operator init -key-shares=1 -key-threshold=1
\`\`\`

### After initialization:
\`\`\`bash
# Unseal Vault
vault operator unseal <unseal-key>

# Login with root token
vault auth <root-token>

# Test basic functionality
vault secrets list
vault kv put secret/test key=value
vault kv get secret/test
\`\`\`
EOF
            ;;
        staging|production)
            cat >> "$instructions_file" <<EOF

⚠️ **SECURITY CRITICAL** for $ENVIRONMENT:

\`\`\`bash
# Initialize with recovery keys (auto-unseal environments)
vault operator init -recovery-shares=5 -recovery-threshold=3 -format=json > vault-init-$ENVIRONMENT.json

# IMMEDIATELY secure the keys:
# 1. Backup vault-init-$ENVIRONMENT.json to secure storage
# 2. Distribute recovery keys among trusted individuals
# 3. Remove the file from this system
# 4. Never store keys in plain text
\`\`\`

### Production Setup:
\`\`\`bash
# Set root token
export VAULT_TOKEN="<root-token-from-init>"

# Run production setup (if available)
vault auth <root-token>
# Configure auth methods, policies, secrets engines

# REVOKE root token after setup
vault token revoke <root-token>
\`\`\`
EOF
            ;;
    esac
    
    cat >> "$instructions_file" <<EOF

## Monitoring & Troubleshooting

### View Logs:
\`\`\`bash
# Nomad job logs
nomad alloc logs -namespace=$NOMAD_NAMESPACE \$(nomad job allocs -namespace=$NOMAD_NAMESPACE vault-$ENVIRONMENT | grep running | head -1 | awk '{print \$1}')

# Follow logs
nomad alloc logs -namespace=$NOMAD_NAMESPACE -f \$(nomad job allocs -namespace=$NOMAD_NAMESPACE vault-$ENVIRONMENT | grep running | head -1 | awk '{print \$1}')
\`\`\`

### Common Issues:
1. **Vault sealed**: Use recovery/unseal keys
2. **TLS errors**: Check certificate configuration
3. **Permission errors**: Verify volume permissions
4. **Service not accessible**: Check network configuration

### Health Checks:
\`\`\`bash
# Vault health endpoint
curl -k $vault_addr/v1/sys/health

# Nomad service checks
nomad job status -namespace=$NOMAD_NAMESPACE vault-$ENVIRONMENT
\`\`\`

## Security Checklist for $ENVIRONMENT

EOF
    
    case $ENVIRONMENT in
        develop)
            cat >> "$instructions_file" <<EOF
- [ ] Vault initialized and unsealed
- [ ] Basic secrets engine tested
- [ ] Development policies configured
EOF
            ;;
        staging)
            cat >> "$instructions_file" <<EOF
- [ ] Recovery keys secured and distributed
- [ ] TLS certificates properly configured
- [ ] Auth methods configured
- [ ] Policies implemented
- [ ] Audit logging enabled
- [ ] Monitoring configured
EOF
            ;;
        production)
            cat >> "$instructions_file" <<EOF
- [ ] **CRITICAL**: Recovery keys secured offline
- [ ] **CRITICAL**: Root token revoked after setup
- [ ] TLS certificates from trusted CA
- [ ] All auth methods configured and tested
- [ ] All policies implemented and audited
- [ ] Audit logging enabled and monitored
- [ ] Automated backups configured
- [ ] Disaster recovery procedures tested
- [ ] Security scanning enabled
- [ ] Compliance requirements verified
- [ ] Monitoring and alerting configured
- [ ] Incident response procedures documented
EOF
            ;;
    esac
    
    cat >> "$instructions_file" <<EOF

---
*Generated by vault deployment script*
EOF
    
    log_success "Instructions written to: $instructions_file"
    
    if [[ "$DRY_RUN" != "true" ]]; then
        log_info "=== POST-DEPLOYMENT SUMMARY ==="
        cat "$instructions_file"
    fi
}

# Cleanup on failure
cleanup_on_failure() {
    if [[ "$DRY_RUN" == "true" ]]; then
        return 0
    fi
    
    log_warning "Deployment failed, checking if cleanup is needed..."
    
    local job_name="vault-${ENVIRONMENT}"
    
    if nomad job status -namespace="$NOMAD_NAMESPACE" "$job_name" &> /dev/null; then
        local status
        status=$(nomad job status -namespace="$NOMAD_NAMESPACE" "$job_name" | grep "Status" | awk '{print $3}')
        
        if [[ "$status" == "failed" || "$status" == "dead" ]]; then
            log_info "Stopping failed job..."
            nomad job stop -namespace="$NOMAD_NAMESPACE" "$job_name" || true
        fi
    fi
    
    # Clean up temporary files
    rm -f "${PROJECT_ROOT}/tmp/vault-${ENVIRONMENT}"-*.nomad
}

# Main deployment function
main() {
    log_info "=== Vault Deployment Script ==="
    log_info "Environment: $ENVIRONMENT"
    log_info "Namespace: $NOMAD_NAMESPACE"
    log_info "Region: $NOMAD_REGION"
    log_info "Version: $VAULT_VERSION"
    log_info "Dry Run: $DRY_RUN"
    log_info "Auto Init: $AUTO_INIT"
    log_info "Force Deploy: $FORCE_DEPLOY"
    
    # Setup error handling
    trap cleanup_on_failure ERR
    
    # Execute deployment steps
    setup_directories
    check_prerequisites
    validate_environment
    determine_job_file
    
    if ! should_deploy; then
        log_info "Skipping deployment based on current status"
        exit 0
    fi
    
    validate_job
    plan_deployment
    deploy_vault
    wait_for_healthy
    wait_for_vault
    initialize_vault
    verify_deployment
    generate_instructions
    
    # Remove error trap
    trap - ERR
    
    log_success "=== Vault deployment completed successfully! ==="
    
    if [[ "$ENVIRONMENT" == "production" ]]; then
        echo ""
        log_warning "🔐 PRODUCTION DEPLOYMENT COMPLETED"
        log_warning "CRITICAL NEXT STEPS:"
        log_warning "1. Secure recovery keys immediately"
        log_warning "2. Revoke root token after setup"
        log_warning "3. Configure monitoring and backups"
        log_warning "4. Test disaster recovery procedures"
        log_warning "5. Complete security audit"
    fi
}

# Parse arguments and run main function
parse_args "$@"
main "$@"