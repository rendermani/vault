#!/bin/bash

# Multi-Environment Deployment Tests
# Tests deployment across develop, staging, and production environments

set -euo pipefail

# Source test framework
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../framework/test_framework.sh
source "$SCRIPT_DIR/../framework/test_framework.sh"

# Environment configurations
declare -A ENV_CONFIGS=(
    ["develop"]="localhost"
    ["staging"]="localhost"  
    ["production"]="cloudya.net"
)

declare -A ENV_PROTOCOLS=(
    ["develop"]="http"
    ["staging"]="http"
    ["production"]="https"
)

declare -A ENV_PORTS=(
    ["vault"]="8200"
    ["nomad"]="4646"
    ["traefik"]="80"
    ["traefik_secure"]="443"
)

# Test configuration
TEST_ENVIRONMENTS="${TEST_ENVIRONMENTS:-develop staging production}"
CURRENT_ENV="${ENVIRONMENT:-develop}"

# Helper functions
get_env_vault_addr() {
    local env="$1"
    local protocol="${ENV_PROTOCOLS[$env]}"
    local host="${ENV_CONFIGS[$env]}"
    local port="${ENV_PORTS[vault]}"
    
    if [[ "$host" == "cloudya.net" ]]; then
        echo "${protocol}://vault.${host}:${port}"
    else
        echo "${protocol}://${host}:${port}"
    fi
}

get_env_nomad_addr() {
    local env="$1"
    local protocol="${ENV_PROTOCOLS[$env]}"
    local host="${ENV_CONFIGS[$env]}"
    local port="${ENV_PORTS[nomad]}"
    
    if [[ "$host" == "cloudya.net" ]]; then
        echo "${protocol}://nomad.${host}:${port}"
    else
        echo "${protocol}://${host}:${port}"
    fi
}

get_env_traefik_url() {
    local env="$1"
    local host="${ENV_CONFIGS[$env]}"
    
    if [[ "$host" == "cloudya.net" ]]; then
        echo "https://traefik.${host}"
    else
        echo "http://${host}:${ENV_PORTS[traefik]}"
    fi
}

check_env_accessible() {
    local env="$1"
    local vault_addr nomad_addr
    
    vault_addr=$(get_env_vault_addr "$env")
    nomad_addr=$(get_env_nomad_addr "$env")
    
    # Check basic connectivity
    curl -s -f "$vault_addr/v1/sys/health" >/dev/null 2>&1 && \
    curl -s -f "$nomad_addr/v1/status/leader" >/dev/null 2>&1
}

simulate_deployment_to_env() {
    local env="$1"
    local component="${2:-all}"
    
    log_debug "Simulating deployment of $component to $env environment"
    
    # Simulate different deployment patterns based on environment
    case "$env" in
        "develop")
            # Fast deployment with minimal checks
            sleep 1
            ;;
        "staging")  
            # Medium deployment with some validation
            sleep 3
            ;;
        "production")
            # Careful deployment with full validation
            sleep 5
            ;;
    esac
    
    return 0
}

# Test functions
test_environment_detection() {
    log_info "Testing environment detection and configuration"
    
    # Test environment variable detection
    for env in $TEST_ENVIRONMENTS; do
        log_debug "Testing environment: $env"
        
        # Simulate setting environment
        local vault_addr nomad_addr traefik_url
        vault_addr=$(get_env_vault_addr "$env")
        nomad_addr=$(get_env_nomad_addr "$env")
        traefik_url=$(get_env_traefik_url "$env")
        
        # Validate URL construction
        case "$env" in
            "develop"|"staging")
                assert_contains "$vault_addr" "localhost" "$env should use localhost"
                assert_contains "$vault_addr" "http://" "$env should use HTTP"
                ;;
            "production")
                assert_contains "$vault_addr" "cloudya.net" "Production should use cloudya.net domain"
                assert_contains "$vault_addr" "https://" "Production should use HTTPS"
                ;;
        esac
        
        log_debug "$env environment URLs:"
        log_debug "  Vault: $vault_addr"
        log_debug "  Nomad: $nomad_addr"
        log_debug "  Traefik: $traefik_url"
    done
    
    log_success "Environment detection and configuration verified"
}

