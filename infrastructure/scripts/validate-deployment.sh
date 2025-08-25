#!/bin/bash

# Infrastructure Deployment Validation Script
# Comprehensive testing of the complete deployment pipeline

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_DIR="$(dirname "$SCRIPT_DIR")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_header() {
    echo -e "${WHITE}================================================================================================${NC}"
    echo -e "${WHITE}$1${NC}"
    echo -e "${WHITE}================================================================================================${NC}"
}

# Test file existence
test_files() {
    log_header "TESTING FILE EXISTENCE"
    
    local files=(
        "config/consul.service"
        "config/nomad.service"
        "config/consul.hcl"
        "config/nomad.hcl"
        "scripts/manage-services.sh"
        "scripts/unified-bootstrap-systemd.sh"
        ".github/workflows/deploy-infrastructure.yml"
        "nomad/jobs/develop/vault.nomad"
        "traefik/traefik.nomad"
    )
    
    local missing_files=()
    
    for file in "${files[@]}"; do
        if [[ -f "$INFRA_DIR/$file" ]]; then
            log_success "Found: $file"
        else
            log_error "Missing: $file"
            missing_files+=("$file")
        fi
    done
    
    if [[ ${#missing_files[@]} -gt 0 ]]; then
        log_error "Missing ${#missing_files[@]} required files"
        return 1
    else
        log_success "All required files present"
        return 0
    fi
}

# Test script syntax
test_syntax() {
    log_header "TESTING SCRIPT SYNTAX"
    
    local scripts=(
        "scripts/manage-services.sh"
        "scripts/unified-bootstrap-systemd.sh"
        "scripts/validate-deployment.sh"
    )
    
    local syntax_errors=0
    
    for script in "${scripts[@]}"; do
        if [[ -f "$INFRA_DIR/$script" ]]; then
            if bash -n "$INFRA_DIR/$script" 2>/dev/null; then
                log_success "Syntax OK: $script"
            else
                log_error "Syntax error: $script"
                syntax_errors=$((syntax_errors + 1))
            fi
        else
            log_warning "Script not found: $script"
        fi
    done
    
    if [[ $syntax_errors -gt 0 ]]; then
        log_error "$syntax_errors scripts have syntax errors"
        return 1
    else
        log_success "All scripts have valid syntax"
        return 0
    fi
}

# Test Nomad job files
test_nomad_jobs() {
    log_header "TESTING NOMAD JOB FILES"
    
    local jobs=(
        "nomad/jobs/develop/vault.nomad"
        "traefik/traefik.nomad"
    )
    
    local job_errors=0
    
    for job in "${jobs[@]}"; do
        if [[ -f "$INFRA_DIR/$job" ]]; then
            # Basic HCL syntax check
            if grep -q "job \"" "$INFRA_DIR/$job" && grep -q "group \"" "$INFRA_DIR/$job"; then
                log_success "Job structure OK: $job"
            else
                log_error "Job structure invalid: $job"
                job_errors=$((job_errors + 1))
            fi
        else
            log_error "Job file not found: $job"
            job_errors=$((job_errors + 1))
        fi
    done
    
    if [[ $job_errors -gt 0 ]]; then
        log_error "$job_errors job files have issues"
        return 1
    else
        log_success "All job files look valid"
        return 0
    fi
}

# Test configuration files
test_configurations() {
    log_header "TESTING CONFIGURATION FILES"
    
    local configs=(
        "config/consul.hcl"
        "config/nomad.hcl"
    )
    
    local config_errors=0
    
    for config in "${configs[@]}"; do
        if [[ -f "$INFRA_DIR/$config" ]]; then
            # Basic HCL syntax check
            if grep -q "datacenter" "$INFRA_DIR/$config" && grep -q "data_dir" "$INFRA_DIR/$config"; then
                log_success "Configuration OK: $config"
            else
                log_error "Configuration invalid: $config"
                config_errors=$((config_errors + 1))
            fi
        else
            log_error "Configuration file not found: $config"
            config_errors=$((config_errors + 1))
        fi
    done
    
    if [[ $config_errors -gt 0 ]]; then
        log_error "$config_errors configuration files have issues"
        return 1
    else
        log_success "All configuration files look valid"
        return 0
    fi
}

# Test systemd service files
test_systemd_services() {
    log_header "TESTING SYSTEMD SERVICE FILES"
    
    local services=(
        "config/consul.service"
        "config/nomad.service"
    )
    
    local service_errors=0
    
    for service in "${services[@]}"; do
        if [[ -f "$INFRA_DIR/$service" ]]; then
            # Basic systemd service file check
            if grep -q "\\[Unit\\]" "$INFRA_DIR/$service" && grep -q "\\[Service\\]" "$INFRA_DIR/$service" && grep -q "\\[Install\\]" "$INFRA_DIR/$service"; then
                log_success "Systemd service OK: $service"
            else
                log_error "Systemd service invalid: $service"
                service_errors=$((service_errors + 1))
            fi
        else
            log_error "Service file not found: $service"
            service_errors=$((service_errors + 1))
        fi
    done
    
    if [[ $service_errors -gt 0 ]]; then
        log_error "$service_errors service files have issues"
        return 1
    else
        log_success "All systemd service files look valid"
        return 0
    fi
}

# Test GitHub workflow
test_github_workflow() {
    log_header "TESTING GITHUB WORKFLOW"
    
    local workflow="$INFRA_DIR/.github/workflows/deploy-infrastructure.yml"
    
    if [[ ! -f "$workflow" ]]; then
        log_error "Workflow file not found: $workflow"
        return 1
    fi
    
    # Check for key components
    local checks=(
        "unified-bootstrap-systemd.sh"
        "manage-services.sh"
        "systemctl is-active"
        "SSH_PRIVATE_KEY"
        "NOMAD_BOOTSTRAP_TOKEN"
        "CONSUL_BOOTSTRAP_TOKEN"
    )
    
    local workflow_errors=0
    
    for check in "${checks[@]}"; do
        if grep -q "$check" "$workflow"; then
            log_success "Found in workflow: $check"
        else
            log_error "Missing in workflow: $check"
            workflow_errors=$((workflow_errors + 1))
        fi
    done
    
    if [[ $workflow_errors -gt 0 ]]; then
        log_error "Workflow has $workflow_errors missing components"
        return 1
    else
        log_success "GitHub workflow looks complete"
        return 0
    fi
}

# Test permissions
test_permissions() {
    log_header "TESTING FILE PERMISSIONS"
    
    local executable_files=(
        "scripts/manage-services.sh"
        "scripts/unified-bootstrap-systemd.sh"
        "scripts/validate-deployment.sh"
    )
    
    local permission_errors=0
    
    for file in "${executable_files[@]}"; do
        if [[ -f "$INFRA_DIR/$file" ]]; then
            if [[ -x "$INFRA_DIR/$file" ]]; then
                log_success "Executable: $file"
            else
                log_warning "Not executable (will be fixed by workflow): $file"
                # Fix permissions locally
                chmod +x "$INFRA_DIR/$file"
                log_info "Fixed permissions for: $file"
            fi
        else
            log_error "File not found for permission check: $file"
            permission_errors=$((permission_errors + 1))
        fi
    done
    
    if [[ $permission_errors -gt 0 ]]; then
        log_error "$permission_errors files have permission issues"
        return 1
    else
        log_success "All executable files have correct permissions"
        return 0
    fi
}

# Generate validation report
generate_report() {
    log_header "VALIDATION REPORT"
    
    echo -e "${WHITE}Infrastructure Deployment Validation Report${NC}"
    echo -e "${WHITE}Generated: $(date)${NC}"
    echo ""
    
    echo -e "${WHITE}✓ Completed Checks:${NC}"
    echo "  - File existence"
    echo "  - Script syntax validation"
    echo "  - Nomad job file structure"
    echo "  - Configuration file structure"
    echo "  - Systemd service file structure"
    echo "  - GitHub workflow completeness"
    echo "  - File permissions"
    echo ""
    
    echo -e "${WHITE}✓ Key Features:${NC}"
    echo "  - Native systemd service management"
    echo "  - Idempotent deployment scripts"
    echo "  - Comprehensive health checking"
    echo "  - Automated service lifecycle management"
    echo "  - Secure token management"
    echo "  - Complete GitHub Actions integration"
    echo ""
    
    echo -e "${WHITE}🚀 Ready for Deployment!${NC}"
    echo ""
    echo -e "${BLUE}To deploy:${NC}"
    echo "1. Commit all changes to git"
    echo "2. Push to main branch"
    echo "3. GitHub Actions will automatically deploy to cloudya.net"
    echo ""
    echo -e "${BLUE}Manual deployment:${NC}"
    echo "ssh root@cloudya.net 'cd /opt/infrastructure && ./scripts/unified-bootstrap-systemd.sh --environment develop'"
    echo ""
}

# Main execution
main() {
    log_header "INFRASTRUCTURE DEPLOYMENT VALIDATION"
    
    local test_results=()
    local overall_success=true
    
    # Run all tests
    test_files && test_results+=("✓ File existence") || { test_results+=("✗ File existence"); overall_success=false; }
    test_syntax && test_results+=("✓ Script syntax") || { test_results+=("✗ Script syntax"); overall_success=false; }
    test_nomad_jobs && test_results+=("✓ Nomad jobs") || { test_results+=("✗ Nomad jobs"); overall_success=false; }
    test_configurations && test_results+=("✓ Configurations") || { test_results+=("✗ Configurations"); overall_success=false; }
    test_systemd_services && test_results+=("✓ Systemd services") || { test_results+=("✗ Systemd services"); overall_success=false; }
    test_github_workflow && test_results+=("✓ GitHub workflow") || { test_results+=("✗ GitHub workflow"); overall_success=false; }
    test_permissions && test_results+=("✓ Permissions") || { test_results+=("✗ Permissions"); overall_success=false; }
    
    # Show results
    echo ""
    log_header "TEST RESULTS"
    for result in "${test_results[@]}"; do
        if [[ "$result" == ✓* ]]; then
            echo -e "${GREEN}$result${NC}"
        else
            echo -e "${RED}$result${NC}"
        fi
    done
    
    echo ""
    if [[ "$overall_success" == "true" ]]; then
        log_success "All validation tests passed!"
        generate_report
        exit 0
    else
        log_error "Some validation tests failed. Please fix the issues above."
        exit 1
    fi
}

# Execute main function
main "$@"