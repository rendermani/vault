#!/bin/bash
# Comprehensive deployment verification script
# Verifies all components are working correctly
set -euo pipefail

# Configuration variables
ENVIRONMENT="${ENVIRONMENT:-production}"
NOMAD_NAMESPACE="${NOMAD_NAMESPACE:-default}"
NOMAD_REGION="${NOMAD_REGION:-global}"
DOMAIN_NAME="${DOMAIN_NAME:-cloudya.net}"
TIMEOUT="${TIMEOUT:-300}"
VERBOSE="${VERBOSE:-false}"
SKIP_EXTERNAL="${SKIP_EXTERNAL:-false}"
OUTPUT_FORMAT="${OUTPUT_FORMAT:-text}"

# Paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
LOGS_DIR="${PROJECT_ROOT}/logs"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Verification results
declare -A RESULTS
declare -a TESTS_RUN
declare -i TESTS_PASSED=0
declare -i TESTS_FAILED=0
declare -i TESTS_WARNING=0

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "${LOGS_DIR}/verify-deployment.log"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "${LOGS_DIR}/verify-deployment.log"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "${LOGS_DIR}/verify-deployment.log"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "${LOGS_DIR}/verify-deployment.log"
}

log_test() {
    echo -e "${PURPLE}[TEST]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "${LOGS_DIR}/verify-deployment.log"
}

log_detail() {
    if [[ "$VERBOSE" == "true" ]]; then
        echo -e "${CYAN}[DETAIL]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "${LOGS_DIR}/verify-deployment.log"
    fi
}

# Usage information
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Comprehensive deployment verification script"
    echo ""
    echo "Options:"
    echo "  -e, --environment ENV     Environment (develop|staging|production) [default: production]"
    echo "  -n, --namespace NS        Nomad namespace [default: default]"
    echo "  -r, --region REGION       Nomad region [default: global]"
    echo "  -d, --domain DOMAIN       Domain name [default: cloudya.net]"
    echo "  -t, --timeout SECONDS     Timeout for tests [default: 300]"
    echo "  -v, --verbose            Enable verbose output"
    echo "  --skip-external          Skip external connectivity tests"
    echo "  --output FORMAT          Output format (text|json|junit) [default: text]"
    echo "  -h, --help               Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 --environment production"
    echo "  $0 --environment staging --verbose"
    echo "  $0 --skip-external --output json"
    echo ""
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -e|--environment)
                ENVIRONMENT="$2"
                shift 2
                ;;
            -n|--namespace)
                NOMAD_NAMESPACE="$2"
                shift 2
                ;;
            -r|--region)
                NOMAD_REGION="$2"
                shift 2
                ;;
            -d|--domain)
                DOMAIN_NAME="$2"
                shift 2
                ;;
            -t|--timeout)
                TIMEOUT="$2"
                shift 2
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            --skip-external)
                SKIP_EXTERNAL=true
                shift
                ;;
            --output)
                OUTPUT_FORMAT="$2"
                shift 2
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
}

# Setup directories and logging
setup_environment() {
    mkdir -p "$LOGS_DIR"
    
    # Clear previous test results
    RESULTS=()
    TESTS_RUN=()
    TESTS_PASSED=0
    TESTS_FAILED=0
    TESTS_WARNING=0
}

# Record test result
record_test() {
    local test_name="$1"
    local result="$2"
    local message="$3"
    
    TESTS_RUN+=("$test_name")
    RESULTS["$test_name"]="$result:$message"
    
    case "$result" in
        "PASS")
            ((TESTS_PASSED++))
            log_success "✓ $test_name: $message"
            ;;
        "FAIL")
            ((TESTS_FAILED++))
            log_error "✗ $test_name: $message"
            ;;
        "WARN")
            ((TESTS_WARNING++))
            log_warning "⚠ $test_name: $message"
            ;;
    esac
}

# Check if command is available
check_command() {
    local cmd="$1"
    if command -v "$cmd" &> /dev/null; then
        return 0
    else
        return 1
    fi
}

# Test Prerequisites
test_prerequisites() {
    log_test "Checking prerequisites..."
    
    local missing_commands=()
    local required_commands=("nomad" "curl" "jq")
    
    for cmd in "${required_commands[@]}"; do
        if ! check_command "$cmd"; then
            missing_commands+=("$cmd")
        fi
    done
    
    if [[ ${#missing_commands[@]} -eq 0 ]]; then
        record_test "prerequisites" "PASS" "All required commands available"
    else
        record_test "prerequisites" "FAIL" "Missing commands: ${missing_commands[*]}"
        return 1
    fi
}

# Test Nomad connectivity
test_nomad_connectivity() {
    log_test "Testing Nomad connectivity..."
    
    if nomad node status &> /dev/null; then
        local nodes
        nodes=$(nomad node status | grep -c "ready" || echo "0")
        record_test "nomad_connectivity" "PASS" "Connected to Nomad cluster ($nodes nodes ready)"
        
        # Get additional details
        if [[ "$VERBOSE" == "true" ]]; then
            log_detail "Nomad server info:"
            nomad server members 2>/dev/null || log_detail "Single node or client-only setup"
        fi
    else
        record_test "nomad_connectivity" "FAIL" "Cannot connect to Nomad cluster"
        return 1
    fi
}

# Test Consul connectivity (if available)
test_consul_connectivity() {
    log_test "Testing Consul connectivity..."
    
    if check_command "consul"; then
        if consul members &> /dev/null; then
            local members
            members=$(consul members | grep -c "alive" || echo "0")
            record_test "consul_connectivity" "PASS" "Connected to Consul cluster ($members members alive)"
        else
            record_test "consul_connectivity" "WARN" "Consul CLI available but cannot connect to cluster"
        fi
    else
        record_test "consul_connectivity" "WARN" "Consul CLI not available (optional)"
    fi
}

# Test Vault connectivity (if available)
test_vault_connectivity() {
    log_test "Testing Vault connectivity..."
    
    if check_command "vault"; then
        # Try different endpoints based on environment
        local vault_endpoints
        case "$ENVIRONMENT" in
            develop)
                vault_endpoints=("http://localhost:8200")
                ;;
            staging)
                vault_endpoints=("https://localhost:8210" "https://vault-staging.$DOMAIN_NAME")
                ;;
            production)
                vault_endpoints=("https://localhost:8220" "https://vault.$DOMAIN_NAME")
                ;;
        esac
        
        local vault_accessible=false
        local vault_endpoint=""
        
        for endpoint in "${vault_endpoints[@]}"; do
            export VAULT_ADDR="$endpoint"
            if [[ "$ENVIRONMENT" != "develop" ]]; then
                export VAULT_SKIP_VERIFY=true
            fi
            
            if timeout 10 vault status &> /dev/null; then
                vault_accessible=true
                vault_endpoint="$endpoint"
                break
            fi
        done
        
        if [[ "$vault_accessible" == "true" ]]; then
            local vault_status
            vault_status=$(vault status 2>/dev/null || echo "unknown")
            record_test "vault_connectivity" "PASS" "Vault accessible at $vault_endpoint"
            
            if [[ "$VERBOSE" == "true" ]]; then
                log_detail "Vault status: $vault_status"
            fi
        else
            record_test "vault_connectivity" "WARN" "Vault not accessible (may need initialization)"
        fi
    else
        record_test "vault_connectivity" "WARN" "Vault CLI not available (optional)"
    fi
}

# Test Nomad job status
test_nomad_jobs() {
    log_test "Testing Nomad jobs status..."
    
    local jobs_to_check=()
    case "$ENVIRONMENT" in
        develop)
            jobs_to_check=("vault-develop" "traefik")
            ;;
        staging)
            jobs_to_check=("vault-staging" "traefik")
            ;;
        production)
            jobs_to_check=("vault-production" "traefik")
            ;;
    esac
    
    local all_jobs_healthy=true
    local job_status_details=""
    
    for job in "${jobs_to_check[@]}"; do
        log_detail "Checking job: $job"
        
        if nomad job status -namespace="$NOMAD_NAMESPACE" "$job" &> /dev/null; then
            local status
            status=$(nomad job status -namespace="$NOMAD_NAMESPACE" "$job" | grep "Status" | awk '{print $3}' || echo "unknown")
            
            if [[ "$status" == "running" ]]; then
                # Check allocation health
                local healthy_allocs failed_allocs
                healthy_allocs=$(nomad job status -namespace="$NOMAD_NAMESPACE" "$job" | grep -c "running" || echo "0")
                failed_allocs=$(nomad job status -namespace="$NOMAD_NAMESPACE" "$job" | grep -c "failed" || echo "0")
                
                job_status_details+="$job: $status ($healthy_allocs running, $failed_allocs failed); "
                
                if [[ "$failed_allocs" -gt 0 ]]; then
                    all_jobs_healthy=false
                fi
            else
                job_status_details+="$job: $status; "
                all_jobs_healthy=false
            fi
        else
            job_status_details+="$job: not found; "
            all_jobs_healthy=false
        fi
    done
    
    if [[ "$all_jobs_healthy" == "true" ]]; then
        record_test "nomad_jobs" "PASS" "All jobs running: ${job_status_details}"
    else
        record_test "nomad_jobs" "FAIL" "Some jobs unhealthy: ${job_status_details}"
    fi
}

# Test service endpoints
test_service_endpoints() {
    log_test "Testing service endpoints..."
    
    local endpoints_to_test=()
    
    # HTTP endpoints (should redirect to HTTPS)
    endpoints_to_test+=("http://localhost:80/ping:Traefik HTTP")
    
    # HTTPS endpoints
    endpoints_to_test+=("https://localhost:443/ping:Traefik HTTPS")
    
    # Service-specific endpoints based on environment
    case "$ENVIRONMENT" in
        develop)
            endpoints_to_test+=("http://localhost:8200/v1/sys/health:Vault")
            endpoints_to_test+=("http://localhost:4646/v1/status/leader:Nomad")
            ;;
        staging)
            endpoints_to_test+=("https://localhost:8210/v1/sys/health:Vault")
            endpoints_to_test+=("http://localhost:4646/v1/status/leader:Nomad")
            ;;
        production)
            endpoints_to_test+=("https://localhost:8220/v1/sys/health:Vault")
            endpoints_to_test+=("http://localhost:4646/v1/status/leader:Nomad")
            ;;
    esac
    
    local all_endpoints_ok=true
    local endpoint_results=""
    
    for endpoint_info in "${endpoints_to_test[@]}"; do
        local endpoint="${endpoint_info%%:*}"
        local name="${endpoint_info##*:}"
        
        log_detail "Testing endpoint: $endpoint ($name)"
        
        local response_code
        response_code=$(curl -k -s -o /dev/null -w "%{http_code}" --connect-timeout 10 --max-time 30 "$endpoint" 2>/dev/null || echo "000")
        
        if [[ "$response_code" =~ ^[23] ]]; then
            endpoint_results+="$name: $response_code OK; "
        else
            endpoint_results+="$name: $response_code ERROR; "
            all_endpoints_ok=false
        fi
    done
    
    if [[ "$all_endpoints_ok" == "true" ]]; then
        record_test "service_endpoints" "PASS" "All endpoints responding: ${endpoint_results}"
    else
        record_test "service_endpoints" "FAIL" "Some endpoints failing: ${endpoint_results}"
    fi
}

# Test TLS certificates
test_tls_certificates() {
    log_test "Testing TLS certificates..."
    
    if [[ "$SKIP_EXTERNAL" == "true" ]]; then
        record_test "tls_certificates" "WARN" "Skipped (--skip-external flag)"
        return 0
    fi
    
    local domains_to_check=()
    domains_to_check+=("traefik.$DOMAIN_NAME")
    
    if [[ "$ENVIRONMENT" != "develop" ]]; then
        domains_to_check+=("vault.$DOMAIN_NAME")
        domains_to_check+=("nomad.$DOMAIN_NAME")
    fi
    
    local all_certs_ok=true
    local cert_results=""
    
    for domain in "${domains_to_check[@]}"; do
        log_detail "Checking certificate for: $domain"
        
        # Check if we can connect and get certificate info
        local cert_info
        cert_info=$(echo | timeout 10 openssl s_client -servername "$domain" -connect "localhost:443" 2>/dev/null | openssl x509 -noout -subject -dates 2>/dev/null || echo "ERROR")
        
        if [[ "$cert_info" != "ERROR" ]] && [[ "$cert_info" != "" ]]; then
            # Extract expiry date
            local expiry
            expiry=$(echo "$cert_info" | grep "notAfter" | cut -d= -f2 || echo "unknown")
            cert_results+="$domain: Valid (expires $expiry); "
        else
            cert_results+="$domain: Invalid or unreachable; "
            all_certs_ok=false
        fi
    done
    
    if [[ "$all_certs_ok" == "true" ]]; then
        record_test "tls_certificates" "PASS" "All certificates valid: ${cert_results}"
    else
        record_test "tls_certificates" "WARN" "Some certificate issues: ${cert_results}"
    fi
}

# Test file permissions and storage
test_file_permissions() {
    log_test "Testing file permissions and storage..."
    
    local critical_paths=()
    critical_paths+=("/opt/nomad/volumes")
    
    local all_permissions_ok=true
    local permission_results=""
    
    for path in "${critical_paths[@]}"; do
        if [[ -d "$path" ]]; then
            # Check if we can read the directory
            if sudo ls -la "$path" &> /dev/null; then
                permission_results+="$path: accessible; "
                
                # Check specific subdirectories if they exist
                if [[ -d "$path/traefik-certs" ]]; then
                    local acme_file="$path/traefik-certs/acme.json"
                    if [[ -f "$acme_file" ]]; then
                        local perms
                        perms=$(sudo stat -c "%a" "$acme_file" 2>/dev/null || echo "unknown")
                        if [[ "$perms" == "600" ]]; then
                            permission_results+="acme.json: secure ($perms); "
                        else
                            permission_results+="acme.json: insecure ($perms); "
                            all_permissions_ok=false
                        fi
                    fi
                fi
            else
                permission_results+="$path: not accessible; "
                all_permissions_ok=false
            fi
        else
            permission_results+="$path: not found; "
            all_permissions_ok=false
        fi
    done
    
    if [[ "$all_permissions_ok" == "true" ]]; then
        record_test "file_permissions" "PASS" "File permissions correct: ${permission_results}"
    else
        record_test "file_permissions" "WARN" "Permission issues found: ${permission_results}"
    fi
}

# Test DNS resolution
test_dns_resolution() {
    log_test "Testing DNS resolution..."
    
    if [[ "$SKIP_EXTERNAL" == "true" ]]; then
        record_test "dns_resolution" "WARN" "Skipped (--skip-external flag)"
        return 0
    fi
    
    local domains_to_resolve=()
    domains_to_resolve+=("$DOMAIN_NAME")
    domains_to_resolve+=("traefik.$DOMAIN_NAME")
    
    if [[ "$ENVIRONMENT" != "develop" ]]; then
        domains_to_resolve+=("vault.$DOMAIN_NAME")
        domains_to_resolve+=("nomad.$DOMAIN_NAME")
    fi
    
    local all_dns_ok=true
    local dns_results=""
    
    for domain in "${domains_to_resolve[@]}"; do
        log_detail "Resolving DNS for: $domain"
        
        local ip
        ip=$(dig +short "$domain" 2>/dev/null | tail -n1 || echo "")
        
        if [[ -n "$ip" ]] && [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            dns_results+="$domain: $ip; "
        else
            dns_results+="$domain: no resolution; "
            all_dns_ok=false
        fi
    done
    
    if [[ "$all_dns_ok" == "true" ]]; then
        record_test "dns_resolution" "PASS" "All domains resolve: ${dns_results}"
    else
        record_test "dns_resolution" "WARN" "DNS issues found: ${dns_results}"
    fi
}

# Test system resources
test_system_resources() {
    log_test "Testing system resources..."
    
    local resource_ok=true
    local resource_info=""
    
    # Check disk space
    local disk_usage
    disk_usage=$(df /opt 2>/dev/null | awk 'NR==2 {print $5}' | sed 's/%//' || echo "unknown")
    
    if [[ "$disk_usage" != "unknown" ]] && [[ "$disk_usage" -lt 90 ]]; then
        resource_info+="disk: ${disk_usage}% used; "
    elif [[ "$disk_usage" != "unknown" ]]; then
        resource_info+="disk: ${disk_usage}% used (HIGH); "
        resource_ok=false
    else
        resource_info+="disk: unknown; "
    fi
    
    # Check memory
    local mem_available
    mem_available=$(free | awk 'NR==2{printf "%.1f", $7/$2*100}' 2>/dev/null || echo "unknown")
    
    if [[ "$mem_available" != "unknown" ]]; then
        resource_info+="memory: ${mem_available}% available; "
        if (( $(echo "$mem_available < 10" | bc -l) )); then
            resource_ok=false
        fi
    else
        resource_info+="memory: unknown; "
    fi
    
    # Check load average
    local load_avg
    load_avg=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | sed 's/,//' 2>/dev/null || echo "unknown")
    
    if [[ "$load_avg" != "unknown" ]]; then
        resource_info+="load: $load_avg; "
    else
        resource_info+="load: unknown; "
    fi
    
    if [[ "$resource_ok" == "true" ]]; then
        record_test "system_resources" "PASS" "System resources healthy: ${resource_info}"
    else
        record_test "system_resources" "WARN" "Resource concerns: ${resource_info}"
    fi
}

# Test network connectivity
test_network_connectivity() {
    log_test "Testing network connectivity..."
    
    local connectivity_ok=true
    local connectivity_info=""
    
    # Test localhost connectivity
    if curl -s http://localhost:80/ping &> /dev/null || curl -k -s https://localhost:443/ping &> /dev/null; then
        connectivity_info+="localhost: OK; "
    else
        connectivity_info+="localhost: FAIL; "
        connectivity_ok=false
    fi
    
    # Test external connectivity (if not skipped)
    if [[ "$SKIP_EXTERNAL" != "true" ]]; then
        if curl -s --connect-timeout 10 https://google.com &> /dev/null; then
            connectivity_info+="external: OK; "
        else
            connectivity_info+="external: FAIL; "
            connectivity_ok=false
        fi
    else
        connectivity_info+="external: SKIPPED; "
    fi
    
    if [[ "$connectivity_ok" == "true" ]]; then
        record_test "network_connectivity" "PASS" "Network connectivity good: ${connectivity_info}"
    else
        record_test "network_connectivity" "FAIL" "Network issues: ${connectivity_info}"
    fi
}

# Generate output in different formats
generate_output() {
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case "$OUTPUT_FORMAT" in
        "json")
            generate_json_output "$timestamp"
            ;;
        "junit")
            generate_junit_output "$timestamp"
            ;;
        "text"|*)
            generate_text_output "$timestamp"
            ;;
    esac
}

# Generate text output
generate_text_output() {
    local timestamp="$1"
    
    echo ""
    echo "====================================================================="
    echo "DEPLOYMENT VERIFICATION SUMMARY"
    echo "====================================================================="
    echo "Timestamp: $timestamp"
    echo "Environment: $ENVIRONMENT"
    echo "Domain: $DOMAIN_NAME"
    echo "Namespace: $NOMAD_NAMESPACE"
    echo "Region: $NOMAD_REGION"
    echo ""
    echo "Test Results:"
    echo "  Total Tests: ${#TESTS_RUN[@]}"
    echo "  Passed: $TESTS_PASSED"
    echo "  Failed: $TESTS_FAILED"
    echo "  Warnings: $TESTS_WARNING"
    echo ""
    
    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo -e "${GREEN}✓ OVERALL STATUS: HEALTHY${NC}"
    elif [[ $TESTS_FAILED -le 2 ]]; then
        echo -e "${YELLOW}⚠ OVERALL STATUS: DEGRADED${NC}"
    else
        echo -e "${RED}✗ OVERALL STATUS: UNHEALTHY${NC}"
    fi
    
    echo ""
    echo "Detailed Results:"
    echo "=================="
    
    for test_name in "${TESTS_RUN[@]}"; do
        local result="${RESULTS[$test_name]}"
        local status="${result%%:*}"
        local message="${result#*:}"
        
        case "$status" in
            "PASS")
                echo -e "  ${GREEN}✓${NC} $test_name: $message"
                ;;
            "FAIL")
                echo -e "  ${RED}✗${NC} $test_name: $message"
                ;;
            "WARN")
                echo -e "  ${YELLOW}⚠${NC} $test_name: $message"
                ;;
        esac
    done
    
    echo ""
    echo "====================================================================="
}

# Generate JSON output
generate_json_output() {
    local timestamp="$1"
    
    cat <<EOF
{
  "verification_summary": {
    "timestamp": "$timestamp",
    "environment": "$ENVIRONMENT",
    "domain": "$DOMAIN_NAME",
    "namespace": "$NOMAD_NAMESPACE",
    "region": "$NOMAD_REGION",
    "test_stats": {
      "total": ${#TESTS_RUN[@]},
      "passed": $TESTS_PASSED,
      "failed": $TESTS_FAILED,
      "warnings": $TESTS_WARNING
    },
    "overall_status": $(if [[ $TESTS_FAILED -eq 0 ]]; then echo '"HEALTHY"'; elif [[ $TESTS_FAILED -le 2 ]]; then echo '"DEGRADED"'; else echo '"UNHEALTHY"'; fi)
  },
  "test_results": {
EOF
    
    local first=true
    for test_name in "${TESTS_RUN[@]}"; do
        if [[ "$first" == "false" ]]; then
            echo ","
        fi
        first=false
        
        local result="${RESULTS[$test_name]}"
        local status="${result%%:*}"
        local message="${result#*:}"
        
        echo -n "    \"$test_name\": {"
        echo -n "\"status\": \"$status\", "
        echo -n "\"message\": \"$message\""
        echo -n "}"
    done
    
    echo ""
    echo "  }"
    echo "}"
}

# Generate JUnit XML output
generate_junit_output() {
    local timestamp="$1"
    
    cat <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<testsuite name="Deployment Verification" 
           tests="${#TESTS_RUN[@]}" 
           failures="$TESTS_FAILED" 
           warnings="$TESTS_WARNING"
           timestamp="$timestamp">
EOF
    
    for test_name in "${TESTS_RUN[@]}"; do
        local result="${RESULTS[$test_name]}"
        local status="${result%%:*}"
        local message="${result#*:}"
        
        echo "  <testcase name=\"$test_name\" classname=\"DeploymentVerification\">"
        
        case "$status" in
            "FAIL")
                echo "    <failure message=\"$message\"/>"
                ;;
            "WARN")
                echo "    <warning message=\"$message\"/>"
                ;;
        esac
        
        echo "  </testcase>"
    done
    
    echo "</testsuite>"
}

# Main verification function
main() {
    log_info "=== Deployment Verification Script ==="
    log_info "Environment: $ENVIRONMENT"
    log_info "Domain: $DOMAIN_NAME"
    log_info "Namespace: $NOMAD_NAMESPACE"
    log_info "Region: $NOMAD_REGION"
    log_info "Timeout: $TIMEOUT seconds"
    log_info "Verbose: $VERBOSE"
    log_info "Skip External: $SKIP_EXTERNAL"
    log_info "Output Format: $OUTPUT_FORMAT"
    
    setup_environment
    
    # Run all verification tests
    test_prerequisites || true
    test_nomad_connectivity || true
    test_consul_connectivity || true
    test_vault_connectivity || true
    test_nomad_jobs || true
    test_service_endpoints || true
    test_tls_certificates || true
    test_file_permissions || true
    test_dns_resolution || true
    test_system_resources || true
    test_network_connectivity || true
    
    # Generate output
    generate_output
    
    # Exit with appropriate code
    if [[ $TESTS_FAILED -eq 0 ]]; then
        log_success "=== All critical tests passed! ==="
        exit 0
    elif [[ $TESTS_FAILED -le 2 ]]; then
        log_warning "=== Some tests failed but deployment is functional ==="
        exit 1
    else
        log_error "=== Critical failures detected! ==="
        exit 2
    fi
}

# Parse arguments and run main function
parse_args "$@"
main "$@"