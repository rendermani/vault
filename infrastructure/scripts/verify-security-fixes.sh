#!/bin/bash

# Security Fixes Verification Script
# Verifies all critical security issues have been remediated

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_DIR="$(dirname "$SCRIPT_DIR")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "=== VERIFYING CRITICAL SECURITY FIXES ==="
echo

# Initialize counters
PASSED=0
FAILED=0

# Check TLS configuration
echo "1. TLS Configuration:"
if grep -q 'api_addr = "https://' "$INFRA_DIR/vault/config/vault.hcl"; then
    echo -e "   ${GREEN}✅ HTTPS API address configured${NC}"
    ((PASSED++))
else
    echo -e "   ${RED}❌ HTTP still configured for API${NC}"
    ((FAILED++))
fi

if grep -q 'tls_disable   = false' "$INFRA_DIR/vault/config/vault.hcl"; then
    echo -e "   ${GREEN}✅ TLS enabled in listener${NC}"
    ((PASSED++))
else
    echo -e "   ${RED}❌ TLS still disabled${NC}"
    ((FAILED++))
fi

# Check bootstrap cleanup
echo "2. Bootstrap Token Security:"
if grep -q "secure_cleanup" "$INFRA_DIR/scripts/unified-bootstrap.sh"; then
    echo -e "   ${GREEN}✅ Secure cleanup implemented${NC}"
    ((PASSED++))
else
    echo -e "   ${RED}❌ Secure cleanup not found${NC}"
    ((FAILED++))
fi

if grep -q "mktemp -d" "$INFRA_DIR/scripts/unified-bootstrap.sh"; then
    echo -e "   ${GREEN}✅ Using secure temporary directory${NC}"
    ((PASSED++))
else
    echo -e "   ${RED}❌ Not using secure temp directory${NC}"
    ((FAILED++))
fi

if grep -q "shred -vfz -n 3" "$INFRA_DIR/scripts/unified-bootstrap.sh"; then
    echo -e "   ${GREEN}✅ Secure file deletion with shred${NC}"
    ((PASSED++))
else
    echo -e "   ${RED}❌ Not using secure file deletion${NC}"
    ((FAILED++))
fi

# Check network binding
echo "3. Network Security:"
if grep -q 'address.*127.0.0.1:8200' "$INFRA_DIR/vault/config/vault.hcl"; then
    echo -e "   ${GREEN}✅ Vault bound to localhost${NC}"
    ((PASSED++))
else
    echo -e "   ${RED}❌ Vault still bound to all interfaces${NC}"
    ((FAILED++))
fi

if grep -q 'bind_addr = "127.0.0.1"' "$INFRA_DIR/nomad/config/nomad-server.hcl"; then
    echo -e "   ${GREEN}✅ Nomad bound to localhost${NC}"
    ((PASSED++))
else
    echo -e "   ${RED}❌ Nomad still bound to all interfaces${NC}"
    ((FAILED++))
fi

# Check audit logging
echo "4. Audit Logging:"
if grep -q '^audit "file"' "$INFRA_DIR/vault/config/vault.hcl"; then
    echo -e "   ${GREEN}✅ File audit enabled${NC}"
    ((PASSED++))
else
    echo -e "   ${RED}❌ File audit still disabled${NC}"
    ((FAILED++))
fi

if grep -q '^audit "syslog"' "$INFRA_DIR/vault/config/vault.hcl"; then
    echo -e "   ${GREEN}✅ Syslog audit enabled${NC}"
    ((PASSED++))
else
    echo -e "   ${RED}❌ Syslog audit still disabled${NC}"
    ((FAILED++))
fi

# Production configuration check
echo "5. Production Configuration:"
PROD_CONFIG="$INFRA_DIR/vault/config/environments/production.hcl"
if [[ -f "$PROD_CONFIG" ]]; then
    if grep -q 'tls_min_version = "tls13"' "$PROD_CONFIG"; then
        echo -e "   ${GREEN}✅ Production uses TLS 1.3${NC}"
        ((PASSED++))
    else
        echo -e "   ${RED}❌ Production not using TLS 1.3${NC}"
        ((FAILED++))
    fi
    
    if grep -q 'tls_require_and_verify_client_cert = true' "$PROD_CONFIG"; then
        echo -e "   ${GREEN}✅ Production uses mutual TLS${NC}"
        ((PASSED++))
    else
        echo -e "   ${RED}❌ Production not using mutual TLS${NC}"
        ((FAILED++))
    fi
else
    echo -e "   ${YELLOW}⚠️ Production config not found${NC}"
fi

echo
echo "=== FIX VERIFICATION COMPLETE ==="
echo -e "Passed: ${GREEN}$PASSED${NC}"
echo -e "Failed: ${RED}$FAILED${NC}"

if [[ $FAILED -eq 0 ]]; then
    echo -e "${GREEN}✅ All critical security fixes have been applied!${NC}"
    echo
    echo "Infrastructure is ready for deployment testing."
    exit 0
else
    echo -e "${RED}❌ Some security fixes are missing. Please review and fix.${NC}"
    exit 1
fi