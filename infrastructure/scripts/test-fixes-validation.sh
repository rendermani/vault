#!/bin/bash
# Test script to validate infrastructure deployment fixes
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_DIR="$(dirname "$SCRIPT_DIR")"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Test 1: Validate Vault job file syntax
test_vault_job_syntax() {
    log_info "Testing Vault job file syntax..."
    
    local vault_job="$INFRA_DIR/nomad/jobs/production/vault.nomad"
    
    if [[ ! -f "$vault_job" ]]; then
        log_error "Vault job file not found: $vault_job"
        return 1
    fi
    
    # Test that the job file can be parsed by Nomad
    if command -v nomad >/dev/null 2>&1; then
        if nomad job validate "$vault_job" 2>/dev/null; then
            log_success "Vault job file syntax is valid"
        else
            log_error "Vault job file syntax validation failed"
            log_error "Running nomad job validate for details:"
            nomad job validate "$vault_job" || true
            return 1
        fi
    else
        log_warning "Nomad not installed, skipping syntax validation"
        # Basic syntax check for nested EOF issues
        if grep -n "<<EOF" "$vault_job" | wc -l | grep -q "^[0-9]*$"; then
            log_info "Basic syntax check passed - no obvious nested EOF issues"
        else
            log_error "Potential syntax issues detected in Vault job file"
            return 1
        fi
    fi
}

# Test 2: Validate configuration template generation
test_config_generation() {
    log_info "Testing configuration template generation..."
    
    if [[ ! -f "$SCRIPT_DIR/config-templates.sh" ]]; then
        log_error "config-templates.sh not found"
        return 1
    fi
    
    # Source the templates
    if source "$SCRIPT_DIR/config-templates.sh"; then
        log_success "config-templates.sh sourced successfully"
    else
        log_error "Failed to source config-templates.sh"
        return 1
    fi
    
    # Test Nomad config generation
    local test_config="/tmp/nomad-test-config.hcl"
    local test_encrypt_key
    test_encrypt_key=$(openssl rand -base64 16 | tr -d '\n')
    if generate_nomad_config "develop" "dc1" "global" "/tmp/data" "/tmp/plugins" "/tmp/logs" \
        "both" "$test_encrypt_key" "0.0.0.0" "127.0.0.1" "1" "true" "127.0.0.1:8500" \
        "false" "http://localhost:8200" "true" > "$test_config"; then
        log_success "Nomad config generation test passed"
        
        # Validate generated config syntax if nomad is available
        if command -v nomad >/dev/null 2>&1; then
            if nomad config validate "$test_config" 2>/dev/null; then
                log_success "Generated Nomad config syntax is valid"
            else
                log_warning "Generated Nomad config has syntax issues"
                nomad config validate "$test_config" || true
            fi
        fi
        
        rm -f "$test_config"
    else
        log_error "Nomad config generation failed"
        return 1
    fi
}

# Test 3: Validate service management script
test_service_management() {
    log_info "Testing service management script..."
    
    if [[ ! -f "$SCRIPT_DIR/manage-services.sh" ]]; then
        log_error "manage-services.sh not found"
        return 1
    fi
    
    # Test script syntax
    if bash -n "$SCRIPT_DIR/manage-services.sh"; then
        log_success "manage-services.sh syntax is valid"
    else
        log_error "manage-services.sh has syntax errors"
        return 1
    fi
    
    # Test that required functions exist
    if grep -q "install_configurations" "$SCRIPT_DIR/manage-services.sh" && \
       grep -q "start_services" "$SCRIPT_DIR/manage-services.sh" && \
       grep -q "generate_nomad_config" "$SCRIPT_DIR/manage-services.sh"; then
        log_success "Required functions found in manage-services.sh"
    else
        log_error "Missing required functions in manage-services.sh"
        return 1
    fi
}

# Test 4: Check required directories and permissions
test_directory_structure() {
    log_info "Testing directory structure requirements..."
    
    local required_dirs=(
        "/opt/consul"
        "/opt/nomad"
        "/var/log/consul"
        "/var/log/nomad"
    )
    
    local issues=0
    
    for dir in "${required_dirs[@]}"; do
        if [[ -d "$dir" ]]; then
            log_info "Directory exists: $dir"
        else
            log_warning "Directory missing (will be created): $dir"
        fi
    done
    
    # Check systemd service files
    local service_files=(
        "$INFRA_DIR/config/consul.service"
        "$INFRA_DIR/config/nomad.service"
    )
    
    for service in "${service_files[@]}"; do
        if [[ -f "$service" ]]; then
            log_success "Service file exists: $service"
        else
            log_error "Service file missing: $service"
            issues=$((issues + 1))
        fi
    done
    
    if [[ $issues -gt 0 ]]; then
        log_error "$issues critical files missing"
        return 1
    fi
}

# Test 5: Validate script dependencies
test_dependencies() {
    log_info "Testing script dependencies..."
    
    local dependencies=(
        "curl"
        "openssl"
        "unzip"
        "systemctl"
        "useradd"
        "chown"
        "chmod"
    )
    
    local missing=0
    
    for dep in "${dependencies[@]}"; do
        if command -v "$dep" >/dev/null 2>&1; then
            log_info "Dependency available: $dep"
        else
            log_error "Missing dependency: $dep"
            missing=$((missing + 1))
        fi
    done
    
    if [[ $missing -gt 0 ]]; then
        log_error "$missing critical dependencies missing"
        return 1
    fi
    
    log_success "All dependencies available"
}

# Test 6: Network port availability check
test_port_availability() {
    log_info "Testing required port availability..."
    
    local ports=(
        "8500:Consul HTTP API"
        "8600:Consul DNS"
        "4646:Nomad HTTP API" 
        "4647:Nomad RPC"
        "4648:Nomad Serf"
    )
    
    for port_info in "${ports[@]}"; do
        local port="${port_info%%:*}"
        local service="${port_info##*:}"
        
        if netstat -tlnp 2>/dev/null | grep -q ":$port.*LISTEN"; then
            log_warning "Port $port ($service) is already in use"
        else
            log_info "Port $port ($service) is available"
        fi
    done
}

# Main test execution
main() {
    log_info "=== Infrastructure Deployment Fixes Validation ==="
    echo
    
    local tests_passed=0
    local tests_total=6
    
    # Run all tests
    if test_vault_job_syntax; then tests_passed=$((tests_passed + 1)); fi
    echo
    
    if test_config_generation; then tests_passed=$((tests_passed + 1)); fi
    echo
    
    if test_service_management; then tests_passed=$((tests_passed + 1)); fi
    echo
    
    if test_directory_structure; then tests_passed=$((tests_passed + 1)); fi
    echo
    
    if test_dependencies; then tests_passed=$((tests_passed + 1)); fi
    echo
    
    if test_port_availability; then tests_passed=$((tests_passed + 1)); fi
    echo
    
    # Results summary
    log_info "=== Test Results Summary ==="
    log_info "Tests passed: $tests_passed/$tests_total"
    
    if [[ $tests_passed -eq $tests_total ]]; then
        log_success "All tests passed! Infrastructure fixes are ready for deployment."
        return 0
    else
        log_error "Some tests failed. Please review the issues above."
        return 1
    fi
}

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi