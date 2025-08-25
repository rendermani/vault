#!/bin/bash

# Quick Deployment Validation Script
# Performs essential checks to validate deployment status

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
SERVICES=("vault.cloudya.net" "consul.cloudya.net" "traefik.cloudya.net")
SERVER_IP="65.109.81.169"
PORTS=(80 443 8080 8200 8500 22)

echo -e "${BLUE}=======================================${NC}"
echo -e "${BLUE}  Cloudya Infrastructure Validation${NC}"
echo -e "${BLUE}=======================================${NC}"
echo

# Function to test connectivity
test_connectivity() {
    local host=$1
    local port=$2
    local timeout=3
    
    if (echo >/dev/tcp/$host/$port) &>/dev/null; then
        echo -e "${GREEN}✓${NC} Port $port: OPEN"
        return 0
    else
        echo -e "${RED}✗${NC} Port $port: CLOSED"
        return 1
    fi
}

# 1. DNS Resolution Check
echo -e "${YELLOW}1. DNS Resolution Test${NC}"
echo "----------------------------------------"
for service in "${SERVICES[@]}"; do
    if nslookup $service | grep -q "Address:"; then
        ip=$(nslookup $service | grep "Address:" | tail -1 | awk '{print $2}')
        echo -e "${GREEN}✓${NC} $service → $ip"
    else
        echo -e "${RED}✗${NC} $service → DNS resolution failed"
    fi
done
echo

# 2. Server Connectivity Test
echo -e "${YELLOW}2. Server Connectivity Test${NC}"
echo "----------------------------------------"
if ping -c 1 -W 3000 $SERVER_IP &>/dev/null; then
    echo -e "${GREEN}✓${NC} Server $SERVER_IP is reachable"
else
    echo -e "${RED}✗${NC} Server $SERVER_IP is not reachable"
fi
echo

# 3. Port Connectivity Test
echo -e "${YELLOW}3. Port Connectivity Test${NC}"
echo "----------------------------------------"
port_status=()
for port in "${PORTS[@]}"; do
    if test_connectivity $SERVER_IP $port; then
        port_status+=("open")
    else
        port_status+=("closed")
    fi
done
echo

# 4. Service Endpoint Test
echo -e "${YELLOW}4. Service Endpoint Test${NC}"
echo "----------------------------------------"
for service in "${SERVICES[@]}"; do
    echo -n "Testing https://$service... "
    response=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 --max-time 10 "https://$service" 2>/dev/null || echo "000")
    
    case $response in
        200|301|302|401|403)
            echo -e "${GREEN}✓${NC} Responding (HTTP $response)"
            ;;
        000)
            echo -e "${RED}✗${NC} No response (connection failed)"
            ;;
        *)
            echo -e "${YELLOW}⚠${NC} Unexpected response (HTTP $response)"
            ;;
    esac
done
echo

# 5. Quick Health Summary
echo -e "${YELLOW}5. Deployment Health Summary${NC}"
echo "----------------------------------------"

# Count open ports
open_ports=0
for status in "${port_status[@]}"; do
    if [ "$status" = "open" ]; then
        open_ports=$((open_ports + 1))
    fi
done

# Calculate health score
total_checks=6  # DNS + ping + 4 critical services
health_score=1  # Start with DNS working

if ping -c 1 -W 3000 $SERVER_IP &>/dev/null; then
    health_score=$((health_score + 1))
fi

# Check critical ports (80, 443)
for port in 80 443; do
    if test_connectivity $SERVER_IP $port &>/dev/null; then
        health_score=$((health_score + 1))
    fi
done

# Check if any HTTPS service responds
for service in "${SERVICES[@]}"; do
    response=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 --max-time 10 "https://$service" 2>/dev/null || echo "000")
    if [[ "$response" =~ ^[23] ]]; then
        health_score=$((health_score + 1))
        break
    fi
done

health_percentage=$((health_score * 100 / total_checks))

echo "Open Ports: $open_ports/${#PORTS[@]}"
echo "Health Score: $health_score/$total_checks ($health_percentage%)"
echo

if [ "$health_percentage" -ge 80 ]; then
    echo -e "${GREEN}🎉 DEPLOYMENT STATUS: HEALTHY${NC}"
    echo "All critical services appear to be operational."
elif [ "$health_percentage" -ge 50 ]; then
    echo -e "${YELLOW}⚠️  DEPLOYMENT STATUS: PARTIAL${NC}"
    echo "Some services are operational, but issues detected."
else
    echo -e "${RED}🚨 DEPLOYMENT STATUS: CRITICAL${NC}"
    echo "Major issues detected - immediate attention required."
fi

echo
echo -e "${BLUE}Next Steps:${NC}"
if [ "$health_percentage" -ge 80 ]; then
    echo "• Run full test suite: ./tests/deployment-test.sh"
    echo "• Perform security audit: ./tests/security-test.sh"
    echo "• Execute performance tests: ./tests/performance-test.sh"
elif [ "$health_percentage" -ge 50 ]; then
    echo "• Investigate failing services"
    echo "• Check Docker container status"
    echo "• Verify firewall configuration"
else
    echo "• SSH to server and check service status"
    echo "• Review Docker logs for errors"
    echo "• Restart services if necessary"
    echo "• Check firewall and network configuration"
fi

echo
echo "For detailed diagnostics, see: docs/TEST_RESULTS.md"