#!/bin/bash
# Vault API Endpoint Test Suite
# Tests all critical API endpoints for accessibility and functionality

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Test configuration
VAULT_ADDR=${VAULT_ADDR:-"http://127.0.0.1:8200"}
API_VERSION="v1"
TEST_RESULTS=()
ENDPOINT_COUNT=0
SUCCESSFUL_TESTS=0

# Helper functions
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
}

log_failure() {
    echo -e "${RED}  ✗${NC} $1"
    TEST_RESULTS+=("❌ $1")
}

# Function to test an endpoint
test_endpoint() {
    local endpoint=$1
    local expected_codes=$2
    local description=$3
    
    log_endpoint "$endpoint"
    
    RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" "$VAULT_ADDR/$API_VERSION/$endpoint" 2>/dev/null)
    
    if echo "$expected_codes" | grep -q "$RESPONSE"; then
        log_success "$description (HTTP $RESPONSE)"
        return 0
    else
        log_failure "$description (HTTP $RESPONSE)"
        return 1
    fi
}

# Function to test endpoint with data
test_endpoint_with_data() {
    local endpoint=$1
    local method=$2
    local data=$3
    local expected_codes=$4
    local description=$5
    
    log_endpoint "$endpoint [$method]"
    
    if [[ "$method" == "GET" ]]; then
        RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" "$VAULT_ADDR/$API_VERSION/$endpoint" 2>/dev/null)
    else
        RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" -X "$method" \
            -H "Content-Type: application/json" \
            -d "$data" \
            "$VAULT_ADDR/$API_VERSION/$endpoint" 2>/dev/null)
    fi
    
    if echo "$expected_codes" | grep -q "$RESPONSE"; then
        log_success "$description (HTTP $RESPONSE)"
        return 0
    else
        log_failure "$description (HTTP $RESPONSE)"
        return 1
    fi
}

# Main test execution
main() {
    echo "========================================="
    echo "Vault API Endpoint Test Suite"
    echo "========================================="
    echo "Configuration:"
    echo "  - Vault Address: $VAULT_ADDR"
    echo "  - API Version: $API_VERSION"
    echo "========================================="
    echo
    
    # Category: System Health
    echo -e "${BLUE}[Category] System Health & Status${NC}"
    test_endpoint "sys/health" "200|429|473|501|503" "Health check endpoint"
    test_endpoint "sys/seal-status" "200|400" "Seal status endpoint"
    test_endpoint "sys/leader" "200" "Leader information endpoint"
    test_endpoint "sys/host-info" "200|400|403" "Host information endpoint"
    
    # Category: Authentication
    echo -e "\n${BLUE}[Category] Authentication${NC}"
    test_endpoint "sys/auth" "200|403" "List auth methods"
    test_endpoint "auth/token/lookup-self" "200|403" "Token self-lookup"
    test_endpoint "auth/token/renew-self" "200|403" "Token self-renewal"
    
    # Category: Secrets Engines
    echo -e "\n${BLUE}[Category] Secrets Engines${NC}"
    test_endpoint "sys/mounts" "200|403" "List mounted secrets engines"
    test_endpoint "sys/mounts/secret" "200|400|403|404" "Check KV secrets engine"
    test_endpoint "sys/mounts/database" "200|400|403|404" "Check database secrets engine"
    test_endpoint "sys/mounts/pki" "200|400|403|404" "Check PKI secrets engine"
    test_endpoint "sys/mounts/transit" "200|400|403|404" "Check transit secrets engine"
    
    # Category: Policies
    echo -e "\n${BLUE}[Category] Policies${NC}"
    test_endpoint "sys/policies" "200|403|404" "List policy types"
    test_endpoint "sys/policies/acl" "200|403|404" "List ACL policies"
    test_endpoint "sys/policy" "200|403|404" "Policy management endpoint"
    
    # Category: Audit
    echo -e "\n${BLUE}[Category] Audit${NC}"
    test_endpoint "sys/audit" "200|403" "List audit devices"
    test_endpoint "sys/audit-hash/file" "200|400|403|404" "Audit hash endpoint"
    
    # Category: Storage/Raft
    echo -e "\n${BLUE}[Category] Storage Backend (Raft)${NC}"
    test_endpoint "sys/storage/raft/configuration" "200|403|501" "Raft configuration"
    test_endpoint "sys/storage/raft/autopilot/state" "200|403|501" "Raft autopilot state"
    
    # Category: Metrics & Monitoring
    echo -e "\n${BLUE}[Category] Metrics & Monitoring${NC}"
    test_endpoint "sys/metrics" "200|400|403" "Metrics endpoint"
    test_endpoint "sys/in-flight-req" "200|403|404" "In-flight requests"
    test_endpoint "sys/internal/counters/activity" "200|403|404" "Activity counters"
    test_endpoint "sys/internal/counters/requests" "200|403|404" "Request counters"
    
    # Category: License & Version
    echo -e "\n${BLUE}[Category] License & Version${NC}"
    test_endpoint "sys/license/status" "200|403|404" "License status"
    test_endpoint "sys/version-history" "200|403|404" "Version history"
    
    # Category: Replication (Enterprise)
    echo -e "\n${BLUE}[Category] Replication (Enterprise Features)${NC}"
    test_endpoint "sys/replication/status" "200|403|501" "Replication status"
    test_endpoint "sys/replication/dr/status" "200|403|501" "DR replication status"
    test_endpoint "sys/replication/performance/status" "200|403|501" "Performance replication status"
    
    # Test with authentication if token is provided
    if [[ -n "$VAULT_TOKEN" ]]; then
        echo -e "\n${BLUE}[Category] Authenticated Endpoints${NC}"
        
        # Test with auth header
        log_endpoint "sys/capabilities-self [AUTH]"
        RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" \
            -H "X-Vault-Token: $VAULT_TOKEN" \
            "$VAULT_ADDR/$API_VERSION/sys/capabilities-self" 2>/dev/null)
        
        if [[ "$RESPONSE" == "200" ]]; then
            log_success "Token capabilities check (HTTP $RESPONSE)"
        else
            log_warning "Token capabilities check failed (HTTP $RESPONSE) - token may be invalid"
        fi
    else
        echo -e "\n${YELLOW}[INFO]${NC} Set VAULT_TOKEN environment variable to test authenticated endpoints"
    fi
    
    # Test specific endpoints that should always work
    echo -e "\n${BLUE}[Category] Essential Endpoints (Must Work)${NC}"
    
    # Health endpoint with detailed check
    log_endpoint "sys/health [DETAILED]"
    HEALTH_DATA=$(curl -s "$VAULT_ADDR/$API_VERSION/sys/health" 2>/dev/null)
    if [[ -n "$HEALTH_DATA" ]]; then
        # Try to parse JSON response
        if command -v jq &> /dev/null; then
            INITIALIZED=$(echo "$HEALTH_DATA" | jq -r '.initialized' 2>/dev/null)
            SEALED=$(echo "$HEALTH_DATA" | jq -r '.sealed' 2>/dev/null)
            STANDBY=$(echo "$HEALTH_DATA" | jq -r '.standby' 2>/dev/null)
            VERSION=$(echo "$HEALTH_DATA" | jq -r '.version' 2>/dev/null)
            
            if [[ -n "$VERSION" ]]; then
                log_success "Vault version: $VERSION"
            fi
            if [[ "$INITIALIZED" == "true" ]]; then
                log_success "Vault is initialized"
            elif [[ "$INITIALIZED" == "false" ]]; then
                log_warning "Vault is not initialized"
            fi
            if [[ "$SEALED" == "false" ]]; then
                log_success "Vault is unsealed"
            elif [[ "$SEALED" == "true" ]]; then
                log_warning "Vault is sealed"
            fi
            if [[ "$STANDBY" == "false" ]]; then
                log_success "Vault is active (not standby)"
            elif [[ "$STANDBY" == "true" ]]; then
                log_warning "Vault is in standby mode"
            fi
        else
            log_success "Health endpoint responding with data"
        fi
    else
        log_failure "Health endpoint not returning data"
    fi
    
    # Print summary
    echo
    echo "========================================="
    echo "API Test Summary"
    echo "========================================="
    echo "Total Endpoints Tested: $ENDPOINT_COUNT"
    echo "Successful Tests: $SUCCESSFUL_TESTS"
    echo "Success Rate: $(( (SUCCESSFUL_TESTS * 100) / ENDPOINT_COUNT ))%"
    echo "========================================="
    
    # Print detailed results
    echo -e "\n${BLUE}Detailed Results:${NC}"
    for result in "${TEST_RESULTS[@]}"; do
        echo "  $result"
    done
    
    echo
    echo "========================================="
    
    if [[ $SUCCESSFUL_TESTS -eq $ENDPOINT_COUNT ]]; then
        echo -e "${GREEN}All API endpoints are accessible!${NC}"
        exit 0
    elif [[ $SUCCESSFUL_TESTS -gt $((ENDPOINT_COUNT / 2)) ]]; then
        echo -e "${YELLOW}Most API endpoints are accessible${NC}"
        echo "Some endpoints may require authentication or initialization"
        exit 0
    else
        echo -e "${RED}Many API endpoints are not accessible${NC}"
        echo "Please check Vault configuration and status"
        exit 1
    fi
}

# Run tests if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi