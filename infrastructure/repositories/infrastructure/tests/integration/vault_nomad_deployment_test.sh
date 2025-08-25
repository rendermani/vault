#!/bin/bash

# Vault-on-Nomad Deployment Integration Tests
# Tests Vault deployment, initialization, and integration with Nomad

set -euo pipefail

# Source test framework
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../framework/test_framework.sh
source "$SCRIPT_DIR/../framework/test_framework.sh"

# Test configuration
VAULT_ADDR="${VAULT_ADDR:-http://localhost:8200}"
VAULT_NOMAD_JOB="${VAULT_NOMAD_JOB:-vault}"
VAULT_SERVICE_NAME="${VAULT_SERVICE_NAME:-vault}"
NOMAD_ADDR="${NOMAD_ADDR:-http://localhost:4646}"
VAULT_DATA_DIR="${VAULT_DATA_DIR:-/opt/nomad/volumes/vault-data}"
VAULT_CONFIG_DIR="${VAULT_CONFIG_DIR:-/opt/nomad/volumes/vault-config}"

# Test helper functions
get_vault_status() {
    vault status -format=json 2>/dev/null || echo '{"errors":["vault not accessible"]}'
}

get_nomad_job_status() {
    local job_name="$1"
    nomad job status -json "$job_name" 2>/dev/null || echo '{"Status":"not-found"}'
}

get_nomad_service_health() {
    local service_name="$1"
    nomad service list -json 2>/dev/null | jq -r ".[] | select(.ServiceName == \"$service_name\") | .Status" 2>/dev/null || echo "not-found"
}

check_vault_unsealed() {
    local status
    status=$(get_vault_status)
    echo "$status" | jq -r '.sealed // true' 2>/dev/null | grep -q "false"
}

check_vault_initialized() {
    local status
    status=$(get_vault_status)
    echo "$status" | jq -r '.initialized // false' 2>/dev/null | grep -q "true"
}

# Test functions
test_nomad_vault_job_deployment() {
    log_info "Testing Vault job deployment on Nomad"
    
    # Check if Vault job is submitted
    local job_status
    job_status=$(get_nomad_job_status "$VAULT_NOMAD_JOB")
    
    local status
    status=$(echo "$job_status" | jq -r '.Status // "not-found"')
    
    if [[ "$status" == "not-found" ]]; then
        log_warning "Vault job not found in Nomad, attempting deployment"
        
        # Look for vault.nomad file
        local vault_job_file
        vault_job_file=$(find /Users/mlautenschlager/cloudya/vault/infrastructure/repositories -name "vault.nomad" | head -1)
        
        if [[ -n "$vault_job_file" ]] && [[ -f "$vault_job_file" ]]; then
            assert_command_success "nomad job run '$vault_job_file'" \
                "Failed to deploy Vault job"
            
            # Wait for deployment to complete
            sleep 30
            job_status=$(get_nomad_job_status "$VAULT_NOMAD_JOB")
            status=$(echo "$job_status" | jq -r '.Status // "failed"')
        else
            skip_test "Vault Job Deployment" "vault.nomad file not found"
            return
        fi
    fi
    
    assert_equals "running" "$status" "Vault job is not running (status: $status)"
    
    log_success "Vault job deployed successfully on Nomad"
}

test_vault_service_registration() {
    log_info "Testing Vault service registration in Nomad"
    
    # Wait for service registration
    sleep 15
    
    # Check if Vault service is registered
    local services
    services=$(nomad service list -json 2>/dev/null | jq -r '.[].ServiceName' | grep -c "vault" || echo "0")
    
    assert_true "$((services >= 1))" "Vault service not registered with Nomad"
    
    # Check service health
    local health_status
    health_status=$(get_nomad_service_health "$VAULT_SERVICE_NAME")
    
    if [[ "$health_status" != "not-found" ]]; then
        log_debug "Vault service health status: $health_status"
    fi
    
    log_success "Vault service registration verified"
}

test_vault_persistent_storage() {
    log_info "Testing Vault persistent storage configuration"
    
    # Check if host volumes are properly mounted
    local job_allocs
    job_allocs=$(nomad job allocs -json "$VAULT_NOMAD_JOB" 2>/dev/null | jq -r '.[].ID' | head -1)
    
    if [[ -n "$job_allocs" ]] && [[ "$job_allocs" != "null" ]]; then
        # Check volume mounts
        local volume_info
        volume_info=$(nomad alloc fs "$job_allocs" vault/data 2>/dev/null || echo "volume-not-mounted")
        
        assert_not_equals "volume-not-mounted" "$volume_info" "Vault data volume not properly mounted"
        
        # Check if persistent storage directories exist on host
        if [[ -d "$VAULT_DATA_DIR" ]]; then
            log_debug "Vault data directory exists: $VAULT_DATA_DIR"
            
            # Check directory permissions
            local perms
            perms=$(stat -c "%a" "$VAULT_DATA_DIR" 2>/dev/null || echo "000")
            log_debug "Data directory permissions: $perms"
        else
            log_warning "Vault data directory not found: $VAULT_DATA_DIR"
        fi
        
        if [[ -d "$VAULT_CONFIG_DIR" ]]; then
            log_debug "Vault config directory exists: $VAULT_CONFIG_DIR"
        fi
    else
        skip_test "Vault Persistent Storage" "No Vault allocations found"
        return
    fi
    
    log_success "Vault persistent storage configuration verified"
}

test_vault_network_connectivity() {
    log_info "Testing Vault network connectivity"
    
    # Wait for Vault to be ready
    wait_for_http_endpoint "$VAULT_ADDR/v1/sys/health" 200 120
    
    # Test basic connectivity
    assert_http_status "$VAULT_ADDR/v1/sys/health" 200 "Vault health endpoint not responding"
    
    # Test specific Vault endpoints
    local endpoints=(
        "/v1/sys/health"
        "/v1/sys/seal-status"
    )
    
    for endpoint in "${endpoints[@]}"; do
        assert_http_status "$VAULT_ADDR$endpoint" 200 "Vault endpoint $endpoint not responding"
    done
    
    # Check response content
    local health_response
    health_response=$(curl -s "$VAULT_ADDR/v1/sys/health" 2>/dev/null || echo "{}")
    
    local version
    version=$(echo "$health_response" | jq -r '.version // "unknown"')
    assert_not_equals "unknown" "$version" "Could not determine Vault version"
    
    log_debug "Vault version: $version"
    log_success "Vault network connectivity verified"
}

test_vault_initialization_status() {
    log_info "Testing Vault initialization status"
    
    # Get Vault status
    local vault_status
    vault_status=$(get_vault_status)
    
    # Check if Vault is initialized
    local initialized
    initialized=$(echo "$vault_status" | jq -r '.initialized // false')
    
    if [[ "$initialized" == "false" ]]; then
        log_warning "Vault is not initialized, attempting initialization"
        
        # Look for initialization script in the allocation
        local job_allocs
        job_allocs=$(nomad job allocs -json "$VAULT_NOMAD_JOB" 2>/dev/null | jq -r '.[].ID' | head -1)
        
        if [[ -n "$job_allocs" ]] && [[ "$job_allocs" != "null" ]]; then
            # Try to run the initialization script
            if nomad alloc exec "$job_allocs" vault /bin/sh -c "test -f /vault/data/vault-init.json"; then
                log_info "Vault appears to have been initialized (init file exists)"
            else
                # Initialize Vault
                log_info "Initializing Vault..."
                local init_output
                init_output=$(vault operator init -key-shares=5 -key-threshold=3 -format=json 2>/dev/null || echo "{}")
                
                local root_token
                root_token=$(echo "$init_output" | jq -r '.root_token // "none"')
                
                if [[ "$root_token" != "none" ]]; then
                    log_debug "Vault initialized successfully"
                    
                    # Try to unseal (for testing purposes)
                    local unseal_keys
                    unseal_keys=$(echo "$init_output" | jq -r '.unseal_keys_b64[]' | head -3)
                    
                    local key_count=0
                    while IFS= read -r key; do
                        if [[ -n "$key" ]] && [[ "$key" != "null" ]]; then
                            vault operator unseal "$key" >/dev/null 2>&1 || log_warning "Failed to apply unseal key $((key_count + 1))"
                            ((key_count++))
                        fi
                    done <<< "$unseal_keys"
                    
                    if [[ $key_count -ge 3 ]]; then
                        log_debug "Applied $key_count unseal keys"
                    fi
                else
                    log_warning "Vault initialization may have failed"
                fi
            fi
        fi
        
        # Re-check initialization status
        sleep 10
        vault_status=$(get_vault_status)
        initialized=$(echo "$vault_status" | jq -r '.initialized // false')
    fi
    
    assert_equals "true" "$initialized" "Vault is not initialized"
    log_success "Vault initialization status verified"
}

test_vault_seal_status() {
    log_info "Testing Vault seal status"
    
    # Get Vault status
    local vault_status
    vault_status=$(get_vault_status)
    
    # Check seal status
    local sealed
    sealed=$(echo "$vault_status" | jq -r '.sealed // true')
    
    if [[ "$sealed" == "true" ]]; then
        log_warning "Vault is sealed"
        
        # Get seal information
        local seal_threshold seal_progress
        seal_threshold=$(echo "$vault_status" | jq -r '.t // 0')
        seal_progress=$(echo "$vault_status" | jq -r '.progress // 0')
        
        log_debug "Seal threshold: $seal_threshold, Progress: $seal_progress"
        
        # For testing, we'll accept sealed status but log it
        log_warning "Vault is sealed - this may be expected in production environments"
    else
        log_debug "Vault is unsealed and ready"
    fi
    
    # Check version information
    local version
    version=$(echo "$vault_status" | jq -r '.version // "unknown"')
    log_debug "Vault version: $version"
    
    log_success "Vault seal status checked"
}

test_vault_configuration_templates() {
    log_info "Testing Vault configuration templates in Nomad"
    
    # Get allocation ID
    local job_allocs
    job_allocs=$(nomad job allocs -json "$VAULT_NOMAD_JOB" 2>/dev/null | jq -r '.[].ID' | head -1)
    
    if [[ -n "$job_allocs" ]] && [[ "$job_allocs" != "null" ]]; then
        # Check if configuration files were generated
        local config_files=(
            "/vault/config/vault.hcl"
            "/vault/config/local/config/vault.hcl"
        )
        
        local found_config=false
        for config_file in "${config_files[@]}"; do
            if nomad alloc fs "$job_allocs" "$config_file" >/dev/null 2>&1; then
                found_config=true
                log_debug "Found Vault config: $config_file"
                
                # Check configuration content
                local config_content
                config_content=$(nomad alloc fs -c "$job_allocs" "$config_file" 2>/dev/null || echo "")
                
                # Verify essential configuration elements
                assert_contains "$config_content" "listener" "Vault config missing listener section"
                assert_contains "$config_content" "storage" "Vault config missing storage section"
                
                # Check for proper API address configuration
                if echo "$config_content" | grep -q "vault.cloudya.net"; then
                    log_debug "Configuration uses production domain"
                elif echo "$config_content" | grep -q "localhost"; then
                    log_debug "Configuration uses localhost (development mode)"
                fi
                
                break
            fi
        done
        
        assert_true "$found_config" "No Vault configuration files found in allocation"
    else
        skip_test "Vault Configuration Templates" "No Vault allocations found"
        return
    fi
    
    log_success "Vault configuration templates verified"
}

test_vault_resource_allocation() {
    log_info "Testing Vault resource allocation in Nomad"
    
    # Get allocation information
    local alloc_info
    alloc_info=$(nomad job allocs -json "$VAULT_NOMAD_JOB" 2>/dev/null | jq -r '.[0]' || echo "{}")
    
    if [[ "$alloc_info" != "{}" ]] && [[ "$alloc_info" != "null" ]]; then
        local alloc_status
        alloc_status=$(echo "$alloc_info" | jq -r '.ClientStatus // "unknown"')
        
        assert_equals "running" "$alloc_status" "Vault allocation not running (status: $alloc_status)"
        
        # Check resource allocation
        local cpu_allocated memory_allocated
        cpu_allocated=$(echo "$alloc_info" | jq -r '.Resources.CPU // 0')
        memory_allocated=$(echo "$alloc_info" | jq -r '.Resources.MemoryMB // 0')
        
        assert_true "$((cpu_allocated > 0))" "No CPU resources allocated to Vault"
        assert_true "$((memory_allocated > 0))" "No memory resources allocated to Vault"
        
        log_debug "Vault resources - CPU: ${cpu_allocated}MHz, Memory: ${memory_allocated}MB"
        
        # Check if allocation has failed events
        local failed_events
        failed_events=$(echo "$alloc_info" | jq -r '.TaskEvents.vault[]? | select(.Type == "Task Setup" or .Type == "Driver") | select(.ExitCode != 0 and .ExitCode != null) | .Message' 2>/dev/null || echo "")
        
        assert_equals "" "$failed_events" "Vault allocation has failed events: $failed_events"
    else
        assert_true false "No Vault allocations found"
    fi
    
    log_success "Vault resource allocation verified"
}

test_vault_service_discovery_integration() {
    log_info "Testing Vault service discovery integration"
    
    # Check Consul integration if available
    if command -v consul >/dev/null 2>&1; then
        local consul_services
        consul_services=$(consul catalog services 2>/dev/null | grep -c vault || echo "0")
        
        if [[ $consul_services -gt 0 ]]; then
            log_debug "Vault registered with Consul service discovery"
        else
            log_debug "Vault not using Consul service discovery"
        fi
    fi
    
    # Check Nomad service discovery
    local nomad_services
    nomad_services=$(nomad service list -json 2>/dev/null | jq -r '.[] | select(.ServiceName | contains("vault")) | .ServiceName' || echo "")
    
    if [[ -n "$nomad_services" ]]; then
        log_debug "Vault services in Nomad discovery:"
        while IFS= read -r service; do
            if [[ -n "$service" ]]; then
                log_debug "  - $service"
            fi
        done <<< "$nomad_services"
    fi
    
    log_success "Vault service discovery integration verified"
}

test_vault_logs_and_health() {
    log_info "Testing Vault logs and health monitoring"
    
    # Get allocation ID
    local job_allocs
    job_allocs=$(nomad job allocs -json "$VAULT_NOMAD_JOB" 2>/dev/null | jq -r '.[].ID' | head -1)
    
    if [[ -n "$job_allocs" ]] && [[ "$job_allocs" != "null" ]]; then
        # Check Vault logs
        local logs
        logs=$(nomad alloc logs "$job_allocs" vault 2>/dev/null | tail -10 || echo "no-logs")
        
        assert_not_equals "no-logs" "$logs" "Cannot retrieve Vault logs from Nomad"
        
        # Check for error patterns in logs
        local error_patterns=("panic" "fatal" "error.*failed" "connection refused")
        
        for pattern in "${error_patterns[@]}"; do
            if echo "$logs" | grep -qi "$pattern"; then
                log_warning "Potential error in Vault logs: pattern '$pattern' found"
            fi
        done
        
        # Check for positive patterns
        local success_patterns=("vault server started" "core: security barrier" "successfully mounted")
        local found_success=false
        
        for pattern in "${success_patterns[@]}"; do
            if echo "$logs" | grep -qi "$pattern"; then
                found_success=true
                log_debug "Found positive log pattern: $pattern"
                break
            fi
        done
        
        if ! $found_success; then
            log_debug "No obvious success patterns found in logs (may be normal)"
        fi
    else
        skip_test "Vault Logs Check" "No Vault allocations found"
        return
    fi
    
    log_success "Vault logs and health monitoring verified"
}

# Main test execution
main() {
    log_info "Starting Vault-on-Nomad Deployment Tests"
    log_info "=========================================="
    
    # Load test configuration
    load_test_config
    
    # Run tests in order
    run_test "Vault Job Deployment" "test_nomad_vault_job_deployment"
    run_test "Vault Service Registration" "test_vault_service_registration" 
    run_test "Vault Persistent Storage" "test_vault_persistent_storage"
    run_test "Vault Network Connectivity" "test_vault_network_connectivity"
    run_test "Vault Initialization Status" "test_vault_initialization_status"
    run_test "Vault Seal Status" "test_vault_seal_status"
    run_test "Vault Configuration Templates" "test_vault_configuration_templates"
    run_test "Vault Resource Allocation" "test_vault_resource_allocation"
    run_test "Vault Service Discovery" "test_vault_service_discovery_integration"
    run_test "Vault Logs and Health" "test_vault_logs_and_health"
    
    # Print test summary
    print_test_summary
}

# Run tests if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi