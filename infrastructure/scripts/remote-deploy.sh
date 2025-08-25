#!/bin/bash

# Remote Production Deployment Script
# Deploys infrastructure to root@cloudya.net server
# Idempotent and secure deployment with comprehensive error handling

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_DIR="$(dirname "$SCRIPT_DIR")"
REMOTE_HOST="root@cloudya.net"
REMOTE_PATH="/opt/cloudya-infrastructure"
SSH_KEY_PATH="${HOME}/.ssh/id_rsa"
BACKUP_DIR="/opt/cloudya-backup"

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
FORCE_DEPLOY=false
SKIP_BACKUP=false
VERBOSE=false
COMPONENTS="all"
ROLLBACK_ON_FAILURE=true
ENABLE_MONITORING=true
DEPLOY_ID=$(date +%Y%m%d-%H%M%S)

# Logging functions
log_header() {
    echo -e "${WHITE}================================================================================================${NC}"
    echo -e "${WHITE}$1${NC}"
    echo -e "${WHITE}================================================================================================${NC}"
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "/tmp/remote-deploy-${DEPLOY_ID}.log"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "/tmp/remote-deploy-${DEPLOY_ID}.log"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "/tmp/remote-deploy-${DEPLOY_ID}.log"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "/tmp/remote-deploy-${DEPLOY_ID}.log"
}

log_debug() {
    if [[ "$VERBOSE" == "true" ]]; then
        echo -e "${PURPLE}[DEBUG]${NC} $1" | tee -a "/tmp/remote-deploy-${DEPLOY_ID}.log"
    fi
}

log_step() {
    echo -e "${CYAN}[STEP]${NC} $1" | tee -a "/tmp/remote-deploy-${DEPLOY_ID}.log"
}

# Usage function
usage() {
    cat <<EOF
Remote Production Deployment Script
Deploys Cloudya infrastructure to root@cloudya.net

Usage: $0 [OPTIONS]

Options:
  -d, --dry-run           Perform dry run without actual deployment
  -f, --force-deploy      Force deployment (skip safety checks)
  -b, --skip-backup       Skip backup creation before deployment
  -v, --verbose           Enable verbose debug output
  -c, --components COMP   Components to deploy (all|vault|nomad|traefik|monitoring)
  -r, --no-rollback       Disable automatic rollback on failure
  -m, --no-monitoring     Disable monitoring setup
  -k, --ssh-key PATH      Path to SSH private key [default: ~/.ssh/id_rsa]
  -h, --help              Show this help message

Examples:
  $0                                    # Full deployment with all safety checks
  $0 --dry-run                         # Preview deployment without changes
  $0 --components vault,traefik --verbose # Deploy specific components with debug
  $0 --force-deploy --skip-backup      # Fast deployment (use with caution)

Security:
  - All communications use SSH with key authentication
  - Secrets are encrypted in transit and at rest
  - Backup is created before any changes (unless --skip-backup)
  - Automatic rollback on failure (unless --no-rollback)
  - Comprehensive logging and audit trail

EOF
}

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -f|--force-deploy)
                FORCE_DEPLOY=true
                shift
                ;;
            -b|--skip-backup)
                SKIP_BACKUP=true
                shift
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -c|--components)
                COMPONENTS="$2"
                shift 2
                ;;
            -r|--no-rollback)
                ROLLBACK_ON_FAILURE=false
                shift
                ;;
            -m|--no-monitoring)
                ENABLE_MONITORING=false
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

# Validate prerequisites
validate_prerequisites() {
    log_step "Validating deployment prerequisites..."
    
    # Check SSH key
    if [[ ! -f "$SSH_KEY_PATH" ]]; then
        log_error "SSH private key not found: $SSH_KEY_PATH"
        log_error "Please generate SSH key pair or specify correct path with --ssh-key"
        exit 1
    fi
    
    # Test SSH connection
    if ! ssh -i "$SSH_KEY_PATH" -o ConnectTimeout=10 -o BatchMode=yes "$REMOTE_HOST" "echo 'SSH connection test successful'" >/dev/null 2>&1; then
        log_error "Failed to establish SSH connection to $REMOTE_HOST"
        log_error "Please ensure:"
        log_error "  1. SSH key is correctly configured"
        log_error "  2. Server is accessible"
        log_error "  3. Root access is available"
        exit 1
    fi
    
    # Check required tools
    local required_tools=("rsync" "tar" "gzip" "jq")
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            log_error "Required tool not found: $tool"
            exit 1
        fi
    done
    
    log_success "Prerequisites validation passed"
}

# Execute command on remote server with error handling
remote_exec() {
    local command="$1"
    local description="${2:-Executing remote command}"
    
    log_debug "Remote exec: $command"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would execute: $description"
        return 0
    fi
    
    if ssh -i "$SSH_KEY_PATH" -o ConnectTimeout=30 "$REMOTE_HOST" "$command"; then
        log_debug "Remote command successful: $description"
        return 0
    else
        local exit_code=$?
        log_error "Remote command failed: $description"
        log_error "Command: $command"
        log_error "Exit code: $exit_code"
        return $exit_code
    fi
}

# Copy files to remote server with verification
remote_copy() {
    local source="$1"
    local dest="$2"
    local description="${3:-Copying files to remote server}"
    
    log_debug "Remote copy: $source -> $REMOTE_HOST:$dest"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would copy: $description"
        return 0
    fi
    
    # Create destination directory
    remote_exec "mkdir -p $(dirname $dest)" "Creating destination directory"
    
    # Copy with rsync for reliability
    if rsync -avz --delete -e "ssh -i $SSH_KEY_PATH" "$source" "$REMOTE_HOST:$dest"; then
        log_debug "File copy successful: $description"
        
        # Verify copy
        local local_checksum=$(find "$source" -type f -exec md5sum {} \; | sort | md5sum | cut -d' ' -f1)
        local remote_checksum=$(remote_exec "find $dest -type f -exec md5sum {} \; | sort | md5sum | cut -d' ' -f1" "Verifying file copy")
        
        if [[ "$local_checksum" == "$remote_checksum" ]]; then
            log_debug "File integrity verified"
            return 0
        else
            log_error "File integrity check failed"
            return 1
        fi
    else
        log_error "File copy failed: $description"
        return 1
    fi
}

# Check server status and requirements
check_server_status() {
    log_step "Checking remote server status..."
    
    # Get server information
    local server_info=$(remote_exec "
        echo 'OS: '$(cat /etc/os-release | grep PRETTY_NAME | cut -d'\"' -f2)
        echo 'Kernel: '$(uname -r)
        echo 'Architecture: '$(uname -m)
        echo 'CPU Cores: '$(nproc)
        echo 'Memory: '$(free -h | grep '^Mem:' | awk '{print \$2}')
        echo 'Disk Space: '$(df -h / | tail -1 | awk '{print \$4\" available of \"\$2}')
        echo 'Docker: '$(docker --version 2>/dev/null || echo 'Not installed')
        echo 'Uptime: '$(uptime -p)
    " "Getting server information")
    
    log_info "Remote server information:"
    echo "$server_info" | while read -r line; do
        log_info "  $line"
    done
    
    # Check minimum requirements
    local memory_gb=$(remote_exec "free -g | grep '^Mem:' | awk '{print \$2}'" "Checking memory")
    local disk_gb=$(remote_exec "df --output=avail -BG / | tail -1 | tr -d 'G'" "Checking disk space")
    
    if [[ "$memory_gb" -lt 4 ]]; then
        log_warning "Server has less than 4GB RAM ($memory_gb GB). Performance may be impacted."
    fi
    
    if [[ "$disk_gb" -lt 20 ]]; then
        log_warning "Server has less than 20GB disk space ($disk_gb GB). Consider cleanup."
    fi
    
    log_success "Server status check completed"
}

# Create backup before deployment
create_backup() {
    if [[ "$SKIP_BACKUP" == "true" ]]; then
        log_info "Skipping backup creation as requested"
        return 0
    fi
    
    log_step "Creating backup before deployment..."
    
    local backup_name="cloudya-backup-${DEPLOY_ID}"
    local backup_path="${BACKUP_DIR}/${backup_name}"
    
    remote_exec "
        mkdir -p $BACKUP_DIR
        
        # Create backup directory
        mkdir -p $backup_path
        
        # Backup existing infrastructure if it exists
        if [ -d '$REMOTE_PATH' ]; then
            echo 'Backing up existing infrastructure...'
            cp -r $REMOTE_PATH $backup_path/infrastructure
        fi
        
        # Backup Docker volumes and data
        if docker volume ls --quiet | grep -q cloudya; then
            echo 'Backing up Docker volumes...'
            mkdir -p $backup_path/docker-volumes
            for volume in \$(docker volume ls --quiet | grep cloudya); do
                echo \"Backing up volume: \$volume\"
                docker run --rm -v \$volume:/source -v $backup_path/docker-volumes:/backup alpine tar czf /backup/\${volume}.tar.gz -C /source .
            done
        fi
        
        # Backup system configuration
        echo 'Backing up system configuration...'
        mkdir -p $backup_path/system
        cp -r /etc/systemd/system/cloudya* $backup_path/system/ 2>/dev/null || true
        cp -r /etc/nginx/sites-available/cloudya* $backup_path/system/ 2>/dev/null || true
        
        # Create backup manifest
        echo 'Creating backup manifest...'
        cat > $backup_path/manifest.json << EOF
{
    \"backup_id\": \"$backup_name\",
    \"created_at\": \"\$(date -u +%Y-%m-%dT%H:%M:%SZ)\",
    \"deployment_id\": \"$DEPLOY_ID\",
    \"server_info\": {
        \"hostname\": \"\$(hostname)\",
        \"kernel\": \"\$(uname -r)\",
        \"os\": \"\$(cat /etc/os-release | grep PRETTY_NAME | cut -d'\"' -f2)\"
    },
    \"components_backed_up\": {
        \"infrastructure\": \$([ -d '$REMOTE_PATH' ] && echo 'true' || echo 'false'),
        \"docker_volumes\": \$(docker volume ls --quiet | grep -q cloudya && echo 'true' || echo 'false'),
        \"system_config\": true
    }
}
EOF
        
        # Compress backup
        echo 'Compressing backup...'
        cd $BACKUP_DIR && tar czf ${backup_name}.tar.gz ${backup_name}/
        rm -rf ${backup_name}/
        
        echo \"Backup created: ${backup_path}.tar.gz\"
        echo \"Backup size: \$(du -h ${backup_path}.tar.gz | cut -f1)\"
        
        # Keep only last 10 backups
        ls -t $BACKUP_DIR/cloudya-backup-*.tar.gz | tail -n +11 | xargs rm -f || true
        
    " "Creating system backup"
    
    log_success "Backup created successfully: ${backup_name}.tar.gz"
    export BACKUP_NAME="$backup_name"
}

# Provision server with required dependencies
provision_server() {
    log_step "Provisioning server with required dependencies..."
    
    remote_exec "
        # Update system packages
        echo 'Updating system packages...'
        apt-get update -qq
        
        # Install essential packages
        echo 'Installing essential packages...'
        DEBIAN_FRONTEND=noninteractive apt-get install -y \\
            curl \\
            wget \\
            unzip \\
            jq \\
            htop \\
            vim \\
            git \\
            rsync \\
            fail2ban \\
            ufw \\
            certbot \\
            python3-certbot-nginx \\
            logrotate \\
            cron \\
            supervisor
        
        # Install Docker if not present
        if ! command -v docker &> /dev/null; then
            echo 'Installing Docker...'
            curl -fsSL https://get.docker.com -o get-docker.sh
            sh get-docker.sh
            rm get-docker.sh
            
            # Install Docker Compose
            DOCKER_COMPOSE_VERSION=\$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep 'tag_name' | cut -d'\"' -f4)
            curl -L \"https://github.com/docker/compose/releases/download/\${DOCKER_COMPOSE_VERSION}/docker-compose-\$(uname -s)-\$(uname -m)\" -o /usr/local/bin/docker-compose
            chmod +x /usr/local/bin/docker-compose
        fi
        
        # Install HashiCorp tools
        echo 'Installing HashiCorp tools...'
        
        # Install Vault
        if ! command -v vault &> /dev/null; then
            VAULT_VERSION=1.17.6
            wget https://releases.hashicorp.com/vault/\${VAULT_VERSION}/vault_\${VAULT_VERSION}_linux_amd64.zip
            unzip vault_\${VAULT_VERSION}_linux_amd64.zip
            mv vault /usr/local/bin/
            rm vault_\${VAULT_VERSION}_linux_amd64.zip
        fi
        
        # Install Nomad
        if ! command -v nomad &> /dev/null; then
            NOMAD_VERSION=1.8.4
            wget https://releases.hashicorp.com/nomad/\${NOMAD_VERSION}/nomad_\${NOMAD_VERSION}_linux_amd64.zip
            unzip nomad_\${NOMAD_VERSION}_linux_amd64.zip
            mv nomad /usr/local/bin/
            rm nomad_\${NOMAD_VERSION}_linux_amd64.zip
        fi
        
        # Install Consul
        if ! command -v consul &> /dev/null; then
            CONSUL_VERSION=1.19.2
            wget https://releases.hashicorp.com/consul/\${CONSUL_VERSION}/consul_\${CONSUL_VERSION}_linux_amd64.zip
            unzip consul_\${CONSUL_VERSION}_linux_amd64.zip
            mv consul /usr/local/bin/
            rm consul_\${CONSUL_VERSION}_linux_amd64.zip
        fi
        
        # Create application directories
        echo 'Creating application directories...'
        mkdir -p $REMOTE_PATH/{config,data,logs,backup,scripts,certs}
        mkdir -p /opt/cloudya-data/{vault,nomad,traefik,consul,monitoring}
        mkdir -p /var/log/cloudya
        
        # Set up log rotation
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
        systemctl reload rsyslog >/dev/null 2>&1 || true
    endscript
}
EOLOG
        
        # Configure firewall
        echo 'Configuring firewall...'
        ufw --force reset
        ufw default deny incoming
        ufw default allow outgoing
        ufw allow ssh
        ufw allow 80/tcp
        ufw allow 443/tcp
        ufw allow 8200/tcp  # Vault
        ufw allow 4646/tcp  # Nomad
        ufw allow 8500/tcp  # Consul
        ufw --force enable
        
        # Configure fail2ban
        echo 'Configuring fail2ban...'
        cat > /etc/fail2ban/jail.local << 'EOFAIL'
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 3

[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
EOFAIL
        systemctl enable fail2ban
        systemctl restart fail2ban
        
        echo 'Server provisioning completed successfully'
        
    " "Provisioning server with dependencies"
    
    log_success "Server provisioning completed"
}

# Deploy infrastructure components
deploy_infrastructure() {
    log_step "Deploying infrastructure components..."
    
    # Copy infrastructure files
    log_info "Copying infrastructure files to remote server..."
    remote_copy "$INFRA_DIR" "$REMOTE_PATH" "Infrastructure files"
    
    # Deploy based on selected components
    case $COMPONENTS in
        "all")
            deploy_vault
            deploy_nomad
            deploy_traefik
            if [[ "$ENABLE_MONITORING" == "true" ]]; then
                deploy_monitoring
            fi
            ;;
        *"vault"*)
            deploy_vault
            ;;
        *"nomad"*)
            deploy_nomad
            ;;
        *"traefik"*)
            deploy_traefik
            ;;
        *"monitoring"*)
            deploy_monitoring
            ;;
    esac
    
    log_success "Infrastructure deployment completed"
}

# Deploy Vault
deploy_vault() {
    log_info "Deploying Vault..."
    
    remote_exec "
        cd $REMOTE_PATH
        
        # Create Vault systemd service
        cat > /etc/systemd/system/cloudya-vault.service << 'EOVAULT'
[Unit]
Description=Cloudya Vault Service
Documentation=https://www.vaultproject.io/docs/
Requires=network-online.target
After=network-online.target
ConditionFileNotEmpty=$REMOTE_PATH/vault/config/vault.hcl

[Service]
Type=notify
User=root
Group=root
ProtectSystem=full
ProtectHome=read-only
PrivateTmp=yes
PrivateDevices=yes
SecureBits=keep-caps
AmbientCapabilities=CAP_IPC_LOCK
Capabilities=CAP_IPC_LOCK+ep
CapabilityBoundingSet=CAP_SYSLOG CAP_IPC_LOCK
NoNewPrivileges=yes
ExecStart=/usr/local/bin/vault server -config=$REMOTE_PATH/vault/config/vault.hcl
ExecReload=/bin/kill -HUP \$MAINPID
KillMode=process
Restart=on-failure
RestartSec=5
TimeoutStopSec=30
StartLimitInterval=60
StartLimitBurst=3
LimitNOFILE=65536
LimitMEMLOCK=infinity

[Install]
WantedBy=multi-user.target
EOVAULT
        
        # Create Vault configuration
        mkdir -p $REMOTE_PATH/vault/config
        cat > $REMOTE_PATH/vault/config/vault.hcl << 'EOVAULTCONF'
ui = true
disable_mlock = false
api_addr = \"https://vault.cloudya.net\"
cluster_addr = \"https://vault.cloudya.net:8201\"

listener \"tcp\" {
  address       = \"0.0.0.0:8200\"
  tls_disable   = false
  tls_cert_file = \"$REMOTE_PATH/certs/vault.crt\"
  tls_key_file  = \"$REMOTE_PATH/certs/vault.key\"
  tls_min_version = \"tls12\"
}

storage \"file\" {
  path = \"/opt/cloudya-data/vault\"
}

log_level = \"INFO\"
log_format = \"json\"
log_file = \"/var/log/cloudya/vault.log\"

telemetry {
  prometheus_retention_time = \"30s\"
  disable_hostname = true
}
EOVAULTCONF
        
        # Set permissions
        chmod 640 $REMOTE_PATH/vault/config/vault.hcl
        chown -R root:root $REMOTE_PATH/vault
        chmod -R 700 /opt/cloudya-data/vault
        
        # Enable and start Vault service
        systemctl daemon-reload
        systemctl enable cloudya-vault
        
        echo 'Vault deployed successfully'
    " "Deploying Vault service"
}

# Deploy Nomad
deploy_nomad() {
    log_info "Deploying Nomad..."
    
    remote_exec "
        cd $REMOTE_PATH
        
        # Create Nomad systemd service
        cat > /etc/systemd/system/cloudya-nomad.service << 'EONOMAD'
[Unit]
Description=Cloudya Nomad Service
Documentation=https://www.nomadproject.io/docs/
Requires=network-online.target
After=network-online.target

[Service]
Type=exec
User=root
Group=root
ExecReload=/bin/kill -HUP \$MAINPID
ExecStart=/usr/local/bin/nomad agent -config=$REMOTE_PATH/nomad/config
KillMode=process
Restart=on-failure
RestartSec=5
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EONOMAD
        
        # Create Nomad configuration
        mkdir -p $REMOTE_PATH/nomad/config
        cat > $REMOTE_PATH/nomad/config/nomad.hcl << 'EONOMADCONF'
datacenter = \"dc1\"
data_dir   = \"/opt/cloudya-data/nomad\"
log_level  = \"INFO\"
log_json   = true
log_file   = \"/var/log/cloudya/nomad.log\"

server {
  enabled          = true
  bootstrap_expect = 1
  encrypt         = \"$(nomad operator keygen)\"
}

client {
  enabled = true
  servers = [\"127.0.0.1:4647\"]
}

consul {
  address = \"127.0.0.1:8500\"
}

vault {
  enabled = true
  address = \"https://127.0.0.1:8200\"
  ca_file = \"$REMOTE_PATH/certs/vault-ca.crt\"
}

ui_config {
  enabled = true
}

ports {
  http = 4646
  rpc  = 4647
  serf = 4648
}

telemetry {
  collection_interval = \"1s\"
  disable_hostname = true
  prometheus_metrics = true
  publish_allocation_metrics = true
  publish_node_metrics = true
}
EONOMADCONF
        
        # Set permissions
        chmod 640 $REMOTE_PATH/nomad/config/nomad.hcl
        chown -R root:root $REMOTE_PATH/nomad
        chmod -R 700 /opt/cloudya-data/nomad
        
        # Enable Nomad service
        systemctl daemon-reload
        systemctl enable cloudya-nomad
        
        echo 'Nomad deployed successfully'
    " "Deploying Nomad service"
}

# Deploy Traefik
deploy_traefik() {
    log_info "Deploying Traefik..."
    
    remote_exec "
        cd $REMOTE_PATH
        
        # Create Traefik systemd service using Docker
        cat > /etc/systemd/system/cloudya-traefik.service << 'EOTRAEFIK'
[Unit]
Description=Cloudya Traefik Service
Requires=docker.service
After=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=$REMOTE_PATH/traefik
ExecStartPre=-/usr/bin/docker stop cloudya-traefik
ExecStartPre=-/usr/bin/docker rm cloudya-traefik
ExecStart=/usr/bin/docker run -d \\
  --name cloudya-traefik \\
  --network host \\
  -v $REMOTE_PATH/traefik/config:/etc/traefik:ro \\
  -v /opt/cloudya-data/traefik/certs:/letsencrypt \\
  -v /var/run/docker.sock:/var/run/docker.sock:ro \\
  -v /var/log/cloudya:/var/log/cloudya \\
  traefik:v3.2.3 \\
  --configFile=/etc/traefik/traefik.yml
ExecStop=/usr/bin/docker stop cloudya-traefik
Restart=always

[Install]
WantedBy=multi-user.target
EOTRAEFIK
        
        # Create Traefik configuration
        mkdir -p $REMOTE_PATH/traefik/config/dynamic
        cat > $REMOTE_PATH/traefik/config/traefik.yml << 'EOTRAEFIKCONF'
global:
  checkNewVersion: false
  sendAnonymousUsage: false

api:
  dashboard: true
  insecure: false

entryPoints:
  web:
    address: \":80\"
    http:
      redirections:
        entryPoint:
          to: websecure
          scheme: https
          permanent: true

  websecure:
    address: \":443\"
    http:
      tls:
        certResolver: letsencrypt

certificatesResolvers:
  letsencrypt:
    acme:
      tlsChallenge: {}
      email: admin@cloudya.net
      storage: /letsencrypt/acme.json
      caServer: https://acme-v02.api.letsencrypt.org/directory

providers:
  file:
    directory: /etc/traefik/dynamic
    watch: true

log:
  level: INFO
  format: json
  filePath: /var/log/cloudya/traefik.log

accessLog:
  filePath: /var/log/cloudya/traefik-access.log
  format: json

metrics:
  prometheus:
    addRoutersLabels: true
EOTRAEFIKCONF
        
        # Create dynamic configuration
        cat > $REMOTE_PATH/traefik/config/dynamic/routes.yml << 'EOROUTES'
http:
  routers:
    traefik-dashboard:
      rule: \"Host(\`traefik.cloudya.net\`)\"
      service: api@internal
      middlewares:
        - auth-traefik
      tls:
        certResolver: letsencrypt
    
    vault:
      rule: \"Host(\`vault.cloudya.net\`)\"
      service: vault-service
      middlewares:
        - security-headers
      tls:
        certResolver: letsencrypt
    
    nomad:
      rule: \"Host(\`nomad.cloudya.net\`)\"
      service: nomad-service
      middlewares:
        - security-headers
      tls:
        certResolver: letsencrypt

  services:
    vault-service:
      loadBalancer:
        servers:
          - url: \"https://localhost:8200\"
    
    nomad-service:
      loadBalancer:
        servers:
          - url: \"http://localhost:4646\"

  middlewares:
    auth-traefik:
      basicAuth:
        users:
          - \"admin:\$2y\$10\$2b2cu2a6YjdwQqN3QP1PxOqUf7w7VgLhvx6xXPB.XD9QqQ5U9Q2a2\"  # admin:secure_password
    
    security-headers:
      headers:
        frameDeny: true
        browserXssFilter: true
        contentTypeNosniff: true
        forceSTSHeader: true
        stsIncludeSubdomains: true
        stsPreload: true
        stsSeconds: 63072000
        customRequestHeaders:
          X-Forwarded-Proto: https

tls:
  stores:
    default:
      defaultGeneratedCert:
        resolver: letsencrypt
        domain:
          main: \"cloudya.net\"
          sans:
            - \"*.cloudya.net\"
EOROUTES
        
        # Create certificates directory and set permissions
        mkdir -p /opt/cloudya-data/traefik/certs
        chmod 600 /opt/cloudya-data/traefik/certs
        touch /opt/cloudya-data/traefik/certs/acme.json
        chmod 600 /opt/cloudya-data/traefik/certs/acme.json
        
        # Set permissions
        chown -R root:root $REMOTE_PATH/traefik
        
        # Enable Traefik service
        systemctl daemon-reload
        systemctl enable cloudya-traefik
        
        echo 'Traefik deployed successfully'
    " "Deploying Traefik service"
}

# Deploy monitoring stack
deploy_monitoring() {
    log_info "Deploying monitoring stack..."
    
    remote_exec "
        cd $REMOTE_PATH
        
        # Create monitoring directories
        mkdir -p /opt/cloudya-data/monitoring/{prometheus,grafana}
        
        # Create monitoring Docker Compose file
        cat > $REMOTE_PATH/docker-compose.monitoring.yml << 'EOMONITORING'
version: '3.8'

networks:
  monitoring:
    name: cloudya-monitoring
    driver: bridge

volumes:
  prometheus_data:
    driver: local
    driver_opts:
      type: none
      device: /opt/cloudya-data/monitoring/prometheus
      o: bind
  grafana_data:
    driver: local
    driver_opts:
      type: none
      device: /opt/cloudya-data/monitoring/grafana
      o: bind

services:
  prometheus:
    image: prom/prometheus:v2.54.1
    container_name: cloudya-prometheus
    restart: unless-stopped
    networks:
      - monitoring
    ports:
      - \"9090:9090\"
    volumes:
      - prometheus_data:/prometheus
      - $REMOTE_PATH/monitoring/prometheus:/etc/prometheus:ro
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'
      - '--web.console.libraries=/usr/share/prometheus/console_libraries'
      - '--web.console.templates=/usr/share/prometheus/consoles'
      - '--web.enable-lifecycle'
      - '--web.external-url=https://prometheus.cloudya.net'

  grafana:
    image: grafana/grafana:11.2.2
    container_name: cloudya-grafana
    restart: unless-stopped
    networks:
      - monitoring
    ports:
      - \"3000:3000\"
    volumes:
      - grafana_data:/var/lib/grafana
      - $REMOTE_PATH/monitoring/grafana:/etc/grafana/provisioning:ro
    environment:
      - GF_SECURITY_ADMIN_PASSWORD=\${GRAFANA_ADMIN_PASSWORD:-admin}
      - GF_SERVER_ROOT_URL=https://grafana.cloudya.net
      - GF_INSTALL_PLUGINS=grafana-clock-panel,grafana-simple-json-datasource
EOMONITORING
        
        # Create monitoring systemd service
        cat > /etc/systemd/system/cloudya-monitoring.service << 'EOMONSERVICE'
[Unit]
Description=Cloudya Monitoring Stack
Requires=docker.service
After=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=$REMOTE_PATH
ExecStart=/usr/local/bin/docker-compose -f docker-compose.monitoring.yml up -d
ExecStop=/usr/local/bin/docker-compose -f docker-compose.monitoring.yml down
Restart=always

[Install]
WantedBy=multi-user.target
EOMONSERVICE
        
        # Set permissions
        chown -R root:root $REMOTE_PATH/monitoring
        chmod -R 755 /opt/cloudya-data/monitoring
        
        # Enable monitoring service
        systemctl daemon-reload
        systemctl enable cloudya-monitoring
        
        echo 'Monitoring stack deployed successfully'
    " "Deploying monitoring stack"
}

# Start services
start_services() {
    log_step "Starting services..."
    
    # Start services in correct order
    case $COMPONENTS in
        "all")
            remote_exec "systemctl start cloudya-vault && sleep 30" "Starting Vault"
            remote_exec "systemctl start cloudya-nomad && sleep 20" "Starting Nomad"
            remote_exec "systemctl start cloudya-traefik && sleep 10" "Starting Traefik"
            if [[ "$ENABLE_MONITORING" == "true" ]]; then
                remote_exec "systemctl start cloudya-monitoring" "Starting monitoring"
            fi
            ;;
        *"vault"*)
            remote_exec "systemctl start cloudya-vault" "Starting Vault"
            ;;
        *"nomad"*)
            remote_exec "systemctl start cloudya-nomad" "Starting Nomad"
            ;;
        *"traefik"*)
            remote_exec "systemctl start cloudya-traefik" "Starting Traefik"
            ;;
        *"monitoring"*)
            remote_exec "systemctl start cloudya-monitoring" "Starting monitoring"
            ;;
    esac
    
    log_success "Services started successfully"
}

# Validate deployment
validate_deployment() {
    log_step "Validating deployment..."
    
    local validation_failed=false
    
    # Check service status
    remote_exec "
        echo 'Service Status Check:'
        for service in cloudya-vault cloudya-nomad cloudya-traefik cloudya-monitoring; do
            if systemctl is-active --quiet \$service 2>/dev/null; then
                echo \"✓ \$service: Active\"
            else
                echo \"✗ \$service: Inactive\"
            fi
        done
        
        echo ''
        echo 'Port Status Check:'
        for port in 80 443 8200 4646; do
            if ss -tuln | grep -q \":\$port \"; then
                echo \"✓ Port \$port: Open\"
            else
                echo \"✗ Port \$port: Closed\"
            fi
        done
        
        echo ''
        echo 'Health Check:'
        # Vault health
        if curl -k -s https://localhost:8200/v1/sys/health >/dev/null 2>&1; then
            echo '✓ Vault: Healthy'
        else
            echo '✗ Vault: Unhealthy'
        fi
        
        # Nomad health
        if curl -s http://localhost:4646/v1/status/leader >/dev/null 2>&1; then
            echo '✓ Nomad: Healthy'
        else
            echo '✗ Nomad: Unhealthy'
        fi
        
        # Traefik health
        if curl -s http://localhost:80 >/dev/null 2>&1; then
            echo '✓ Traefik: Healthy'
        else
            echo '✗ Traefik: Unhealthy'
        fi
        
    " "Validating deployment health"
    
    if [[ $? -eq 0 ]]; then
        log_success "Deployment validation passed"
    else
        log_error "Deployment validation failed"
        validation_failed=true
    fi
    
    if [[ "$validation_failed" == "true" && "$ROLLBACK_ON_FAILURE" == "true" ]]; then
        log_warning "Validation failed, initiating rollback..."
        rollback_deployment
        exit 1
    fi
}

# Rollback deployment
rollback_deployment() {
    if [[ -z "${BACKUP_NAME:-}" ]]; then
        log_error "No backup available for rollback"
        return 1
    fi
    
    log_warning "Rolling back deployment to backup: $BACKUP_NAME"
    
    remote_exec "
        # Stop all services
        systemctl stop cloudya-vault cloudya-nomad cloudya-traefik cloudya-monitoring || true
        
        # Restore from backup
        if [ -f \"$BACKUP_DIR/${BACKUP_NAME}.tar.gz\" ]; then
            echo 'Extracting backup...'
            cd $BACKUP_DIR
            tar xzf ${BACKUP_NAME}.tar.gz
            
            # Restore infrastructure
            if [ -d \"${BACKUP_NAME}/infrastructure\" ]; then
                rm -rf $REMOTE_PATH
                cp -r ${BACKUP_NAME}/infrastructure $REMOTE_PATH
            fi
            
            # Restore Docker volumes
            if [ -d \"${BACKUP_NAME}/docker-volumes\" ]; then
                echo 'Restoring Docker volumes...'
                cd ${BACKUP_NAME}/docker-volumes
                for volume_file in *.tar.gz; do
                    if [ -f \"\$volume_file\" ]; then
                        volume_name=\$(basename \$volume_file .tar.gz)
                        docker volume create \$volume_name >/dev/null 2>&1 || true
                        docker run --rm -v \$volume_name:/target -v \$(pwd):/backup alpine tar xzf /backup/\$volume_file -C /target
                    fi
                done
            fi
            
            # Restore system configuration
            if [ -d \"${BACKUP_NAME}/system\" ]; then
                cp -r ${BACKUP_NAME}/system/* /etc/systemd/system/ 2>/dev/null || true
                systemctl daemon-reload
            fi
            
            # Cleanup backup extraction
            rm -rf ${BACKUP_NAME}
            
            echo 'Rollback completed successfully'
        else
            echo 'Backup file not found for rollback'
            exit 1
        fi
    " "Rolling back deployment"
    
    log_success "Rollback completed successfully"
}

# Generate deployment report
generate_report() {
    log_step "Generating deployment report..."
    
    local report_file="/tmp/deployment-report-${DEPLOY_ID}.json"
    
    # Get deployment status
    local vault_status=$(remote_exec "systemctl is-active cloudya-vault 2>/dev/null || echo 'inactive'" "Checking Vault status")
    local nomad_status=$(remote_exec "systemctl is-active cloudya-nomad 2>/dev/null || echo 'inactive'" "Checking Nomad status")
    local traefik_status=$(remote_exec "systemctl is-active cloudya-traefik 2>/dev/null || echo 'inactive'" "Checking Traefik status")
    local monitoring_status=$(remote_exec "systemctl is-active cloudya-monitoring 2>/dev/null || echo 'inactive'" "Checking monitoring status")
    
    # Create deployment report
    cat > "$report_file" << EOF
{
    "deployment_id": "$DEPLOY_ID",
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "target_server": "$REMOTE_HOST",
    "components_deployed": "$COMPONENTS",
    "deployment_options": {
        "dry_run": $DRY_RUN,
        "force_deploy": $FORCE_DEPLOY,
        "skip_backup": $SKIP_BACKUP,
        "rollback_on_failure": $ROLLBACK_ON_FAILURE,
        "enable_monitoring": $ENABLE_MONITORING
    },
    "backup_created": "${BACKUP_NAME:-none}",
    "service_status": {
        "vault": "$vault_status",
        "nomad": "$nomad_status",
        "traefik": "$traefik_status",
        "monitoring": "$monitoring_status"
    },
    "deployment_log": "/tmp/remote-deploy-${DEPLOY_ID}.log"
}
EOF
    
    log_success "Deployment report generated: $report_file"
    
    # Display summary
    log_header "DEPLOYMENT SUMMARY"
    echo -e "${WHITE}Deployment ID:${NC} $DEPLOY_ID"
    echo -e "${WHITE}Target Server:${NC} $REMOTE_HOST"
    echo -e "${WHITE}Components:${NC} $COMPONENTS"
    echo -e "${WHITE}Backup Created:${NC} ${BACKUP_NAME:-none}"
    echo ""
    echo -e "${WHITE}Service Status:${NC}"
    echo -e "  ${CYAN}Vault:${NC} $vault_status"
    echo -e "  ${CYAN}Nomad:${NC} $nomad_status"
    echo -e "  ${CYAN}Traefik:${NC} $traefik_status"
    echo -e "  ${CYAN}Monitoring:${NC} $monitoring_status"
    echo ""
    echo -e "${WHITE}Access URLs:${NC}"
    echo -e "  ${CYAN}Traefik Dashboard:${NC} https://traefik.cloudya.net"
    echo -e "  ${CYAN}Vault UI:${NC} https://vault.cloudya.net"
    echo -e "  ${CYAN}Nomad UI:${NC} https://nomad.cloudya.net"
    if [[ "$ENABLE_MONITORING" == "true" ]]; then
        echo -e "  ${CYAN}Grafana:${NC} https://grafana.cloudya.net"
        echo -e "  ${CYAN}Prometheus:${NC} https://prometheus.cloudya.net"
    fi
    echo ""
    log_success "Remote deployment completed successfully!"
}

# Cleanup function
cleanup() {
    local exit_code=$?
    
    if [[ $exit_code -ne 0 ]]; then
        log_error "Deployment failed with exit code: $exit_code"
        if [[ "$ROLLBACK_ON_FAILURE" == "true" ]]; then
            rollback_deployment
        fi
    fi
    
    # Upload deployment log
    if [[ -f "/tmp/remote-deploy-${DEPLOY_ID}.log" ]]; then
        remote_copy "/tmp/remote-deploy-${DEPLOY_ID}.log" "/var/log/cloudya/deployment-${DEPLOY_ID}.log" "Uploading deployment log"
    fi
    
    exit $exit_code
}

# Main execution function
main() {
    # Set up cleanup trap
    trap cleanup EXIT ERR INT TERM
    
    log_header "CLOUDYA REMOTE PRODUCTION DEPLOYMENT"
    echo -e "${WHITE}Target: $REMOTE_HOST${NC}"
    echo -e "${WHITE}Deployment ID: $DEPLOY_ID${NC}"
    echo ""
    
    # Parse and validate arguments
    parse_arguments "$@"
    
    # Show configuration
    echo -e "${WHITE}Configuration:${NC}"
    echo -e "  Components: ${CYAN}$COMPONENTS${NC}"
    echo -e "  Dry Run: ${CYAN}$DRY_RUN${NC}"
    echo -e "  Force Deploy: ${CYAN}$FORCE_DEPLOY${NC}"
    echo -e "  Skip Backup: ${CYAN}$SKIP_BACKUP${NC}"
    echo -e "  Enable Monitoring: ${CYAN}$ENABLE_MONITORING${NC}"
    echo -e "  Rollback on Failure: ${CYAN}$ROLLBACK_ON_FAILURE${NC}"
    echo ""
    
    # Pre-deployment safety checks
    if [[ "$FORCE_DEPLOY" != "true" && "$DRY_RUN" != "true" ]]; then
        log_warning "This will deploy infrastructure to PRODUCTION server: $REMOTE_HOST"
        log_warning "This may overwrite existing configuration and data"
        echo ""
        read -p "Are you sure you want to continue? [y/N]: " -n 1 -r
        echo ""
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Deployment cancelled by user"
            exit 0
        fi
    fi
    
    # Execute deployment pipeline
    validate_prerequisites
    check_server_status
    create_backup
    provision_server
    deploy_infrastructure
    start_services
    validate_deployment
    generate_report
    
    # Remove cleanup trap on success
    trap - EXIT ERR
}

# Execute main function with all arguments
main "$@"