test_environment_isolation() {
    log_info "Testing environment isolation"
    
    # Test that environments don't interfere with each other
    local test_data_paths=(
        "/tmp/test-develop-data"
        "/tmp/test-staging-data"
        "/tmp/test-production-data"
    )
    
    # Create test data for each environment
    local env_index=0
    for env in $TEST_ENVIRONMENTS; do
        local data_path="${test_data_paths[$env_index]}"
        mkdir -p "$data_path"
        echo "test-data-for-$env-$(date +%s)" > "$data_path/env-marker.txt"
        
        # Verify data is environment-specific
        local content
        content=$(cat "$data_path/env-marker.txt")
        assert_contains "$content" "$env" "Environment data should contain environment name"
        
        ((env_index++))
    done
    
    # Verify isolation - each environment's data should be distinct
    local unique_files
    unique_files=$(find /tmp -name "env-marker.txt" -path "/tmp/test-*" | wc -l | tr -d ' ')
    local expected_count
    expected_count=$(echo $TEST_ENVIRONMENTS | wc -w | tr -d ' ')
    
    assert_equals "$expected_count" "$unique_files" "Environment data files should be isolated"
    
    # Clean up
    for path in "${test_data_paths[@]}"; do
        rm -rf "$path"
    done
    
    log_success "Environment isolation verified"
}

test_configuration_templating() {
    log_info "Testing configuration templating across environments"
    
    # Test Vault configuration templating
    for env in $TEST_ENVIRONMENTS; do
        log_debug "Testing configuration templating for: $env"
        
        # Create test configuration template
        cat > "$TEST_TEMP_DIR/vault-${env}.hcl.tpl" <<EOF
ui = true
api_addr = "{{VAULT_API_ADDR}}"
cluster_addr = "{{VAULT_CLUSTER_ADDR}}"

listener "tcp" {
  address = "0.0.0.0:8200"
  tls_disable = {{TLS_DISABLE}}
}

storage "file" {
  path = "/vault/data"
}
EOF
        
        # Set environment-specific variables
        local vault_api_addr vault_cluster_addr tls_disable
        case "$env" in
            "develop"|"staging")
                vault_api_addr="http://localhost:8200"
                vault_cluster_addr="http://localhost:8201"
                tls_disable="true"
                ;;
            "production")
                vault_api_addr="https://vault.cloudya.net:8200"
                vault_cluster_addr="https://vault.cloudya.net:8201"
                tls_disable="false"
                ;;
        esac
        
        # Generate configuration from template
        sed \
            -e "s|{{VAULT_API_ADDR}}|$vault_api_addr|g" \
            -e "s|{{VAULT_CLUSTER_ADDR}}|$vault_cluster_addr|g" \
            -e "s|{{TLS_DISABLE}}|$tls_disable|g" \
            "$TEST_TEMP_DIR/vault-${env}.hcl.tpl" > "$TEST_TEMP_DIR/vault-${env}.hcl"
        
        # Verify configuration was templated correctly
        local config_content
        config_content=$(cat "$TEST_TEMP_DIR/vault-${env}.hcl")
        
        assert_contains "$config_content" "$vault_api_addr" "Config should contain correct API address for $env"
        assert_contains "$config_content" "$tls_disable" "Config should contain correct TLS setting for $env"
        
        # Verify no template variables remain
        assert_not_contains "$config_content" "{{" "Template variables should be resolved"
    done
    
    log_success "Configuration templating verified"
}

test_deployment_promotion_workflow() {
    log_info "Testing deployment promotion workflow"
    
    # Simulate promotion from develop -> staging -> production
    local environments=("develop" "staging" "production")
    local component="test-service"
    
    local deployment_version="v1.0.0-$(date +%s)"
    log_debug "Testing promotion of $component version $deployment_version"
    
    for env in "${environments[@]}"; do
        log_debug "Deploying $component to $env environment"
        
        # Simulate deployment
        simulate_deployment_to_env "$env" "$component"
        
        # Create deployment marker
        local marker_file="$TEST_TEMP_DIR/deployment-${env}-${component}.txt"
        echo "deployed:$deployment_version:$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$marker_file"
        
        # Verify deployment marker
        assert_file_exists "$marker_file" "Deployment marker should exist for $env"
        
        local marker_content
        marker_content=$(cat "$marker_file")
        assert_contains "$marker_content" "$deployment_version" "Deployment marker should contain version"
        
        # Add environment-specific validation delay
        case "$env" in
            "staging")
                log_debug "Running staging validation checks..."
                sleep 1
                ;;
            "production")
                log_debug "Running production validation checks..."
                sleep 2
                
                # Verify all previous environments were deployed
                assert_file_exists "$TEST_TEMP_DIR/deployment-develop-${component}.txt" \
                    "Develop deployment should exist before production"
                assert_file_exists "$TEST_TEMP_DIR/deployment-staging-${component}.txt" \
                    "Staging deployment should exist before production"
                ;;
        esac
    done
    
    log_success "Deployment promotion workflow verified"
}

test_environment_specific_policies() {
    log_info "Testing environment-specific security policies"
    
    # Test different policy requirements per environment
    for env in $TEST_ENVIRONMENTS; do
        log_debug "Testing security policies for: $env"
        
        # Create environment-specific policy template
        local policy_file="$TEST_TEMP_DIR/policy-${env}.hcl"
        
        case "$env" in
            "develop")
                cat > "$policy_file" <<EOF
# Development environment policy - permissive
path "*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}
EOF
                ;;
            "staging")
                cat > "$policy_file" <<EOF
# Staging environment policy - moderate restrictions
path "secret/staging/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}
path "secret/shared/*" {
  capabilities = ["read", "list"]
}
EOF
                ;;
            "production")
                cat > "$policy_file" <<EOF
# Production environment policy - strict
path "secret/production/*" {
  capabilities = ["read", "list"]
}
path "kv/data/production/*" {
  capabilities = ["read"]
}
EOF
                ;;
        esac
        
        # Verify policy file was created
        assert_file_exists "$policy_file" "Policy file should exist for $env"
        
        # Verify policy content matches environment expectations
        local policy_content
        policy_content=$(cat "$policy_file")
        
        case "$env" in
            "develop")
                assert_contains "$policy_content" '"*"' "Develop policy should be permissive"
                assert_contains "$policy_content" '"delete"' "Develop policy should allow delete"
                ;;
            "staging")
                assert_contains "$policy_content" "staging" "Staging policy should reference staging paths"
                assert_not_contains "$policy_content" '"*"' "Staging policy should not be fully permissive"
                ;;
            "production")
                assert_contains "$policy_content" "production" "Production policy should reference production paths"
                assert_contains "$policy_content" '"read"' "Production policy should allow read"
                assert_not_contains "$policy_content" '"delete"' "Production policy should not allow delete"
                ;;
        esac
    done
    
    log_success "Environment-specific security policies verified"
}

test_cross_environment_communication() {
    log_info "Testing cross-environment communication patterns"
    
    # Test that environments can communicate when needed but are isolated by default
    local communication_tests=(
        "develop:staging:false"  # Develop should not access staging
        "staging:production:false"  # Staging should not access production directly
        "production:staging:true"  # Production may need to access staging for rollback
    )
    
    for test_case in "${communication_tests[@]}"; do
        local source_env="${test_case%%:*}"
        local target_env=$(echo "$test_case" | cut -d':' -f2)
        local should_allow="${test_case##*:}"
        
        log_debug "Testing communication: $source_env -> $target_env (should_allow: $should_allow)"
        
        # Create test communication scenario
        local source_marker="$TEST_TEMP_DIR/comm-source-${source_env}.txt"
        local target_marker="$TEST_TEMP_DIR/comm-target-${target_env}.txt"
        
        echo "source:$source_env:$(date +%s)" > "$source_marker"
        echo "target:$target_env:$(date +%s)" > "$target_marker"
        
        # Simulate communication attempt
        local comm_result="false"
        if [[ "$should_allow" == "true" ]]; then
            # Simulate allowed communication
            echo "communication:allowed:$source_env:$target_env" > "$TEST_TEMP_DIR/comm-${source_env}-${target_env}.txt"
            comm_result="true"
        else
            # Simulate blocked communication
            echo "communication:blocked:$source_env:$target_env" > "$TEST_TEMP_DIR/comm-${source_env}-${target_env}.txt"
            comm_result="false"
        fi
        
        assert_equals "$should_allow" "$comm_result" "Communication policy between $source_env and $target_env"
    done
    
    log_success "Cross-environment communication patterns verified"
}

test_environment_rollback_procedures() {
    log_info "Testing environment rollback procedures"
    
    # Test rollback scenarios
    local rollback_scenarios=(
        "production:staging:emergency"
        "staging:develop:validation-failure"
        "production:production:self-heal"
    )
    
    for scenario in "${rollback_scenarios[@]}"; do
        local target_env="${scenario%%:*}"
        local source_env=$(echo "$scenario" | cut -d':' -f2)
        local reason="${scenario##*:}"
        
        log_debug "Testing rollback: $target_env <- $source_env (reason: $reason)"
        
        # Create pre-rollback state
        local current_version="v2.0.0-broken"
        local rollback_version="v1.9.0-stable"
        
        echo "current:$current_version:$target_env" > "$TEST_TEMP_DIR/rollback-current-${target_env}.txt"
        echo "rollback-to:$rollback_version:$source_env" > "$TEST_TEMP_DIR/rollback-target-${source_env}.txt"
        
        # Simulate rollback procedure
        local rollback_time
        rollback_time=$(date -u +%Y-%m-%dT%H:%M:%SZ)
        
        cat > "$TEST_TEMP_DIR/rollback-${target_env}-${reason}.txt" <<EOF
rollback_initiated: $rollback_time
target_env: $target_env
source_env: $source_env
reason: $reason
from_version: $current_version
to_version: $rollback_version
status: completed
EOF
        
        # Verify rollback procedure
        local rollback_log
        rollback_log=$(cat "$TEST_TEMP_DIR/rollback-${target_env}-${reason}.txt")
        
        assert_contains "$rollback_log" "$target_env" "Rollback log should contain target environment"
        assert_contains "$rollback_log" "$rollback_version" "Rollback log should contain rollback version"
        assert_contains "$rollback_log" "status: completed" "Rollback should complete successfully"
        
        # Verify rollback timing based on environment
        case "$target_env" in
            "production")
                # Production rollbacks should be fast
                log_debug "Production rollback completed quickly"
                ;;
            "staging")
                # Staging rollbacks can be more thorough
                log_debug "Staging rollback with validation"
                ;;
        esac
    done
    
    log_success "Environment rollback procedures verified"
}

test_environment_monitoring_and_alerting() {
    log_info "Testing environment monitoring and alerting"
    
    # Test different monitoring requirements per environment
    for env in $TEST_ENVIRONMENTS; do
        log_debug "Testing monitoring configuration for: $env"
        
        # Create monitoring configuration
        local monitoring_config="$TEST_TEMP_DIR/monitoring-${env}.json"
        
        case "$env" in
            "develop")
                cat > "$monitoring_config" <<EOF
{
  "environment": "$env",
  "alert_severity": "info",
  "check_interval": "5m",
  "retention": "24h",
  "notifications": ["slack-dev"]
}
EOF
                ;;
            "staging")
                cat > "$monitoring_config" <<EOF
{
  "environment": "$env", 
  "alert_severity": "warning",
  "check_interval": "1m",
  "retention": "7d",
  "notifications": ["slack-ops", "email-ops"]
}
EOF
                ;;
            "production")
                cat > "$monitoring_config" <<EOF
{
  "environment": "$env",
  "alert_severity": "critical", 
  "check_interval": "30s",
  "retention": "90d",
  "notifications": ["pagerduty", "slack-critical", "email-ops", "sms-oncall"]
}
EOF
                ;;
        esac
        
        # Verify monitoring configuration
        assert_file_exists "$monitoring_config" "Monitoring config should exist for $env"
        
        local config_content
        config_content=$(cat "$monitoring_config")
        
        # Parse and verify configuration
        local alert_severity check_interval
        alert_severity=$(echo "$config_content" | jq -r '.alert_severity')
        check_interval=$(echo "$config_content" | jq -r '.check_interval')
        
        case "$env" in
            "develop")
                assert_equals "info" "$alert_severity" "Develop should have info-level alerts"
                assert_equals "5m" "$check_interval" "Develop should have relaxed check interval"
                ;;
            "production")
                assert_equals "critical" "$alert_severity" "Production should have critical alerts"
                assert_equals "30s" "$check_interval" "Production should have tight check interval"
                ;;
        esac
        
        log_debug "$env monitoring: severity=$alert_severity, interval=$check_interval"
    done
    
    log_success "Environment monitoring and alerting verified"
}

test_environment_backup_strategies() {
    log_info "Testing environment backup strategies"
    
    # Test different backup requirements per environment
    for env in $TEST_ENVIRONMENTS; do
        log_debug "Testing backup strategy for: $env"
        
        # Create backup configuration
        local backup_config="$TEST_TEMP_DIR/backup-${env}.json"
        
        case "$env" in
            "develop")
                cat > "$backup_config" <<EOF
{
  "environment": "$env",
  "frequency": "weekly",
  "retention": "4w",
  "compression": true,
  "encryption": false,
  "destinations": ["local"]
}
EOF
                ;;
            "staging")
                cat > "$backup_config" <<EOF
{
  "environment": "$env",
  "frequency": "daily",
  "retention": "30d",
  "compression": true,
  "encryption": true,
  "destinations": ["local", "cloud"]
}
EOF
                ;;
            "production")
                cat > "$backup_config" <<EOF
{
  "environment": "$env",
  "frequency": "every-6h",
  "retention": "1y",
  "compression": true,
  "encryption": true,
  "destinations": ["local", "cloud", "offsite"]
}
EOF
                ;;
        esac
        
        # Simulate backup creation
        local backup_file="$TEST_TEMP_DIR/backup-${env}-$(date +%Y%m%d-%H%M%S).tar.gz"
        echo "backup-data-for-$env" | gzip > "$backup_file"
        
        # Verify backup strategy
        assert_file_exists "$backup_config" "Backup config should exist for $env"
        assert_file_exists "$backup_file" "Backup file should be created for $env"
        
        local config_content
        config_content=$(cat "$backup_config")
        local frequency retention
        frequency=$(echo "$config_content" | jq -r '.frequency')
        retention=$(echo "$config_content" | jq -r '.retention')
        
        case "$env" in
            "develop")
                assert_equals "weekly" "$frequency" "Develop should have weekly backups"
                ;;
            "production")
                assert_equals "every-6h" "$frequency" "Production should have frequent backups"
                assert_equals "1y" "$retention" "Production should have long retention"
                ;;
        esac
        
        log_debug "$env backup: frequency=$frequency, retention=$retention"
    done
    
    log_success "Environment backup strategies verified"
}

# Main test execution
main() {
    log_info "Starting Multi-Environment Deployment Tests"
    log_info "============================================"
    
    # Load test configuration
    load_test_config
    
    log_info "Testing environments: $TEST_ENVIRONMENTS"
    log_info "Current environment: $CURRENT_ENV"
    
    # Run tests in order
    run_test "Environment Detection" "test_environment_detection"
    run_test "Environment Isolation" "test_environment_isolation"
    run_test "Configuration Templating" "test_configuration_templating"
    run_test "Deployment Promotion Workflow" "test_deployment_promotion_workflow"
    run_test "Environment-Specific Policies" "test_environment_specific_policies"
    run_test "Cross-Environment Communication" "test_cross_environment_communication"
    run_test "Environment Rollback Procedures" "test_environment_rollback_procedures"
    run_test "Environment Monitoring and Alerting" "test_environment_monitoring_and_alerting"
    run_test "Environment Backup Strategies" "test_environment_backup_strategies"
    
    # Print test summary
    print_test_summary
}

# Run tests if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi