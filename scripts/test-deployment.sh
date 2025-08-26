#!/bin/bash
# test-deployment.sh - Comprehensive deployment testing script
set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
LOG_FILE="/tmp/deployment-test-$(date +%Y%m%d-%H%M%S).log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case $level in
        ERROR)
            echo -e "${RED}[ERROR]${NC} $message" | tee -a "$LOG_FILE"
            ;;
        SUCCESS)
            echo -e "${GREEN}[SUCCESS]${NC} $message" | tee -a "$LOG_FILE"
            ;;
        WARNING)
            echo -e "${YELLOW}[WARNING]${NC} $message" | tee -a "$LOG_FILE"
            ;;
        INFO)
            echo -e "${BLUE}[INFO]${NC} $message" | tee -a "$LOG_FILE"
            ;;
        *)
            echo "[$timestamp] $level $message" >> "$LOG_FILE"
            ;;
    esac
}

# Usage function
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Test the one-button deployment functionality

Options:
    -e, --environment ENV    Target environment (develop|staging|production)
    -t, --test-type TYPE     Test type (syntax|connectivity|deployment|full)
    -d, --dry-run           Perform dry run only
    -s, --skip-secrets      Skip secrets validation (for CI)
    -v, --verbose           Enable verbose output
    -h, --help              Show this help message

Examples:
    $0 -e develop -t syntax          # Test syntax only
    $0 -e develop -t connectivity    # Test connectivity only  
    $0 -e develop -t deployment -d   # Test deployment (dry run)
    $0 -e develop -t full           # Full deployment test

Test Types:
    syntax       - Validate YAML/HCL syntax
    connectivity - Test server and service connectivity
    deployment   - Execute deployment workflow
    full         - All of the above
EOF
}

# Default values
ENVIRONMENT="develop"
TEST_TYPE="syntax"
DRY_RUN="false"
SKIP_SECRETS="false"
VERBOSE="false"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -e|--environment)
            ENVIRONMENT="$2"
            shift 2
            ;;
        -t|--test-type)
            TEST_TYPE="$2"
            shift 2
            ;;
        -d|--dry-run)
            DRY_RUN="true"
            shift
            ;;
        -s|--skip-secrets)
            SKIP_SECRETS="true"
            shift
            ;;
        -v|--verbose)
            VERBOSE="true"
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            log ERROR "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Validate environment
if [[ ! "$ENVIRONMENT" =~ ^(develop|staging|production)$ ]]; then
    log ERROR "Invalid environment: $ENVIRONMENT"
    exit 1
fi

# Validate test type
if [[ ! "$TEST_TYPE" =~ ^(syntax|connectivity|deployment|full)$ ]]; then
    log ERROR "Invalid test type: $TEST_TYPE"
    exit 1
fi

log INFO "Starting deployment test"
log INFO "Environment: $ENVIRONMENT"
log INFO "Test Type: $TEST_TYPE"
log INFO "Dry Run: $DRY_RUN"
log INFO "Log File: $LOG_FILE"

# Test 1: Syntax Validation
test_syntax() {
    log INFO "=== Testing Syntax Validation ==="
    
    local errors=0
    
    # Test GitHub Actions workflows
    log INFO "Validating GitHub Actions workflows..."
    for workflow in "$PROJECT_ROOT"/.github/workflows/*.yml; do
        if [[ -f "$workflow" ]]; then
            if command -v yamllint >/dev/null 2>&1; then
                if yamllint "$workflow" >/dev/null 2>&1; then
                    log SUCCESS "✓ $(basename "$workflow")"
                else
                    log ERROR "✗ $(basename "$workflow") - YAML syntax error"
                    ((errors++))
                fi
            else
                log WARNING "yamllint not available, skipping YAML validation"
            fi
        fi
    done
    
    # Test Ansible playbooks
    log INFO "Validating Ansible playbooks..."
    for playbook in "$PROJECT_ROOT"/src/ansible/playbooks/*.yml; do
        if [[ -f "$playbook" ]]; then
            if command -v ansible-playbook >/dev/null 2>&1; then
                if ansible-playbook --syntax-check "$playbook" >/dev/null 2>&1; then
                    log SUCCESS "✓ $(basename "$playbook")"
                else
                    log ERROR "✗ $(basename "$playbook") - Ansible syntax error"
                    ((errors++))
                fi
            else
                log WARNING "ansible-playbook not available, skipping Ansible validation"
            fi
        fi
    done
    
    # Test Terraform configurations
    log INFO "Validating Terraform configurations..."
    for tf_dir in "$PROJECT_ROOT"/src/terraform/environments/*; do
        if [[ -d "$tf_dir" && -f "$tf_dir/main.tf" ]]; then
            local env_name=$(basename "$tf_dir")
            if command -v terraform >/dev/null 2>&1; then
                cd "$tf_dir"
                if terraform fmt -check >/dev/null 2>&1 && terraform validate >/dev/null 2>&1; then
                    log SUCCESS "✓ Terraform ($env_name)"
                else
                    log ERROR "✗ Terraform ($env_name) - validation failed"
                    ((errors++))
                fi
                cd - >/dev/null
            else
                log WARNING "terraform not available, skipping Terraform validation"
            fi
        fi
    done
    
    if [[ $errors -eq 0 ]]; then
        log SUCCESS "All syntax validations passed"
        return 0
    else
        log ERROR "$errors syntax validation(s) failed"
        return 1
    fi
}

# Test 2: Connectivity Testing  
test_connectivity() {
    log INFO "=== Testing Connectivity ==="
    
    local errors=0
    local server="${REMOTE_SERVER:-cloudya.net}"
    local user="${REMOTE_USER:-root}"
    
    # Test SSH connectivity
    log INFO "Testing SSH connectivity to $user@$server..."
    if command -v ssh >/dev/null 2>&1; then
        if timeout 10 ssh -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=no \
           "$user@$server" 'echo "SSH connection successful"' >/dev/null 2>&1; then
            log SUCCESS "✓ SSH connectivity"
        else
            log ERROR "✗ SSH connectivity failed"
            ((errors++))
        fi
    else
        log WARNING "ssh not available, skipping SSH test"
    fi
    
    # Test HashiCorp services
    local services=(
        "Consul:8500:/v1/status/leader"
        "Nomad:4646:/v1/status/leader"
        "Vault:8200:/v1/sys/health"
    )
    
    for service_info in "${services[@]}"; do
        IFS=':' read -r service_name port endpoint <<< "$service_info"
        log INFO "Testing $service_name connectivity..."
        
        if command -v curl >/dev/null 2>&1; then
            if timeout 10 curl -s "http://$server:$port$endpoint" >/dev/null 2>&1; then
                log SUCCESS "✓ $service_name connectivity"
            else
                log WARNING "✗ $service_name not accessible (may be expected if not deployed yet)"
            fi
        else
            log WARNING "curl not available, skipping service connectivity tests"
        fi
    done
    
    # Test GitHub CLI connectivity (for deployment trigger)
    log INFO "Testing GitHub CLI connectivity..."
    if command -v gh >/dev/null 2>&1; then
        if gh api user >/dev/null 2>&1; then
            log SUCCESS "✓ GitHub CLI authentication"
        else
            log ERROR "✗ GitHub CLI not authenticated"
            ((errors++))
        fi
    else
        log WARNING "gh CLI not available, skipping GitHub connectivity test"
    fi
    
    if [[ $errors -eq 0 ]]; then
        log SUCCESS "All connectivity tests passed"
        return 0
    else
        log ERROR "$errors connectivity test(s) failed"
        return 1
    fi
}

# Test 3: Secrets Validation
test_secrets() {
    if [[ "$SKIP_SECRETS" == "true" ]]; then
        log INFO "Skipping secrets validation"
        return 0
    fi
    
    log INFO "=== Testing Secrets Configuration ==="
    
    local errors=0
    local required_secrets=("SSH_PRIVATE_KEY")
    
    # Environment-specific secrets
    case "$ENVIRONMENT" in
        staging|production)
            required_secrets+=("ANSIBLE_VAULT_PASSWORD" "CONSUL_HTTP_TOKEN")
            ;;
        develop)
            required_secrets+=("ANSIBLE_VAULT_PASSWORD")
            ;;
    esac
    
    if command -v gh >/dev/null 2>&1; then
        for secret in "${required_secrets[@]}"; do
            # Note: gh secret list doesn't show values, just names
            if gh secret list | grep -q "^$secret"; then
                log SUCCESS "✓ Secret $secret is configured"
            else
                log ERROR "✗ Secret $secret is missing"
                ((errors++))
            fi
        done
    else
        log WARNING "gh CLI not available, skipping secrets validation"
        log INFO "Manual verification required for: ${required_secrets[*]}"
    fi
    
    if [[ $errors -eq 0 ]]; then
        log SUCCESS "All required secrets are configured"
        return 0
    else
        log ERROR "$errors required secret(s) missing"
        return 1
    fi
}

# Test 4: Deployment Testing
test_deployment() {
    log INFO "=== Testing Deployment Workflow ==="
    
    local workflow_file=".github/workflows/unified-deployment-fixed.yml"
    local dry_run_arg=""
    
    if [[ "$DRY_RUN" == "true" ]]; then
        dry_run_arg="--field dry_run=true"
    fi
    
    log INFO "Triggering deployment workflow for $ENVIRONMENT environment..."
    
    if command -v gh >/dev/null 2>&1; then
        # Trigger the workflow
        local run_id
        if run_id=$(gh workflow run "$workflow_file" \
                      --field environment="$ENVIRONMENT" \
                      --field deployment_phases="all" \
                      $dry_run_arg \
                      --json url --jq '.url' 2>/dev/null); then
            log SUCCESS "✓ Workflow triggered successfully"
            log INFO "Workflow URL: $run_id"
            
            if [[ "$DRY_RUN" == "true" ]]; then
                log INFO "Dry run mode - workflow will validate but not make changes"
            fi
            
            # Wait for workflow to start
            log INFO "Waiting for workflow to start..."
            sleep 10
            
            # Monitor workflow progress (basic)
            local max_wait=300  # 5 minutes
            local wait_time=0
            
            while [[ $wait_time -lt $max_wait ]]; do
                local status
                if status=$(gh run list --limit 1 --json status --jq '.[0].status' 2>/dev/null); then
                    case "$status" in
                        "completed")
                            local conclusion
                            if conclusion=$(gh run list --limit 1 --json conclusion --jq '.[0].conclusion' 2>/dev/null); then
                                if [[ "$conclusion" == "success" ]]; then
                                    log SUCCESS "✓ Deployment workflow completed successfully"
                                    return 0
                                else
                                    log ERROR "✗ Deployment workflow failed with conclusion: $conclusion"
                                    return 1
                                fi
                            fi
                            ;;
                        "in_progress"|"queued"|"requested"|"waiting")
                            log INFO "Workflow status: $status (waiting...)"
                            sleep 30
                            ((wait_time += 30))
                            ;;
                        "failure"|"cancelled")
                            log ERROR "✗ Deployment workflow failed with status: $status"
                            return 1
                            ;;
                    esac
                else
                    log WARNING "Could not get workflow status"
                    break
                fi
            done
            
            log WARNING "Workflow monitoring timed out after ${max_wait}s"
            log INFO "Check workflow status manually: gh run list"
            return 2  # Timeout, but not necessarily failure
            
        else
            log ERROR "✗ Failed to trigger workflow"
            return 1
        fi
    else
        log ERROR "gh CLI not available, cannot trigger deployment"
        return 1
    fi
}

# Main test execution
main() {
    local overall_result=0
    
    case "$TEST_TYPE" in
        syntax)
            test_syntax || overall_result=1
            ;;
        connectivity)
            test_connectivity || overall_result=1
            ;;
        deployment)
            test_secrets || overall_result=1
            if [[ $overall_result -eq 0 ]]; then
                test_deployment || overall_result=1
            fi
            ;;
        full)
            log INFO "Running full test suite..."
            test_syntax || overall_result=1
            test_connectivity || overall_result=1
            test_secrets || overall_result=1
            if [[ $overall_result -eq 0 ]]; then
                test_deployment || overall_result=1
            fi
            ;;
    esac
    
    log INFO "=== Test Summary ==="
    if [[ $overall_result -eq 0 ]]; then
        log SUCCESS "All tests passed successfully!"
        log INFO "One-button deployment is ready for $ENVIRONMENT environment"
    else
        log ERROR "Some tests failed - review logs and fix issues before deployment"
    fi
    
    log INFO "Full test log available at: $LOG_FILE"
    return $overall_result
}

# Cleanup function
cleanup() {
    if [[ "$VERBOSE" != "true" ]]; then
        # Remove log file if not verbose and tests passed
        if [[ $? -eq 0 ]]; then
            rm -f "$LOG_FILE"
        fi
    fi
}

trap cleanup EXIT

# Run main function
main "$@"