#!/bin/bash

# Server Provisioning Script for Cloudya Infrastructure
# Prepares a clean Ubuntu/Debian server for production deployment
# Idempotent and safe to run multiple times

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVER_HOST="${1:-root@cloudya.net}"
SSH_KEY_PATH="${HOME}/.ssh/id_rsa"
LOG_FILE="/tmp/provision-$(date +%Y%m%d-%H%M%S).log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'

# Configuration variables
DRY_RUN=false
FORCE_PROVISION=false
SKIP_SECURITY=false
VERBOSE=false
SETUP_MONITORING=true
INSTALL_DOCKER=true
SETUP_FIREWALL=true

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"
}

log_debug() {
    if [[ "$VERBOSE" == "true" ]]; then
        echo -e "${PURPLE}[DEBUG]${NC} $1" | tee -a "$LOG_FILE"
    fi
}

log_step() {
    echo -e "${CYAN}[STEP]${NC} $1" | tee -a "$LOG_FILE"
}

# Usage function
usage() {
    cat <<EOF
Server Provisioning Script for Cloudya Infrastructure
Prepares Ubuntu/Debian servers for production deployment

Usage: $0 [SERVER] [OPTIONS]

Arguments:
  SERVER              Target server (default: root@cloudya.net)

Options:
  -d, --dry-run       Show what would be done without making changes
  -f, --force         Force provisioning without confirmation prompts
  -s, --skip-security Skip security hardening setup
  -v, --verbose       Enable verbose debug output
  -m, --no-monitoring Disable monitoring agent installation
  -c, --no-docker     Skip Docker installation
  -w, --no-firewall   Skip firewall configuration
  -k, --ssh-key PATH  Path to SSH private key [default: ~/.ssh/id_rsa]
  -h, --help          Show this help message

Examples:
  $0                                    # Provision cloudya.net with defaults
  $0 root@server.example.com --dry-run  # Preview provisioning
  $0 --force --verbose                  # Force provision with debug output

What this script does:
  1. Updates system packages
  2. Installs essential tools and dependencies
  3. Configures security hardening (firewall, fail2ban, SSH)
  4. Installs Docker and Docker Compose
  5. Installs HashiCorp tools (Vault, Nomad, Consul)
  6. Sets up monitoring agents
  7. Configures log rotation and system maintenance
  8. Creates application directories with proper permissions
  9. Validates the provisioning

EOF
}

# Parse command line arguments
parse_arguments() {
    # First argument is server if provided
    if [[ $# -gt 0 && ! "$1" =~ ^- ]]; then
        SERVER_HOST="$1"
        shift
    fi
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -f|--force)
                FORCE_PROVISION=true
                shift
                ;;
            -s|--skip-security)
                SKIP_SECURITY=true
                shift
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -m|--no-monitoring)
                SETUP_MONITORING=false
                shift
                ;;
            -c|--no-docker)
                INSTALL_DOCKER=false
                shift
                ;;
            -w|--no-firewall)
                SETUP_FIREWALL=false
                shift
                ;;
            -k|--ssh-key)
                SSH_KEY_PATH="$2"
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

# Execute command on remote server
remote_exec() {
    local command="$1"
    local description="${2:-Executing remote command}"
    
    log_debug "Remote exec: $command"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would execute: $description"
        return 0
    fi
    
    if ssh -i "$SSH_KEY_PATH" -o ConnectTimeout=30 -o BatchMode=yes "$SERVER_HOST" "$command" 2>&1 | tee -a "$LOG_FILE"; then
        log_debug "Remote command successful: $description"
        return 0
    else
        local exit_code=$?
        log_error "Remote command failed: $description (exit code: $exit_code)"
        return $exit_code
    fi
}

# Validate prerequisites
validate_prerequisites() {
    log_step "Validating prerequisites..."
    
    # Check SSH key
    if [[ ! -f "$SSH_KEY_PATH" ]]; then
        log_error "SSH private key not found: $SSH_KEY_PATH"
        exit 1
    fi
    
    # Test SSH connection
    if ! ssh -i "$SSH_KEY_PATH" -o ConnectTimeout=10 -o BatchMode=yes "$SERVER_HOST" "echo 'SSH test successful'" >/dev/null 2>&1; then
        log_error "Failed to establish SSH connection to $SERVER_HOST"
        exit 1
    fi
    
    # Check required local tools
    local required_tools=("ssh" "scp" "rsync")
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            log_error "Required tool not found: $tool"
            exit 1
        fi
    done
    
    log_success "Prerequisites validation passed"
}

# Check server information
check_server_info() {
    log_step "Gathering server information..."
    
    local server_info=$(remote_exec "
        echo 'Hostname: '$(hostname -f)
        echo 'OS: '$(lsb_release -d 2>/dev/null | cut -f2 || cat /etc/os-release | grep PRETTY_NAME | cut -d'\"' -f2)
        echo 'Kernel: '$(uname -r)
        echo 'Architecture: '$(uname -m)
        echo 'CPU Cores: '$(nproc)
        echo 'Memory: '$(free -h | grep '^Mem:' | awk '{print \$2}')
        echo 'Disk Space: '$(df -h / | tail -1 | awk '{print \$4\" available of \"\$2}')
        echo 'Uptime: '$(uptime -p)
        echo 'Current User: '$(whoami)
        echo 'Shell: '\$SHELL
        echo 'Timezone: '$(timedatectl show --value -p Timezone 2>/dev/null || cat /etc/timezone 2>/dev/null || echo 'Unknown')
    " "Gathering server information")
    
    log_info "Server Information:"
    echo "$server_info" | while read -r line; do
        log_info "  $line"
    done
    
    # Check minimum requirements
    local memory_gb=$(remote_exec "free -g | grep '^Mem:' | awk '{print \$2}'" "Checking memory")
    local disk_gb=$(remote_exec "df --output=avail -BG / | tail -1 | tr -d 'G'" "Checking disk space")
    
    if [[ "$memory_gb" -lt 4 ]]; then
        log_warning "Server has less than 4GB RAM ($memory_gb GB). Consider upgrading for production use."
    fi
    
    if [[ "$disk_gb" -lt 50 ]]; then
        log_warning "Server has less than 50GB disk space ($disk_gb GB). Consider adding storage."
    fi
    
    log_success "Server information check completed"
}

# Update system packages
update_system() {
    log_step "Updating system packages..."
    
    remote_exec "
        # Update package list
        export DEBIAN_FRONTEND=noninteractive
        apt-get update -qq
        
        # Upgrade existing packages
        apt-get upgrade -y -qq
        
        # Install security updates
        unattended-upgrade -d || apt-get upgrade -y -qq
        
        # Clean up package cache
        apt-get autoremove -y -qq
        apt-get autoclean -qq
        
        echo 'System packages updated successfully'
    " "Updating system packages"
    
    log_success "System packages updated"
}

# Install essential packages
install_essential_packages() {
    log_step "Installing essential packages..."
    
    remote_exec "
        export DEBIAN_FRONTEND=noninteractive
        
        # Essential system tools
        apt-get install -y -qq \\
            curl \\
            wget \\
            unzip \\
            zip \\
            tar \\
            gzip \\
            jq \\
            vim \\
            nano \\
            htop \\
            iotop \\
            nethogs \\
            tcpdump \\
            net-tools \\
            dnsutils \\
            telnet \\
            nc \\
            lsof \\
            strace \\
            tree \\
            git \\
            rsync \\
            screen \\
            tmux \\
            sudo \\
            cron \\
            logrotate \\
            ca-certificates \\
            gnupg \\
            lsb-release \\
            software-properties-common \\
            apt-transport-https
        
        # Development tools
        apt-get install -y -qq \\
            build-essential \\
            python3 \\
            python3-pip \\
            python3-venv \\
            nodejs \\
            npm
        
        # System monitoring and performance tools
        apt-get install -y -qq \\
            sysstat \\
            iftop \\
            nload \\
            glances \\
            atop
        
        echo 'Essential packages installed successfully'
    " "Installing essential packages"
    
    log_success "Essential packages installed"
}

# Configure security hardening
configure_security() {
    if [[ "$SKIP_SECURITY" == "true" ]]; then
        log_info "Skipping security configuration as requested"
        return 0
    fi
    
    log_step "Configuring security hardening..."
    
    remote_exec "
        # Install security packages
        export DEBIAN_FRONTEND=noninteractive
        apt-get install -y -qq fail2ban ufw aide chkrootkit rkhunter
        
        # Configure SSH security
        echo 'Configuring SSH security...'
        cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup
        
        # SSH hardening configuration
        cat > /etc/ssh/sshd_config.d/99-cloudya-security.conf << 'EOSSH'
# Cloudya SSH Security Configuration
Protocol 2
PermitRootLogin yes
PasswordAuthentication no
ChallengeResponseAuthentication no
UsePAM yes
X11Forwarding no
PrintMotd no
TCPKeepAlive yes
ClientAliveInterval 300
ClientAliveCountMax 2
MaxAuthTries 3
MaxSessions 10
MaxStartups 10:30:100
LoginGraceTime 60
AllowUsers root
Banner /etc/ssh/banner.txt
EOSSH
        
        # Create SSH banner
        cat > /etc/ssh/banner.txt << 'EOBANNER'
***************************************************************************
                    AUTHORIZED ACCESS ONLY
                    
This system is for authorized users only. All activities on this system
are logged and monitored. Unauthorized access is strictly prohibited and
will be prosecuted to the full extent of the law.

By accessing this system, you agree to comply with all applicable policies
and procedures.
***************************************************************************
EOBANNER
        
        # Restart SSH service
        systemctl restart sshd
        
        echo 'SSH security configured'
    " "Configuring SSH security"
    
    # Configure firewall if requested
    if [[ "$SETUP_FIREWALL" == "true" ]]; then
        remote_exec "
            echo 'Configuring firewall...'
            
            # Reset firewall to defaults
            ufw --force reset
            
            # Default policies
            ufw default deny incoming
            ufw default allow outgoing
            
            # Allow SSH (critical - don't lock ourselves out)
            ufw allow ssh
            ufw allow 22/tcp
            
            # Allow HTTP and HTTPS
            ufw allow 80/tcp
            ufw allow 443/tcp
            
            # Allow HashiCorp services
            ufw allow 8200/tcp  # Vault
            ufw allow 4646/tcp  # Nomad
            ufw allow 8500/tcp  # Consul
            
            # Allow monitoring
            ufw allow 9090/tcp  # Prometheus
            ufw allow 3000/tcp  # Grafana
            
            # Allow ping
            ufw allow from any to any port 22 proto tcp
            
            # Enable firewall
            ufw --force enable
            
            echo 'Firewall configured'
        " "Configuring firewall"
    fi
    
    # Configure fail2ban
    remote_exec "
        echo 'Configuring fail2ban...'
        
        # Backup original configuration
        cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.conf.backup
        
        # Create custom jail configuration
        cat > /etc/fail2ban/jail.local << 'EOFAIL'
[DEFAULT]
# Ban settings
bantime = 3600
findtime = 600
maxretry = 3
backend = systemd

# Email notifications (configure if needed)
# destemail = admin@cloudya.net
# sendername = Cloudya-Security
# sender = security@cloudya.net

[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
bantime = 7200

[apache-auth]
enabled = false

[apache-badbots]
enabled = false

[apache-noscript]
enabled = false

[apache-overflows]
enabled = false

[nginx-http-auth]
enabled = true
port = http,https
logpath = /var/log/nginx/error.log

[nginx-limit-req]
enabled = true
port = http,https
logpath = /var/log/nginx/error.log
EOFAIL
        
        # Enable and start fail2ban
        systemctl enable fail2ban
        systemctl restart fail2ban
        
        echo 'Fail2ban configured'
    " "Configuring fail2ban"
    
    log_success "Security hardening configured"
}

# Install Docker and Docker Compose
install_docker() {
    if [[ "$INSTALL_DOCKER" != "true" ]]; then
        log_info "Skipping Docker installation as requested"
        return 0
    fi
    
    log_step "Installing Docker and Docker Compose..."
    
    remote_exec "
        # Check if Docker is already installed
        if command -v docker &> /dev/null; then
            echo 'Docker is already installed:'
            docker --version
            echo 'Updating to latest version...'
        else
            echo 'Installing Docker...'
        fi
        
        # Install Docker using official script
        curl -fsSL https://get.docker.com -o get-docker.sh
        sh get-docker.sh
        rm get-docker.sh
        
        # Install Docker Compose
        echo 'Installing Docker Compose...'
        DOCKER_COMPOSE_VERSION=\$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep 'tag_name' | cut -d'\"' -f4)
        curl -L \"https://github.com/docker/compose/releases/download/\${DOCKER_COMPOSE_VERSION}/docker-compose-\$(uname -s)-\$(uname -m)\" -o /usr/local/bin/docker-compose
        chmod +x /usr/local/bin/docker-compose
        
        # Create docker-compose symlink for backwards compatibility
        ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose
        
        # Enable Docker service
        systemctl enable docker
        systemctl start docker
        
        # Configure Docker daemon for production
        mkdir -p /etc/docker
        cat > /etc/docker/daemon.json << 'EODOCKER'
{
    \"log-driver\": \"json-file\",
    \"log-opts\": {
        \"max-size\": \"100m\",
        \"max-file\": \"5\"
    },
    \"storage-driver\": \"overlay2\",
    \"live-restore\": true,
    \"userland-proxy\": false,
    \"no-new-privileges\": true,
    \"seccomp-profile\": \"/etc/docker/seccomp.json\",
    \"default-ulimits\": {
        \"nofile\": {
            \"Name\": \"nofile\",
            \"Hard\": 64000,
            \"Soft\": 64000
        }
    }
}
EODOCKER
        
        # Download default seccomp profile
        curl -fsSL https://raw.githubusercontent.com/moby/moby/master/profiles/seccomp/default.json -o /etc/docker/seccomp.json
        
        # Restart Docker with new configuration
        systemctl restart docker
        
        # Verify installation
        docker --version
        docker-compose --version
        
        echo 'Docker installation completed successfully'
    " "Installing Docker and Docker Compose"
    
    log_success "Docker and Docker Compose installed"
}

# Install HashiCorp tools
install_hashicorp_tools() {
    log_step "Installing HashiCorp tools..."
    
    remote_exec "
        # Create temporary directory for downloads
        mkdir -p /tmp/hashicorp-install
        cd /tmp/hashicorp-install
        
        # Function to install HashiCorp binary
        install_hashicorp_binary() {
            local product=\$1
            local version=\$2
            local binary_name=\${3:-\$product}
            
            echo \"Installing \$product version \$version...\"
            
            # Skip if already installed with correct version
            if command -v \$binary_name &> /dev/null; then
                current_version=\$(\$binary_name version | head -1 | grep -o 'v[0-9]\\+\\.[0-9]\\+\\.[0-9]\\+' | sed 's/v//')
                if [ \"\$current_version\" = \"\$version\" ]; then
                    echo \"\$product version \$version is already installed\"
                    return 0
                fi
            fi
            
            # Download and install
            wget -q \"https://releases.hashicorp.com/\$product/\$version/\${product}_\${version}_linux_amd64.zip\"
            unzip -q \"\${product}_\${version}_linux_amd64.zip\"
            mv \$binary_name /usr/local/bin/
            chmod +x /usr/local/bin/\$binary_name
            rm \"\${product}_\${version}_linux_amd64.zip\"
            
            echo \"\$product installed successfully\"
        }
        
        # Install Vault
        install_hashicorp_binary vault 1.17.6
        
        # Install Nomad
        install_hashicorp_binary nomad 1.8.4
        
        # Install Consul
        install_hashicorp_binary consul 1.19.2
        
        # Install Terraform (useful for infrastructure management)
        install_hashicorp_binary terraform 1.9.6
        
        # Cleanup
        cd /
        rm -rf /tmp/hashicorp-install
        
        # Verify installations
        echo 'Verifying HashiCorp tool installations:'
        vault version
        nomad version
        consul version
        terraform version
        
        echo 'HashiCorp tools installed successfully'
    " "Installing HashiCorp tools"
    
    log_success "HashiCorp tools installed"
}

# Setup monitoring agents
setup_monitoring() {
    if [[ "$SETUP_MONITORING" != "true" ]]; then
        log_info "Skipping monitoring setup as requested"
        return 0
    fi
    
    log_step "Setting up monitoring agents..."
    
    remote_exec "
        # Install Node Exporter for Prometheus monitoring
        echo 'Installing Node Exporter...'
        
        NODE_EXPORTER_VERSION=1.8.2
        cd /tmp
        wget -q https://github.com/prometheus/node_exporter/releases/download/v\${NODE_EXPORTER_VERSION}/node_exporter-\${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz
        tar xzf node_exporter-\${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz
        mv node_exporter-\${NODE_EXPORTER_VERSION}.linux-amd64/node_exporter /usr/local/bin/
        rm -rf node_exporter-*
        
        # Create node_exporter user
        useradd -rs /bin/false node_exporter 2>/dev/null || true
        
        # Create systemd service for Node Exporter
        cat > /etc/systemd/system/node_exporter.service << 'EONODE'
[Unit]
Description=Node Exporter
After=network.target

[Service]
User=node_exporter
Group=node_exporter
Type=simple
ExecStart=/usr/local/bin/node_exporter --web.listen-address=:9100
Restart=always

[Install]
WantedBy=multi-user.target
EONODE
        
        # Enable and start Node Exporter
        systemctl daemon-reload
        systemctl enable node_exporter
        systemctl start node_exporter
        
        # Install Filebeat for log shipping (optional)
        echo 'Installing Filebeat...'
        curl -L -O https://artifacts.elastic.co/downloads/beats/filebeat/filebeat-8.15.0-amd64.deb
        dpkg -i filebeat-8.15.0-amd64.deb 2>/dev/null || apt-get install -f -y
        rm filebeat-8.15.0-amd64.deb
        
        # Basic Filebeat configuration
        cat > /etc/filebeat/filebeat.yml << 'EOFILEBEAT'
filebeat.inputs:
- type: log
  enabled: true
  paths:
    - /var/log/cloudya/*.log
    - /var/log/syslog
    - /var/log/auth.log
  fields:
    server: cloudya-production
    environment: production
  fields_under_root: true

output.file:
  path: \"/var/log/filebeat\"
  filename: filebeat.log
  rotate_every_kb: 10000
  number_of_files: 5

logging.level: info
logging.to_files: true
logging.files:
  path: /var/log/filebeat
  name: filebeat
  keepfiles: 7
  permissions: 0644
EOFILEBEAT
        
        # Enable Filebeat (but don't start until configured)
        systemctl enable filebeat
        
        echo 'Monitoring agents installed successfully'
    " "Setting up monitoring agents"
    
    log_success "Monitoring agents setup completed"
}

# Create application directories
create_directories() {
    log_step "Creating application directories..."
    
    remote_exec "
        # Main application directories
        mkdir -p /opt/cloudya-infrastructure/{config,data,logs,backup,scripts,certs,tmp}
        mkdir -p /opt/cloudya-data/{vault,nomad,traefik,consul,monitoring,minio}
        mkdir -p /var/log/cloudya
        mkdir -p /var/backups/cloudya
        
        # Service-specific directories
        mkdir -p /opt/cloudya-data/vault/{data,config,logs,certs,backup}
        mkdir -p /opt/cloudya-data/nomad/{data,config,logs}
        mkdir -p /opt/cloudya-data/traefik/{config,certs,logs}
        mkdir -p /opt/cloudya-data/consul/{data,config,logs}
        mkdir -p /opt/cloudya-data/monitoring/{prometheus,grafana,alertmanager}
        mkdir -p /opt/cloudya-data/minio/data
        
        # Set appropriate permissions
        chown -R root:root /opt/cloudya-*
        chmod -R 755 /opt/cloudya-infrastructure
        chmod -R 700 /opt/cloudya-data/vault
        chmod -R 755 /opt/cloudya-data/nomad
        chmod -R 755 /opt/cloudya-data/traefik
        chmod -R 755 /opt/cloudya-data/consul
        chmod -R 755 /opt/cloudya-data/monitoring
        chmod -R 755 /opt/cloudya-data/minio
        
        # Log directories
        chmod 755 /var/log/cloudya
        chmod 755 /var/backups/cloudya
        
        # Create placeholder files for log rotation
        touch /var/log/cloudya/{vault,nomad,traefik,consul,deployment}.log
        chmod 644 /var/log/cloudya/*.log
        
        echo 'Application directories created successfully'
        
        # List created directories
        echo 'Created directory structure:'
        tree /opt/cloudya-* /var/log/cloudya /var/backups/cloudya 2>/dev/null || find /opt/cloudya-* /var/log/cloudya /var/backups/cloudya -type d | sort
        
    " "Creating application directories"
    
    log_success "Application directories created"
}

# Configure system services and maintenance
configure_system_services() {
    log_step "Configuring system services and maintenance..."
    
    remote_exec "
        # Configure log rotation for Cloudya services
        cat > /etc/logrotate.d/cloudya << 'EOLOG'
/var/log/cloudya/*.log {
    daily
    rotate 30
    compress
    delaycompress
    missingok
    notifempty
    create 0644 root root
    postrotate
        # Send SIGHUP to services to reopen log files
        systemctl reload-or-restart rsyslog >/dev/null 2>&1 || true
        # Restart Docker containers to reopen log files
        docker kill --signal=HUP \$(docker ps -q --filter \"name=cloudya-\") >/dev/null 2>&1 || true
    endscript
}
EOLOG
        
        # Configure automatic updates
        echo 'Configuring automatic security updates...'
        apt-get install -y -qq unattended-upgrades apt-listchanges
        
        cat > /etc/apt/apt.conf.d/50unattended-upgrades << 'EOUPDATE'
Unattended-Upgrade::Allowed-Origins {
    \"\${distro_id}:\${distro_codename}-security\";
    \"\${distro_id}ESMApps:\${distro_codename}-apps-security\";
    \"\${distro_id}ESM:\${distro_codename}-infra-security\";
};
Unattended-Upgrade::AutoFixInterruptedDpkg \"true\";
Unattended-Upgrade::MinimalSteps \"true\";
Unattended-Upgrade::Remove-Unused-Kernel-Packages \"true\";
Unattended-Upgrade::Remove-New-Unused-Dependencies \"true\";
Unattended-Upgrade::Remove-Unused-Dependencies \"true\";
Unattended-Upgrade::Automatic-Reboot \"false\";
Unattended-Upgrade::Automatic-Reboot-Time \"02:00\";
EOUPDATE
        
        cat > /etc/apt/apt.conf.d/20auto-upgrades << 'EOAUTO'
APT::Periodic::Update-Package-Lists \"1\";
APT::Periodic::Download-Upgradeable-Packages \"1\";
APT::Periodic::AutocleanInterval \"7\";
APT::Periodic::Unattended-Upgrade \"1\";
EOAUTO
        
        # Configure system maintenance cron jobs
        cat > /etc/cron.d/cloudya-maintenance << 'EOCRON'
# Cloudya System Maintenance Cron Jobs

# Daily cleanup and maintenance
0 2 * * * root /opt/cloudya-infrastructure/scripts/daily-maintenance.sh >/dev/null 2>&1

# Weekly system health check
0 3 * * 0 root /opt/cloudya-infrastructure/scripts/weekly-health-check.sh >/dev/null 2>&1

# Monthly backup cleanup
0 4 1 * * root find /var/backups/cloudya -type f -mtime +90 -delete >/dev/null 2>&1
EOCRON
        
        # Create maintenance scripts directory
        mkdir -p /opt/cloudya-infrastructure/scripts
        
        # Create daily maintenance script
        cat > /opt/cloudya-infrastructure/scripts/daily-maintenance.sh << 'EOMAINT'
#!/bin/bash
# Daily maintenance script for Cloudya infrastructure

LOG_FILE=\"/var/log/cloudya/maintenance.log\"

log() {
    echo \"[\$(date '+%Y-%m-%d %H:%M:%S')] \$1\" >> \$LOG_FILE
}

log \"Starting daily maintenance\"

# Cleanup Docker
log \"Cleaning up Docker resources\"
docker system prune -f >/dev/null 2>&1

# Cleanup old log files
log \"Cleaning up old log files\"
find /var/log/cloudya -name \"*.log\" -size +100M -exec truncate -s 50M {} \\; 2>/dev/null

# Check disk usage
log \"Checking disk usage\"
DISK_USAGE=\$(df / | tail -1 | awk '{print \$5}' | tr -d '%')
if [ \$DISK_USAGE -gt 85 ]; then
    log \"WARNING: Disk usage is \${DISK_USAGE}%\"
fi

# Check memory usage
log \"Checking memory usage\"
MEMORY_USAGE=\$(free | grep Mem | awk '{printf \"%.0f\", \$3/\$2 * 100}')
if [ \$MEMORY_USAGE -gt 90 ]; then
    log \"WARNING: Memory usage is \${MEMORY_USAGE}%\"
fi

# Restart services if needed
log \"Checking service health\"
for service in cloudya-vault cloudya-nomad cloudya-traefik; do
    if ! systemctl is-active --quiet \$service 2>/dev/null; then
        log \"WARNING: Service \$service is not running\"
        systemctl restart \$service && log \"Service \$service restarted\" || log \"ERROR: Failed to restart \$service\"
    fi
done

log \"Daily maintenance completed\"
EOMAINT
        
        chmod +x /opt/cloudya-infrastructure/scripts/daily-maintenance.sh
        
        # Create weekly health check script
        cat > /opt/cloudya-infrastructure/scripts/weekly-health-check.sh << 'EOHEALTH'
#!/bin/bash
# Weekly health check script for Cloudya infrastructure

LOG_FILE=\"/var/log/cloudya/health-check.log\"

log() {
    echo \"[\$(date '+%Y-%m-%d %H:%M:%S')] \$1\" >> \$LOG_FILE
}

log \"Starting weekly health check\"

# System health
log \"System uptime: \$(uptime -p)\"
log \"Load average: \$(uptime | awk -F'load average:' '{print \$2}')\"
log \"Memory usage: \$(free -h | grep '^Mem:')\"
log \"Disk usage: \$(df -h / | tail -1)\"

# Service health
for service in docker fail2ban ufw node_exporter; do
    if systemctl is-active --quiet \$service; then
        log \"Service \$service: Active\"
    else
        log \"Service \$service: Inactive\"
    fi
done

# Network connectivity
if ping -c 1 8.8.8.8 >/dev/null 2>&1; then
    log \"Network connectivity: OK\"
else
    log \"Network connectivity: FAIL\"
fi

# Certificate expiry check (if certificates exist)
if [ -d \"/opt/cloudya-data/traefik/certs\" ]; then
    for cert in /opt/cloudya-data/traefik/certs/*.crt; do
        if [ -f \"\$cert\" ]; then
            expiry=\$(openssl x509 -in \"\$cert\" -noout -dates | grep notAfter | cut -d= -f2)
            log \"Certificate \$(basename \$cert) expires: \$expiry\"
        fi
    done
fi

log \"Weekly health check completed\"
EOHEALTH
        
        chmod +x /opt/cloudya-infrastructure/scripts/weekly-health-check.sh
        
        echo 'System services and maintenance configured successfully'
    " "Configuring system services and maintenance"
    
    log_success "System services and maintenance configured"
}

# Validate provisioning
validate_provisioning() {
    log_step "Validating server provisioning..."
    
    local validation_output=$(remote_exec "
        echo 'Validation Report:'
        echo '=================='
        echo ''
        
        # System information
        echo 'System Information:'
        echo '  OS: '\$(lsb_release -d 2>/dev/null | cut -f2 || cat /etc/os-release | grep PRETTY_NAME | cut -d'\"' -f2)
        echo '  Kernel: '\$(uname -r)
        echo '  Uptime: '\$(uptime -p)
        echo ''
        
        # Package installations
        echo 'Installed Tools:'
        for tool in docker docker-compose vault nomad consul terraform node_exporter; do
            if command -v \$tool &> /dev/null; then
                version=\$(\$tool version 2>/dev/null | head -1 | awk '{print \$2}' || \$tool --version 2>/dev/null | head -1 | awk '{print \$3}' || echo 'installed')
                echo \"  ✓ \$tool: \$version\"
            else
                echo \"  ✗ \$tool: Not found\"
            fi
        done
        echo ''
        
        # Service status
        echo 'System Services:'
        for service in docker fail2ban ufw node_exporter filebeat; do
            if systemctl is-active --quiet \$service 2>/dev/null; then
                echo \"  ✓ \$service: Active\"
            elif systemctl list-unit-files \$service.service &>/dev/null; then
                echo \"  ✗ \$service: Inactive\"
            else
                echo \"  - \$service: Not installed\"
            fi
        done
        echo ''
        
        # Directory structure
        echo 'Directory Structure:'
        if [ -d '/opt/cloudya-infrastructure' ]; then
            echo '  ✓ /opt/cloudya-infrastructure: Exists'
        else
            echo '  ✗ /opt/cloudya-infrastructure: Missing'
        fi
        if [ -d '/opt/cloudya-data' ]; then
            echo '  ✓ /opt/cloudya-data: Exists'
        else
            echo '  ✗ /opt/cloudya-data: Missing'
        fi
        if [ -d '/var/log/cloudya' ]; then
            echo '  ✓ /var/log/cloudya: Exists'
        else
            echo '  ✗ /var/log/cloudya: Missing'
        fi
        echo ''
        
        # Network and security
        echo 'Security Configuration:'
        if ufw status | grep -q 'Status: active'; then
            echo '  ✓ UFW Firewall: Active'
        else
            echo '  ✗ UFW Firewall: Inactive'
        fi
        if systemctl is-active --quiet fail2ban; then
            echo '  ✓ Fail2ban: Active'
        else
            echo '  ✗ Fail2ban: Inactive'
        fi
        echo ''
        
        # Resource usage
        echo 'Resource Usage:'
        echo '  Memory: '\$(free -h | grep '^Mem:' | awk '{print \$3 \"/\" \$2}')
        echo '  Disk: '\$(df -h / | tail -1 | awk '{print \$3 \"/\" \$2 \" (\" \$5 \" used)\"}')
        echo '  Load: '\$(uptime | awk -F'load average:' '{print \$2}')
        echo ''
        
        echo 'Server provisioning validation completed'
    " "Running provisioning validation")
    
    echo "$validation_output"
    log_success "Server provisioning validation completed"
}

# Generate provisioning report
generate_report() {
    log_step "Generating provisioning report..."
    
    local report_file="/tmp/provisioning-report-$(date +%Y%m%d-%H%M%S).json"
    
    # Create provisioning report
    cat > "$report_file" << EOF
{
    "provisioning_timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "target_server": "$SERVER_HOST",
    "provisioning_options": {
        "dry_run": $DRY_RUN,
        "force_provision": $FORCE_PROVISION,
        "skip_security": $SKIP_SECURITY,
        "setup_monitoring": $SETUP_MONITORING,
        "install_docker": $INSTALL_DOCKER,
        "setup_firewall": $SETUP_FIREWALL
    },
    "log_file": "$LOG_FILE",
    "status": "completed"
}
EOF
    
    log_success "Provisioning report generated: $report_file"
    
    # Display summary
    echo ""
    log_info "========================================="
    log_info "    PROVISIONING SUMMARY"
    log_info "========================================="
    log_info "Target Server: $SERVER_HOST"
    log_info "Provisioning Log: $LOG_FILE"
    log_info "Report File: $report_file"
    echo ""
    log_info "Next Steps:"
    log_info "1. Run the remote deployment script:"
    log_info "   ./scripts/remote-deploy.sh"
    log_info "2. Configure SSL certificates"
    log_info "3. Initialize Vault and create initial secrets"
    log_info "4. Deploy applications using Nomad"
    log_info "5. Configure monitoring dashboards"
    echo ""
    log_success "Server provisioning completed successfully!"
}

# Main execution function
main() {
    echo -e "${WHITE}Cloudya Server Provisioning Script${NC}"
    echo -e "${WHITE}===================================${NC}"
    echo ""
    
    # Parse and validate arguments
    parse_arguments "$@"
    
    # Show configuration
    echo -e "${WHITE}Configuration:${NC}"
    echo -e "  Target Server: ${CYAN}$SERVER_HOST${NC}"
    echo -e "  Dry Run: ${CYAN}$DRY_RUN${NC}"
    echo -e "  Force Provision: ${CYAN}$FORCE_PROVISION${NC}"
    echo -e "  Skip Security: ${CYAN}$SKIP_SECURITY${NC}"
    echo -e "  Setup Monitoring: ${CYAN}$SETUP_MONITORING${NC}"
    echo -e "  Install Docker: ${CYAN}$INSTALL_DOCKER${NC}"
    echo -e "  Setup Firewall: ${CYAN}$SETUP_FIREWALL${NC}"
    echo ""
    
    # Safety confirmation
    if [[ "$FORCE_PROVISION" != "true" && "$DRY_RUN" != "true" ]]; then
        log_warning "This will provision and configure the server: $SERVER_HOST"
        log_warning "This may modify system packages and configuration"
        echo ""
        read -p "Are you sure you want to continue? [y/N]: " -n 1 -r
        echo ""
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Provisioning cancelled by user"
            exit 0
        fi
    fi
    
    # Execute provisioning steps
    validate_prerequisites
    check_server_info
    update_system
    install_essential_packages
    configure_security
    install_docker
    install_hashicorp_tools
    setup_monitoring
    create_directories
    configure_system_services
    validate_provisioning
    generate_report
}

# Execute main function with all arguments
main "$@"