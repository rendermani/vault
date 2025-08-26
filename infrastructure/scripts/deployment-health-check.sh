#!/bin/bash
# Comprehensive Deployment Health Check Script
# Validates all aspects of the HashiCorp infrastructure deployment

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color

# Configuration
CONSUL_ADDR="http://localhost:8500"
NOMAD_ADDR="http://localhost:4646"
VAULT_ADDR="${VAULT_ADDR:-http://localhost:8200}"

# Health check results
HEALTH_RESULTS=()

# Logging functions
log_info() {
    echo -e "${BLUE}[HEALTH-CHECK]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
    HEALTH_RESULTS+=("✅ $1")
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
    HEALTH_RESULTS+=("⚠️  $1")
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
    HEALTH_RESULTS+=("❌ $1")
}

log_debug() {
    if [[ "${VERBOSE:-false}" == "true" ]]; then
        echo -e "${PURPLE}[DEBUG]${NC} $1"
    fi
}

# Check if service is running
check_service_status() {
    local service_name="$1"
    log_info "Checking $service_name systemd service status..."
    
    if systemctl is-active --quiet "$service_name"; then
        log_success "$service_name systemd service is active"
        return 0
    else
        log_error "$service_name systemd service is not active"
        log_error "$service_name service status:"
        systemctl status "$service_name" --no-pager --lines=10 || true
        return 1
    fi
}

# Check if service API is responding
check_api_health() {
    local service_name="$1"
    local endpoint="$2"
    local timeout="${3:-10}"
    
    log_info "Checking $service_name API health at $endpoint..."
    
    if curl -s --connect-timeout "$timeout" --max-time "$timeout" "$endpoint" >/dev/null 2>&1; then
        log_success "$service_name API is responding"
        return 0
    else
        log_error "$service_name API is not responding at $endpoint"
        return 1
    fi
}

# Check detailed Consul health
check_consul_health() {
    log_info "Performing detailed Consul health check..."
    
    local consul_healthy=true
    
    # Check systemd service
    if ! check_service_status "consul"; then
        consul_healthy=false
    fi
    
    # Check API health
    if ! check_api_health "Consul" "$CONSUL_ADDR/v1/status/leader"; then
        consul_healthy=false
    fi
    
    # Additional Consul checks
    if [[ "$consul_healthy" == "true" ]]; then
        # Check cluster members
        if curl -s "$CONSUL_ADDR/v1/status/peers" | jq -r '.[]' >/dev/null 2>&1; then
            local peer_count=$(curl -s "$CONSUL_ADDR/v1/status/peers" | jq -r '. | length')
            log_success "Consul cluster has $peer_count peer(s)"
        else
            log_warning "Could not retrieve Consul cluster peer information"
        fi
        
        # Check if leader is elected
        local leader=$(curl -s "$CONSUL_ADDR/v1/status/leader" 2>/dev/null)
        if [[ -n "$leader" && "$leader" != '""' ]]; then
            log_success "Consul leader elected: $leader"
        else
            log_error "Consul has no leader elected"
            consul_healthy=false
        fi
        
        # Check catalog services
        if curl -s "$CONSUL_ADDR/v1/catalog/services" >/dev/null 2>&1; then
            log_success "Consul catalog is accessible"
        else
            log_warning "Consul catalog is not accessible"
        fi
    fi
    
    return $([[ "$consul_healthy" == "true" ]] && echo 0 || echo 1)
}

# Check detailed Nomad health
check_nomad_health() {
    log_info "Performing detailed Nomad health check..."
    
    local nomad_healthy=true
    
    # Check systemd service
    if ! check_service_status "nomad"; then
        nomad_healthy=false
    fi
    
    # Check API health
    if ! check_api_health "Nomad" "$NOMAD_ADDR/v1/status/leader"; then
        nomad_healthy=false
    fi
    
    # Additional Nomad checks
    if [[ "$nomad_healthy" == "true" ]]; then
        # Check cluster members
        if curl -s "$NOMAD_ADDR/v1/status/peers" >/dev/null 2>&1; then
            local peer_count=$(curl -s "$NOMAD_ADDR/v1/status/peers" | jq -r '. | length')
            log_success "Nomad cluster has $peer_count peer(s)"
        else
            log_warning "Could not retrieve Nomad cluster peer information"
        fi
        
        # Check if leader is elected
        local leader=$(curl -s "$NOMAD_ADDR/v1/status/leader" 2>/dev/null)
        if [[ -n "$leader" && "$leader" != '""' ]]; then
            log_success "Nomad leader elected: $leader"
        else
            log_error "Nomad has no leader elected"
            nomad_healthy=false
        fi
        
        # Check node status
        if curl -s "$NOMAD_ADDR/v1/nodes" >/dev/null 2>&1; then
            local node_count=$(curl -s "$NOMAD_ADDR/v1/nodes" | jq -r '. | length')
            log_success "Nomad has $node_count node(s) registered"
            
            # Check node readiness
            local ready_nodes=$(curl -s "$NOMAD_ADDR/v1/nodes" | jq -r '[.[] | select(.Status == "ready")] | length')
            if [[ "$ready_nodes" -gt 0 ]]; then
                log_success "$ready_nodes Nomad node(s) are ready"
            else
                log_error "No Nomad nodes are ready"
                nomad_healthy=false
            fi
        else
            log_warning "Could not retrieve Nomad node information"
        fi
        
        # Check job status
        if curl -s "$NOMAD_ADDR/v1/jobs" >/dev/null 2>&1; then
            log_success "Nomad jobs API is accessible"
        else
            log_warning "Nomad jobs API is not accessible"
        fi
    fi
    
    return $([[ "$nomad_healthy" == "true" ]] && echo 0 || echo 1)
}

# Check Vault health (if deployed)
check_vault_health() {
    log_info "Checking Vault health..."
    
    # Check if Vault should be running (look for vault job in Nomad)
    local vault_should_be_running=false
    if curl -s "$NOMAD_ADDR/v1/jobs" 2>/dev/null | jq -r '.[].ID' | grep -q "vault"; then
        vault_should_be_running=true
    fi
    
    if [[ "$vault_should_be_running" == "true" ]]; then
        if check_api_health "Vault" "$VAULT_ADDR/v1/sys/health" 30; then
            # Get Vault status
            local vault_status=$(curl -s "$VAULT_ADDR/v1/sys/health" | jq -r '.initialized, .sealed')
            local initialized=$(echo "$vault_status" | head -n1)
            local sealed=$(echo "$vault_status" | tail -n1)
            
            log_success "Vault API is responding"
            
            if [[ "$initialized" == "true" ]]; then
                log_success "Vault is initialized"
            else
                log_warning "Vault is not initialized"
            fi
            
            if [[ "$sealed" == "false" ]]; then
                log_success "Vault is unsealed"
            else
                log_warning "Vault is sealed"
            fi
            
            return 0
        else
            log_error "Vault API is not responding"
            return 1
        fi
    else
        log_info "Vault not deployed or not running - skipping Vault health check"
        return 0
    fi
}

# Check Traefik health (if deployed)
check_traefik_health() {
    log_info "Checking Traefik health..."
    
    # Check if Traefik should be running (look for traefik job in Nomad)
    local traefik_should_be_running=false
    if curl -s "$NOMAD_ADDR/v1/jobs" 2>/dev/null | jq -r '.[].ID' | grep -q "traefik"; then
        traefik_should_be_running=true
    fi
    
    if [[ "$traefik_should_be_running" == "true" ]]; then
        if check_api_health "Traefik" "http://localhost:8080/ping" 10; then
            log_success "Traefik is responding"
            return 0
        else
            log_error "Traefik ping endpoint is not responding"
            return 1
        fi
    else
        log_info "Traefik not deployed or not running - skipping Traefik health check"
        return 0
    fi
}

# Check port availability
check_port_availability() {
    log_info "Checking port availability..."
    
    local ports=("8500:Consul" "4646:Nomad" "4647:Nomad-RPC" "4648:Nomad-Serf")
    
    for port_info in "${ports[@]}"; do
        local port="${port_info%:*}"
        local service="${port_info#*:}"
        
        if netstat -tlnp | grep -q ":$port "; then
            local process=$(netstat -tlnp | grep ":$port " | awk '{print $7}' | head -1)
            log_success "Port $port ($service) is in use by $process"
        else
            log_error "Port $port ($service) is not listening"
        fi
    done
}

# Check resource utilization
check_resource_utilization() {
    log_info "Checking resource utilization..."
    
    # Check memory usage
    local mem_total=$(free -m | awk '/^Mem:/{print $2}')
    local mem_used=$(free -m | awk '/^Mem:/{print $3}')
    local mem_percent=$((mem_used * 100 / mem_total))
    
    if [[ $mem_percent -lt 80 ]]; then
        log_success "Memory usage: ${mem_percent}% (${mem_used}MB / ${mem_total}MB)"
    else
        log_warning "High memory usage: ${mem_percent}% (${mem_used}MB / ${mem_total}MB)"
    fi
    
    # Check disk usage for data directories
    for dir in "/opt/consul/data" "/opt/nomad/data"; do
        if [[ -d "$dir" ]]; then
            local disk_usage=$(df -h "$dir" | awk 'NR==2 {print $5}' | sed 's/%//')
            if [[ $disk_usage -lt 80 ]]; then
                log_success "Disk usage for $dir: ${disk_usage}%"
            else
                log_warning "High disk usage for $dir: ${disk_usage}%"
            fi
        fi
    done
}

# Check log files for errors
check_log_files() {
    log_info "Checking recent log entries for errors..."
    
    # Check Consul logs
    local consul_errors=$(journalctl -u consul --since="5 minutes ago" | grep -i error | wc -l)
    if [[ $consul_errors -eq 0 ]]; then
        log_success "No recent Consul errors in logs"
    else
        log_warning "$consul_errors recent Consul errors found in logs"
    fi
    
    # Check Nomad logs
    local nomad_errors=$(journalctl -u nomad --since="5 minutes ago" | grep -i error | wc -l)
    if [[ $nomad_errors -eq 0 ]]; then
        log_success "No recent Nomad errors in logs"
    else
        log_warning "$nomad_errors recent Nomad errors found in logs"
    fi
}

# Generate health report summary
generate_health_report() {
    echo -e "${WHITE}================================================================================================${NC}"
    echo -e "${WHITE}DEPLOYMENT HEALTH CHECK SUMMARY${NC}"
    echo -e "${WHITE}================================================================================================${NC}"
    
    echo -e "${CYAN}Timestamp:${NC} $(date)"
    echo -e "${CYAN}Environment:${NC} ${ENVIRONMENT:-unknown}"
    echo ""
    
    local success_count=0
    local warning_count=0
    local error_count=0
    
    for result in "${HEALTH_RESULTS[@]}"; do
        echo "$result"
        if [[ "$result" == ✅* ]]; then
            ((success_count++))
        elif [[ "$result" == ⚠️* ]]; then
            ((warning_count++))
        elif [[ "$result" == ❌* ]]; then
            ((error_count++))
        fi
    done
    
    echo ""
    echo -e "${WHITE}Summary:${NC}"
    echo -e "  ${GREEN}Success: $success_count${NC}"
    echo -e "  ${YELLOW}Warnings: $warning_count${NC}"
    echo -e "  ${RED}Errors: $error_count${NC}"
    
    echo -e "${WHITE}================================================================================================${NC}"
    
    # Return exit code based on results
    if [[ $error_count -gt 0 ]]; then
        echo -e "${RED}Health check FAILED - $error_count critical errors found${NC}"
        return 1
    elif [[ $warning_count -gt 0 ]]; then
        echo -e "${YELLOW}Health check passed with $warning_count warnings${NC}"
        return 0
    else
        echo -e "${GREEN}Health check PASSED - all systems healthy${NC}"
        return 0
    fi
}

# Usage function
usage() {
    cat <<EOF
Deployment Health Check Script
Comprehensive validation of HashiCorp infrastructure deployment

Usage: $0 [OPTIONS]

Options:
  --consul-only     Check only Consul
  --nomad-only      Check only Nomad
  --skip-vault      Skip Vault health check
  --skip-traefik    Skip Traefik health check
  --verbose         Enable verbose debug output
  -h, --help        Show this help message

Examples:
  $0                    # Full health check
  $0 --consul-only      # Check only Consul
  $0 --skip-vault       # Skip Vault check
  $0 --verbose          # Verbose output

Exit Codes:
  0 - All checks passed (warnings allowed)
  1 - Critical errors found
EOF
}

# Main execution
main() {
    local check_consul=true
    local check_nomad=true
    local check_vault=true
    local check_traefik=true
    
    # Parse options
    while [[ $# -gt 0 ]]; do
        case $1 in
            --consul-only)
                check_nomad=false
                check_vault=false
                check_traefik=false
                shift
                ;;
            --nomad-only)
                check_consul=false
                check_vault=false
                check_traefik=false
                shift
                ;;
            --skip-vault)
                check_vault=false
                shift
                ;;
            --skip-traefik)
                check_traefik=false
                shift
                ;;
            --verbose)
                export VERBOSE=true
                shift
                ;;
            --help|-h)
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
    
    echo -e "${WHITE}================================================================================================${NC}"
    echo -e "${WHITE}DEPLOYMENT HEALTH CHECK${NC}"
    echo -e "${WHITE}================================================================================================${NC}"
    
    # Export environment variables for health checks
    export CONSUL_HTTP_ADDR="$CONSUL_ADDR"
    export NOMAD_ADDR="$NOMAD_ADDR"
    
    # Perform health checks
    if [[ "$check_consul" == "true" ]]; then
        check_consul_health || true
    fi
    
    if [[ "$check_nomad" == "true" ]]; then
        check_nomad_health || true
    fi
    
    if [[ "$check_vault" == "true" ]]; then
        check_vault_health || true
    fi
    
    if [[ "$check_traefik" == "true" ]]; then
        check_traefik_health || true
    fi
    
    # System-wide checks
    check_port_availability
    check_resource_utilization
    check_log_files
    
    # Generate final report
    generate_health_report
}

# Execute main function
main "$@"