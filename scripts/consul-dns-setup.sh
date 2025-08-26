#!/bin/bash

# Consul DNS Integration Setup Script
# Configures DNS forwarding, service discovery, and health checks
# Usage: ./consul-dns-setup.sh [environment]

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
LOG_FILE="/var/log/consul-dns-setup.log"

# Environment variables
CONSUL_HTTP_ADDR="${CONSUL_HTTP_ADDR:-http://127.0.0.1:8500}"
ENVIRONMENT="${1:-development}"

# Logging function
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

# Error handling
error() {
    log "ERROR: $*"
    exit 1
}

# Detect operating system
detect_os() {
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        if command -v systemctl &> /dev/null; then
            echo "systemd"
        else
            echo "linux"
        fi
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        echo "macos"
    else
        echo "unknown"
    fi
}

# Configure systemd-resolved for DNS forwarding (Ubuntu/Debian)
configure_systemd_resolved() {
    log "Configuring systemd-resolved for Consul DNS forwarding"
    
    # Create resolved configuration
    sudo tee /etc/systemd/resolved.conf.d/consul.conf > /dev/null <<EOF
[Resolve]
DNS=127.0.0.1:8600
Domains=~consul
DNSSEC=false
EOF

    # Restart systemd-resolved
    sudo systemctl restart systemd-resolved
    
    log "systemd-resolved configured for .consul domain"
}

# Configure dnsmasq for DNS forwarding
configure_dnsmasq() {
    log "Configuring dnsmasq for Consul DNS forwarding"
    
    # Install dnsmasq if not present
    if ! command -v dnsmasq &> /dev/null; then
        log "Installing dnsmasq..."
        case $(detect_os) in
            "systemd")
                sudo apt-get update && sudo apt-get install -y dnsmasq
                ;;
            "macos")
                if command -v brew &> /dev/null; then
                    brew install dnsmasq
                else
                    error "Please install dnsmasq manually on macOS"
                fi
                ;;
        esac
    fi
    
    # Configure dnsmasq for Consul
    sudo tee /etc/dnsmasq.d/10-consul > /dev/null <<EOF
# Forward .consul domain to Consul DNS
server=/consul/127.0.0.1#8600

# Consul service discovery
address=/.consul/127.0.0.1

# Cache size for better performance
cache-size=1000

# Log queries for debugging (disable in production)
log-queries
log-facility=/var/log/dnsmasq-consul.log
EOF

    # Restart dnsmasq
    case $(detect_os) in
        "systemd")
            sudo systemctl restart dnsmasq
            sudo systemctl enable dnsmasq
            ;;
        "macos")
            sudo brew services restart dnsmasq
            ;;
    esac
    
    log "dnsmasq configured for Consul DNS"
}

# Configure macOS DNS resolver
configure_macos_resolver() {
    log "Configuring macOS DNS resolver for Consul"
    
    # Create resolver directory if it doesn't exist
    sudo mkdir -p /etc/resolver
    
    # Configure .consul domain resolution
    sudo tee /etc/resolver/consul > /dev/null <<EOF
nameserver 127.0.0.1
port 8600
EOF

    log "macOS resolver configured for .consul domain"
}

# Test DNS configuration
test_dns_configuration() {
    local test_domain="consul.service.consul"
    
    log "Testing DNS configuration..."
    
    # Wait for Consul to be ready
    local attempts=0
    while [[ $attempts -lt 30 ]]; do
        if curl -sf "$CONSUL_HTTP_ADDR/v1/status/leader" &>/dev/null; then
            break
        fi
        log "Waiting for Consul to be ready... (attempt $((attempts + 1))/30)"
        sleep 2
        ((attempts++))
    done
    
    if [[ $attempts -eq 30 ]]; then
        error "Consul is not responding after 60 seconds"
    fi
    
    # Test 1: Direct Consul DNS query
    log "Testing direct Consul DNS query..."
    if dig @127.0.0.1 -p 8600 consul.service.consul &>/dev/null; then
        log "✅ Direct Consul DNS query: PASSED"
    else
        log "❌ Direct Consul DNS query: FAILED"
    fi
    
    # Test 2: System DNS resolution
    log "Testing system DNS resolution..."
    if dig consul.service.consul &>/dev/null; then
        log "✅ System DNS resolution: PASSED"
    else
        log "⚠️  System DNS resolution: FAILED (may need system restart)"
    fi
    
    # Test 3: Service discovery
    log "Testing service discovery..."
    if consul catalog services &>/dev/null; then
        log "✅ Service catalog: ACCESSIBLE"
        consul catalog services | while read -r service; do
            log "  Registered service: $service"
        done
    else
        log "❌ Service catalog: NOT ACCESSIBLE"
    fi
    
    # Test 4: Health check integration
    log "Testing health check integration..."
    local healthy_services
    if healthy_services=$(consul catalog services -tags); then
        log "✅ Health check integration: WORKING"
        log "  Services with health checks: $healthy_services"
    else
        log "⚠️  Health check integration: NEEDS VERIFICATION"
    fi
}

# Register test service for DNS verification
register_test_service() {
    log "Registering test service for DNS verification..."
    
    # Register a test service
    consul services register - <<EOF
{
    "ID": "test-service-dns",
    "Name": "test-service",
    "Tags": ["dns-test"],
    "Port": 8080,
    "Check": {
        "HTTP": "http://127.0.0.1:8080/health",
        "Interval": "30s",
        "Timeout": "5s"
    }
}
EOF

    log "Test service registered: test-service.service.consul"
}

# Clean up test service
cleanup_test_service() {
    log "Cleaning up test service..."
    consul services deregister test-service-dns || true
}

# Generate DNS monitoring script
create_dns_monitor() {
    log "Creating DNS monitoring script..."
    
    cat > "$PROJECT_ROOT/scripts/consul-dns-monitor.sh" <<'EOF'
#!/bin/bash

# Consul DNS Monitoring Script
# Monitors DNS resolution and service discovery health

CONSUL_HTTP_ADDR="${CONSUL_HTTP_ADDR:-http://127.0.0.1:8500}"
LOG_FILE="/var/log/consul-dns-monitor.log"

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

# Monitor DNS resolution
check_dns_resolution() {
    local failures=0
    
    # Test critical services
    local services=("consul.service.consul" "vault.service.consul" "nomad.service.consul")
    
    for service in "${services[@]}"; do
        if ! dig @127.0.0.1 -p 8600 "$service" +short &>/dev/null; then
            log "DNS resolution failed for: $service"
            ((failures++))
        fi
    done
    
    return $failures
}

# Monitor service health via DNS
check_service_health() {
    local unhealthy=0
    
    # Get all services and check their health
    while IFS= read -r service; do
        if [[ -n "$service" ]]; then
            local healthy_count
            healthy_count=$(dig @127.0.0.1 -p 8600 "$service.service.consul" +short | wc -l)
            
            if [[ $healthy_count -eq 0 ]]; then
                log "No healthy instances found for: $service"
                ((unhealthy++))
            fi
        fi
    done < <(consul catalog services)
    
    return $unhealthy
}

# Main monitoring loop
main() {
    log "Starting DNS monitoring check..."
    
    local dns_failures=0
    local health_failures=0
    
    if ! check_dns_resolution; then
        dns_failures=$?
    fi
    
    if ! check_service_health; then
        health_failures=$?
    fi
    
    if [[ $dns_failures -eq 0 && $health_failures -eq 0 ]]; then
        log "DNS monitoring check: ALL HEALTHY"
        exit 0
    else
        log "DNS monitoring check: ISSUES DETECTED (DNS: $dns_failures, Health: $health_failures)"
        exit 1
    fi
}

main "$@"
EOF

    chmod +x "$PROJECT_ROOT/scripts/consul-dns-monitor.sh"
    log "DNS monitoring script created: $PROJECT_ROOT/scripts/consul-dns-monitor.sh"
}

# Set up DNS monitoring cron job
setup_dns_monitoring() {
    log "Setting up DNS monitoring cron job..."
    
    local cron_entry="*/5 * * * * $PROJECT_ROOT/scripts/consul-dns-monitor.sh"
    
    # Add to crontab if not already present
    if ! crontab -l 2>/dev/null | grep -q "consul-dns-monitor.sh"; then
        (crontab -l 2>/dev/null; echo "$cron_entry") | crontab -
        log "DNS monitoring cron job added (runs every 5 minutes)"
    else
        log "DNS monitoring cron job already exists"
    fi
}

# Generate DNS configuration for different environments
generate_environment_configs() {
    local env="$1"
    
    case "$env" in
        "production")
            cat > "$PROJECT_ROOT/infrastructure/config/consul-dns-$env.hcl" <<EOF
# Production DNS Configuration
dns_config {
    allow_stale = true
    max_stale = "1s"
    node_ttl = "30s"
    service_ttl = "30s"
    udp_answer_limit = 3
    recursor_timeout = "2s"
    recursors = ["1.1.1.1", "8.8.8.8", "8.8.4.4"]
    enable_truncate = true
    only_passing = true
    prefer_namespace = true
}
EOF
            ;;
        "staging")
            cat > "$PROJECT_ROOT/infrastructure/config/consul-dns-$env.hcl" <<EOF
# Staging DNS Configuration  
dns_config {
    allow_stale = true
    max_stale = "5s"
    node_ttl = "60s"
    service_ttl = "60s"
    udp_answer_limit = 5
    recursor_timeout = "5s"
    recursors = ["8.8.8.8", "1.1.1.1"]
    enable_truncate = true
    only_passing = false
}
EOF
            ;;
        "development")
            cat > "$PROJECT_ROOT/infrastructure/config/consul-dns-$env.hcl" <<EOF
# Development DNS Configuration
dns_config {
    allow_stale = true
    max_stale = "10s"
    node_ttl = "120s"
    service_ttl = "120s"
    udp_answer_limit = 10
    recursor_timeout = "10s"
    recursors = ["8.8.8.8", "1.1.1.1"]
}
EOF
            ;;
    esac
    
    log "DNS configuration generated for $env environment"
}

# Main function
main() {
    local environment="${1:-development}"
    local os_type
    
    # Ensure log file exists
    sudo touch "$LOG_FILE" 2>/dev/null || touch "$LOG_FILE"
    
    log "Setting up Consul DNS integration for environment: $environment"
    
    os_type=$(detect_os)
    log "Detected OS: $os_type"
    
    # Generate environment-specific DNS config
    generate_environment_configs "$environment"
    
    # Configure DNS forwarding based on OS
    case "$os_type" in
        "systemd")
            configure_systemd_resolved
            ;;
        "linux")
            configure_dnsmasq
            ;;
        "macos")
            configure_macos_resolver
            ;;
        *)
            log "Unsupported OS: $os_type"
            log "Please configure DNS forwarding manually"
            ;;
    esac
    
    # Wait a moment for DNS changes to propagate
    sleep 5
    
    # Register test service and test configuration
    register_test_service
    test_dns_configuration
    cleanup_test_service
    
    # Create monitoring tools
    create_dns_monitor
    
    if [[ "$environment" != "development" ]]; then
        setup_dns_monitoring
    fi
    
    log "Consul DNS setup completed for $environment environment"
    log "Test DNS resolution with: dig consul.service.consul"
}

# Run main function
main "$@"