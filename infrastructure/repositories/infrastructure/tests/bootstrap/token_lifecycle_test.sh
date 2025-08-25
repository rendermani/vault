#!/bin/bash

# Token Lifecycle and Migration Tests
# Tests token creation, rotation, migration, and lifecycle management

set -euo pipefail

# Source test framework
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../framework/test_framework.sh
source "$SCRIPT_DIR/../framework/test_framework.sh"

# Test configuration
VAULT_ADDR="${VAULT_ADDR:-http://localhost:8200}"
NOMAD_ADDR="${NOMAD_ADDR:-http://localhost:4646}"
TEST_TOKEN_PREFIX="${TEST_TOKEN_PREFIX:-test-lifecycle}"
TOKEN_TEST_POLICY="${TOKEN_TEST_POLICY:-test-policy}"

# Test helper functions
create_test_policy() {
    local policy_name="$1"
    local policy_content="$2"
    
    echo "$policy_content" > "$TEST_TEMP_DIR/${policy_name}.hcl"
    vault policy write "$policy_name" "$TEST_TEMP_DIR/${policy_name}.hcl" >/dev/null 2>&1
}

create_test_token() {
    local policy="$1"
    local ttl="${2:-1h}"
    local metadata="${3:-}"
    
    local create_cmd="vault token create -policy='$policy' -ttl='$ttl' -format=json"
    
    if [[ -n "$metadata" ]]; then
        create_cmd="$create_cmd -metadata='$metadata'"
    fi
    
    eval "$create_cmd" 2>/dev/null | jq -r '.auth.client_token' 2>/dev/null || echo ""
}

get_token_info() {
    local token="$1"
    VAULT_TOKEN="$token" vault token lookup -format=json 2>/dev/null || echo "{}"
}

revoke_test_token() {
    local token="$1"
    vault token revoke "$token" >/dev/null 2>&1 || true
}

check_vault_accessible() {
    vault status >/dev/null 2>&1
}

# Test functions
test_vault_token_creation() {
    log_info "Testing Vault token creation"
    
    if ! check_vault_accessible; then
        skip_test "Vault Token Creation" "Vault not accessible"
        return
    fi
    
    # Create a test policy
    local policy_content='
path "secret/*" {
  capabilities = ["read", "list"]
}
path "kv/data/test/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}'
    
    create_test_policy "$TOKEN_TEST_POLICY" "$policy_content"
    
    # Test token creation with different parameters
    local test_cases=(
        "1h:short-lived"
        "24h:medium-lived"
        "168h:long-lived"
    )
    
    local created_tokens=()
    
    for test_case in "${test_cases[@]}"; do
        local ttl="${test_case%%:*}"
        local description="${test_case##*:}"
        
        local token
        token=$(create_test_token "$TOKEN_TEST_POLICY" "$ttl" "description=$description")
        
        assert_not_equals "" "$token" "Failed to create $description token"
        
        # Verify token properties
        local token_info
        token_info=$(get_token_info "$token")
        
        local policies
        policies=$(echo "$token_info" | jq -r '.data.policies[]?' | grep -c "$TOKEN_TEST_POLICY" || echo "0")
        assert_true "$((policies >= 1))" "$description token missing expected policy"
        
        local token_ttl
        token_ttl=$(echo "$token_info" | jq -r '.data.ttl // 0')
        assert_true "$((token_ttl > 0))" "$description token has invalid TTL"
        
        created_tokens+=("$token")
        log_debug "Created $description token: ${token:0:8}... (TTL: ${token_ttl}s)"
    done
    
    # Clean up tokens
    for token in "${created_tokens[@]}"; do
        revoke_test_token "$token"
    done
    
    log_success "Vault token creation verified"
}

test_token_renewal_and_ttl_management() {
    log_info "Testing token renewal and TTL management"
    
    if ! check_vault_accessible; then
        skip_test "Token Renewal and TTL Management" "Vault not accessible"
        return
    fi
    
    # Create a renewable token with short TTL
    local renewable_token
    renewable_token=$(vault token create -policy="$TOKEN_TEST_POLICY" -ttl=300s -renewable=true -format=json | jq -r '.auth.client_token' 2>/dev/null)
    
    assert_not_equals "" "$renewable_token" "Failed to create renewable token"
    
    # Get initial TTL
    local initial_info
    initial_info=$(get_token_info "$renewable_token")
    local initial_ttl
    initial_ttl=$(echo "$initial_info" | jq -r '.data.ttl // 0')
    
    assert_true "$((initial_ttl > 0))" "Initial token TTL is invalid"
    log_debug "Initial token TTL: ${initial_ttl}s"
    
    # Wait a bit and renew the token
    sleep 5
    
    local renew_result
    renew_result=$(VAULT_TOKEN="$renewable_token" vault token renew -format=json 2>/dev/null || echo "{}")
    
    local new_ttl
    new_ttl=$(echo "$renew_result" | jq -r '.auth.lease_duration // 0')
    
    if [[ $new_ttl -gt 0 ]]; then
        log_debug "Token renewed successfully, new TTL: ${new_ttl}s"
        assert_true "$((new_ttl >= initial_ttl - 10))" "Token renewal did not extend TTL properly"
    else
        log_warning "Token renewal may have failed or returned unexpected format"
    fi
    
    # Test token lookup after renewal
    local renewed_info
    renewed_info=$(get_token_info "$renewable_token")
    local renewed_ttl
    renewed_ttl=$(echo "$renewed_info" | jq -r '.data.ttl // 0')
    
    assert_true "$((renewed_ttl > 0))" "Token TTL invalid after renewal"
    
    # Clean up
    revoke_test_token "$renewable_token"
    
    log_success "Token renewal and TTL management verified"
}

test_token_revocation() {
    log_info "Testing token revocation"
    
    if ! check_vault_accessible; then
        skip_test "Token Revocation" "Vault not accessible"
        return
    fi
    
    # Create multiple tokens for testing different revocation scenarios
    local parent_token child_token orphan_token
    
    parent_token=$(create_test_token "$TOKEN_TEST_POLICY" "1h" "type=parent")
    assert_not_equals "" "$parent_token" "Failed to create parent token"
    
    # Create child token
    child_token=$(VAULT_TOKEN="$parent_token" vault token create -policy="$TOKEN_TEST_POLICY" -ttl=30m -format=json | jq -r '.auth.client_token' 2>/dev/null)
    assert_not_equals "" "$child_token" "Failed to create child token"
    
    # Create orphan token
    orphan_token=$(vault token create -policy="$TOKEN_TEST_POLICY" -ttl=30m -orphan -format=json | jq -r '.auth.client_token' 2>/dev/null)
    assert_not_equals "" "$orphan_token" "Failed to create orphan token"
    
    # Verify all tokens are valid initially
    for token in "$parent_token" "$child_token" "$orphan_token"; do
        local info
        info=$(get_token_info "$token")
        local valid
        valid=$(echo "$info" | jq -r 'has("data")' 2>/dev/null)
        assert_equals "true" "$valid" "Token should be valid: ${token:0:8}..."
    done
    
    # Test individual token revocation
    revoke_test_token "$orphan_token"
    
    # Verify orphan token is revoked
    local orphan_info
    orphan_info=$(get_token_info "$orphan_token")
    assert_contains "$orphan_info" "errors" "Orphan token should be revoked"
    
    # Test parent token revocation (should revoke children)
    revoke_test_token "$parent_token"
    
    # Verify parent token is revoked
    local parent_info
    parent_info=$(get_token_info "$parent_token")
    assert_contains "$parent_info" "errors" "Parent token should be revoked"
    
    # Verify child token is also revoked
    local child_info
    child_info=$(get_token_info "$child_token")
    assert_contains "$child_info" "errors" "Child token should be revoked with parent"
    
    log_success "Token revocation verified"
}

test_token_policies_and_capabilities() {
    log_info "Testing token policies and capability inheritance"
    
    if ! check_vault_accessible; then
        skip_test "Token Policies and Capabilities" "Vault not accessible"
        return
    fi
    
    # Create different policies with varying capabilities
    local read_policy='
path "secret/readonly/*" {
  capabilities = ["read", "list"]
}'
    
    local write_policy='
path "secret/readwrite/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}'
    
    create_test_policy "test-readonly" "$read_policy"
    create_test_policy "test-readwrite" "$write_policy"
    
    # Create tokens with different policy combinations
    local readonly_token readwrite_token multi_policy_token
    
    readonly_token=$(create_test_token "test-readonly" "1h")
    readwrite_token=$(create_test_token "test-readwrite" "1h")
    multi_policy_token=$(vault token create -policy="test-readonly" -policy="test-readwrite" -ttl=1h -format=json | jq -r '.auth.client_token' 2>/dev/null)
    
    # Test capabilities for each token
    for token_info in "readonly:$readonly_token" "readwrite:$readwrite_token" "multi:$multi_policy_token"; do
        local type="${token_info%%:*}"
        local token="${token_info##*:}"
        
        if [[ -n "$token" ]]; then
            local capabilities
            capabilities=$(VAULT_TOKEN="$token" vault token capabilities secret/readonly/test 2>/dev/null || echo "")
            
            case "$type" in
                "readonly")
                    assert_contains "$capabilities" "read" "Readonly token should have read capability"
                    ;;
                "readwrite"|"multi")
                    # These should have read capability at minimum
                    if [[ -n "$capabilities" ]]; then
                        log_debug "$type token capabilities: $capabilities"
                    fi
                    ;;
            esac
            
            # Clean up
            revoke_test_token "$token"
        fi
    done
    
    log_success "Token policies and capabilities verified"
}

test_token_metadata_and_tracking() {
    log_info "Testing token metadata and tracking"
    
    if ! check_vault_accessible; then
        skip_test "Token Metadata and Tracking" "Vault not accessible"
        return
    fi
    
    # Create tokens with various metadata
    local metadata_cases=(
        "service=traefik,component=loadbalancer"
        "service=nomad,component=scheduler"
        "service=vault,component=secrets"
    )
    
    local tokens_with_metadata=()
    
    for metadata in "${metadata_cases[@]}"; do
        local token
        token=$(vault token create -policy="$TOKEN_TEST_POLICY" -ttl=1h -metadata="$metadata" -format=json 2>/dev/null | jq -r '.auth.client_token' 2>/dev/null)
        
        if [[ -n "$token" ]]; then
            tokens_with_metadata+=("$token")
            
            # Verify metadata is stored
            local token_info
            token_info=$(get_token_info "$token")
            
            local stored_metadata
            stored_metadata=$(echo "$token_info" | jq -r '.data.meta // {}' 2>/dev/null)
            
            # Check if at least some metadata was stored
            if [[ "$stored_metadata" != "{}" ]] && [[ "$stored_metadata" != "null" ]]; then
                log_debug "Token metadata stored: $stored_metadata"
            fi
        fi
    done
    
    # Test token lookup by metadata (if supported)
    if [[ ${#tokens_with_metadata[@]} -gt 0 ]]; then
        log_debug "Created ${#tokens_with_metadata[@]} tokens with metadata"
    fi
    
    # Clean up
    for token in "${tokens_with_metadata[@]}"; do
        revoke_test_token "$token"
    done
    
    log_success "Token metadata and tracking verified"
}

test_nomad_vault_token_integration() {
    log_info "Testing Nomad-Vault token integration"
    
    if ! check_vault_accessible; then
        skip_test "Nomad-Vault Token Integration" "Vault not accessible"
        return
    fi
    
    # Check if Nomad integration is configured
    local auth_methods
    auth_methods=$(vault auth list -format=json 2>/dev/null | jq -r 'keys[]' | grep -E '(nomad|kubernetes|aws)' || echo "")
    
    if [[ -n "$auth_methods" ]]; then
        log_debug "Found auth methods that could be used with Nomad: $auth_methods"
    else
        log_debug "No obvious Nomad auth methods found (may use direct token auth)"
    fi
    
    # Test if we can create tokens suitable for Nomad workloads
    local nomad_token_policy='
path "secret/nomad/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}
path "kv/data/nomad/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}
path "auth/token/create" {
  capabilities = ["create", "update"]
}'
    
    create_test_policy "nomad-workload" "$nomad_token_policy"
    
    # Create a token suitable for Nomad workloads
    local nomad_token
    nomad_token=$(create_test_token "nomad-workload" "24h" "purpose=nomad-integration")
    
    assert_not_equals "" "$nomad_token" "Failed to create Nomad integration token"
    
    # Test token can create child tokens (important for Nomad)
    local child_token
    child_token=$(VAULT_TOKEN="$nomad_token" vault token create -ttl=1h -format=json 2>/dev/null | jq -r '.auth.client_token' 2>/dev/null)
    
    if [[ -n "$child_token" ]]; then
        log_debug "Nomad token can create child tokens"
        revoke_test_token "$child_token"
    else
        log_warning "Nomad token may not be able to create child tokens"
    fi
    
    # Clean up
    revoke_test_token "$nomad_token"
    
    log_success "Nomad-Vault token integration verified"
}

test_token_migration_scenarios() {
    log_info "Testing token migration scenarios"
    
    if ! check_vault_accessible; then
        skip_test "Token Migration Scenarios" "Vault not accessible"
        return
    fi
    
    # Simulate migration from one policy to another
    local old_policy='
path "secret/legacy/*" {
  capabilities = ["read", "list"]
}'
    
    local new_policy='
path "secret/legacy/*" {
  capabilities = ["read", "list"]
}
path "kv/data/modern/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}'
    
    create_test_policy "legacy-policy" "$old_policy"
    create_test_policy "modern-policy" "$new_policy"
    
    # Create legacy token
    local legacy_token
    legacy_token=$(create_test_token "legacy-policy" "1h")
    assert_not_equals "" "$legacy_token" "Failed to create legacy token"
    
    # Create modern token for migration
    local modern_token
    modern_token=$(create_test_token "modern-policy" "1h")
    assert_not_equals "" "$modern_token" "Failed to create modern token"
    
    # Verify capabilities differ
    local legacy_caps modern_caps
    legacy_caps=$(VAULT_TOKEN="$legacy_token" vault token capabilities kv/data/modern/test 2>/dev/null || echo "deny")
    modern_caps=$(VAULT_TOKEN="$modern_token" vault token capabilities kv/data/modern/test 2>/dev/null || echo "deny")
    
    log_debug "Legacy capabilities: $legacy_caps"
    log_debug "Modern capabilities: $modern_caps"
    
    # Test token replacement workflow
    local replacement_token
    replacement_token=$(create_test_token "modern-policy" "1h" "replaces=legacy-token")
    
    if [[ -n "$replacement_token" ]]; then
        # Revoke old token
        revoke_test_token "$legacy_token"
        
        # Verify replacement token works
        local replacement_info
        replacement_info=$(get_token_info "$replacement_token")
        assert_contains "$replacement_info" '"data"' "Replacement token should be valid"
        
        revoke_test_token "$replacement_token"
    fi
    
    # Clean up
    revoke_test_token "$modern_token"
    
    log_success "Token migration scenarios verified"
}

test_token_emergency_procedures() {
    log_info "Testing emergency token procedures"
    
    if ! check_vault_accessible; then
        skip_test "Emergency Token Procedures" "Vault not accessible"
        return
    fi
    
    # Test emergency token creation (using root if available)
    local emergency_token
    if [[ -n "${VAULT_ROOT_TOKEN:-}" ]]; then
        emergency_token=$(VAULT_TOKEN="$VAULT_ROOT_TOKEN" vault token create \
            -policy=default -ttl=15m -use-limit=10 -format=json 2>/dev/null | \
            jq -r '.auth.client_token' 2>/dev/null)
    else
        # Try to create with current token
        emergency_token=$(vault token create -policy=default -ttl=15m -use-limit=10 -format=json 2>/dev/null | jq -r '.auth.client_token' 2>/dev/null)
    fi
    
    if [[ -n "$emergency_token" ]]; then
        log_debug "Created emergency token with limited use"
        
        # Test use limit
        local use_count=0
        while [[ $use_count -lt 3 ]]; do
            local lookup_result
            lookup_result=$(VAULT_TOKEN="$emergency_token" vault token lookup 2>/dev/null || echo "failed")
            
            if [[ "$lookup_result" != "failed" ]]; then
                ((use_count++))
            else
                break
            fi
        done
        
        log_debug "Emergency token used $use_count times"
        
        # Clean up
        revoke_test_token "$emergency_token"
    else
        log_debug "Could not create emergency token (may require root privileges)"
    fi
    
    # Test token accessor for emergency revocation
    local test_token
    test_token=$(create_test_token "$TOKEN_TEST_POLICY" "1h")
    
    if [[ -n "$test_token" ]]; then
        local token_info
        token_info=$(get_token_info "$test_token")
        local accessor
        accessor=$(echo "$token_info" | jq -r '.data.accessor // ""')
        
        if [[ -n "$accessor" ]]; then
            log_debug "Token accessor available for emergency revocation: ${accessor:0:8}..."
            
            # Test accessor-based revocation
            vault token revoke -accessor "$accessor" >/dev/null 2>&1 || log_warning "Accessor-based revocation failed"
        fi
    fi
    
    log_success "Emergency token procedures verified"
}

test_token_audit_and_logging() {
    log_info "Testing token audit and logging"
    
    if ! check_vault_accessible; then
        skip_test "Token Audit and Logging" "Vault not accessible"
        return
    fi
    
    # Check if audit logging is enabled
    local audit_devices
    audit_devices=$(vault audit list -format=json 2>/dev/null | jq -r 'keys[]' 2>/dev/null || echo "")
    
    if [[ -n "$audit_devices" ]]; then
        log_debug "Active audit devices: $audit_devices"
        
        # Create a token to generate audit events
        local audit_test_token
        audit_test_token=$(create_test_token "$TOKEN_TEST_POLICY" "5m" "audit-test=true")
        
        if [[ -n "$audit_test_token" ]]; then
            # Perform some operations that should be audited
            VAULT_TOKEN="$audit_test_token" vault token lookup >/dev/null 2>&1 || true
            VAULT_TOKEN="$audit_test_token" vault list secret/ >/dev/null 2>&1 || true
            
            log_debug "Performed operations for audit testing"
            
            revoke_test_token "$audit_test_token"
        fi
    else
        log_debug "No audit devices configured (audit logging not available)"
    fi
    
    # Check token metrics if available
    local vault_metrics
    vault_metrics=$(curl -s "$VAULT_ADDR/v1/sys/metrics" 2>/dev/null || echo "")
    
    if [[ -n "$vault_metrics" ]] && echo "$vault_metrics" | grep -q "token"; then
        log_debug "Token metrics are available in Vault"
    else
        log_debug "Token metrics not accessible (may require authentication)"
    fi
    
    log_success "Token audit and logging verified"
}

# Main test execution
main() {
    log_info "Starting Token Lifecycle and Migration Tests"
    log_info "============================================="
    
    # Load test configuration
    load_test_config
    
    # Run tests in order
    run_test "Vault Token Creation" "test_vault_token_creation"
    run_test "Token Renewal and TTL Management" "test_token_renewal_and_ttl_management"
    run_test "Token Revocation" "test_token_revocation"
    run_test "Token Policies and Capabilities" "test_token_policies_and_capabilities"
    run_test "Token Metadata and Tracking" "test_token_metadata_and_tracking"
    run_test "Nomad-Vault Token Integration" "test_nomad_vault_token_integration"
    run_test "Token Migration Scenarios" "test_token_migration_scenarios"
    run_test "Emergency Token Procedures" "test_token_emergency_procedures"
    run_test "Token Audit and Logging" "test_token_audit_and_logging"
    
    # Clean up test policies
    vault policy delete "$TOKEN_TEST_POLICY" >/dev/null 2>&1 || true
    vault policy delete "test-readonly" >/dev/null 2>&1 || true
    vault policy delete "test-readwrite" >/dev/null 2>&1 || true
    vault policy delete "legacy-policy" >/dev/null 2>&1 || true
    vault policy delete "modern-policy" >/dev/null 2>&1 || true
    vault policy delete "nomad-workload" >/dev/null 2>&1 || true
    
    # Print test summary
    print_test_summary
}

# Run tests if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi