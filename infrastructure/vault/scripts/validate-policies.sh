#!/bin/bash

# Validate Vault Policies and Secret Paths
# This script tests the vault policies and verifies secret path access

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
VAULT_ADDR="${VAULT_ADDR:-http://localhost:8200}"
ENVIRONMENTS=("develop" "staging" "production")
TEMP_TOKEN_FILE="/tmp/vault_test_tokens"

# Helper functions
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

# Cleanup function
cleanup() {
    if [[ -f "$TEMP_TOKEN_FILE" ]]; then
        while IFS= read -r token; do
            vault token revoke "$token" 2>/dev/null || true
        done < "$TEMP_TOKEN_FILE"
        rm -f "$TEMP_TOKEN_FILE"
    fi
}

trap cleanup EXIT

# Check if Vault is accessible
check_vault_status() {
    log_info "Checking Vault status..."
    
    if ! vault status >/dev/null 2>&1; then
        log_error "Cannot connect to Vault at $VAULT_ADDR"
        return 1
    fi
    
    if vault status | grep -q "Sealed.*true"; then
        log_error "Vault is sealed. Please unseal it first."
        return 1
    fi
    
    log_success "Vault is accessible and unsealed"
    return 0
}

# Validate policy syntax
validate_policy_syntax() {
    log_info "Validating policy syntax..."
    
    local policy_dir="../policies"
    local errors=0
    
    for policy_file in "$policy_dir"/*.hcl "$policy_dir"/environments/*.hcl; do
        if [[ -f "$policy_file" ]]; then
            policy_name=$(basename "$policy_file" .hcl)
            
            # Test policy by attempting to write it
            if vault policy write "test-$policy_name" "$policy_file" >/dev/null 2>&1; then
                log_success "Policy syntax valid: $policy_name"
                # Clean up test policy
                vault policy delete "test-$policy_name" >/dev/null 2>&1
            else
                log_error "Policy syntax invalid: $policy_name"
                ((errors++))
            fi
        fi
    done
    
    if [[ $errors -eq 0 ]]; then
        log_success "All policy syntax validations passed"
        return 0
    else
        log_error "$errors policy syntax errors found"
        return 1
    fi
}

# Test Traefik policy access
test_traefik_policy() {
    log_info "Testing Traefik policy access..."
    
    # Create a token with traefik-policy
    local traefik_token
    traefik_token=$(vault write -field=token auth/token/create \
        policies="traefik-policy" \
        ttl="5m" \
        display_name="test-traefik")
    
    echo "$traefik_token" >> "$TEMP_TOKEN_FILE"
    
    # Test access with traefik token
    export VAULT_TOKEN="$traefik_token"
    
    # Test dashboard credentials access
    if vault kv get secret/traefik/dashboard/credentials >/dev/null 2>&1; then
        log_success "Traefik can access dashboard credentials"
    else
        log_error "Traefik cannot access dashboard credentials"
    fi
    
    # Test certificate access
    if vault kv list secret/traefik/certificates/ >/dev/null 2>&1; then
        log_success "Traefik can access certificate paths"
    else
        log_error "Traefik cannot access certificate paths"
    fi
    
    # Test forbidden paths (should fail)
    if vault kv get secret/database/production/credentials >/dev/null 2>&1; then
        log_error "Traefik has unauthorized access to production database"
    else
        log_success "Traefik properly denied access to production database"
    fi
    
    # Restore original token
    unset VAULT_TOKEN
}

# Test environment-specific policies
test_environment_policies() {
    log_info "Testing environment-specific policies..."
    
    for env in "${ENVIRONMENTS[@]}"; do
        log_info "Testing $env environment policy..."
        
        if vault policy list | grep -q "$env-policy"; then
            # Create a token with environment policy
            local env_token
            env_token=$(vault write -field=token auth/token/create \
                policies="$env-policy" \
                ttl="5m" \
                display_name="test-$env")
            
            echo "$env_token" >> "$TEMP_TOKEN_FILE"
            
            # Test access with environment token
            export VAULT_TOKEN="$env_token"
            
            # Test environment-specific secrets access
            if vault kv get "secret/environments/$env/config" >/dev/null 2>&1; then
                log_success "$env environment can access its secrets"
            else
                log_warning "$env environment cannot access its secrets (may not exist yet)"
            fi
            
            # Test cross-environment access (should fail for prod/staging)
            if [[ "$env" == "production" || "$env" == "staging" ]]; then
                if vault kv get "secret/environments/develop/config" >/dev/null 2>&1; then
                    log_error "$env environment has unauthorized cross-environment access"
                else
                    log_success "$env environment properly denied cross-environment access"
                fi
            fi
            
            # Restore original token
            unset VAULT_TOKEN
        else
            log_warning "$env-policy not found, skipping test"
        fi
    done
}

# Test secret paths structure
test_secret_paths() {
    log_info "Testing secret paths structure..."
    
    local paths=(
        "secret/traefik/dashboard"
        "secret/traefik/certificates"
        "secret/traefik/environments"
        "secret/environments"
        "secret/database"
        "secret/services"
        "secret/monitoring"
    )
    
    for path in "${paths[@]}"; do
        if vault kv list "$path/" >/dev/null 2>&1; then
            log_success "Secret path exists: $path"
        else
            log_warning "Secret path not found: $path (may need initialization)"
        fi
    done
}

# Test token capabilities
test_token_capabilities() {
    log_info "Testing token capabilities..."
    
    # Test admin policy capabilities
    if vault policy list | grep -q "admin"; then
        local admin_token
        admin_token=$(vault write -field=token auth/token/create \
            policies="admin" \
            ttl="5m" \
            display_name="test-admin")
        
        echo "$admin_token" >> "$TEMP_TOKEN_FILE"
        
        export VAULT_TOKEN="$admin_token"
        
        # Test admin capabilities
        if vault policy list >/dev/null 2>&1; then
            log_success "Admin policy can list policies"
        else
            log_error "Admin policy cannot list policies"
        fi
        
        # Test system health access
        if vault read sys/health >/dev/null 2>&1; then
            log_success "Admin policy can access system health"
        else
            log_error "Admin policy cannot access system health"
        fi
        
        unset VAULT_TOKEN
    else
        log_warning "Admin policy not found, skipping admin tests"
    fi
}

# Performance test
performance_test() {
    log_info "Running basic performance tests..."
    
    local start_time end_time duration
    
    # Test policy list performance
    start_time=$(date +%s.%N)
    vault policy list >/dev/null 2>&1
    end_time=$(date +%s.%N)
    duration=$(echo "$end_time - $start_time" | bc)
    
    log_info "Policy list took: ${duration} seconds"
    
    # Test secret read performance
    if vault kv get secret/traefik/dashboard/credentials >/dev/null 2>&1; then
        start_time=$(date +%s.%N)
        vault kv get secret/traefik/dashboard/credentials >/dev/null 2>&1
        end_time=$(date +%s.%N)
        duration=$(echo "$end_time - $start_time" | bc)
        
        log_info "Secret read took: ${duration} seconds"
    fi
}

# Generate validation report
generate_report() {
    log_info "Generating validation report..."
    
    local report_file="/tmp/vault_validation_report.txt"
    
    {
        echo "Vault Policy Validation Report"
        echo "=============================="
        echo "Generated: $(date)"
        echo "Vault Address: $VAULT_ADDR"
        echo ""
        echo "Policy Status:"
        vault policy list | sed 's/^/  - /'
        echo ""
        echo "Secret Engines:"
        vault secrets list | grep -E '^[a-zA-Z]' | sed 's/^/  - /'
        echo ""
        echo "Auth Methods:"
        vault auth list | grep -E '^[a-zA-Z]' | sed 's/^/  - /'
        echo ""
        echo "Environment Policies:"
        for env in "${ENVIRONMENTS[@]}"; do
            if vault policy list | grep -q "$env-policy"; then
                echo "  ✓ $env-policy exists"
            else
                echo "  ✗ $env-policy missing"
            fi
        done
    } > "$report_file"
    
    log_success "Validation report generated: $report_file"
    cat "$report_file"
}

# Main execution
main() {
    log_info "Starting Vault policy validation..."
    
    check_vault_status || exit 1
    
    local errors=0
    
    validate_policy_syntax || ((errors++))
    test_traefik_policy || ((errors++))
    test_environment_policies || ((errors++))
    test_secret_paths
    test_token_capabilities || ((errors++))
    performance_test
    generate_report
    
    if [[ $errors -eq 0 ]]; then
        log_success "All policy validations passed!"
    else
        log_error "$errors validation errors found"
        exit 1
    fi
}

# Execute main function
main "$@"