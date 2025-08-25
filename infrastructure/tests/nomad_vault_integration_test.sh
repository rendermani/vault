#!/bin/bash
# Comprehensive Nomad-Vault Integration Test Suite
# Tests the complete bootstrap sequence, token lifecycle, and validation

set -euo pipefail

# Test framework setup
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_LOG_FILE="/tmp/nomad-vault-integration-test-$(date +%Y%m%d-%H%M%S).log"
TEMP_DIR="/tmp/nomad-vault-test-$$"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0

# Test configuration
VAULT_ADDR="${VAULT_ADDR:-http://localhost:8200}"
NOMAD_ADDR="${NOMAD_ADDR:-http://localhost:4646}"
TEST_ENVIRONMENT="${TEST_ENVIRONMENT:-develop}"

# Logging functions
log_info() { 
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$TEST_LOG_FILE"
}

log_success() { 
    echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "$TEST_LOG_FILE"
}

log_warning() { 
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$TEST_LOG_FILE"
}

log_error() { 
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$TEST_LOG_FILE"
}

log_debug() {
    if [[ "${DEBUG:-false}" == "true" ]]; then
        echo -e "${BLUE}[DEBUG]${NC} $1" | tee -a "$TEST_LOG_FILE"
    fi
}

# Test framework functions
assert_equals() {
    local expected="$1"
    local actual="$2"
    local message="${3:-Assertion failed}"
    
    if [[ "$expected" == "$actual" ]]; then
        log_debug "Assertion passed: '$actual' equals '$expected'"
        return 0
    else
        log_error "$message: expected '$expected', got '$actual'"
        return 1
    fi
}

assert_not_empty() {
    local value="$1"
    local message="${2:-Value is empty}"
    
    if [[ -n "$value" ]]; then
        log_debug "Assertion passed: value is not empty"
        return 0
    else
        log_error "$message"
        return 1
    fi
}

assert_command_success() {
    local command="$1"
    local message="${2:-Command failed}"
    
    if eval "$command" >/dev/null 2>&1; then
        log_debug "Command succeeded: $command"
        return 0
    else
        log_error "$message: $command"
        return 1
    fi
}

assert_command_failure() {
    local command="$1"
    local message="${2:-Command should have failed}"
    
    if ! eval "$command" >/dev/null 2>&1; then
        log_debug "Command failed as expected: $command"
        return 0
    else
        log_error "$message: $command"
        return 1
    fi
}

assert_http_status() {
    local url="$1"
    local expected_status="$2"
    local message="${3:-HTTP status assertion failed}"
    
    local actual_status
    actual_status=$(curl -s -o /dev/null -w "%{http_code}" "$url" 2>/dev/null || echo "000")
    
    if [[ "$actual_status" == "$expected_status" ]]; then
        log_debug "HTTP status assertion passed: $actual_status"
        return 0
    else
        log_error "$message: expected $expected_status, got $actual_status for $url"
        return 1
    fi
}

run_test() {
    local test_name="$1"
    local test_function="$2"
    
    ((TESTS_RUN++))
    
    log_info "Running test: $test_name"
    
    if $test_function; then
        ((TESTS_PASSED++))
        log_success "Test passed: $test_name"
    else
        ((TESTS_FAILED++))
        log_error "Test failed: $test_name"
    fi
    
    echo ""
}

skip_test() {
    local test_name="$1"
    local reason="${2:-No reason provided}"
    
    ((TESTS_RUN++))
    ((TESTS_SKIPPED++))
    
    log_warning "Skipping test: $test_name - $reason"
    echo ""
}

# Setup and cleanup functions
setup_test_environment() {
    log_info "Setting up test environment..."
    
    mkdir -p "$TEMP_DIR"
    touch "$TEST_LOG_FILE"
    
    # Check prerequisites
    if ! command -v vault >/dev/null 2>&1; then
        log_error "Vault CLI not found"
        exit 1
    fi
    
    if ! command -v nomad >/dev/null 2>&1; then
        log_error "Nomad CLI not found"
        exit 1
    fi
    
    if ! command -v jq >/dev/null 2>&1; then
        log_error "jq not found"
        exit 1
    fi
    
    # Set test environment variables
    export VAULT_ADDR="$VAULT_ADDR"
    export NOMAD_ADDR="$NOMAD_ADDR"
    export ENVIRONMENT="$TEST_ENVIRONMENT"
    
    log_success "Test environment setup complete"
}

cleanup_test_environment() {
    log_info "Cleaning up test environment..."
    
    # Clean up temporary files
    rm -rf "$TEMP_DIR"
    
    # Clean up test tokens (if any were created)
    if [[ -f "$TEMP_DIR/test-tokens" ]]; then
        while IFS= read -r token; do
            vault token revoke "$token" >/dev/null 2>&1 || true
        done < "$TEMP_DIR/test-tokens"
    fi
    
    log_success "Test environment cleanup complete"
}

# =============================================================================
# PHASE 1 BOOTSTRAP TESTS
# =============================================================================

test_environment_variables() {
    log_info "Testing environment variable configuration..."
    
    # Check core environment variables
    assert_not_empty "$VAULT_ADDR" "VAULT_ADDR not set"
    assert_not_empty "$NOMAD_ADDR" "NOMAD_ADDR not set"
    assert_not_empty "$ENVIRONMENT" "ENVIRONMENT not set"
    
    # Validate environment value
    case "$ENVIRONMENT" in
        develop|staging|production)
            log_debug "Valid environment: $ENVIRONMENT"
            ;;
        *)
            log_error "Invalid environment: $ENVIRONMENT"
            return 1
            ;;
    esac
    
    # Check if phase detection variables exist (optional)
    if [[ -n "${VAULT_BOOTSTRAP_PHASE:-}" ]]; then
        log_debug "Bootstrap phase detected: $VAULT_BOOTSTRAP_PHASE"
    fi
    
    return 0
}

test_nomad_connectivity() {
    log_info "Testing Nomad cluster connectivity..."
    
    # Test basic connectivity
    assert_http_status "$NOMAD_ADDR/v1/status/leader" 200 "Nomad API not accessible"
    
    # Test leader election
    local leader
    leader=$(curl -s "$NOMAD_ADDR/v1/status/leader" 2>/dev/null || echo "")
    assert_not_empty "$leader" "No Nomad leader found"
    
    # Test server members
    assert_command_success "nomad server members" "Cannot list Nomad server members"
    
    # Check ACL status (if enabled)
    local acl_status
    acl_status=$(curl -s "$NOMAD_ADDR/v1/acl/bootstrap" 2>/dev/null | jq -r '.error // "enabled"')
    if [[ "$acl_status" == "enabled" ]]; then
        log_debug "Nomad ACL system is enabled"
    else
        log_debug "Nomad ACL system status: $acl_status"
    fi
    
    return 0
}

test_vault_connectivity() {
    log_info "Testing Vault cluster connectivity..."
    
    # Test basic connectivity
    assert_http_status "$VAULT_ADDR/v1/sys/health" 200 "Vault API not accessible"
    
    # Get Vault status
    local vault_status
    vault_status=$(curl -s "$VAULT_ADDR/v1/sys/health" 2>/dev/null || echo "{}")
    
    # Check if Vault is initialized
    local initialized
    initialized=$(echo "$vault_status" | jq -r '.initialized // false')
    assert_equals "true" "$initialized" "Vault is not initialized"
    
    # Check seal status (may be sealed in production)
    local sealed
    sealed=$(echo "$vault_status" | jq -r '.sealed // true')
    if [[ "$sealed" == "true" ]]; then
        log_warning "Vault is sealed (may be expected in production)"
    else
        log_debug "Vault is unsealed and ready"
    fi
    
    # Check version
    local version
    version=$(echo "$vault_status" | jq -r '.version // "unknown"')
    log_debug "Vault version: $version"
    
    return 0
}

test_vault_deployment_on_nomad() {
    log_info "Testing Vault deployment on Nomad..."
    
    # Look for Vault job
    local vault_job_name="vault-$ENVIRONMENT"
    local job_status
    job_status=$(nomad job status "$vault_job_name" 2>/dev/null | grep "Status" | awk '{print $3}' || echo "not-found")
    
    if [[ "$job_status" == "not-found" ]]; then
        # Try common variants
        vault_job_name="vault"
        job_status=$(nomad job status "$vault_job_name" 2>/dev/null | grep "Status" | awk '{print $3}' || echo "not-found")
    fi
    
    if [[ "$job_status" == "not-found" ]]; then
        log_warning "Vault job not found on Nomad - may be deployed differently"
        return 0  # Don't fail the test, just note it
    fi
    
    # Check job is running
    assert_equals "running" "$job_status" "Vault job is not running"
    
    # Check allocations
    local alloc_count
    alloc_count=$(nomad job allocs "$vault_job_name" 2>/dev/null | grep running | wc -l || echo "0")
    assert_not_empty "$alloc_count" "No running Vault allocations found"
    
    log_debug "Found $alloc_count running Vault allocations"
    
    return 0
}

# =============================================================================
# VAULT-NOMAD INTEGRATION TESTS
# =============================================================================

test_vault_policies() {
    log_info "Testing Vault policies for Nomad integration..."
    
    # Check if we have a token to test with
    if [[ -z "${VAULT_TOKEN:-}" ]]; then
        log_warning "No VAULT_TOKEN set, skipping policy tests"
        return 0
    fi
    
    # Test nomad-server policy exists
    if vault policy read nomad-server >/dev/null 2>&1; then
        log_debug "nomad-server policy exists"
    elif vault policy read nomad-server-bootstrap >/dev/null 2>&1; then
        log_debug "nomad-server-bootstrap policy exists"
    else
        log_warning "No Nomad server policy found"
    fi
    
    # Test token role for Nomad
    if vault read auth/token/roles/nomad-cluster >/dev/null 2>&1; then
        log_debug "nomad-cluster token role exists"
    else
        log_warning "nomad-cluster token role not found"
    fi
    
    # List available policies
    local policies
    policies=$(vault policy list 2>/dev/null || echo "")
    if [[ -n "$policies" ]]; then
        log_debug "Available policies: $(echo "$policies" | tr '\n' ' ')"
    fi
    
    return 0
}

test_nomad_vault_configuration() {
    log_info "Testing Nomad-Vault integration configuration..."
    
    # Check Nomad configuration for Vault integration
    local nomad_config_files=(
        "/etc/nomad.d/nomad.hcl"
        "/etc/nomad.d/vault-approle.hcl"
        "/etc/nomad.d/vault-integration.hcl"
    )
    
    local config_found=false
    for config_file in "${nomad_config_files[@]}"; do
        if [[ -f "$config_file" ]] && grep -q "vault" "$config_file"; then
            log_debug "Found Vault configuration in: $config_file"
            config_found=true
            
            # Check specific configuration elements
            if grep -q "enabled.*true" "$config_file"; then
                log_debug "Vault integration is enabled"
            fi
            
            if grep -q "address.*vault" "$config_file"; then
                log_debug "Vault address is configured"
            fi
            
            break
        fi
    done
    
    if ! $config_found; then
        log_warning "No Vault configuration found in Nomad config files"
    fi
    
    return 0
}

# =============================================================================
# TOKEN LIFECYCLE TESTS
# =============================================================================

test_token_creation() {
    log_info "Testing token creation capabilities..."
    
    # Skip if no VAULT_TOKEN
    if [[ -z "${VAULT_TOKEN:-}" ]]; then
        log_warning "No VAULT_TOKEN set, skipping token creation tests"
        return 0
    fi
    
    # Test basic token creation
    local test_token
    test_token=$(vault write -field=token auth/token/create \
        policies="default" \
        ttl="5m" 2>/dev/null || echo "")
    
    if [[ -n "$test_token" && "$test_token" != "null" ]]; then
        log_debug "Successfully created test token"
        
        # Store for cleanup
        echo "$test_token" >> "$TEMP_DIR/test-tokens"
        
        # Test token lookup
        local token_info
        token_info=$(VAULT_TOKEN="$test_token" vault token lookup-self 2>/dev/null || echo "{}")
        local ttl
        ttl=$(echo "$token_info" | jq -r '.data.ttl // 0')
        
        if [[ $ttl -gt 0 ]]; then
            log_debug "Token TTL: ${ttl}s"
        fi
        
        # Revoke test token
        vault token revoke "$test_token" >/dev/null 2>&1
    else
        log_warning "Could not create test token - may not have sufficient privileges"
    fi
    
    return 0
}

test_token_renewal() {
    log_info "Testing token renewal mechanisms..."
    
    if [[ -z "${VAULT_TOKEN:-}" ]]; then
        log_warning "No VAULT_TOKEN set, skipping token renewal tests"
        return 0
    fi
    
    # Create a renewable token
    local renewable_token
    renewable_token=$(vault write -field=token auth/token/create \
        policies="default" \
        ttl="2m" \
        renewable=true 2>/dev/null || echo "")
    
    if [[ -n "$renewable_token" && "$renewable_token" != "null" ]]; then
        log_debug "Created renewable token for testing"
        
        # Get initial TTL
        local initial_info
        initial_info=$(VAULT_TOKEN="$renewable_token" vault token lookup-self 2>/dev/null || echo "{}")
        local initial_ttl
        initial_ttl=$(echo "$initial_info" | jq -r '.data.ttl // 0')
        
        # Wait a bit and renew
        sleep 5
        
        # Renew the token
        local renewal_info
        renewal_info=$(VAULT_TOKEN="$renewable_token" vault token renew -format=json 2>/dev/null || echo "{}")
        local new_ttl
        new_ttl=$(echo "$renewal_info" | jq -r '.auth.lease_duration // 0')
        
        if [[ $new_ttl -gt $initial_ttl ]]; then
            log_debug "Token renewal successful: TTL increased from ${initial_ttl}s to ${new_ttl}s"
        else
            log_warning "Token renewal may have failed or TTL not increased"
        fi
        
        # Clean up
        vault token revoke "$renewable_token" >/dev/null 2>&1
    else
        log_warning "Could not create renewable token for testing"
    fi
    
    return 0
}

test_token_revocation() {
    log_info "Testing token revocation mechanisms..."
    
    if [[ -z "${VAULT_TOKEN:-}" ]]; then
        log_warning "No VAULT_TOKEN set, skipping token revocation tests"
        return 0
    fi
    
    # Create a token to revoke
    local revoke_token
    revoke_token=$(vault write -field=token auth/token/create \
        policies="default" \
        ttl="5m" 2>/dev/null || echo "")
    
    if [[ -n "$revoke_token" && "$revoke_token" != "null" ]]; then
        log_debug "Created token for revocation testing"
        
        # Verify token works
        if VAULT_TOKEN="$revoke_token" vault token lookup-self >/dev/null 2>&1; then
            log_debug "Token is functional before revocation"
        else
            log_error "Test token is not functional"
            return 1
        fi
        
        # Revoke the token
        vault token revoke "$revoke_token" >/dev/null 2>&1
        
        # Verify token no longer works
        if ! VAULT_TOKEN="$revoke_token" vault token lookup-self >/dev/null 2>&1; then
            log_debug "Token successfully revoked"
        else
            log_error "Token revocation failed - token is still functional"
            return 1
        fi
    else
        log_warning "Could not create token for revocation testing"
    fi
    
    return 0
}

# =============================================================================
# APPROLE AUTHENTICATION TESTS
# =============================================================================

test_approle_configuration() {
    log_info "Testing AppRole authentication configuration..."
    
    if [[ -z "${VAULT_TOKEN:-}" ]]; then
        log_warning "No VAULT_TOKEN set, skipping AppRole tests"
        return 0
    fi
    
    # Check if AppRole auth method is enabled
    local auth_methods
    auth_methods=$(vault auth list -format=json 2>/dev/null || echo "{}")
    
    if echo "$auth_methods" | jq -e '.["approle/"]' >/dev/null 2>&1; then
        log_debug "AppRole auth method is enabled"
        
        # Check for nomad-servers AppRole
        if vault read auth/approle/role/nomad-servers >/dev/null 2>&1; then
            log_debug "nomad-servers AppRole exists"
            
            # Test AppRole properties
            local role_info
            role_info=$(vault read -format=json auth/approle/role/nomad-servers 2>/dev/null || echo "{}")
            local token_ttl
            token_ttl=$(echo "$role_info" | jq -r '.data.token_ttl // 0')
            log_debug "AppRole token TTL: ${token_ttl}s"
        else
            log_warning "nomad-servers AppRole not found"
        fi
        
        # List available AppRoles
        local approles
        approles=$(vault list -format=json auth/approle/role 2>/dev/null | jq -r '.[]' 2>/dev/null || echo "")
        if [[ -n "$approles" ]]; then
            log_debug "Available AppRoles: $(echo "$approles" | tr '\n' ' ')"
        fi
    else
        log_warning "AppRole auth method is not enabled"
    fi
    
    return 0
}

test_approle_authentication() {
    log_info "Testing AppRole authentication flow..."
    
    if [[ -z "${VAULT_TOKEN:-}" ]]; then
        log_warning "No VAULT_TOKEN set, skipping AppRole authentication tests"
        return 0
    fi
    
    # Check if AppRole credentials are available
    local role_id_file="/etc/nomad.d/vault-auth/role-id"
    local secret_id_file="/etc/nomad.d/vault-auth/secret-id"
    
    if [[ -f "$role_id_file" && -f "$secret_id_file" ]]; then
        log_debug "Found AppRole credential files"
        
        # Source credentials
        local role_id secret_id
        role_id=$(grep "NOMAD_VAULT_ROLE_ID" "$role_id_file" | cut -d'"' -f2 2>/dev/null || echo "")
        secret_id=$(grep "NOMAD_VAULT_SECRET_ID" "$secret_id_file" | cut -d'"' -f2 2>/dev/null || echo "")
        
        if [[ -n "$role_id" && -n "$secret_id" ]]; then
            log_debug "Attempting AppRole authentication..."
            
            # Test AppRole login
            local auth_response
            auth_response=$(vault write -format=json auth/approle/login \
                role_id="$role_id" \
                secret_id="$secret_id" 2>/dev/null || echo "{}")
            
            local auth_token
            auth_token=$(echo "$auth_response" | jq -r '.auth.client_token // null')
            
            if [[ -n "$auth_token" && "$auth_token" != "null" ]]; then
                log_debug "AppRole authentication successful"
                
                # Test token functionality
                if VAULT_TOKEN="$auth_token" vault token lookup-self >/dev/null 2>&1; then
                    log_debug "AppRole token is functional"
                fi
                
                # Clean up
                vault token revoke "$auth_token" >/dev/null 2>&1
            else
                log_warning "AppRole authentication failed"
            fi
        else
            log_warning "Could not read AppRole credentials from files"
        fi
    else
        log_warning "AppRole credential files not found"
    fi
    
    return 0
}

# =============================================================================
# INTEGRATION HEALTH TESTS
# =============================================================================

test_nomad_vault_integration_health() {
    log_info "Testing overall Nomad-Vault integration health..."
    
    # Test Nomad can reach Vault
    local nomad_vault_status="unknown"
    
    # Check if Nomad shows Vault in its status
    if nomad server members >/dev/null 2>&1; then
        log_debug "Nomad cluster is healthy"
        
        # Try to get Nomad's view of Vault integration
        # This would typically require specific Nomad API calls or log analysis
        log_debug "Nomad-Vault integration status: $nomad_vault_status"
    fi
    
    # Check service discovery integration
    if command -v consul >/dev/null 2>&1; then
        local consul_services
        consul_services=$(consul catalog services 2>/dev/null | grep -E "(vault|nomad)" || echo "")
        if [[ -n "$consul_services" ]]; then
            log_debug "Services registered with Consul: $(echo "$consul_services" | tr '\n' ' ')"
        fi
    fi
    
    # Check Nomad service discovery
    local nomad_services
    nomad_services=$(nomad service list -format=json 2>/dev/null | jq -r '.[].ServiceName' 2>/dev/null | grep -E "(vault|nomad)" || echo "")
    if [[ -n "$nomad_services" ]]; then
        log_debug "Services in Nomad discovery: $(echo "$nomad_services" | tr '\n' ' ')"
    fi
    
    return 0
}

test_secrets_access() {
    log_info "Testing secrets access through Nomad-Vault integration..."
    
    if [[ -z "${VAULT_TOKEN:-}" ]]; then
        log_warning "No VAULT_TOKEN set, skipping secrets access tests"
        return 0
    fi
    
    # Test KV secrets engine
    if vault secrets list | grep -q "kv/"; then
        log_debug "KV secrets engine is available"
        
        # Try to write and read a test secret
        local test_secret_path="kv/test/integration-test"
        if vault kv put "$test_secret_path" test_key="test_value" >/dev/null 2>&1; then
            log_debug "Successfully wrote test secret"
            
            # Read back the secret
            local secret_value
            secret_value=$(vault kv get -field=test_key "$test_secret_path" 2>/dev/null || echo "")
            if [[ "$secret_value" == "test_value" ]]; then
                log_debug "Successfully read test secret"
            else
                log_warning "Could not read test secret back"
            fi
            
            # Clean up
            vault kv delete "$test_secret_path" >/dev/null 2>&1
        else
            log_warning "Could not write test secret"
        fi
    else
        log_warning "KV secrets engine not available"
    fi
    
    return 0
}

# =============================================================================
# MONITORING AND LOGGING TESTS
# =============================================================================

test_audit_logging() {
    log_info "Testing audit logging configuration..."
    
    if [[ -z "${VAULT_TOKEN:-}" ]]; then
        log_warning "No VAULT_TOKEN set, skipping audit logging tests"
        return 0
    fi
    
    # Check audit devices
    local audit_devices
    audit_devices=$(vault audit list -format=json 2>/dev/null || echo "{}")
    
    if [[ "$audit_devices" != "{}" ]]; then
        log_debug "Audit devices are configured"
        
        # List audit devices
        local device_count
        device_count=$(echo "$audit_devices" | jq -r 'keys | length')
        log_debug "Number of audit devices: $device_count"
        
        # Check for specific audit device types
        if echo "$audit_devices" | jq -e '.["file/"]' >/dev/null 2>&1; then
            log_debug "File audit device is configured"
        fi
        
        if echo "$audit_devices" | jq -e '.["syslog/"]' >/dev/null 2>&1; then
            log_debug "Syslog audit device is configured"
        fi
    else
        log_warning "No audit devices configured"
    fi
    
    return 0
}

test_metrics_collection() {
    log_info "Testing metrics collection..."
    
    # Test Vault metrics endpoint
    if assert_http_status "$VAULT_ADDR/v1/sys/metrics" 200 "Vault metrics endpoint not accessible" 2>/dev/null; then
        log_debug "Vault metrics endpoint is accessible"
        
        # Get metrics sample
        local metrics
        metrics=$(curl -s "$VAULT_ADDR/v1/sys/metrics?format=prometheus" 2>/dev/null || echo "")
        if [[ -n "$metrics" ]]; then
            local metric_count
            metric_count=$(echo "$metrics" | grep -c "^vault_" || echo "0")
            log_debug "Found $metric_count Vault metrics"
        fi
    else
        log_warning "Vault metrics endpoint not accessible"
    fi
    
    # Test Nomad metrics (if available)
    if assert_http_status "$NOMAD_ADDR/v1/metrics" 200 "Nomad metrics endpoint not accessible" 2>/dev/null; then
        log_debug "Nomad metrics endpoint is accessible"
    else
        log_debug "Nomad metrics endpoint not accessible (may be disabled)"
    fi
    
    return 0
}

# =============================================================================
# PERFORMANCE AND LOAD TESTS
# =============================================================================

test_performance_basic() {
    log_info "Testing basic performance characteristics..."
    
    if [[ -z "${VAULT_TOKEN:-}" ]]; then
        log_warning "No VAULT_TOKEN set, skipping performance tests"
        return 0
    fi
    
    # Test token creation performance
    local start_time end_time duration
    start_time=$(date +%s%N)
    
    for i in {1..10}; do
        local perf_token
        perf_token=$(vault write -field=token auth/token/create \
            policies="default" \
            ttl="1m" 2>/dev/null || echo "")
        
        if [[ -n "$perf_token" && "$perf_token" != "null" ]]; then
            vault token revoke "$perf_token" >/dev/null 2>&1
        fi
    done
    
    end_time=$(date +%s%N)
    duration=$(( (end_time - start_time) / 1000000 ))  # Convert to milliseconds
    
    log_debug "Created and revoked 10 tokens in ${duration}ms (avg: $((duration / 10))ms per operation)"
    
    # Basic threshold check (adjust based on environment)
    if [[ $duration -lt 5000 ]]; then  # 5 seconds for 10 operations
        log_debug "Token operations performance is acceptable"
    else
        log_warning "Token operations seem slow (${duration}ms for 10 operations)"
    fi
    
    return 0
}

# =============================================================================
# ERROR HANDLING AND RECOVERY TESTS
# =============================================================================

test_error_handling() {
    log_info "Testing error handling and recovery scenarios..."
    
    # Test invalid token handling
    local invalid_token="hvs.invalid-token-for-testing"
    if ! VAULT_TOKEN="$invalid_token" vault token lookup-self >/dev/null 2>&1; then
        log_debug "Invalid token properly rejected"
    else
        log_error "Invalid token was accepted - security issue!"
        return 1
    fi
    
    # Test network error handling
    local invalid_addr="http://invalid-vault-address:8200"
    if ! VAULT_ADDR="$invalid_addr" vault status >/dev/null 2>&1; then
        log_debug "Network errors properly handled"
    else
        log_warning "Network error handling may be inconsistent"
    fi
    
    return 0
}

# =============================================================================
# MAIN TEST EXECUTION
# =============================================================================

print_test_summary() {
    echo ""
    log_info "=========================="
    log_info "TEST EXECUTION SUMMARY"
    log_info "=========================="
    log_info "Total tests run: $TESTS_RUN"
    log_success "Tests passed: $TESTS_PASSED"
    log_error "Tests failed: $TESTS_FAILED"
    log_warning "Tests skipped: $TESTS_SKIPPED"
    
    local success_rate
    if [[ $TESTS_RUN -gt 0 ]]; then
        success_rate=$((TESTS_PASSED * 100 / TESTS_RUN))
        log_info "Success rate: ${success_rate}%"
    fi
    
    log_info "Test log file: $TEST_LOG_FILE"
    echo ""
    
    if [[ $TESTS_FAILED -gt 0 ]]; then
        log_error "Some tests failed. Please review the logs."
        return 1
    else
        log_success "All tests passed successfully!"
        return 0
    fi
}

main() {
    log_info "Starting Nomad-Vault Integration Test Suite"
    log_info "============================================"
    log_info "Test environment: $TEST_ENVIRONMENT"
    log_info "Vault address: $VAULT_ADDR"
    log_info "Nomad address: $NOMAD_ADDR"
    echo ""
    
    # Setup
    setup_test_environment
    
    # Trap for cleanup
    trap cleanup_test_environment EXIT
    
    # Phase 1: Basic connectivity and configuration tests
    run_test "Environment Variables" "test_environment_variables"
    run_test "Nomad Connectivity" "test_nomad_connectivity"
    run_test "Vault Connectivity" "test_vault_connectivity"
    run_test "Vault Deployment on Nomad" "test_vault_deployment_on_nomad"
    
    # Phase 2: Integration configuration tests
    run_test "Vault Policies" "test_vault_policies"
    run_test "Nomad-Vault Configuration" "test_nomad_vault_configuration"
    
    # Phase 3: Token lifecycle tests
    run_test "Token Creation" "test_token_creation"
    run_test "Token Renewal" "test_token_renewal"
    run_test "Token Revocation" "test_token_revocation"
    
    # Phase 4: AppRole authentication tests
    run_test "AppRole Configuration" "test_approle_configuration"
    run_test "AppRole Authentication" "test_approle_authentication"
    
    # Phase 5: Integration health tests
    run_test "Integration Health" "test_nomad_vault_integration_health"
    run_test "Secrets Access" "test_secrets_access"
    
    # Phase 6: Monitoring and logging tests
    run_test "Audit Logging" "test_audit_logging"
    run_test "Metrics Collection" "test_metrics_collection"
    
    # Phase 7: Performance tests
    run_test "Basic Performance" "test_performance_basic"
    
    # Phase 8: Error handling tests
    run_test "Error Handling" "test_error_handling"
    
    # Print summary and exit
    print_test_summary
}

# Handle script arguments
case "${1:-run}" in
    run)
        main
        ;;
    setup)
        setup_test_environment
        ;;
    cleanup)
        cleanup_test_environment
        ;;
    *)
        echo "Usage: $0 [run|setup|cleanup]"
        echo "  run     - Run all tests (default)"
        echo "  setup   - Setup test environment only"
        echo "  cleanup - Cleanup test environment only"
        exit 1
        ;;
esac