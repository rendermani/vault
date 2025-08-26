#!/usr/bin/env bash
#
# 🔍 CLOUDYA VAULT HEALTH CHECK SCRIPT
#
# This script performs comprehensive health checks on the deployed infrastructure
#

set -euo pipefail

readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

readonly REMOTE_SERVER="${REMOTE_SERVER:-cloudya.net}"
readonly REMOTE_USER="${REMOTE_USER:-root}"

log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case "$level" in
        "INFO")  echo -e "${BLUE}[INFO]${NC}  ${timestamp} - $message" ;;
        "WARN")  echo -e "${YELLOW}[WARN]${NC}  ${timestamp} - $message" ;;
        "ERROR") echo -e "${RED}[ERROR]${NC} ${timestamp} - $message" ;;
        "SUCCESS") echo -e "${GREEN}[SUCCESS]${NC} ${timestamp} - $message" ;;
    esac
}

check_ssh_connectivity() {
    log "INFO" "Checking SSH connectivity to $REMOTE_SERVER..."
    
    if ssh -o ConnectTimeout=10 -o BatchMode=yes "$REMOTE_USER@$REMOTE_SERVER" 'echo "SSH OK"' &>/dev/null; then
        log "SUCCESS" "SSH connectivity: OK"
        return 0
    else
        log "ERROR" "SSH connectivity: FAILED"
        return 1
    fi
}

check_services() {
    log "INFO" "Checking service status..."
    
    ssh "$REMOTE_USER@$REMOTE_SERVER" << 'EOF'
set -euo pipefail

echo "=== SERVICE STATUS ==="

services=("consul" "nomad" "docker")
for service in "${services[@]}"; do
    if systemctl is-active --quiet "$service" 2>/dev/null; then
        echo "✅ $service: RUNNING"
        
        # Additional service-specific checks
        case "$service" in
            "consul")
                if curl -s -f http://localhost:8500/v1/status/leader >/dev/null; then
                    echo "  ✅ Consul API: RESPONSIVE"
                    
                    # Check cluster members
                    member_count=$(curl -s http://localhost:8500/v1/agent/members | jq '. | length' 2>/dev/null || echo "0")
                    echo "  ✅ Cluster members: $member_count"
                else
                    echo "  ❌ Consul API: NOT RESPONSIVE"
                fi
                ;;
            "nomad")
                if curl -s -f http://localhost:4646/v1/status/leader >/dev/null; then
                    echo "  ✅ Nomad API: RESPONSIVE"
                    
                    # Check node status
                    if command -v nomad &>/dev/null; then
                        node_count=$(nomad node status -short 2>/dev/null | grep -c ready || echo "0")
                        echo "  ✅ Ready nodes: $node_count"
                        
                        job_count=$(nomad job status 2>/dev/null | grep -c running || echo "0")
                        echo "  ✅ Running jobs: $job_count"
                    fi
                else
                    echo "  ❌ Nomad API: NOT RESPONSIVE"
                fi
                ;;
            "docker")
                containers=$(docker ps -q | wc -l 2>/dev/null || echo "0")
                echo "  ✅ Running containers: $containers"
                ;;
        esac
    else
        echo "❌ $service: NOT RUNNING"
    fi
done

echo ""
echo "=== NETWORK PORTS ==="
netstat -tlnp 2>/dev/null | grep -E ":(22|4646|8500|8200|8080)" | while read line; do
    port=$(echo "$line" | awk '{print $4}' | cut -d: -f2)
    case "$port" in
        "22") echo "✅ SSH (22): LISTENING" ;;
        "4646") echo "✅ Nomad (4646): LISTENING" ;;
        "8500") echo "✅ Consul (8500): LISTENING" ;;
        "8200") echo "✅ Vault (8200): LISTENING" ;;
        "8080") echo "✅ Traefik (8080): LISTENING" ;;
    esac
done

echo ""
echo "=== SYSTEM RESOURCES ==="
echo "CPU Load: $(uptime | awk -F'load average:' '{print $2}')"
echo "Memory: $(free -h | grep Mem | awk '{print "Used: "$3" / "$2" ("$3/$2*100"%)"}')"
echo "Disk: $(df -h / | tail -1 | awk '{print "Used: "$3" / "$2" ("$5")"}')"

echo ""
echo "=== DEPLOYMENT STATE ==="
if [[ -f /opt/infrastructure/state/deployment-complete ]]; then
    echo "✅ Deployment state file exists"
    echo "Last deployment info:"
    cat /opt/infrastructure/state/deployment-complete | jq -r '
        "  Environment: " + .environment + "\n" +
        "  Strategy: " + .strategy + "\n" +
        "  Timestamp: " + .timestamp + "\n" +
        "  Workflow: " + .workflow_run
    ' 2>/dev/null || cat /opt/infrastructure/state/deployment-complete
else
    echo "⚠️ No deployment state file found"
fi
EOF
}

check_connectivity() {
    log "INFO" "Checking external connectivity..."
    
    ssh "$REMOTE_USER@$REMOTE_SERVER" << 'EOF'
set -euo pipefail

echo "=== CONNECTIVITY TESTS ==="

# DNS resolution
if nslookup google.com >/dev/null 2>&1; then
    echo "✅ DNS resolution: OK"
else
    echo "❌ DNS resolution: FAILED"
fi

# External connectivity
if curl -s -m 5 https://google.com >/dev/null; then
    echo "✅ External HTTPS: OK"
else
    echo "❌ External HTTPS: FAILED"
fi

# GitHub connectivity (for updates)
if curl -s -m 5 https://api.github.com/zen >/dev/null; then
    echo "✅ GitHub API: OK"
else
    echo "❌ GitHub API: FAILED"
fi

# HashiCorp registry (for Nomad packs)
if curl -s -m 5 https://registry.nomadproject.io >/dev/null; then
    echo "✅ Nomad Registry: OK"
else
    echo "⚠️ Nomad Registry: FAILED (may affect pack deployments)"
fi
EOF
}

run_health_check() {
    echo -e "\n${BLUE}════════════════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  🔍 CLOUDYA VAULT INFRASTRUCTURE HEALTH CHECK${NC}"
    echo -e "${BLUE}════════════════════════════════════════════════════════════════════════════════${NC}\n"
    
    local overall_status=0
    
    # Check SSH connectivity first
    if ! check_ssh_connectivity; then
        log "ERROR" "Cannot proceed with health check - SSH connectivity failed"
        return 1
    fi
    
    # Run service checks
    if ! check_services; then
        log "WARN" "Some service checks failed"
        overall_status=1
    fi
    
    # Run connectivity checks
    if ! check_connectivity; then
        log "WARN" "Some connectivity checks failed"
        overall_status=1
    fi
    
    echo -e "\n${BLUE}════════════════════════════════════════════════════════════════════════════════${NC}"
    if [[ $overall_status -eq 0 ]]; then
        echo -e "${GREEN}  ✅ OVERALL HEALTH: GOOD${NC}"
    else
        echo -e "${YELLOW}  ⚠️ OVERALL HEALTH: DEGRADED (check warnings above)${NC}"
    fi
    echo -e "${BLUE}════════════════════════════════════════════════════════════════════════════════${NC}\n"
    
    return $overall_status
}

show_usage() {
    cat << EOF
USAGE: $0 [OPTIONS]

OPTIONS:
    -h, --help       Show this help message
    --services-only  Check only services (skip connectivity)
    --network-only   Check only network connectivity
    --json          Output results in JSON format

EXAMPLES:
    $0                    # Full health check
    $0 --services-only    # Check only local services
    $0 --network-only     # Check only network connectivity

EOF
}

main() {
    local services_only="false"
    local network_only="false"
    local json_output="false"
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --services-only)
                services_only="true"
                shift
                ;;
            --network-only)
                network_only="true"
                shift
                ;;
            --json)
                json_output="true"
                shift
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            *)
                log "ERROR" "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    if [[ "$services_only" == "true" ]]; then
        check_ssh_connectivity && check_services
    elif [[ "$network_only" == "true" ]]; then
        check_ssh_connectivity && check_connectivity
    else
        run_health_check
    fi
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi