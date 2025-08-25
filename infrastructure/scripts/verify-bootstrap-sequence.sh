#!/bin/bash

# Verification script to check if the bootstrap sequence will work correctly
# This performs dry-run checks without actually deploying anything

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_DIR="$(dirname "$SCRIPT_DIR")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
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

# Check if required files exist
check_file_structure() {
    log_header "CHECKING FILE STRUCTURE"
    
    local files_ok=true
    
    # Required scripts
    local required_files=(
        "$SCRIPT_DIR/config-templates.sh"
        "$SCRIPT_DIR/manage-services.sh"
        "$SCRIPT_DIR/unified-bootstrap-systemd.sh"
        "$INFRA_DIR/config/nomad.service"
        "$INFRA_DIR/config/consul.service"
        "$INFRA_DIR/config/nomad.hcl"
    )
    
    for file in "${required_files[@]}"; do
        if [[ -f "$file" ]]; then
            log_success "✅ Found: $file"
        else
            log_error "❌ Missing: $file"
            files_ok=false
        fi
    done
    
    if [[ "$files_ok" == "true" ]]; then
        log_success "All required files found"
    else
        log_error "Some required files are missing"
        return 1
    fi
}

# Check static Nomad configuration
check_static_config() {
    log_header "CHECKING STATIC NOMAD CONFIGURATION"
    
    if [[ -f "$INFRA_DIR/config/nomad.hcl" ]]; then
        log_info "Checking static Nomad configuration..."
        
        if grep -A5 -B5 "vault {" "$INFRA_DIR/config/nomad.hcl" | grep -q "enabled = false"; then
            log_success "✅ Static config has Vault properly disabled"
        else
            log_error "❌ Static config does not have Vault disabled"
            log_error "Configuration content:"
            grep -A10 -B2 "vault {" "$INFRA_DIR/config/nomad.hcl" || true
            return 1
        fi
    else
        log_warning "Static Nomad configuration not found (will be generated dynamically)"
    fi
}

# Simulate bootstrap environment
simulate_bootstrap_phase() {
    log_header "SIMULATING BOOTSTRAP PHASE ENVIRONMENT"
    
    # Set bootstrap environment variables
    export VAULT_ENABLED="false"
    export NOMAD_VAULT_BOOTSTRAP_PHASE="true"
    export BOOTSTRAP_PHASE="true"
    
    log_info "Bootstrap environment variables set:"
    log_info "  VAULT_ENABLED=$VAULT_ENABLED"
    log_info "  NOMAD_VAULT_BOOTSTRAP_PHASE=$NOMAD_VAULT_BOOTSTRAP_PHASE"
    log_info "  BOOTSTRAP_PHASE=$BOOTSTRAP_PHASE"
    
    # Source configuration templates
    if [[ -f "$SCRIPT_DIR/config-templates.sh" ]]; then
        source "$SCRIPT_DIR/config-templates.sh"
        log_success "Configuration templates loaded"
    else
        log_error "Configuration templates not found"
        return 1
    fi
    
    # Generate test configuration
    local temp_config=$(mktemp)
    log_info "Generating bootstrap phase configuration..."
    
    generate_nomad_config "develop" "dc1" "global" "/opt/nomad/data" "/opt/nomad/plugins" "/var/log/nomad" \
        "both" "test-encrypt-key" "0.0.0.0" "127.0.0.1" "1" "true" "127.0.0.1:8500" \
        "$VAULT_ENABLED" "http://localhost:8200" "$NOMAD_VAULT_BOOTSTRAP_PHASE" > "$temp_config"
    
    # Verify bootstrap configuration
    if grep -A5 -B5 "vault {" "$temp_config" | grep -q "enabled = false"; then
        log_success "✅ Bootstrap configuration correctly disables Vault"
    else
        log_error "❌ Bootstrap configuration does not disable Vault"
        log_error "Generated configuration:"
        grep -A10 -B2 "vault {" "$temp_config" || true
        rm "$temp_config"
        return 1
    fi
    
    rm "$temp_config"
}

# Simulate Phase 2 environment
simulate_phase2_environment() {
    log_header "SIMULATING PHASE 2 ENVIRONMENT"
    
    # Set Phase 2 environment variables
    export VAULT_ENABLED="true"
    export NOMAD_VAULT_BOOTSTRAP_PHASE="false"
    export BOOTSTRAP_PHASE="false"
    
    log_info "Phase 2 environment variables set:"
    log_info "  VAULT_ENABLED=$VAULT_ENABLED"
    log_info "  NOMAD_VAULT_BOOTSTRAP_PHASE=$NOMAD_VAULT_BOOTSTRAP_PHASE"
    log_info "  BOOTSTRAP_PHASE=$BOOTSTRAP_PHASE"
    
    # Generate test configuration
    local temp_config=$(mktemp)
    log_info "Generating Phase 2 configuration..."
    
    generate_nomad_config "develop" "dc1" "global" "/opt/nomad/data" "/opt/nomad/plugins" "/var/log/nomad" \
        "both" "test-encrypt-key" "0.0.0.0" "127.0.0.1" "1" "true" "127.0.0.1:8500" \
        "$VAULT_ENABLED" "http://localhost:8200" "$NOMAD_VAULT_BOOTSTRAP_PHASE" > "$temp_config"
    
    # Verify Phase 2 configuration
    if grep -A5 -B5 "vault {" "$temp_config" | grep -q "enabled = true"; then
        log_success "✅ Phase 2 configuration correctly enables Vault"
    else
        log_error "❌ Phase 2 configuration does not enable Vault"
        log_error "Generated configuration:"
        grep -A10 -B2 "vault {" "$temp_config" || true
        rm "$temp_config"
        return 1
    fi
    
    rm "$temp_config"
}

# Check service management script
check_service_management() {
    log_header "CHECKING SERVICE MANAGEMENT SCRIPT"
    
    if [[ -x "$SCRIPT_DIR/manage-services.sh" ]]; then
        log_success "✅ Service management script is executable"
        
        # Check if it handles bootstrap environment variables
        if grep -q "BOOTSTRAP_PHASE" "$SCRIPT_DIR/manage-services.sh"; then
            log_success "✅ Service management script handles bootstrap phase"
        else
            log_error "❌ Service management script does not handle bootstrap phase"
            return 1
        fi
    else
        log_error "❌ Service management script is not executable or not found"
        return 1
    fi
}

# Check bootstrap script
check_bootstrap_script() {
    log_header "CHECKING BOOTSTRAP SCRIPT"
    
    if [[ -x "$SCRIPT_DIR/unified-bootstrap-systemd.sh" ]]; then
        log_success "✅ Bootstrap script is executable"
        
        # Check if it sets bootstrap environment variables
        if grep -q "export BOOTSTRAP_PHASE" "$SCRIPT_DIR/unified-bootstrap-systemd.sh"; then
            log_success "✅ Bootstrap script sets bootstrap phase variables"
        else
            log_error "❌ Bootstrap script does not set bootstrap phase variables"
            return 1
        fi
        
        # Check if it validates configuration
        if grep -q "Validating Nomad configuration for bootstrap phase" "$SCRIPT_DIR/unified-bootstrap-systemd.sh"; then
            log_success "✅ Bootstrap script includes configuration validation"
        else
            log_warning "⚠️ Bootstrap script may not include configuration validation"
        fi
    else
        log_error "❌ Bootstrap script is not executable or not found"
        return 1
    fi
}

# Test reconfiguration function
test_reconfiguration() {
    log_header "TESTING RECONFIGURATION FUNCTION"
    
    # Check if reconfigure function exists
    if grep -q "reconfigure_nomad_with_vault" "$SCRIPT_DIR/config-templates.sh"; then
        log_success "✅ Reconfiguration function found"
        
        # Check if it validates the new configuration
        if grep -q "enabled = true" "$SCRIPT_DIR/config-templates.sh"; then
            log_success "✅ Reconfiguration function includes validation"
        else
            log_warning "⚠️ Reconfiguration function may not include proper validation"
        fi
    else
        log_error "❌ Reconfiguration function not found"
        return 1
    fi
}

# Main verification
main() {
    log_header "BOOTSTRAP SEQUENCE VERIFICATION"
    echo ""
    
    local checks_passed=0
    local checks_failed=0
    
    # Run all checks
    local checks=(
        "check_file_structure"
        "check_static_config"
        "simulate_bootstrap_phase"
        "simulate_phase2_environment"
        "check_service_management"
        "check_bootstrap_script"
        "test_reconfiguration"
    )
    
    for check in "${checks[@]}"; do
        if $check; then
            checks_passed=$((checks_passed + 1))
        else
            checks_failed=$((checks_failed + 1))
        fi
        echo ""
    done
    
    # Summary
    log_header "VERIFICATION SUMMARY"
    echo -e "${WHITE}Checks Passed:${NC} ${GREEN}$checks_passed${NC}"
    echo -e "${WHITE}Checks Failed:${NC} ${RED}$checks_failed${NC}"
    
    if [[ $checks_failed -eq 0 ]]; then
        log_success "🎉 ALL VERIFICATION CHECKS PASSED!"
        log_success "The two-phase bootstrap implementation should work correctly."
        log_info ""
        log_info "Next steps:"
        log_info "1. Run the bootstrap script: sudo ./unified-bootstrap-systemd.sh --environment develop"
        log_info "2. Monitor for the bootstrap validation message"
        log_info "3. Verify Nomad starts without 'Vault token must be set' error"
        log_info "4. After Vault deployment, verify Phase 2 reconfiguration"
        return 0
    else
        log_error "❌ Some verification checks failed."
        log_error "Please review and fix the issues before running the bootstrap."
        return 1
    fi
}

# Execute main function
main "$@"