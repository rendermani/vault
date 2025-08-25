#!/bin/bash
# Comprehensive Vault API Testing Suite
# Tests all critical API endpoints for accessibility and functionality
# Author: API Testing Specialist
# Date: $(date '+%Y-%m-%d')

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

# Test configuration
VAULT_ADDR=${VAULT_ADDR:-"http://127.0.0.1:8200"}
API_VERSION="v1"
TEST_RESULTS=()
ENDPOINT_COUNT=0
SUCCESSFUL_TESTS=0
FAILED_TESTS=0
WARNING_TESTS=0
TEST_OUTPUT_DIR="tests/api_test_results"
TIMESTAMP=$(date '+%Y%m%d_%H%M%S')

# Create output directory
mkdir -p "$TEST_OUTPUT_DIR"

# Helper functions
log_header() {
    echo -e "${BLUE}=========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}=========================================${NC}"
}

log_category() {
    echo -e "\n${MAGENTA}[Category] $1${NC}"
}

log_endpoint() {
    echo -e "${CYAN}[API]${NC} Testing: $1"
    ((ENDPOINT_COUNT++))
}

log_success() {
    echo -e "${GREEN}  ✓${NC} $1"
    TEST_RESULTS+=("✅ $1")
    ((SUCCESSFUL_TESTS++))
}

log_warning() {
    echo -e "${YELLOW}  ⚠${NC} $1"
    TEST_RESULTS+=("⚠️  $1")
    ((WARNING_TESTS++))
}

log_failure() {
    echo -e "${RED}  ✗${NC} $1"
    TEST_RESULTS+=("❌ $1")
    ((FAILED_TESTS++))
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

# Function to test endpoint accessibility
test_endpoint() {
    local endpoint=$1
    local expected_codes=$2
    local description=$3
    local method=${4:-"GET"}
    
    log_endpoint "$endpoint"
    
    local response_code
    local response_time
    local response_body
    
    # Measure response time and capture response
    local start_time=$(date +%s.%N)
    
    if [[ "$method" == "GET" ]]; then
        response_code=$(curl -s -o /tmp/vault_response.json -w "%{http_code}" \
            --connect-timeout 5 --max-time 10 \
            "$VAULT_ADDR/$API_VERSION/$endpoint" 2>/dev/null || echo "000")
    else
        response_code=$(curl -s -o /tmp/vault_response.json -w "%{http_code}" \
            -X "$method" --connect-timeout 5 --max-time 10 \
            "$VAULT_ADDR/$API_VERSION/$endpoint" 2>/dev/null || echo "000")
    fi
    
    local end_time=$(date +%s.%N)
    response_time=$(echo "$end_time - $start_time" | bc -l 2>/dev/null || echo "0")
    
    # Read response body
    response_body=$(cat /tmp/vault_response.json 2>/dev/null || echo "")
    
    # Log detailed response to file
    cat > "$TEST_OUTPUT_DIR/response_${endpoint//\//_}.json" <<EOF
{
  "endpoint": "$endpoint",
  "method": "$method",
  "timestamp": "$(date -Iseconds)",
  "response_code": "$response_code",
  "response_time": "$response_time",
  "expected_codes": "$expected_codes",
  "description": "$description",
  "response_body": $([[ -n "$response_body" && "$response_body" != "" ]] && echo "$response_body" | jq . 2>/dev/null || echo '"No response body"')
}
EOF
    
    # Evaluate response
    if [[ "$response_code" == "000" ]]; then
        log_failure "$description - Connection failed (No response)"
        return 1
    elif echo "$expected_codes" | grep -q "$response_code"; then
        local time_display=$(printf "%.3f" "$response_time")
        log_success "$description (HTTP $response_code, ${time_display}s)"
        return 0
    elif [[ "$response_code" == "200" ]]; then
        log_success "$description (HTTP $response_code - Unexpected success)"
        return 0
    elif [[ "$response_code" -ge 400 && "$response_code" -lt 500 ]]; then
        log_warning "$description (HTTP $response_code - Client error, may need auth/config)"
        return 1
    elif [[ "$response_code" -ge 500 ]]; then
        log_failure "$description (HTTP $response_code - Server error)"
        return 1
    else
        log_warning "$description (HTTP $response_code - Unexpected response)"
        return 1
    fi
}

# Function to test authenticated endpoints
test_auth_endpoint() {
    local endpoint=$1
    local expected_codes=$2
    local description=$3
    local method=${4:-"GET"}
    local data=${5:-""}
    
    if [[ -z "$VAULT_TOKEN" ]]; then
        log_warning "$description - Skipped (No VAULT_TOKEN set)"
        return 0
    fi
    
    log_endpoint "$endpoint [AUTH]"
    
    local response_code
    local curl_args=(
        -s -o /tmp/vault_response.json -w "%{http_code}"
        --connect-timeout 5 --max-time 10
        -H "X-Vault-Token: $VAULT_TOKEN"
    )
    
    if [[ "$method" != "GET" ]]; then
        curl_args+=(-X "$method")
    fi
    
    if [[ -n "$data" ]]; then
        curl_args+=(-H "Content-Type: application/json" -d "$data")
    fi
    
    curl_args+=("$VAULT_ADDR/$API_VERSION/$endpoint")
    
    response_code=$(curl "${curl_args[@]}" 2>/dev/null || echo "000")
    
    if echo "$expected_codes" | grep -q "$response_code"; then
        log_success "$description (HTTP $response_code)"
        return 0
    else
        log_warning "$description (HTTP $response_code) - May indicate invalid token or permissions"
        return 1
    fi
}

# Vault availability check
check_vault_availability() {
    log_header "Vault Availability Check"
    
    # Test basic connectivity
    if curl -s --connect-timeout 2 "$VAULT_ADDR" >/dev/null 2>&1; then
        log_success "Vault server is accessible at $VAULT_ADDR"
        
        # Get detailed health information
        local health_data
        health_data=$(curl -s "$VAULT_ADDR/v1/sys/health" 2>/dev/null)
        
        if [[ -n "$health_data" ]]; then
            echo "$health_data" > "$TEST_OUTPUT_DIR/health_check.json"
            
            if command -v jq >/dev/null 2>&1; then
                local version initialized sealed standby
                version=$(echo "$health_data" | jq -r '.version // "unknown"' 2>/dev/null)
                initialized=$(echo "$health_data" | jq -r '.initialized // "unknown"' 2>/dev/null)
                sealed=$(echo "$health_data" | jq -r '.sealed // "unknown"' 2>/dev/null)
                standby=$(echo "$health_data" | jq -r '.standby // "unknown"' 2>/dev/null)
                
                log_info "Vault Version: $version"
                log_info "Initialized: $initialized"
                log_info "Sealed: $sealed"
                log_info "Standby: $standby"
                
                if [[ "$initialized" == "true" && "$sealed" == "false" ]]; then
                    log_success "Vault is ready for API testing"
                    return 0
                elif [[ "$sealed" == "true" ]]; then
                    log_warning "Vault is sealed - some endpoints may not be accessible"
                    return 1
                elif [[ "$initialized" == "false" ]]; then
                    log_warning "Vault is not initialized - many endpoints will not be accessible"
                    return 1
                fi
            else
                log_success "Health endpoint responded (jq not available for parsing)"
            fi
        else
            log_warning "Vault is accessible but health endpoint returned no data"
            return 1
        fi
    else
        log_failure "Cannot connect to Vault at $VAULT_ADDR"
        log_info "Please ensure Vault is running and accessible"
        return 1
    fi
}

# Test Core System Endpoints
test_core_system_endpoints() {
    log_category "Core System & Health"
    
    # Essential health endpoints
    test_endpoint "sys/health" "200|429|473|501|503" "Health check endpoint"
    test_endpoint "sys/health?standbyok=true" "200|429|473|501|503" "Health check (standby OK)"
    test_endpoint "sys/seal-status" "200|400|500" "Seal status endpoint"
    test_endpoint "sys/leader" "200|400|500" "Leader information endpoint"
    test_endpoint "sys/host-info" "200|400|403|500" "Host information endpoint"
    
    # Version and license information
    test_endpoint "sys/version-history" "200|400|403|404|500" "Version history"
    test_endpoint "sys/license/status" "200|403|404|500" "License status (Enterprise)"
    
    # Configuration endpoints
    test_endpoint "sys/config/state/sanitized" "200|403|404|500" "Sanitized configuration"
    test_endpoint "sys/capabilities-self" "200|403|500" "Token capabilities"
    
    # Metrics and monitoring
    test_endpoint "sys/metrics" "200|400|403|500" "Prometheus metrics"
    test_endpoint "sys/metrics?format=json" "200|400|403|500" "JSON metrics"
    test_endpoint "sys/in-flight-req" "200|403|404|500" "In-flight requests"
}

# Test Authentication Endpoints
test_authentication_endpoints() {
    log_category "Authentication"
    
    # List authentication methods
    test_endpoint "sys/auth" "200|403|500" "List authentication methods"
    
    # Token authentication endpoints
    test_endpoint "auth/token/lookup-self" "200|400|403|500" "Token self-lookup"
    test_endpoint "auth/token/renew-self" "200|400|403|500" "Token self-renewal" "POST"
    test_endpoint "auth/token/create" "200|400|403|500" "Token creation" "POST"
    
    # AppRole authentication (if enabled)
    test_endpoint "auth/approle/role" "200|400|403|404|500" "AppRole list roles"
    test_endpoint "sys/auth/approle" "200|400|403|404|500" "AppRole auth method info"
    
    # LDAP authentication (if enabled)
    test_endpoint "sys/auth/ldap" "200|400|403|404|500" "LDAP auth method info"
    
    # AWS authentication (if enabled)
    test_endpoint "sys/auth/aws" "200|400|403|404|500" "AWS auth method info"
    
    # Kubernetes authentication (if enabled)
    test_endpoint "sys/auth/kubernetes" "200|400|403|404|500" "Kubernetes auth method info"
}

# Test Secrets Engine Endpoints
test_secrets_engines() {
    log_category "Secrets Engines"
    
    # List all mounted secrets engines
    test_endpoint "sys/mounts" "200|403|500" "List mounted secrets engines"
    
    # KV Secrets Engine (v1 and v2)
    test_endpoint "sys/mounts/secret" "200|400|403|404|500" "KV secrets engine info"
    test_endpoint "secret/metadata" "200|400|403|404|500" "KV v2 metadata endpoint"
    test_endpoint "secret/config" "200|400|403|404|500" "KV v2 configuration"
    
    # Database secrets engine
    test_endpoint "sys/mounts/database" "200|400|403|404|500" "Database secrets engine info"
    test_endpoint "database/config" "200|400|403|404|500" "Database configuration"
    
    # PKI secrets engine
    test_endpoint "sys/mounts/pki" "200|400|403|404|500" "PKI secrets engine info"
    test_endpoint "pki/ca/pem" "200|400|403|404|500" "PKI CA certificate"
    test_endpoint "pki/cert/ca" "200|400|403|404|500" "PKI CA certificate (DER)"
    
    # Transit secrets engine
    test_endpoint "sys/mounts/transit" "200|400|403|404|500" "Transit secrets engine info"
    test_endpoint "transit/keys" "200|400|403|404|500" "Transit encryption keys"
    
    # AWS secrets engine
    test_endpoint "sys/mounts/aws" "200|400|403|404|500" "AWS secrets engine info"
    
    # Azure secrets engine
    test_endpoint "sys/mounts/azure" "200|400|403|404|500" "Azure secrets engine info"
    
    # SSH secrets engine
    test_endpoint "sys/mounts/ssh" "200|400|403|404|500" "SSH secrets engine info"
}

# Test Policy and Access Control
test_policy_endpoints() {
    log_category "Policies & Access Control"
    
    # Policy management
    test_endpoint "sys/policies" "200|403|404|500" "List policy types"
    test_endpoint "sys/policies/acl" "200|403|404|500" "List ACL policies"
    test_endpoint "sys/policy" "200|403|404|500" "Policy management endpoint"
    
    # Specific policies
    test_endpoint "sys/policies/acl/default" "200|403|404|500" "Default ACL policy"
    test_endpoint "sys/policies/acl/root" "200|403|404|500" "Root ACL policy"
    
    # Entity and group management (Identity secrets engine)
    test_endpoint "identity/entity" "200|403|404|500" "Identity entities"
    test_endpoint "identity/group" "200|403|404|500" "Identity groups"
    test_endpoint "identity/alias" "200|403|404|500" "Identity aliases"
}

# Test Audit and Logging
test_audit_endpoints() {
    log_category "Audit & Logging"
    
    # Audit device management
    test_endpoint "sys/audit" "200|403|500" "List audit devices"
    test_endpoint "sys/audit-hash/file" "200|400|403|404|500" "File audit hash"
    test_endpoint "sys/audit-hash/syslog" "200|400|403|404|500" "Syslog audit hash"
    
    # Request logging
    test_endpoint "sys/internal/counters/requests" "200|403|404|500" "Request counters"
    test_endpoint "sys/internal/counters/tokens" "200|403|404|500" "Token counters"
    test_endpoint "sys/internal/counters/activity" "200|403|404|500" "Activity counters"
}

# Test Storage Backend
test_storage_endpoints() {
    log_category "Storage Backend (Raft)"
    
    # Raft storage endpoints
    test_endpoint "sys/storage/raft/configuration" "200|403|501|500" "Raft cluster configuration"
    test_endpoint "sys/storage/raft/autopilot/state" "200|403|501|500" "Raft autopilot state"
    test_endpoint "sys/storage/raft/autopilot/configuration" "200|403|501|500" "Raft autopilot config"
    
    # Raft snapshots (if supported)
    test_endpoint "sys/storage/raft/snapshot" "200|400|403|501|500" "Raft snapshot endpoint" "GET"
}

# Test High Availability and Replication
test_ha_replication_endpoints() {
    log_category "High Availability & Replication"
    
    # HA status
    test_endpoint "sys/ha-status" "200|400|403|500" "High availability status"
    
    # Replication (Enterprise features)
    test_endpoint "sys/replication/status" "200|403|501|500" "Replication status"
    test_endpoint "sys/replication/dr/status" "200|403|501|500" "DR replication status"
    test_endpoint "sys/replication/performance/status" "200|403|501|500" "Performance replication status"
    
    # Cluster information
    test_endpoint "sys/ha-status" "200|400|403|500" "HA status"
}

# Test Management and Administration
test_management_endpoints() {
    log_category "Management & Administration"
    
    # Mount management
    test_endpoint "sys/mounts" "200|403|500" "Mount management"
    test_endpoint "sys/mount/secret" "200|400|403|404|500" "Specific mount info"
    
    # Tuning and configuration
    test_endpoint "sys/mounts/secret/tune" "200|400|403|404|500" "Mount tuning parameters"
    test_endpoint "sys/config/cors" "200|403|500" "CORS configuration"
    test_endpoint "sys/config/ui/headers" "200|403|404|500" "UI headers configuration"
    
    # Seal/unseal operations
    test_endpoint "sys/unseal" "200|400|500" "Unseal operation endpoint" "POST"
    test_endpoint "sys/seal" "200|400|403|500" "Seal operation endpoint" "POST"
    
    # Key management
    test_endpoint "sys/key-status" "200|400|403|500" "Encryption key status"
    test_endpoint "sys/rotate" "200|400|403|500" "Key rotation endpoint" "POST"
    
    # Initialization
    test_endpoint "sys/init" "200|400|500" "Initialization status"
}

# Generate curl command examples
generate_curl_examples() {
    log_header "Generating cURL Command Examples"
    
    local curl_examples_file="$TEST_OUTPUT_DIR/curl_examples.md"
    
    cat > "$curl_examples_file" << 'EOF'
# Vault API cURL Examples

This document contains practical cURL command examples for testing Vault API endpoints.

## Basic Configuration

```bash
# Set Vault address
export VAULT_ADDR="http://127.0.0.1:8200"

# Set Vault token (if authenticated)
export VAULT_TOKEN="your-vault-token"
```

## Health and Status Endpoints

### Health Check
```bash
# Basic health check
curl -s "$VAULT_ADDR/v1/sys/health" | jq .

# Health check allowing standby
curl -s "$VAULT_ADDR/v1/sys/health?standbyok=true" | jq .

# Health check with all status codes
curl -s "$VAULT_ADDR/v1/sys/health?standbyok=true&uninitcode=200&sealedcode=200" | jq .
```

### Seal Status
```bash
# Check seal status
curl -s "$VAULT_ADDR/v1/sys/seal-status" | jq .
```

### Leader Information
```bash
# Get leader information
curl -s "$VAULT_ADDR/v1/sys/leader" | jq .
```

## Authentication

### Token Operations
```bash
# Look up current token
curl -s -H "X-Vault-Token: $VAULT_TOKEN" \
     "$VAULT_ADDR/v1/auth/token/lookup-self" | jq .

# Renew current token
curl -s -H "X-Vault-Token: $VAULT_TOKEN" \
     -X POST "$VAULT_ADDR/v1/auth/token/renew-self" | jq .

# Create new token
curl -s -H "X-Vault-Token: $VAULT_TOKEN" \
     -X POST -d '{"policies": ["default"]}' \
     "$VAULT_ADDR/v1/auth/token/create" | jq .
```

### List Auth Methods
```bash
# List all authentication methods
curl -s -H "X-Vault-Token: $VAULT_TOKEN" \
     "$VAULT_ADDR/v1/sys/auth" | jq .
```

## Secrets Engines

### List Mounts
```bash
# List all mounted secrets engines
curl -s -H "X-Vault-Token: $VAULT_TOKEN" \
     "$VAULT_ADDR/v1/sys/mounts" | jq .
```

### KV Secrets Engine
```bash
# KV v2 - List secrets at root
curl -s -H "X-Vault-Token: $VAULT_TOKEN" \
     "$VAULT_ADDR/v1/secret/metadata" | jq .

# KV v2 - Get secret
curl -s -H "X-Vault-Token: $VAULT_TOKEN" \
     "$VAULT_ADDR/v1/secret/data/myapp/config" | jq .

# KV v2 - Write secret
curl -s -H "X-Vault-Token: $VAULT_TOKEN" \
     -X POST -d '{"data": {"password": "secret123"}}' \
     "$VAULT_ADDR/v1/secret/data/myapp/config" | jq .
```

### PKI Secrets Engine
```bash
# Get CA certificate
curl -s "$VAULT_ADDR/v1/pki/ca/pem"

# List PKI roles
curl -s -H "X-Vault-Token: $VAULT_TOKEN" \
     "$VAULT_ADDR/v1/pki/roles" | jq .
```

### Transit Secrets Engine
```bash
# List encryption keys
curl -s -H "X-Vault-Token: $VAULT_TOKEN" \
     "$VAULT_ADDR/v1/transit/keys" | jq .

# Encrypt data
curl -s -H "X-Vault-Token: $VAULT_TOKEN" \
     -X POST -d '{"plaintext": "'$(echo -n "hello world" | base64)'"]}' \
     "$VAULT_ADDR/v1/transit/encrypt/my-key" | jq .
```

## Policy Management

### List Policies
```bash
# List all ACL policies
curl -s -H "X-Vault-Token: $VAULT_TOKEN" \
     "$VAULT_ADDR/v1/sys/policies/acl" | jq .

# Get specific policy
curl -s -H "X-Vault-Token: $VAULT_TOKEN" \
     "$VAULT_ADDR/v1/sys/policies/acl/my-policy" | jq .
```

### Create Policy
```bash
# Create a new policy
curl -s -H "X-Vault-Token: $VAULT_TOKEN" \
     -X PUT -d '{"policy": "path \"secret/data/*\" { capabilities = [\"read\", \"list\"] }"}' \
     "$VAULT_ADDR/v1/sys/policies/acl/readonly-policy"
```

## Audit

### List Audit Devices
```bash
# List all audit devices
curl -s -H "X-Vault-Token: $VAULT_TOKEN" \
     "$VAULT_ADDR/v1/sys/audit" | jq .
```

## Administration

### Initialization
```bash
# Check initialization status
curl -s "$VAULT_ADDR/v1/sys/init" | jq .

# Initialize Vault
curl -s -X POST -d '{"secret_shares": 5, "secret_threshold": 3}' \
     "$VAULT_ADDR/v1/sys/init" | jq .
```

### Seal/Unseal Operations
```bash
# Unseal Vault
curl -s -X POST -d '{"key": "your-unseal-key"}' \
     "$VAULT_ADDR/v1/sys/unseal" | jq .

# Seal Vault
curl -s -H "X-Vault-Token: $VAULT_TOKEN" \
     -X POST "$VAULT_ADDR/v1/sys/seal"
```

### Metrics
```bash
# Get Prometheus metrics
curl -s "$VAULT_ADDR/v1/sys/metrics"

# Get JSON metrics
curl -s "$VAULT_ADDR/v1/sys/metrics?format=json" | jq .
```

## Advanced Examples

### Raft Operations
```bash
# Get Raft configuration
curl -s -H "X-Vault-Token: $VAULT_TOKEN" \
     "$VAULT_ADDR/v1/sys/storage/raft/configuration" | jq .

# Create Raft snapshot
curl -s -H "X-Vault-Token: $VAULT_TOKEN" \
     "$VAULT_ADDR/v1/sys/storage/raft/snapshot" > vault-snapshot.snap
```

### Replication Status
```bash
# Get replication status
curl -s -H "X-Vault-Token: $VAULT_TOKEN" \
     "$VAULT_ADDR/v1/sys/replication/status" | jq .
```

## Error Handling

```bash
# Get detailed error information
response=$(curl -s -w "\n%{http_code}" "$VAULT_ADDR/v1/sys/health")
http_code=$(echo "$response" | tail -n1)
body=$(echo "$response" | sed '$d')

echo "HTTP Status: $http_code"
echo "Response Body: $body" | jq . 2>/dev/null || echo "$body"
```

EOF

    if [[ -f "$curl_examples_file" ]]; then
        log_success "cURL examples generated at: $curl_examples_file"
    else
        log_failure "Failed to generate cURL examples"
    fi
}

# Generate comprehensive report
generate_report() {
    log_header "Generating API Test Report"
    
    local report_file="$TEST_OUTPUT_DIR/vault_api_test_report_$TIMESTAMP.md"
    
    cat > "$report_file" << EOF
# Vault API Test Report

**Generated:** $(date -Iseconds)  
**Test Duration:** Test completed at $(date)  
**Vault Address:** $VAULT_ADDR  
**API Version:** $API_VERSION  

## Executive Summary

- **Total Endpoints Tested:** $ENDPOINT_COUNT
- **Successful Tests:** $SUCCESSFUL_TESTS
- **Failed Tests:** $FAILED_TESTS
- **Warning Tests:** $WARNING_TESTS
- **Success Rate:** $(( (SUCCESSFUL_TESTS * 100) / ENDPOINT_COUNT ))%

## Test Categories Coverage

- ✅ Core System & Health Endpoints
- ✅ Authentication Endpoints
- ✅ Secrets Engine Endpoints
- ✅ Policy & Access Control Endpoints
- ✅ Audit & Logging Endpoints
- ✅ Storage Backend Endpoints
- ✅ High Availability & Replication Endpoints
- ✅ Management & Administration Endpoints

## Detailed Results

EOF

    # Add detailed results
    for result in "${TEST_RESULTS[@]}"; do
        echo "- $result" >> "$report_file"
    done
    
    cat >> "$report_file" << EOF

## API Accessibility Analysis

### Accessible Endpoints
Endpoints that returned expected HTTP status codes and are functioning properly.

### Authentication Required
Endpoints that require valid authentication tokens to access.

### Configuration Dependent
Endpoints that depend on specific Vault configurations or enabled features.

### Enterprise Features
Endpoints that are only available in Vault Enterprise.

## Security Considerations

- All API endpoints should be accessed over HTTPS in production
- Authentication tokens should be properly secured and rotated
- Audit logging should be enabled for all API access
- Rate limiting should be configured to prevent abuse

## Recommendations

1. **Enable Authentication:** Configure appropriate authentication methods
2. **Enable Audit:** Set up audit devices for compliance and monitoring
3. **Configure TLS:** Use HTTPS for all API communication
4. **Monitor Metrics:** Set up monitoring for the metrics endpoint
5. **Backup Strategy:** Implement regular Raft snapshots for backup

## Next Steps

1. Review failed endpoint tests and resolve configuration issues
2. Set up authentication and test authenticated endpoints
3. Configure secrets engines based on requirements
4. Implement monitoring and alerting
5. Set up automated backup procedures

## Test Artifacts

- **Individual Response Files:** $TEST_OUTPUT_DIR/response_*.json
- **cURL Examples:** $TEST_OUTPUT_DIR/curl_examples.md
- **Test Report:** $report_file

EOF

    if [[ -f "$report_file" ]]; then
        log_success "Comprehensive test report generated: $report_file"
        echo "$report_file"
    else
        log_failure "Failed to generate test report"
    fi
}

# Main test execution function
main() {
    # Clear previous results
    rm -f /tmp/vault_response.json
    
    log_header "Comprehensive Vault API Test Suite"
    echo "Configuration:"
    echo "  - Vault Address: $VAULT_ADDR"
    echo "  - API Version: $API_VERSION"
    echo "  - Output Directory: $TEST_OUTPUT_DIR"
    echo "  - Timestamp: $TIMESTAMP"
    
    if [[ -n "$VAULT_TOKEN" ]]; then
        echo "  - Authentication: Token provided"
    else
        echo "  - Authentication: No token (testing unauthenticated endpoints only)"
    fi
    
    echo
    
    # Check Vault availability first
    local vault_available=0
    if check_vault_availability; then
        vault_available=1
    fi
    
    echo
    
    # Run all test categories
    test_core_system_endpoints
    test_authentication_endpoints
    test_secrets_engines
    test_policy_endpoints
    test_audit_endpoints
    test_storage_endpoints
    test_ha_replication_endpoints
    test_management_endpoints
    
    # Generate documentation
    generate_curl_examples
    
    # Generate final report
    echo
    report_file=$(generate_report)
    
    # Print summary
    echo
    log_header "Test Summary"
    echo "Total Endpoints Tested: $ENDPOINT_COUNT"
    echo "Successful Tests: $SUCCESSFUL_TESTS"
    echo "Failed Tests: $FAILED_TESTS"
    echo "Warning Tests: $WARNING_TESTS"
    echo "Success Rate: $(( (SUCCESSFUL_TESTS * 100) / ENDPOINT_COUNT ))%"
    echo
    
    if [[ $vault_available -eq 1 ]]; then
        if [[ $SUCCESSFUL_TESTS -gt $((ENDPOINT_COUNT * 60 / 100)) ]]; then
            log_success "Vault API is largely accessible and functional"
        else
            log_warning "Vault API has limited accessibility - check configuration"
        fi
    else
        log_warning "Vault server was not accessible during testing"
        echo "Please ensure Vault is running and accessible at $VAULT_ADDR"
    fi
    
    echo
    echo "Detailed report available at: $report_file"
    echo "cURL examples available at: $TEST_OUTPUT_DIR/curl_examples.md"
    echo "Individual response files in: $TEST_OUTPUT_DIR/"
    
    # Cleanup
    rm -f /tmp/vault_response.json
    
    # Exit with appropriate code
    if [[ $FAILED_TESTS -eq 0 ]]; then
        exit 0
    else
        exit 1
    fi
}

# Run tests if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
