#!/bin/bash

# Deployment Remediation Script for Cloudya Vault Infrastructure
# Fixes wrong application deployment and deploys correct infrastructure

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

# Configuration
SERVER_IP="65.109.81.169"
INFRASTRUCTURE_PATH="/opt/vault-infrastructure"
BACKUP_PATH="/opt/backup-$(date +%Y%m%d-%H%M%S)"

log() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')] $1${NC}"
}

success() {
    echo -e "${GREEN}✓ $1${NC}"
}

error() {
    echo -e "${RED}✗ $1${NC}"
}

warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

title() {
    echo
    echo -e "${BOLD}${BLUE}=======================================${NC}"
    echo -e "${BOLD}${BLUE}  $1${NC}"
    echo -e "${BOLD}${BLUE}=======================================${NC}"
    echo
}

# Function to check if running on target server
check_server() {
    local current_ip=$(curl -s ifconfig.me || echo "unknown")
    log "Current server IP: $current_ip"
    log "Expected server IP: $SERVER_IP"
    
    if [ "$current_ip" != "$SERVER_IP" ]; then
        warning "This script should be run on the target server ($SERVER_IP)"
        echo "You may need to SSH to the server first:"
        echo "  ssh user@$SERVER_IP"
        echo "  Then run this script on the remote server."
        echo
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            error "Exiting..."
            exit 1
        fi
    fi
}

# Function to backup current deployment
backup_current_deployment() {
    title "Backing Up Current Deployment"
    
    log "Creating backup directory: $BACKUP_PATH"
    sudo mkdir -p "$BACKUP_PATH"
    
    # Backup current docker state
    if command -v docker &> /dev/null; then
        log "Saving current docker images list..."
        sudo docker images > "$BACKUP_PATH/docker-images.txt" || true
        
        log "Saving current docker containers state..."
        sudo docker ps -a > "$BACKUP_PATH/docker-containers.txt" || true
        
        log "Exporting current container logs..."
        for container in $(sudo docker ps -q); do
            local container_name=$(sudo docker inspect --format='{{.Name}}' $container | sed 's/\///')
            sudo docker logs $container > "$BACKUP_PATH/logs-${container_name}.txt" 2>&1 || true
        done
    fi
    
    # Backup current application files
    if [ -d "/opt" ]; then
        log "Backing up /opt directory contents..."
        sudo cp -r /opt "$BACKUP_PATH/opt-backup" || true
    fi
    
    success "Backup completed: $BACKUP_PATH"
}

# Function to stop current deployment
stop_current_deployment() {
    title "Stopping Current Deployment"
    
    if command -v docker &> /dev/null; then
        log "Checking for running containers..."
        local running_containers=$(sudo docker ps -q)
        
        if [ -n "$running_containers" ]; then
            log "Stopping all running containers..."
            sudo docker stop $running_containers || true
            
            log "Removing stopped containers..."
            sudo docker rm $running_containers || true
            
            success "All containers stopped and removed"
        else
            log "No running containers found"
        fi
        
        # Clean up any docker-compose services
        if [ -f "docker-compose.yml" ]; then
            log "Stopping docker-compose services..."
            sudo docker-compose down || true
        fi
        
        # Check for docker-compose files in common locations
        for compose_path in "/opt/*/docker-compose.yml" "/app/docker-compose.yml" "/home/*/docker-compose.yml"; do
            if [ -f "$compose_path" ]; then
                log "Found docker-compose at $compose_path, stopping..."
                cd "$(dirname "$compose_path")"
                sudo docker-compose down || true
            fi
        done
        
    else
        warning "Docker not found on this system"
    fi
    
    # Stop nginx if running
    if systemctl is-active --quiet nginx; then
        log "Stopping nginx service..."
        sudo systemctl stop nginx || true
    fi
}

# Function to clean up wrong deployment
cleanup_wrong_deployment() {
    title "Cleaning Up Wrong Deployment"
    
    # Remove fake-detector related containers and images
    log "Cleaning up fake-detector related resources..."
    
    # Stop and remove containers with fake-detector in name
    sudo docker ps -a --format "table {{.Names}}\t{{.Image}}" | grep -i fake || true
    sudo docker stop $(sudo docker ps -a -q --filter "name=fake" --format "{{.Names}}") 2>/dev/null || true
    sudo docker rm $(sudo docker ps -a -q --filter "name=fake" --format "{{.Names}}") 2>/dev/null || true
    
    # Remove images related to fake-detector
    sudo docker rmi $(sudo docker images --format "table {{.Repository}}\t{{.Tag}}" | grep -i fake | awk '{print $1":"$2}') 2>/dev/null || true
    
    # Clean up nginx configuration if modified
    if [ -d "/etc/nginx" ]; then
        log "Backing up nginx configuration..."
        sudo cp -r /etc/nginx "$BACKUP_PATH/nginx-backup" || true
    fi
    
    success "Cleanup completed"
}

# Function to prepare infrastructure directory
prepare_infrastructure_directory() {
    title "Preparing Infrastructure Directory"
    
    log "Creating infrastructure directory: $INFRASTRUCTURE_PATH"
    sudo mkdir -p "$INFRASTRUCTURE_PATH"
    cd "$INFRASTRUCTURE_PATH"
    
    # Check if we already have the correct files
    if [ ! -f "docker-compose.yml" ]; then
        error "docker-compose.yml not found in $INFRASTRUCTURE_PATH"
        echo "Please ensure the Vault infrastructure files are present:"
        echo "  - docker-compose.yml"
        echo "  - traefik.yml"
        echo "  - .env (if needed)"
        echo
        echo "You may need to:"
        echo "  1. Clone the correct repository"
        echo "  2. Copy files from your local machine"
        echo "  3. Recreate the configuration files"
        exit 1
    fi
    
    log "Verifying docker-compose.yml content..."
    if grep -q "vault:" "docker-compose.yml" && grep -q "consul:" "docker-compose.yml" && grep -q "traefik:" "docker-compose.yml"; then
        success "docker-compose.yml appears to contain correct services"
    else
        error "docker-compose.yml does not contain expected services (vault, consul, traefik)"
        echo "Current docker-compose.yml content:"
        head -20 docker-compose.yml
        exit 1
    fi
}

# Function to deploy correct infrastructure
deploy_infrastructure() {
    title "Deploying Vault Infrastructure"
    
    cd "$INFRASTRUCTURE_PATH"
    
    log "Pulling latest Docker images..."
    sudo docker-compose pull
    
    log "Starting infrastructure services..."
    sudo docker-compose up -d
    
    log "Waiting for services to start..."
    sleep 10
    
    log "Checking service status..."
    sudo docker-compose ps
    
    success "Infrastructure deployment initiated"
}

# Function to verify deployment
verify_deployment() {
    title "Verifying Deployment"
    
    local retries=30
    local success_count=0
    
    for ((i=1; i<=retries; i++)); do
        log "Verification attempt $i/$retries..."
        
        # Check Vault
        if curl -s --fail http://localhost:8200/v1/sys/health &>/dev/null; then
            success "Vault service is responding"
            ((success_count++))
        else
            warning "Vault service not yet responding"
        fi
        
        # Check Consul
        if curl -s --fail http://localhost:8500/v1/status/leader &>/dev/null; then
            success "Consul service is responding"
            ((success_count++))
        else
            warning "Consul service not yet responding"
        fi
        
        # Check Traefik
        if curl -s --fail http://localhost:8080/api/overview &>/dev/null; then
            success "Traefik service is responding"
            ((success_count++))
        elif curl -s --fail http://localhost:8080/dashboard/ &>/dev/null; then
            success "Traefik dashboard is responding"
            ((success_count++))
        else
            warning "Traefik service not yet responding"
        fi
        
        if [ $success_count -eq 3 ]; then
            success "All services are responding!"
            break
        fi
        
        success_count=0
        sleep 5
    done
    
    if [ $success_count -lt 3 ]; then
        error "Not all services are responding after $retries attempts"
        log "Checking container logs..."
        sudo docker-compose logs --tail=10
        return 1
    fi
    
    return 0
}

# Function to configure firewall
configure_firewall() {
    title "Configuring Firewall"
    
    if command -v ufw &> /dev/null; then
        log "Configuring UFW firewall..."
        sudo ufw allow 22/tcp   # SSH
        sudo ufw allow 80/tcp   # HTTP
        sudo ufw allow 443/tcp  # HTTPS
        sudo ufw allow 8080/tcp # Traefik Dashboard (temporary)
        
        # Enable firewall if not already enabled
        echo "y" | sudo ufw enable || true
        
        success "Firewall configured"
    else
        warning "UFW not available, please configure firewall manually"
        echo "Required open ports: 22, 80, 443, 8080"
    fi
}

# Function to generate remediation report
generate_report() {
    title "Generating Remediation Report"
    
    local report_file="$BACKUP_PATH/remediation-report.txt"
    
    cat > "$report_file" << EOF
Cloudya Vault Infrastructure Remediation Report
===============================================

Date: $(date)
Server: $SERVER_IP
Backup Location: $BACKUP_PATH

ACTIONS PERFORMED:
- Backed up current deployment
- Stopped wrong application (Fake Detector)
- Cleaned up incorrect containers and images
- Deployed correct Vault infrastructure
- Configured firewall rules

SERVICE STATUS:
$(sudo docker-compose ps)

NETWORK STATUS:
$(netstat -tlnp | grep -E ':(80|443|8080|8200|8500)\s')

NEXT STEPS:
1. Test HTTPS access to services
2. Initialize Vault
3. Configure Consul ACLs
4. Set up Traefik authentication
5. Run comprehensive test suite

VERIFICATION COMMANDS:
curl -I https://vault.cloudya.net
curl -I https://consul.cloudya.net
curl -I https://traefik.cloudya.net

EOF

    success "Remediation report saved: $report_file"
    cat "$report_file"
}

# Main execution
main() {
    title "Cloudya Vault Infrastructure Remediation"
    
    log "Starting deployment remediation process..."
    
    # Pre-flight checks
    check_server
    
    # Remediation steps
    backup_current_deployment
    stop_current_deployment
    cleanup_wrong_deployment
    prepare_infrastructure_directory
    deploy_infrastructure
    
    # Verification and configuration
    if verify_deployment; then
        configure_firewall
        generate_report
        
        echo
        success "🎉 Remediation completed successfully!"
        echo
        echo "Next steps:"
        echo "1. Run deployment tests: ./tests/validate-deployment.sh"
        echo "2. Configure SSL certificates"
        echo "3. Initialize Vault and Consul"
        echo "4. Run full test suite"
        echo
        echo "Access URLs (once SSL is configured):"
        echo "  - Vault: https://vault.cloudya.net"
        echo "  - Consul: https://consul.cloudya.net"
        echo "  - Traefik: https://traefik.cloudya.net"
    else
        error "Remediation verification failed!"
        echo
        echo "Check the following:"
        echo "1. Docker containers: sudo docker-compose ps"
        echo "2. Container logs: sudo docker-compose logs"
        echo "3. Port bindings: netstat -tlnp"
        echo
        echo "Backup location: $BACKUP_PATH"
        exit 1
    fi
}

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi