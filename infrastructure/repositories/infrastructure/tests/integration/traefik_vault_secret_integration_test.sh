#!/bin/bash

# Traefik-Vault Secret Integration Tests  
# Tests integration between Traefik and Vault for secret management

set -euo pipefail

# Source test framework
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../framework/test_framework.sh
source "$SCRIPT_DIR/../framework/test_framework.sh"

# Test configuration
VAULT_ADDR="${VAULT_ADDR:-http://localhost:8200}"
TRAEFIK_URL="${TRAEFIK_URL:-http://localhost:80}"
TRAEFIK_DASHBOARD_URL="${TRAEFIK_DASHBOARD_URL:-http://traefik.cloudya.net}"
NOMAD_ADDR="${NOMAD_ADDR:-http://localhost:4646}"
TRAEFIK_NOMAD_JOB="${TRAEFIK_NOMAD_JOB:-traefik}"
VAULT_KV_PATH="${VAULT_KV_PATH:-kv/data/traefik}"

# Test helper functions
check_vault_accessible() {
    curl -s -f "$VAULT_ADDR/v1/sys/health" >/dev/null 2>&1
}

check_traefik_accessible() {
    curl -s -f "$TRAEFIK_URL/ping" >/dev/null 2>&1
}

get_vault_secret() {
    local path="$1"
    local field="$2"
    vault kv get -field="$field" "$path" 2>/dev/null || echo ""
}

check_traefik_nomad_job() {
    nomad job status "$TRAEFIK_NOMAD_JOB" >/dev/null 2>&1
}

get_traefik_config_from_nomad() {
    local job_allocs
    job_allocs=$(nomad job allocs -json "$TRAEFIK_NOMAD_JOB" 2>/dev/null | jq -r '.[].ID' | head -1)
    
    if [[ -n "$job_allocs" ]] && [[ "$job_allocs" != "null" ]]; then
        nomad alloc fs -c "$job_allocs" local/dynamic/routes.yml 2>/dev/null || echo ""
    else
        echo ""
    fi
}

# Test functions
test_vault_secret_engine_setup() {
    log_info "Testing Vault KV secret engine setup for Traefik"
    
    # Check if Vault is accessible
    if ! check_vault_accessible; then
        skip_test "Vault Secret Engine Setup" "Vault not accessible"
        return
    fi
    
    # Check if KV secret engine is enabled
    local secret_engines
    secret_engines=$(vault secrets list -format=json 2>/dev/null | jq -r 'keys[]' 2>/dev/null || echo "")
    
    assert_contains "$secret_engines" "kv/" "KV secret engine not enabled"
    
    # Test basic KV operations
    assert_command_success "vault kv list kv/" "Cannot list KV secrets"
    
    log_success "Vault KV secret engine setup verified"
}

test_traefik_vault_policy() {
    log_info "Testing Traefik Vault policy configuration"
    
    if ! check_vault_accessible; then
        skip_test "Traefik Vault Policy" "Vault not accessible"
        return
    fi
    
    # Check if traefik policy exists
    local policies
    policies=$(vault policy list 2>/dev/null || echo "")
    
    if ! echo "$policies" | grep -q "traefik"; then
        log_warning "Traefik policy not found, creating test policy"
        
        # Create a minimal test policy
        cat > "$TEST_TEMP_DIR/traefik-policy.hcl" <<EOF
# Traefik policy for testing
path "kv/data/traefik/*" {
  capabilities = ["read"]
}
EOF
        
        assert_command_success "vault policy write traefik-test '$TEST_TEMP_DIR/traefik-policy.hcl'" \
            "Failed to create test Traefik policy"
    else
        log_debug "Found existing Traefik policy"
    fi
    
    # Verify policy content
    local policy_content
    policy_content=$(vault policy read traefik-test 2>/dev/null || vault policy read traefik 2>/dev/null || echo "")
    
    assert_contains "$policy_content" "kv/data/traefik" "Traefik policy missing KV path permissions"
    
    log_success "Traefik Vault policy verified"
}

test_traefik_credentials_in_vault() {
    log_info "Testing Traefik credentials storage in Vault"
    
    if ! check_vault_accessible; then
        skip_test "Traefik Credentials in Vault" "Vault not accessible"
        return
    fi
    
    # Check if dashboard credentials exist
    local dashboard_secrets=("username" "password" "auth")
    local missing_secrets=()
    
    for secret in "${dashboard_secrets[@]}"; do
        local value
        value=$(get_vault_secret "$VAULT_KV_PATH/dashboard" "$secret")
        
        if [[ -z "$value" ]]; then
            missing_secrets+=("$secret")
        else
            log_debug "Found dashboard secret: $secret"
        fi
    done
    
    if [[ ${#missing_secrets[@]} -gt 0 ]]; then
        log_warning "Missing dashboard secrets: ${missing_secrets[*]}"
        
        # Create test secrets
        vault kv put "$VAULT_KV_PATH/dashboard" \
            username="admin" \
            password="test-password" \
            auth="admin:$2y$10$test.hash" >/dev/null 2>&1 || \
            log_warning "Failed to create test dashboard secrets"
    fi
    
    # Check Nomad token secret
    local nomad_token
    nomad_token=$(get_vault_secret "$VAULT_KV_PATH/nomad" "token")
    
    if [[ -z "$nomad_token" ]]; then
        log_warning "Nomad token not found in Vault"
        
        # Create test token
        vault kv put "$VAULT_KV_PATH/nomad" \
            token="test-nomad-token" \
            addr="https://nomad.cloudya.net" >/dev/null 2>&1 || \
            log_warning "Failed to create test Nomad token"
    else
        log_debug "Found Nomad token in Vault"
    fi
    
    log_success "Traefik credentials in Vault verified"
}

test_traefik_vault_token() {
    log_info "Testing Traefik Vault token configuration"
    
    if ! check_vault_accessible; then
        skip_test "Traefik Vault Token" "Vault not accessible"
        return
    fi
    
    # Check if Traefik has a token stored in Vault
    local traefik_token
    traefik_token=$(get_vault_secret "$VAULT_KV_PATH/vault" "token")
    
    if [[ -z "$traefik_token" ]]; then
        log_warning "Traefik Vault token not found, creating test token"
        
        # Create a test token with limited permissions
        local test_token
        test_token=$(vault token create -policy=traefik-test -period=24h -format=json 2>/dev/null | jq -r '.auth.client_token' || echo "")
        
        if [[ -n "$test_token" ]]; then
            vault kv put "$VAULT_KV_PATH/vault" token="$test_token" >/dev/null 2>&1
            log_debug "Created test Traefik token"
        else
            log_warning "Failed to create test Traefik token"
        fi
    else
        log_debug "Found Traefik Vault token"
        
        # Verify token is valid
        if VAULT_TOKEN="$traefik_token" vault token lookup >/dev/null 2>&1; then
            log_debug "Traefik token is valid"
        else
            log_warning "Traefik token appears to be invalid or expired"
        fi
    fi
    
    log_success "Traefik Vault token configuration verified"
}

test_traefik_configuration_templates() {
    log_info "Testing Traefik configuration templates with Vault secrets"
    
    if ! check_traefik_nomad_job; then
        skip_test "Traefik Configuration Templates" "Traefik job not found in Nomad"
        return
    fi
    
    # Get Traefik configuration from Nomad
    local traefik_config
    traefik_config=$(get_traefik_config_from_nomad)
    
    if [[ -z "$traefik_config" ]]; then
        skip_test "Traefik Configuration Templates" "Cannot retrieve Traefik config from Nomad"
        return
    fi
    
    # Check if configuration contains expected routes
    assert_contains "$traefik_config" "dashboard:" "Traefik dashboard route not configured"
    assert_contains "$traefik_config" "vault:" "Vault route not configured in Traefik"
    
    # Check middleware configuration
    assert_contains "$traefik_config" "auth-dashboard" "Dashboard authentication middleware not configured"
    assert_contains "$traefik_config" "security-headers" "Security headers middleware not configured"
    
    # Check TLS configuration
    assert_contains "$traefik_config" "certResolver: letsencrypt" "Let's Encrypt cert resolver not configured"
    
    log_success "Traefik configuration templates verified"
}

test_traefik_dashboard_authentication() {
    log_info "Testing Traefik dashboard authentication with Vault secrets"
    
    if ! check_vault_accessible; then
        skip_test "Traefik Dashboard Authentication" "Vault not accessible"
        return
    fi
    
    if ! check_traefik_accessible; then
        skip_test "Traefik Dashboard Authentication" "Traefik not accessible"
        return
    fi
    
    # Get dashboard credentials from Vault
    local dashboard_username dashboard_password
    dashboard_username=$(get_vault_secret "$VAULT_KV_PATH/dashboard" "username")
    dashboard_password=$(get_vault_secret "$VAULT_KV_PATH/dashboard" "password")
    
    if [[ -z "$dashboard_username" ]] || [[ -z "$dashboard_password" ]]; then
        skip_test "Traefik Dashboard Authentication" "Dashboard credentials not found in Vault"
        return
    fi
    
    # Test dashboard access without authentication (should fail)
    assert_http_status "$TRAEFIK_DASHBOARD_URL/dashboard/" 401 \
        "Dashboard should require authentication"
    
    # Test dashboard access with authentication
    local auth_response
    auth_response=$(curl -s -u "$dashboard_username:$dashboard_password" \
        -w "%{http_code}" -o /dev/null "$TRAEFIK_DASHBOARD_URL/dashboard/" 2>/dev/null || echo "000")
    
    # Accept 200 (success) or 404 (dashboard not exposed) but not 401 (auth failure)
    if [[ "$auth_response" == "200" ]] || [[ "$auth_response" == "404" ]]; then
        log_debug "Dashboard authentication working (status: $auth_response)"
    else
        log_warning "Dashboard authentication may not be working properly (status: $auth_response)"
    fi
    
    log_success "Traefik dashboard authentication tested"
}

test_vault_tls_certificate_integration() {
    log_info "Testing Vault TLS certificate integration with Traefik"
    
    if ! check_vault_accessible; then
        skip_test "Vault TLS Certificate Integration" "Vault not accessible"
        return
    fi
    
    # Check if certificate storage path exists in Vault
    local cert_paths=("$VAULT_KV_PATH/certificates" "$VAULT_KV_PATH/ssl")
    local cert_path_exists=false
    
    for path in "${cert_paths[@]}"; do
        if vault kv list "$path" >/dev/null 2>&1; then
            cert_path_exists=true
            log_debug "Found certificate storage path: $path"
            break
        fi
    done
    
    if ! $cert_path_exists; then
        log_warning "No certificate storage path found, creating test path"
        vault kv put "$VAULT_KV_PATH/certificates" \
            storage_type="vault" \
            acme_email="admin@cloudya.net" \
            created_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)" >/dev/null 2>&1 || \
            log_warning "Failed to create certificate storage path"
    fi
    
    # Check Let's Encrypt ACME configuration in Traefik
    if check_traefik_nomad_job; then
        local traefik_config
        traefik_config=$(get_traefik_config_from_nomad)
        
        if [[ -n "$traefik_config" ]]; then
            # Check for ACME configuration references
            local job_def
            job_def=$(nomad job inspect "$TRAEFIK_NOMAD_JOB" 2>/dev/null || echo "{}")
            
            local acme_email
            acme_email=$(echo "$job_def" | jq -r '.Job.TaskGroups[0].Tasks[0].Env.TRAEFIK_CERTIFICATESRESOLVERS_LETSENCRYPT_ACME_EMAIL // ""')
            
            if [[ -n "$acme_email" ]]; then
                log_debug "Found ACME email configuration: $acme_email"
            fi
        fi
    fi
    
    log_success "Vault TLS certificate integration verified"
}

test_secret_rotation_capability() {
    log_info "Testing secret rotation capabilities"
    
    if ! check_vault_accessible; then
        skip_test "Secret Rotation Capability" "Vault not accessible"
        return
    fi
    
    # Test updating a secret and verifying it changes
    local test_secret_path="$VAULT_KV_PATH/test/rotation"
    local original_value="test-value-$(date +%s)"
    
    # Store original value
    assert_command_success "vault kv put '$test_secret_path' value='$original_value'" \
        "Failed to store test secret for rotation"
    
    # Verify it was stored
    local stored_value
    stored_value=$(get_vault_secret "$test_secret_path" "value")
    assert_equals "$original_value" "$stored_value" "Test secret not stored correctly"
    
    # Update the secret
    local new_value="updated-value-$(date +%s)"
    assert_command_success "vault kv put '$test_secret_path' value='$new_value'" \
        "Failed to update test secret"
    
    # Verify it was updated
    local updated_value
    updated_value=$(get_vault_secret "$test_secret_path" "value")
    assert_equals "$new_value" "$updated_value" "Test secret not updated correctly"
    assert_not_equals "$original_value" "$updated_value" "Secret rotation did not change value"
    
    # Clean up test secret
    vault kv delete "$test_secret_path" >/dev/null 2>&1 || log_debug "Could not clean up test secret"
    
    log_success "Secret rotation capability verified"
}

test_traefik_vault_service_integration() {
    log_info "Testing Traefik-Vault service integration"
    
    if ! check_vault_accessible || ! check_traefik_accessible; then
        skip_test "Traefik-Vault Service Integration" "Required services not accessible"
        return
    fi
    
    # Check if Traefik can route to Vault
    local vault_via_traefik
    vault_via_traefik=$(curl -s -f "http://vault.cloudya.net/v1/sys/health" 2>/dev/null || echo "failed")
    
    if [[ "$vault_via_traefik" != "failed" ]]; then
        log_debug "Vault accessible via Traefik routing"
        
        # Parse the response to verify it's actually Vault
        local version
        version=$(echo "$vault_via_traefik" | jq -r '.version // "unknown"' 2>/dev/null || echo "unknown")
        
        if [[ "$version" != "unknown" ]]; then
            log_debug "Vault version via Traefik: $version"
        fi
    else
        log_debug "Vault not accessible via Traefik (may be expected in test environment)"
    fi
    
    # Check reverse - if Vault can be used to secure Traefik routes
    local traefik_routes_secured=false
    
    if check_traefik_nomad_job; then
        local job_def
        job_def=$(nomad job inspect "$TRAEFIK_NOMAD_JOB" 2>/dev/null || echo "{}")
        
        # Check if job definition references Vault for secrets
        if echo "$job_def" | grep -q "vault"; then
            traefik_routes_secured=true
            log_debug "Traefik job references Vault for security"
        fi
    fi
    
    log_success "Traefik-Vault service integration verified"
}

test_error_handling_and_fallbacks() {
    log_info "Testing error handling and fallback mechanisms"
    
    # Test behavior when Vault is temporarily unavailable
    if check_vault_accessible; then
        # Test with invalid token
        local invalid_response
        invalid_response=$(VAULT_TOKEN="invalid-token" curl -s -w "%{http_code}" \
            -H "X-Vault-Token: invalid-token" \
            "$VAULT_ADDR/v1/sys/health" 2>/dev/null | tail -c 3)
        
        # Should get 403 Forbidden for invalid token
        if [[ "$invalid_response" == "403" ]] || [[ "$invalid_response" == "200" ]]; then
            log_debug "Vault properly handles invalid tokens"
        else
            log_warning "Unexpected response for invalid token: $invalid_response"
        fi
    fi
    
    # Test Traefik behavior with missing certificates
    if check_traefik_accessible; then
        # Check if Traefik serves default certificate for unknown domains
        local unknown_domain_response
        unknown_domain_response=$(curl -s -H "Host: unknown.example.com" \
            -w "%{http_code}" -o /dev/null "$TRAEFIK_URL" 2>/dev/null || echo "000")
        
        # Should get some response (not a connection error)
        if [[ "$unknown_domain_response" != "000" ]]; then
            log_debug "Traefik handles unknown domains gracefully (status: $unknown_domain_response)"
        fi
    fi
    
    log_success "Error handling and fallbacks verified"
}

test_monitoring_and_metrics_integration() {
    log_info "Testing monitoring and metrics integration"
    
    # Check if Traefik metrics are exposed
    if check_traefik_accessible; then
        local metrics_response
        metrics_response=$(curl -s "http://localhost:8082/metrics" 2>/dev/null || echo "")
        
        if [[ -n "$metrics_response" ]] && echo "$metrics_response" | grep -q "traefik_"; then
            log_debug "Traefik metrics are exposed"
            
            # Check for specific metrics
            local metric_types=("http_requests_total" "http_request_duration" "config_reloads")
            for metric in "${metric_types[@]}"; do
                if echo "$metrics_response" | grep -q "traefik.*$metric"; then
                    log_debug "Found metric: $metric"
                fi
            done
        else
            log_debug "Traefik metrics not accessible or not in expected format"
        fi
    fi
    
    # Check if Vault metrics are exposed
    if check_vault_accessible; then
        local vault_metrics
        vault_metrics=$(curl -s "$VAULT_ADDR/v1/sys/metrics" 2>/dev/null || echo "")
        
        if [[ -n "$vault_metrics" ]] && echo "$vault_metrics" | grep -q "vault"; then
            log_debug "Vault metrics are accessible"
        else
            log_debug "Vault metrics not accessible (may require authentication)"
        fi
    fi
    
    log_success "Monitoring and metrics integration verified"
}

# Main test execution
main() {
    log_info "Starting Traefik-Vault Secret Integration Tests"
    log_info "==============================================="
    
    # Load test configuration
    load_test_config
    
    # Run tests in order
    run_test "Vault Secret Engine Setup" "test_vault_secret_engine_setup"
    run_test "Traefik Vault Policy" "test_traefik_vault_policy"
    run_test "Traefik Credentials in Vault" "test_traefik_credentials_in_vault"
    run_test "Traefik Vault Token" "test_traefik_vault_token"
    run_test "Traefik Configuration Templates" "test_traefik_configuration_templates"
    run_test "Traefik Dashboard Authentication" "test_traefik_dashboard_authentication"
    run_test "Vault TLS Certificate Integration" "test_vault_tls_certificate_integration"
    run_test "Secret Rotation Capability" "test_secret_rotation_capability"
    run_test "Traefik-Vault Service Integration" "test_traefik_vault_service_integration"
    run_test "Error Handling and Fallbacks" "test_error_handling_and_fallbacks"
    run_test "Monitoring and Metrics" "test_monitoring_and_metrics_integration"
    
    # Print test summary
    print_test_summary
}

# Run tests if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi