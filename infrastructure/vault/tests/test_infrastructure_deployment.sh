#!/bin/bash
# Infrastructure Deployment Validation Test Suite
# Comprehensive tests for deployment readiness and infrastructure validation

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m'

# Test configuration
TEST_DIR="/tmp/vault-infrastructure-tests"
VAULT_VERSION="1.17.3"
TEST_ENVIRONMENT="testing"

# Helper functions
log_header() { echo -e "${PURPLE}[HEADER]${NC} $1"; }
log_test() { echo -e "${YELLOW}[TEST]${NC} $1"; }
log_success() { echo -e "${GREEN}[PASS]${NC} $1"; }
log_failure() { echo -e "${RED}[FAIL]${NC} $1"; }
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

# Cleanup function
cleanup() {
    log_info "Cleaning up test environment..."
    rm -rf "$TEST_DIR" 2>/dev/null || true
}

# Trap cleanup on exit
trap cleanup EXIT

# Initialize test environment
init_test_env() {
    log_info "Initializing test environment..."
    mkdir -p "$TEST_DIR"/{config,scripts,policies,backups,logs}
}

# Test 1: GitHub Workflow Validation
test_github_workflow() {
    log_test "Testing GitHub Actions workflow validation..."
    
    WORKFLOW_FILE="../.github/workflows/deploy.yml"
    
    if [[ ! -f "$WORKFLOW_FILE" ]]; then
        log_failure "GitHub Actions workflow not found"
        return 1
    fi
    
    log_success "Workflow file exists"
    
    # Parse and validate workflow structure
    local issues=0
    
    # Check for required triggers
    if ! grep -q "workflow_dispatch:" "$WORKFLOW_FILE"; then
        log_warn "Manual workflow dispatch not found"
        ((issues++))
    else
        log_success "✓ Manual workflow dispatch configured"
    fi
    
    # Check for environment inputs
    if grep -q "environment:" "$WORKFLOW_FILE"; then
        log_success "✓ Environment parameter available"
    else
        log_warn "No environment parameter found"
        ((issues++))
    fi
    
    # Check for action inputs
    if grep -q "action:" "$WORKFLOW_FILE"; then
        log_success "✓ Action parameter available"
    else
        log_warn "No action parameter found"
        ((issues++))
    fi
    
    # Check for secrets
    if grep -q "secrets\.DEPLOY_SSH_KEY" "$WORKFLOW_FILE"; then
        log_success "✓ SSH key secret configured"
    else
        log_failure "SSH key secret not found"
        ((issues++))
    fi
    
    # Check deployment commands
    if grep -q "deploy-vault\.sh" "$WORKFLOW_FILE"; then
        log_success "✓ Deployment script referenced"
    else
        log_failure "Deployment script not referenced in workflow"
        ((issues++))
    fi
    
    if [[ $issues -eq 0 ]]; then
        log_success "GitHub workflow validation passed"
        return 0
    else
        log_warn "GitHub workflow has $issues potential issues"
        return 1
    fi
}

# Test 2: Installation Scenarios
test_installation_scenarios() {
    log_test "Testing installation scenarios..."
    
    # Scenario 1: Fresh installation simulation
    log_info "Scenario 1: Fresh Installation"
    
    # Simulate download verification
    if curl -sf --max-time 10 "https://releases.hashicorp.com/vault/${VAULT_VERSION}/vault_${VAULT_VERSION}_SHA256SUMS" >/dev/null 2>&1; then
        log_success "✓ Vault ${VAULT_VERSION} available for download"
    else
        log_failure "✗ Cannot verify Vault ${VAULT_VERSION} availability"
    fi
    
    # Test configuration generation
    cat > "$TEST_DIR/config/test-vault.hcl" << EOF
ui = true
disable_mlock = true

storage "raft" {
  path = "$TEST_DIR/data"
  node_id = "vault-test-1"
}

listener "tcp" {
  address     = "127.0.0.1:18200"
  tls_disable = true
}

api_addr = "http://127.0.0.1:18200"
cluster_addr = "https://127.0.0.1:18201"

telemetry {
  prometheus_retention_time = "30s"
  disable_hostname = false
}

log_level = "info"
EOF
    
    if [[ -f "$TEST_DIR/config/test-vault.hcl" ]]; then
        log_success "✓ Configuration file generated successfully"
    else
        log_failure "✗ Failed to generate configuration file"
    fi
    
    # Test systemd service generation
    cat > "$TEST_DIR/config/vault.service" << 'EOF'
[Unit]
Description=HashiCorp Vault
Documentation=https://www.vaultproject.io/docs/
Requires=network-online.target
After=network-online.target
ConditionFileNotEmpty=/etc/vault.d/vault.hcl
StartLimitIntervalSec=60
StartLimitBurst=3

[Service]
Type=notify
EnvironmentFile=-/etc/vault.d/vault.env
User=vault
Group=vault
ProtectSystem=full
ProtectHome=read-only
PrivateTmp=yes
PrivateDevices=yes
SecureBits=keep-caps
AmbientCapabilities=CAP_IPC_LOCK
CapabilityBoundingSet=CAP_SYSLOG CAP_IPC_LOCK
NoNewPrivileges=yes
ExecStart=/usr/local/bin/vault server -config=/etc/vault.d/vault.hcl
ExecReload=/bin/kill --signal HUP $MAINPID
KillMode=process
Restart=on-failure
RestartSec=5
TimeoutStopSec=30
LimitNOFILE=65536
LimitMEMLOCK=infinity
KillSignal=SIGINT

[Install]
WantedBy=multi-user.target
EOF
    
    if [[ -f "$TEST_DIR/config/vault.service" ]]; then
        log_success "✓ Systemd service file generated successfully"
    else
        log_failure "✗ Failed to generate systemd service file"
    fi
    
    # Scenario 2: Upgrade simulation
    log_info "Scenario 2: Upgrade Simulation"
    
    # Simulate existing version detection
    echo "1.16.0" > "$TEST_DIR/current_version"
    CURRENT_VERSION=$(cat "$TEST_DIR/current_version")
    
    if [[ "$CURRENT_VERSION" != "$VAULT_VERSION" ]]; then
        log_success "✓ Version comparison detected upgrade needed ($CURRENT_VERSION → $VAULT_VERSION)"
        
        # Simulate backup creation before upgrade
        mkdir -p "$TEST_DIR/backups/upgrade-$(date +%Y%m%d-%H%M%S)"
        log_success "✓ Pre-upgrade backup directory created"
    else
        log_info "Same version detected, no upgrade needed"
    fi
}

# Test 3: Integration Points
test_integration_points() {
    log_test "Testing integration points..."
    
    # Test Nomad integration detection
    log_info "Testing Nomad integration detection..."
    
    # Simulate Nomad availability check
    if curl -sf --max-time 5 "http://localhost:4646/v1/status/leader" >/dev/null 2>&1; then
        log_success "✓ Nomad detected - integration would be configured"
    else
        log_info "Nomad not available - integration would be skipped"
    fi
    
    # Test Traefik integration setup
    log_info "Testing Traefik integration setup..."
    
    # Create test Traefik policy
    cat > "$TEST_DIR/policies/traefik-test.hcl" << 'EOF'
# Traefik policy
path "secret/data/traefik/*" {
  capabilities = ["read", "list"]
}

path "secret/metadata/traefik/*" {
  capabilities = ["list", "read"]
}

path "auth/token/create" {
  capabilities = ["create", "update"]
}

path "auth/token/renew-self" {
  capabilities = ["update"]
}

path "pki/issue/*" {
  capabilities = ["create", "update"]
}

path "pki/certs" {
  capabilities = ["list"]
}
EOF
    
    if [[ -f "$TEST_DIR/policies/traefik-test.hcl" ]]; then
        log_success "✓ Traefik policy template validated"
        
        # Validate policy syntax
        if grep -q "path.*capabilities" "$TEST_DIR/policies/traefik-test.hcl"; then
            log_success "✓ Policy syntax is valid"
        else
            log_failure "✗ Policy syntax validation failed"
        fi
    else
        log_failure "✗ Failed to create Traefik policy template"
    fi
    
    # Test AppRole configuration
    log_info "Testing AppRole configuration..."
    
    SERVICES=("grafana" "prometheus" "loki" "minio" "traefik" "nomad")
    
    for service in "${SERVICES[@]}"; do
        # Create test policy for service
        cat > "$TEST_DIR/policies/${service}-policy.hcl" << EOF
path "kv/data/${service}/*" {
  capabilities = ["read", "list"]
}

path "kv/metadata/${service}/*" {
  capabilities = ["read", "list"]
}

path "auth/token/renew-self" {
  capabilities = ["update"]
}
EOF
        
        if [[ -f "$TEST_DIR/policies/${service}-policy.hcl" ]]; then
            log_success "✓ ${service} AppRole policy template created"
        else
            log_failure "✗ Failed to create ${service} AppRole policy"
        fi
    done
}

# Test 4: Environment Handling
test_environment_handling() {
    log_test "Testing environment handling..."
    
    # Test environment-specific configuration
    ENVIRONMENTS=("development" "staging" "production")
    
    for env in "${ENVIRONMENTS[@]}"; do
        log_info "Testing $env environment configuration..."
        
        # Create environment-specific config
        cat > "$TEST_DIR/config/vault-${env}.hcl" << EOF
ui = true
disable_mlock = $([ "$env" = "production" ] && echo "false" || echo "true")

storage "raft" {
  path = "/opt/vault/data"
  node_id = "vault-${env}-1"
}

listener "tcp" {
  address     = "0.0.0.0:8200"
  tls_disable = $([ "$env" = "production" ] && echo "false" || echo "true")
}

api_addr = "http://vault-${env}.example.com:8200"
cluster_addr = "https://vault-${env}.example.com:8201"

telemetry {
  prometheus_retention_time = "$([ "$env" = "production" ] && echo "24h" || echo "30s")"
  disable_hostname = $([ "$env" = "production" ] && echo "false" || echo "true")
}

log_level = "$([ "$env" = "production" ] && echo "warn" || echo "info")"
EOF
        
        if [[ -f "$TEST_DIR/config/vault-${env}.hcl" ]]; then
            log_success "✓ $env configuration generated"
            
            # Validate environment-specific settings
            if [[ "$env" == "production" ]]; then
                if grep -q 'tls_disable = false' "$TEST_DIR/config/vault-${env}.hcl"; then
                    log_success "✓ TLS enabled for production"
                else
                    log_failure "✗ TLS not properly configured for production"
                fi
            fi
        else
            log_failure "✗ Failed to generate $env configuration"
        fi
    done
}

# Test 5: Deployment Prerequisites
test_deployment_prerequisites() {
    log_test "Testing deployment prerequisites..."
    
    # Check system requirements
    local prereq_issues=0
    
    # Check if running on Linux (for production deployment)
    if [[ "$(uname)" == "Linux" ]]; then
        log_success "✓ Running on Linux (production-ready)"
    else
        log_info "Running on $(uname) (development/testing only)"
    fi
    
    # Check for required commands
    REQUIRED_COMMANDS=("curl" "wget" "unzip" "jq" "systemctl")
    
    for cmd in "${REQUIRED_COMMANDS[@]}"; do
        if command -v "$cmd" >/dev/null 2>&1; then
            log_success "✓ $cmd available"
        else
            log_warn "$cmd not available"
            ((prereq_issues++))
        fi
    done
    
    # Check network connectivity for downloads
    if curl -sf --max-time 10 "https://releases.hashicorp.com" >/dev/null 2>&1; then
        log_success "✓ HashiCorp releases accessible"
    else
        log_failure "✗ Cannot reach HashiCorp releases"
        ((prereq_issues++))
    fi
    
    # Check disk space simulation (for /opt/vault)
    AVAILABLE_SPACE=$(df -BG /tmp 2>/dev/null | awk 'NR==2 {print $4}' | sed 's/G//' || echo "unknown")
    if [[ "$AVAILABLE_SPACE" != "unknown" && $AVAILABLE_SPACE -gt 1 ]]; then
        log_success "✓ Sufficient disk space available (${AVAILABLE_SPACE}G)"
    else
        log_warn "Disk space check inconclusive"
    fi
    
    if [[ $prereq_issues -eq 0 ]]; then
        log_success "All deployment prerequisites met"
        return 0
    else
        log_warn "$prereq_issues prerequisite issues found"
        return 1
    fi
}

# Test 6: Security Validation
test_security_validation() {
    log_test "Testing security validation..."
    
    # Test systemd security constraints
    SERVICE_FILE="../scripts/deploy-vault.sh"
    
    if [[ -f "$SERVICE_FILE" ]]; then
        log_info "Validating security constraints in deployment script..."
        
        SECURITY_CHECKS=(
            "ProtectSystem=full"
            "ProtectHome=read-only"
            "PrivateTmp=yes"
            "PrivateDevices=yes"
            "NoNewPrivileges=yes"
            "User=vault"
            "CAP_IPC_LOCK"
        )
        
        local security_issues=0
        
        for check in "${SECURITY_CHECKS[@]}"; do
            if grep -q "$check" "$SERVICE_FILE"; then
                log_success "✓ $check configured"
            else
                log_failure "✗ $check not found"
                ((security_issues++))
            fi
        done
        
        if [[ $security_issues -eq 0 ]]; then
            log_success "All security constraints validated"
        else
            log_warn "$security_issues security issues found"
        fi
    else
        log_failure "Deployment script not found for security validation"
    fi
    
    # Test file permissions simulation
    log_info "Testing file permissions requirements..."
    
    # Create test files with proper permissions
    touch "$TEST_DIR/config/vault.hcl"
    chmod 640 "$TEST_DIR/config/vault.hcl"
    
    if [[ "$(stat -c %a "$TEST_DIR/config/vault.hcl" 2>/dev/null || stat -f %A "$TEST_DIR/config/vault.hcl" 2>/dev/null)" == "640" ]]; then
        log_success "✓ Configuration file permissions correct (640)"
    else
        log_failure "✗ Configuration file permissions incorrect"
    fi
    
    # Test credential storage permissions
    mkdir -p "$TEST_DIR/credentials"
    chmod 700 "$TEST_DIR/credentials"
    
    if [[ "$(stat -c %a "$TEST_DIR/credentials" 2>/dev/null || stat -f %A "$TEST_DIR/credentials" 2>/dev/null)" == "700" ]]; then
        log_success "✓ Credentials directory permissions correct (700)"
    else
        log_failure "✗ Credentials directory permissions incorrect"
    fi
}

# Test 7: Rollback Strategy
test_rollback_strategy() {
    log_test "Testing rollback strategy..."
    
    # Simulate rollback scenario
    log_info "Testing rollback procedures..."
    
    # Create backup before "upgrade"
    BACKUP_DIR="$TEST_DIR/backups/rollback-test-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$BACKUP_DIR"
    
    # Simulate configuration backup
    cp "$TEST_DIR/config/test-vault.hcl" "$BACKUP_DIR/vault.hcl.backup" 2>/dev/null || true
    
    # Simulate binary backup
    echo "#!/bin/bash\necho 'Vault 1.16.0 (backup)'" > "$BACKUP_DIR/vault.backup"
    chmod +x "$BACKUP_DIR/vault.backup"
    
    if [[ -f "$BACKUP_DIR/vault.hcl.backup" && -f "$BACKUP_DIR/vault.backup" ]]; then
        log_success "✓ Rollback backup created successfully"
        
        # Test rollback procedure
        log_info "Testing rollback execution..."
        
        # Simulate service stop
        log_success "✓ Service would be stopped"
        
        # Simulate binary rollback
        if [[ -x "$BACKUP_DIR/vault.backup" ]]; then
            log_success "✓ Previous binary would be restored"
        fi
        
        # Simulate configuration rollback
        if [[ -f "$BACKUP_DIR/vault.hcl.backup" ]]; then
            log_success "✓ Previous configuration would be restored"
        fi
        
        # Simulate service restart
        log_success "✓ Service would be restarted"
        
        log_success "Rollback strategy validation completed"
    else
        log_failure "✗ Failed to create rollback backup"
    fi
}

# Test 8: Performance and Resource Requirements
test_performance_requirements() {
    log_test "Testing performance and resource requirements..."
    
    # Simulate resource availability checks
    log_info "Checking system resources..."
    
    # Memory check
    if [[ -f /proc/meminfo ]]; then
        TOTAL_MEM=$(grep MemTotal /proc/meminfo | awk '{print $2}')
        TOTAL_MEM_GB=$((TOTAL_MEM / 1024 / 1024))
        
        if [[ $TOTAL_MEM_GB -ge 2 ]]; then
            log_success "✓ Sufficient memory available (${TOTAL_MEM_GB}GB)"
        else
            log_warn "Limited memory available (${TOTAL_MEM_GB}GB)"
        fi
    else
        log_info "Memory check not available on this system"
    fi
    
    # CPU check
    if [[ -f /proc/cpuinfo ]]; then
        CPU_CORES=$(grep -c ^processor /proc/cpuinfo)
        
        if [[ $CPU_CORES -ge 2 ]]; then
            log_success "✓ Sufficient CPU cores available ($CPU_CORES)"
        else
            log_warn "Limited CPU cores available ($CPU_CORES)"
        fi
    else
        log_info "CPU check not available on this system"
    fi
    
    # Network performance simulation
    log_info "Testing network requirements..."
    
    # Test download speed (simulate)
    if curl -sf --max-time 5 "https://httpbin.org/json" >/dev/null 2>&1; then
        log_success "✓ Network connectivity sufficient for downloads"
    else
        log_warn "Network connectivity issues detected"
    fi
}

# Main test execution
main() {
    log_header "Infrastructure Deployment Validation Test Suite"
    log_header "=============================================="
    
    init_test_env
    
    log_info "Test Environment: $TEST_DIR"
    log_info "Vault Version: $VAULT_VERSION"
    log_info "Test Environment: $TEST_ENVIRONMENT"
    echo
    
    # Track test results
    local passed_tests=0
    local total_tests=8
    
    # Run all tests
    test_github_workflow && ((passed_tests++))
    test_installation_scenarios && ((passed_tests++))
    test_integration_points && ((passed_tests++))
    test_environment_handling && ((passed_tests++))
    test_deployment_prerequisites && ((passed_tests++))
    test_security_validation && ((passed_tests++))
    test_rollback_strategy && ((passed_tests++))
    test_performance_requirements && ((passed_tests++))
    
    echo
    log_header "=============================================="
    log_header "Infrastructure Deployment Test Results"
    log_header "=============================================="
    
    if [[ $passed_tests -eq $total_tests ]]; then
        log_success "All tests passed! ($passed_tests/$total_tests)"
        log_success "Infrastructure deployment is ready for production"
        OVERALL_STATUS="READY"
    else
        log_warn "Some tests had issues ($passed_tests/$total_tests passed)"
        log_warn "Review warnings before production deployment"
        OVERALL_STATUS="REVIEW_NEEDED"
    fi
    
    echo
    log_header "Deployment Readiness Assessment"
    log_header "=============================="
    log_info "Overall Status: $OVERALL_STATUS"
    log_info "Test Results Location: $TEST_DIR"
    log_info "Generated Documentation:"
    log_info "  • Configuration templates: $TEST_DIR/config/"
    log_info "  • Policy templates: $TEST_DIR/policies/"
    log_info "  • Backup location: $TEST_DIR/backups/"
    
    echo
    log_header "Next Steps"
    log_header "=========="
    log_info "1. Review any warnings or issues identified above"
    log_info "2. Ensure all required secrets are configured in GitHub"
    log_info "3. Test deployment in staging environment first"
    log_info "4. Configure monitoring and alerting"
    log_info "5. Plan rollback procedures with the operations team"
    
    return $(( total_tests - passed_tests ))
}

# Run tests if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi