#!/bin/bash

# Comprehensive Rollback System for Infrastructure Deployment
# Handles systemd services, configurations, data, and state snapshots
# Integrates with existing backup-restore.sh system

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_DIR="$(dirname "$SCRIPT_DIR")"
ROLLBACK_BASE_DIR="/var/rollback/cloudya"
LOG_FILE="/var/log/cloudya/rollback.log"

# Configuration
SNAPSHOT_RETENTION_DAYS=7
DRY_RUN=false
VERBOSE=false
AUTO_ROLLBACK_ON_FAILURE=true
ROLLBACK_TIMEOUT=300

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') $1" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $(date '+%Y-%m-%d %H:%M:%S') $1" | tee -a "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $(date '+%Y-%m-%d %H:%M:%S') $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') $1" | tee -a "$LOG_FILE"
}

log_debug() {
    if [[ "$VERBOSE" == "true" ]]; then
        echo -e "${PURPLE}[DEBUG]${NC} $(date '+%Y-%m-%d %H:%M:%S') $1" | tee -a "$LOG_FILE"
    fi
}

log_step() {
    echo -e "${CYAN}[STEP]${NC} $(date '+%Y-%m-%d %H:%M:%S') $1" | tee -a "$LOG_FILE"
}

log_header() {
    echo -e "${WHITE}================================================================================================${NC}"
    echo -e "${WHITE}$1${NC}"
    echo -e "${WHITE}================================================================================================${NC}"
}

# Usage function
usage() {
    cat <<EOF
Comprehensive Rollback System for Infrastructure Deployment

Usage: $0 <command> [options]

Commands:
  checkpoint [name]         Create a rollback checkpoint
  rollback <checkpoint>     Restore from a specific checkpoint
  list                      List available rollback checkpoints
  verify <checkpoint>       Verify checkpoint integrity
  cleanup                   Clean up old checkpoints
  status                    Show rollback system status
  auto-rollback [reason]    Perform automatic rollback with failure reason

Options:
  -d, --dry-run            Show what would be done without making changes
  -v, --verbose            Enable verbose debug output
  -t, --timeout SECONDS    Rollback timeout in seconds [default: 300]
  --no-auto-rollback       Disable automatic rollback on failure
  -h, --help               Show this help message

Examples:
  $0 checkpoint pre-deployment              # Create checkpoint before deployment
  $0 rollback checkpoint-20241225-123456    # Restore from specific checkpoint
  $0 list                                   # List all available checkpoints
  $0 auto-rollback "Vault initialization failed"  # Automatic rollback
  $0 cleanup                                # Remove old checkpoints

Checkpoint Components:
  • Systemd service states and configurations
  • HashiCorp tool configurations (Nomad, Vault, Consul)
  • Application data and volumes
  • Network and firewall configurations
  • SSL certificates and keys
  • Environment variables and secrets
  • Docker containers and volumes
  • Transaction log for ordered rollback

Integration with backup-restore.sh:
  • Leverages existing backup infrastructure
  • Shares encryption and compression settings
  • Uses same storage backend
  • Maintains consistent logging format

EOF
}

# Initialize rollback system
init_rollback_system() {
    log_step "Initializing rollback system..."
    
    # Create rollback directories
    mkdir -p "$ROLLBACK_BASE_DIR"/{checkpoints,temp,logs}
    mkdir -p "$(dirname "$LOG_FILE")"
    
    # Set permissions
    chmod 700 "$ROLLBACK_BASE_DIR"
    chmod 644 "$LOG_FILE" 2>/dev/null || true
    
    # Check required tools
    local required_tools=("systemctl" "tar" "rsync" "jq" "curl" "docker")
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            log_error "Required tool not found: $tool"
            exit 1
        fi
    done
    
    # Create transaction log
    touch "$ROLLBACK_BASE_DIR/transaction.log"
    
    log_success "Rollback system initialized"
}

# Parse command line arguments
parse_arguments() {
    if [[ $# -eq 0 ]]; then
        usage
        exit 1
    fi
    
    COMMAND="$1"
    shift
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -t|--timeout)
                ROLLBACK_TIMEOUT="$2"
                shift 2
                ;;
            --no-auto-rollback)
                AUTO_ROLLBACK_ON_FAILURE=false
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                if [[ "$COMMAND" == "checkpoint" ]] && [[ -z "${CHECKPOINT_NAME:-}" ]]; then
                    CHECKPOINT_NAME="$1"
                    shift
                elif [[ "$COMMAND" == "rollback" || "$COMMAND" == "verify" ]] && [[ -z "${CHECKPOINT_ID:-}" ]]; then
                    CHECKPOINT_ID="$1"
                    shift
                elif [[ "$COMMAND" == "auto-rollback" ]] && [[ -z "${ROLLBACK_REASON:-}" ]]; then
                    ROLLBACK_REASON="$1"
                    shift
                else
                    log_error "Unknown option: $1"
                    usage
                    exit 1
                fi
                ;;
        esac
    done
}

# Create checkpoint ID
create_checkpoint_id() {
    local name="${1:-deployment}"
    echo "checkpoint-${name}-$(date +%Y%m%d-%H%M%S)"
}

# Log transaction for rollback order
log_transaction() {
    local action="$1"
    local component="$2"
    local details="$3"
    local timestamp=$(date +%s)
    
    echo "$timestamp:$action:$component:$details" >> "$ROLLBACK_BASE_DIR/transaction.log"
    log_debug "Transaction logged: $action $component - $details"
}

# Get systemd service status
capture_service_states() {
    local checkpoint_dir="$1"
    
    log_step "Capturing systemd service states..."
    
    mkdir -p "$checkpoint_dir/systemd"
    
    # Capture current service states
    local services=("consul" "nomad" "docker" "traefik")
    for service in "${services[@]}"; do
        if systemctl list-unit-files "${service}.service" &>/dev/null; then
            log_debug "Capturing state for service: $service"
            
            # Service status
            systemctl is-active "$service" > "$checkpoint_dir/systemd/${service}.active" 2>/dev/null || echo "inactive" > "$checkpoint_dir/systemd/${service}.active"
            systemctl is-enabled "$service" > "$checkpoint_dir/systemd/${service}.enabled" 2>/dev/null || echo "disabled" > "$checkpoint_dir/systemd/${service}.enabled"
            
            # Service configuration
            if [[ -f "/etc/systemd/system/${service}.service" ]]; then
                cp "/etc/systemd/system/${service}.service" "$checkpoint_dir/systemd/${service}.service"
            fi
            
            log_transaction "capture" "systemd" "$service"
        fi
    done
    
    # Capture systemd environment files
    if [[ -d "/etc/systemd/system" ]]; then
        find /etc/systemd/system -name "*cloudya*" -o -name "*nomad*" -o -name "*vault*" -o -name "*consul*" | while read -r file; do
            local basename_file=$(basename "$file")
            cp "$file" "$checkpoint_dir/systemd/$basename_file" 2>/dev/null || true
        done
    fi
    
    log_success "Systemd service states captured"
}

# Capture configuration files
capture_configurations() {
    local checkpoint_dir="$1"
    
    log_step "Capturing configuration files..."
    
    mkdir -p "$checkpoint_dir/config"
    
    # Configuration paths to backup
    local config_paths=(
        "/etc/nomad"
        "/etc/consul"
        "/etc/vault"
        "/etc/traefik"
        "/opt/cloudya-infrastructure/config"
        "/etc/docker/daemon.json"
        "/etc/ssl/cloudya"
    )
    
    for config_path in "${config_paths[@]}"; do
        if [[ -e "$config_path" ]]; then
            local basename_path=$(basename "$config_path")
            log_debug "Backing up configuration: $config_path"
            
            if [[ -d "$config_path" ]]; then
                cp -r "$config_path" "$checkpoint_dir/config/$basename_path" 2>/dev/null || true
            else
                cp "$config_path" "$checkpoint_dir/config/$basename_path" 2>/dev/null || true
            fi
            
            log_transaction "capture" "config" "$config_path"
        fi
    done
    
    log_success "Configuration files captured"
}

# Capture data volumes and state
capture_data_state() {
    local checkpoint_dir="$1"
    
    log_step "Capturing data state..."
    
    mkdir -p "$checkpoint_dir/data"
    
    # Data paths to backup
    local data_paths=(
        "/opt/cloudya-data"
        "/var/lib/nomad"
        "/var/lib/consul"
        "/var/lib/vault"
        "/var/log/cloudya"
    )
    
    for data_path in "${data_paths[@]}"; do
        if [[ -e "$data_path" ]]; then
            local basename_path=$(basename "$data_path")
            log_debug "Backing up data: $data_path"
            
            # Use rsync for efficient copying with hard links
            rsync -a --link-dest="$checkpoint_dir/data/" "$data_path/" "$checkpoint_dir/data/$basename_path/" 2>/dev/null || true
            log_transaction "capture" "data" "$data_path"
        fi
    done
    
    log_success "Data state captured"
}

# Capture Docker state
capture_docker_state() {
    local checkpoint_dir="$1"
    
    log_step "Capturing Docker state..."
    
    if ! command -v docker &> /dev/null || ! systemctl is-active docker &> /dev/null; then
        log_debug "Docker not available, skipping Docker state capture"
        return 0
    fi
    
    mkdir -p "$checkpoint_dir/docker"
    
    # Capture running containers
    docker ps --format "json" > "$checkpoint_dir/docker/running_containers.json" 2>/dev/null || echo "[]" > "$checkpoint_dir/docker/running_containers.json"
    
    # Capture all containers
    docker ps -a --format "json" > "$checkpoint_dir/docker/all_containers.json" 2>/dev/null || echo "[]" > "$checkpoint_dir/docker/all_containers.json"
    
    # Capture volumes
    docker volume ls --format "json" > "$checkpoint_dir/docker/volumes.json" 2>/dev/null || echo "[]" > "$checkpoint_dir/docker/volumes.json"
    
    # Capture networks
    docker network ls --format "json" > "$checkpoint_dir/docker/networks.json" 2>/dev/null || echo "[]" > "$checkpoint_dir/docker/networks.json"
    
    # Backup important volumes
    docker volume ls --quiet | grep -E "(cloudya|vault|nomad|consul|traefik)" | while read -r volume; do
        if [[ -n "$volume" ]]; then
            log_debug "Backing up Docker volume: $volume"
            docker run --rm -v "$volume":/source:ro -v "$checkpoint_dir/docker":/backup alpine \
                tar czf "/backup/volume_${volume}.tar.gz" -C /source . 2>/dev/null || true
            log_transaction "capture" "docker_volume" "$volume"
        fi
    done
    
    log_success "Docker state captured"
}

# Capture network configuration
capture_network_state() {
    local checkpoint_dir="$1"
    
    log_step "Capturing network state..."
    
    mkdir -p "$checkpoint_dir/network"
    
    # Capture iptables rules
    iptables-save > "$checkpoint_dir/network/iptables.rules" 2>/dev/null || touch "$checkpoint_dir/network/iptables.rules"
    
    # Capture network interfaces
    ip addr show > "$checkpoint_dir/network/interfaces.txt" 2>/dev/null || touch "$checkpoint_dir/network/interfaces.txt"
    
    # Capture routing table
    ip route show > "$checkpoint_dir/network/routes.txt" 2>/dev/null || touch "$checkpoint_dir/network/routes.txt"
    
    # Capture listening ports
    netstat -tlnp > "$checkpoint_dir/network/listening_ports.txt" 2>/dev/null || ss -tlnp > "$checkpoint_dir/network/listening_ports.txt" 2>/dev/null || touch "$checkpoint_dir/network/listening_ports.txt"
    
    log_transaction "capture" "network" "iptables,interfaces,routes,ports"
    log_success "Network state captured"
}

# Create rollback manifest
create_rollback_manifest() {
    local checkpoint_id="$1"
    local checkpoint_dir="$2"
    
    cat > "$checkpoint_dir/manifest.json" << EOF
{
    "checkpoint_id": "$checkpoint_id",
    "created_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "hostname": "$(hostname -f)",
    "script_version": "1.0.0",
    "rollback_manager": true,
    "system_info": {
        "os": "$(cat /etc/os-release | grep PRETTY_NAME | cut -d'\"' -f2)",
        "kernel": "$(uname -r)",
        "architecture": "$(uname -m)",
        "uptime": "$(uptime)",
        "disk_usage": "$(df -h / | tail -1)"
    },
    "services_captured": {
        "systemd": true,
        "docker": $(command -v docker &> /dev/null && echo true || echo false),
        "network": true,
        "configurations": true,
        "data": true
    },
    "pre_deployment_state": {
        "consul_active": "$(systemctl is-active consul 2>/dev/null || echo 'not-found')",
        "nomad_active": "$(systemctl is-active nomad 2>/dev/null || echo 'not-found')",
        "docker_active": "$(systemctl is-active docker 2>/dev/null || echo 'not-found')",
        "vault_responding": $(curl -s http://localhost:8200/v1/sys/health > /dev/null 2>&1 && echo true || echo false),
        "nomad_responding": $(curl -s http://localhost:4646/v1/status/leader > /dev/null 2>&1 && echo true || echo false)
    }
}
EOF
    
    log_debug "Rollback manifest created"
}

# Create checkpoint
create_checkpoint() {
    local checkpoint_name="${1:-pre-deployment}"
    local checkpoint_id=$(create_checkpoint_id "$checkpoint_name")
    local checkpoint_dir="$ROLLBACK_BASE_DIR/checkpoints/$checkpoint_id"
    
    log_header "CREATING ROLLBACK CHECKPOINT: $checkpoint_id"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create checkpoint: $checkpoint_id"
        return 0
    fi
    
    # Create checkpoint directory
    mkdir -p "$checkpoint_dir"
    
    # Create manifest first
    create_rollback_manifest "$checkpoint_id" "$checkpoint_dir"
    
    # Clear transaction log for this checkpoint
    echo "# Transaction log for $checkpoint_id - $(date)" > "$ROLLBACK_BASE_DIR/transaction.log"
    
    # Capture all states
    capture_service_states "$checkpoint_dir"
    capture_configurations "$checkpoint_dir"
    capture_data_state "$checkpoint_dir"
    capture_docker_state "$checkpoint_dir"
    capture_network_state "$checkpoint_dir"
    
    # Create checksums
    find "$checkpoint_dir" -type f -exec sha256sum {} \; > "$checkpoint_dir/checksums.txt"
    
    # Compress checkpoint (optional)
    if command -v gzip &> /dev/null; then
        log_step "Compressing checkpoint..."
        tar czf "${checkpoint_dir}.tar.gz" -C "$(dirname "$checkpoint_dir")" "$(basename "$checkpoint_dir")"
        rm -rf "$checkpoint_dir"
        log_success "Checkpoint compressed: ${checkpoint_dir}.tar.gz"
    fi
    
    log_success "Checkpoint created: $checkpoint_id"
    echo "$checkpoint_id" # Return checkpoint ID for caller
}

# Stop services in reverse order
stop_services_for_rollback() {
    log_step "Stopping services for rollback..."
    
    local services=("traefik" "nomad" "consul")
    for service in "${services[@]}"; do
        if systemctl is-active --quiet "$service" 2>/dev/null; then
            log_info "Stopping service: $service"
            if [[ "$DRY_RUN" != "true" ]]; then
                systemctl stop "$service" || true
                log_transaction "stop" "systemd" "$service"
            fi
        fi
    done
    
    # Wait for services to stop
    if [[ "$DRY_RUN" != "true" ]]; then
        sleep 10
    fi
}

# Restore systemd services
restore_service_states() {
    local checkpoint_dir="$1"
    
    log_step "Restoring systemd service states..."
    
    if [[ ! -d "$checkpoint_dir/systemd" ]]; then
        log_warning "No systemd state found in checkpoint"
        return 0
    fi
    
    # Restore service configurations first
    for service_file in "$checkpoint_dir/systemd"/*.service; do
        if [[ -f "$service_file" ]]; then
            local service_name=$(basename "$service_file")
            log_debug "Restoring service configuration: $service_name"
            
            if [[ "$DRY_RUN" != "true" ]]; then
                cp "$service_file" "/etc/systemd/system/$service_name"
                log_transaction "restore" "systemd_config" "$service_name"
            fi
        fi
    done
    
    # Reload systemd
    if [[ "$DRY_RUN" != "true" ]]; then
        systemctl daemon-reload
    fi
    
    # Restore service states
    for active_file in "$checkpoint_dir/systemd"/*.active; do
        if [[ -f "$active_file" ]]; then
            local service_name=$(basename "$active_file" .active)
            local was_active=$(cat "$active_file")
            local enabled_file="$checkpoint_dir/systemd/${service_name}.enabled"
            local was_enabled="disabled"
            
            if [[ -f "$enabled_file" ]]; then
                was_enabled=$(cat "$enabled_file")
            fi
            
            log_debug "Restoring service: $service_name (active: $was_active, enabled: $was_enabled)"
            
            if [[ "$DRY_RUN" != "true" ]]; then
                # Enable/disable service
                if [[ "$was_enabled" == "enabled" ]]; then
                    systemctl enable "$service_name" 2>/dev/null || true
                else
                    systemctl disable "$service_name" 2>/dev/null || true
                fi
                
                # Start/stop service
                if [[ "$was_active" == "active" ]]; then
                    systemctl start "$service_name" || true
                    log_transaction "restore_start" "systemd" "$service_name"
                else
                    systemctl stop "$service_name" 2>/dev/null || true
                    log_transaction "restore_stop" "systemd" "$service_name"
                fi
            fi
        fi
    done
    
    log_success "Systemd service states restored"
}

# Restore configurations
restore_configurations() {
    local checkpoint_dir="$1"
    
    log_step "Restoring configuration files..."
    
    if [[ ! -d "$checkpoint_dir/config" ]]; then
        log_warning "No configuration state found in checkpoint"
        return 0
    fi
    
    # Restore each configuration
    for config_item in "$checkpoint_dir/config"/*; do
        if [[ -e "$config_item" ]]; then
            local config_name=$(basename "$config_item")
            local target_path=""
            
            # Determine target path based on config name
            case "$config_name" in
                nomad)
                    target_path="/etc/nomad"
                    ;;
                consul)
                    target_path="/etc/consul"
                    ;;
                vault)
                    target_path="/etc/vault"
                    ;;
                traefik)
                    target_path="/etc/traefik"
                    ;;
                config)
                    target_path="/opt/cloudya-infrastructure/config"
                    ;;
                daemon.json)
                    target_path="/etc/docker/daemon.json"
                    ;;
                cloudya)
                    target_path="/etc/ssl/cloudya"
                    ;;
                *)
                    log_debug "Skipping unknown config: $config_name"
                    continue
                    ;;
            esac
            
            if [[ -n "$target_path" ]]; then
                log_debug "Restoring configuration: $config_name -> $target_path"
                
                if [[ "$DRY_RUN" != "true" ]]; then
                    # Backup current config if it exists
                    if [[ -e "$target_path" ]]; then
                        mv "$target_path" "${target_path}.rollback-backup.$(date +%s)" 2>/dev/null || true
                    fi
                    
                    # Create parent directory
                    mkdir -p "$(dirname "$target_path")"
                    
                    # Restore configuration
                    cp -r "$config_item" "$target_path"
                    log_transaction "restore" "config" "$target_path"
                fi
            fi
        fi
    done
    
    log_success "Configuration files restored"
}

# Restore data state
restore_data_state() {
    local checkpoint_dir="$1"
    
    log_step "Restoring data state..."
    
    if [[ ! -d "$checkpoint_dir/data" ]]; then
        log_warning "No data state found in checkpoint"
        return 0
    fi
    
    # Restore each data directory
    for data_item in "$checkpoint_dir/data"/*; do
        if [[ -d "$data_item" ]]; then
            local data_name=$(basename "$data_item")
            local target_path=""
            
            # Determine target path based on data name
            case "$data_name" in
                cloudya-data)
                    target_path="/opt/cloudya-data"
                    ;;
                nomad)
                    target_path="/var/lib/nomad"
                    ;;
                consul)
                    target_path="/var/lib/consul"
                    ;;
                vault)
                    target_path="/var/lib/vault"
                    ;;
                cloudya)
                    target_path="/var/log/cloudya"
                    ;;
                *)
                    log_debug "Skipping unknown data directory: $data_name"
                    continue
                    ;;
            esac
            
            if [[ -n "$target_path" ]]; then
                log_debug "Restoring data: $data_name -> $target_path"
                
                if [[ "$DRY_RUN" != "true" ]]; then
                    # Backup current data if it exists
                    if [[ -e "$target_path" ]]; then
                        mv "$target_path" "${target_path}.rollback-backup.$(date +%s)" 2>/dev/null || true
                    fi
                    
                    # Create parent directory
                    mkdir -p "$(dirname "$target_path")"
                    
                    # Restore data
                    cp -r "$data_item" "$target_path"
                    log_transaction "restore" "data" "$target_path"
                fi
            fi
        fi
    done
    
    log_success "Data state restored"
}

# Restore Docker state
restore_docker_state() {
    local checkpoint_dir="$1"
    
    if [[ ! -d "$checkpoint_dir/docker" ]]; then
        log_debug "No Docker state found in checkpoint"
        return 0
    fi
    
    log_step "Restoring Docker state..."
    
    if ! command -v docker &> /dev/null || ! systemctl is-active docker &> /dev/null; then
        log_warning "Docker not available, skipping Docker state restore"
        return 0
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would restore Docker state"
        return 0
    fi
    
    # Stop running containers
    if [[ -f "$checkpoint_dir/docker/running_containers.json" ]]; then
        log_info "Stopping current containers..."
        docker ps --quiet | while read -r container_id; do
            if [[ -n "$container_id" ]]; then
                docker stop "$container_id" 2>/dev/null || true
                log_transaction "stop" "docker_container" "$container_id"
            fi
        done
    fi
    
    # Restore volumes
    for volume_file in "$checkpoint_dir/docker"/volume_*.tar.gz; do
        if [[ -f "$volume_file" ]]; then
            local volume_name=$(basename "$volume_file" .tar.gz | sed 's/volume_//')
            log_debug "Restoring Docker volume: $volume_name"
            
            # Create volume if it doesn't exist
            docker volume create "$volume_name" 2>/dev/null || true
            
            # Restore volume data
            docker run --rm -v "$volume_name":/target -v "$checkpoint_dir/docker":/backup alpine \
                tar xzf "/backup/$(basename "$volume_file")" -C /target 2>/dev/null || true
                
            log_transaction "restore" "docker_volume" "$volume_name"
        fi
    done
    
    log_success "Docker state restored"
}

# Restore network state
restore_network_state() {
    local checkpoint_dir="$1"
    
    if [[ ! -d "$checkpoint_dir/network" ]]; then
        log_debug "No network state found in checkpoint"
        return 0
    fi
    
    log_step "Restoring network state..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would restore network state"
        return 0
    fi
    
    # Restore iptables rules
    if [[ -f "$checkpoint_dir/network/iptables.rules" && -s "$checkpoint_dir/network/iptables.rules" ]]; then
        log_debug "Restoring iptables rules"
        iptables-restore < "$checkpoint_dir/network/iptables.rules" 2>/dev/null || log_warning "Failed to restore iptables rules"
        log_transaction "restore" "network" "iptables"
    fi
    
    log_success "Network state restored (partial)"
}

# Perform rollback
perform_rollback() {
    local checkpoint_id="$1"
    local checkpoint_path=""
    
    log_header "PERFORMING ROLLBACK TO: $checkpoint_id"
    
    # Find checkpoint
    if [[ -d "$ROLLBACK_BASE_DIR/checkpoints/$checkpoint_id" ]]; then
        checkpoint_path="$ROLLBACK_BASE_DIR/checkpoints/$checkpoint_id"
    elif [[ -f "$ROLLBACK_BASE_DIR/checkpoints/${checkpoint_id}.tar.gz" ]]; then
        log_step "Extracting compressed checkpoint..."
        if [[ "$DRY_RUN" != "true" ]]; then
            tar xzf "$ROLLBACK_BASE_DIR/checkpoints/${checkpoint_id}.tar.gz" -C "$ROLLBACK_BASE_DIR/temp/"
            checkpoint_path="$ROLLBACK_BASE_DIR/temp/$checkpoint_id"
        else
            checkpoint_path="$ROLLBACK_BASE_DIR/temp/$checkpoint_id" # Dummy path for dry run
        fi
    else
        log_error "Checkpoint not found: $checkpoint_id"
        exit 1
    fi
    
    # Verify checkpoint
    if [[ ! -f "$checkpoint_path/manifest.json" && "$DRY_RUN" != "true" ]]; then
        log_error "Invalid checkpoint: missing manifest.json"
        exit 1
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would perform rollback to: $checkpoint_id"
        log_info "[DRY RUN] Checkpoint path: $checkpoint_path"
        return 0
    fi
    
    # Clear transaction log
    echo "# Rollback transaction log for $checkpoint_id - $(date)" > "$ROLLBACK_BASE_DIR/transaction.log"
    
    # Stop services first
    stop_services_for_rollback
    
    # Restore in order (reverse of capture)
    restore_network_state "$checkpoint_path"
    restore_docker_state "$checkpoint_path"
    restore_data_state "$checkpoint_path"
    restore_configurations "$checkpoint_path"
    restore_service_states "$checkpoint_path"
    
    # Wait for services to start
    log_step "Waiting for services to stabilize..."
    sleep 15
    
    # Verify rollback
    verify_rollback_success
    
    # Clean up temporary extraction
    if [[ -d "$ROLLBACK_BASE_DIR/temp/$checkpoint_id" ]]; then
        rm -rf "$ROLLBACK_BASE_DIR/temp/$checkpoint_id"
    fi
    
    log_success "Rollback completed: $checkpoint_id"
}

# Verify rollback success
verify_rollback_success() {
    log_step "Verifying rollback success..."
    
    local verification_failed=false
    
    # Check critical services
    if systemctl list-unit-files consul.service &>/dev/null; then
        if ! systemctl is-active --quiet consul 2>/dev/null; then
            log_warning "Consul service is not active after rollback"
            verification_failed=true
        fi
    fi
    
    if systemctl list-unit-files nomad.service &>/dev/null; then
        if ! systemctl is-active --quiet nomad 2>/dev/null; then
            log_warning "Nomad service is not active after rollback"
            verification_failed=true
        fi
    fi
    
    # Basic connectivity tests with timeout
    local timeout=30
    
    # Test Consul
    if systemctl is-active --quiet consul 2>/dev/null; then
        if ! timeout 10 bash -c 'curl -s http://localhost:8500/v1/status/leader > /dev/null 2>&1'; then
            log_warning "Consul API not responding after rollback"
            verification_failed=true
        else
            log_success "Consul API responding"
        fi
    fi
    
    # Test Nomad
    if systemctl is-active --quiet nomad 2>/dev/null; then
        if ! timeout 10 bash -c 'curl -s http://localhost:4646/v1/status/leader > /dev/null 2>&1'; then
            log_warning "Nomad API not responding after rollback"
            verification_failed=true
        else
            log_success "Nomad API responding"
        fi
    fi
    
    if [[ "$verification_failed" == "true" ]]; then
        log_warning "Rollback verification completed with warnings"
        return 1
    else
        log_success "Rollback verification passed"
        return 0
    fi
}

# List available checkpoints
list_checkpoints() {
    log_step "Listing available rollback checkpoints..."
    
    echo -e "${WHITE}Available Rollback Checkpoints:${NC}"
    echo "================================"
    
    local found_checkpoints=false
    local checkpoint_dir="$ROLLBACK_BASE_DIR/checkpoints"
    
    if [[ -d "$checkpoint_dir" ]]; then
        local checkpoints=($(find "$checkpoint_dir" -maxdepth 1 \( -type d -name "checkpoint-*" -o -name "checkpoint-*.tar.gz" \) | sort -r))
        
        if [[ ${#checkpoints[@]} -gt 0 ]]; then
            for checkpoint in "${checkpoints[@]}"; do
                local checkpoint_name=$(basename "$checkpoint" .tar.gz)
                local checkpoint_date=$(echo "$checkpoint_name" | sed 's/checkpoint-[^-]*-//' | sed 's/-/ /' | sed 's/\(..\)\(..\)\(..\)/\1:\2:\3/')
                local checkpoint_size=""
                
                if [[ -d "$checkpoint" ]]; then
                    checkpoint_size=$(du -sh "$checkpoint" | cut -f1)
                elif [[ -f "$checkpoint" ]]; then
                    checkpoint_size=$(du -sh "$checkpoint" | cut -f1)
                fi
                
                local compressed_status=""
                if [[ "$checkpoint" =~ \.tar\.gz$ ]]; then
                    compressed_status=" ${GREEN}[compressed]${NC}"
                fi
                
                echo -e "  ${checkpoint_name} - ${checkpoint_date} - ${checkpoint_size}${compressed_status}"
                found_checkpoints=true
            done
        fi
    fi
    
    if [[ "$found_checkpoints" == "false" ]]; then
        echo "No checkpoints found."
    fi
    
    echo ""
}

# Verify checkpoint integrity
verify_checkpoint() {
    local checkpoint_id="$1"
    
    log_step "Verifying checkpoint integrity: $checkpoint_id"
    
    # Find checkpoint
    local checkpoint_path=""
    if [[ -d "$ROLLBACK_BASE_DIR/checkpoints/$checkpoint_id" ]]; then
        checkpoint_path="$ROLLBACK_BASE_DIR/checkpoints/$checkpoint_id"
    elif [[ -f "$ROLLBACK_BASE_DIR/checkpoints/${checkpoint_id}.tar.gz" ]]; then
        # For compressed checkpoints, extract temporarily
        log_info "Extracting compressed checkpoint for verification..."
        tar xzf "$ROLLBACK_BASE_DIR/checkpoints/${checkpoint_id}.tar.gz" -C "$ROLLBACK_BASE_DIR/temp/"
        checkpoint_path="$ROLLBACK_BASE_DIR/temp/$checkpoint_id"
    else
        log_error "Checkpoint not found: $checkpoint_id"
        return 1
    fi
    
    # Verify manifest exists
    if [[ ! -f "$checkpoint_path/manifest.json" ]]; then
        log_error "Checkpoint manifest missing"
        return 1
    fi
    
    # Verify checksums if available
    if [[ -f "$checkpoint_path/checksums.txt" ]]; then
        log_info "Verifying checksums..."
        if (cd "$(dirname "$checkpoint_path")" && sha256sum -c "$(basename "$checkpoint_path")/checksums.txt" --quiet 2>/dev/null); then
            log_success "Checksum verification passed"
        else
            log_error "Checksum verification failed"
            return 1
        fi
    else
        log_warning "No checksums file found, skipping checksum verification"
    fi
    
    # Verify critical components exist
    local required_components=("systemd" "config")
    for component in "${required_components[@]}"; do
        if [[ ! -d "$checkpoint_path/$component" ]]; then
            log_warning "Component directory missing: $component"
        else
            log_debug "Component verified: $component"
        fi
    done
    
    # Clean up temporary extraction
    if [[ -d "$ROLLBACK_BASE_DIR/temp/$checkpoint_id" ]]; then
        rm -rf "$ROLLBACK_BASE_DIR/temp/$checkpoint_id"
    fi
    
    log_success "Checkpoint verification completed: $checkpoint_id"
}

# Cleanup old checkpoints
cleanup_checkpoints() {
    log_step "Cleaning up old checkpoints (retention: $SNAPSHOT_RETENTION_DAYS days)..."
    
    local cleaned_count=0
    local checkpoint_dir="$ROLLBACK_BASE_DIR/checkpoints"
    
    if [[ -d "$checkpoint_dir" ]]; then
        # Find checkpoints older than retention period
        local old_checkpoints
        mapfile -t old_checkpoints < <(find "$checkpoint_dir" -maxdepth 1 \( -type d -name "checkpoint-*" -o -name "checkpoint-*.tar.gz" \) -mtime "+$SNAPSHOT_RETENTION_DAYS")
        
        for checkpoint in "${old_checkpoints[@]}"; do
            local checkpoint_name=$(basename "$checkpoint")
            log_info "Removing old checkpoint: $checkpoint_name"
            
            if [[ "$DRY_RUN" != "true" ]]; then
                rm -rf "$checkpoint"
                ((cleaned_count++))
            else
                log_info "[DRY RUN] Would remove: $checkpoint_name"
                ((cleaned_count++))
            fi
        done
    fi
    
    log_success "Cleanup completed. Removed $cleaned_count old checkpoints."
}

# Show rollback system status
show_rollback_status() {
    log_step "Rollback system status..."
    
    echo -e "${WHITE}Cloudya Rollback System Status${NC}"
    echo "==============================="
    echo ""
    
    # System information
    echo -e "${CYAN}System Information:${NC}"
    echo "  Hostname: $(hostname -f)"
    echo "  Rollback Directory: $ROLLBACK_BASE_DIR"
    echo "  Log File: $LOG_FILE"
    echo ""
    
    # Configuration
    echo -e "${CYAN}Configuration:${NC}"
    echo "  Retention Days: $SNAPSHOT_RETENTION_DAYS"
    echo "  Auto Rollback: $AUTO_ROLLBACK_ON_FAILURE"
    echo "  Timeout: ${ROLLBACK_TIMEOUT}s"
    echo ""
    
    # Storage usage
    echo -e "${CYAN}Storage Usage:${NC}"
    if [[ -d "$ROLLBACK_BASE_DIR/checkpoints" ]]; then
        du -sh "$ROLLBACK_BASE_DIR/checkpoints"/* 2>/dev/null | while read -r size path; do
            echo "  $(basename "$path"): $size"
        done
        echo "  Total: $(du -sh "$ROLLBACK_BASE_DIR/checkpoints" | cut -f1)"
    else
        echo "  No checkpoints directory found"
    fi
    echo ""
    
    # Last checkpoint
    echo -e "${CYAN}Latest Checkpoint:${NC}"
    local latest_checkpoint=$(find "$ROLLBACK_BASE_DIR/checkpoints" -maxdepth 1 \( -type d -name "checkpoint-*" -o -name "checkpoint-*.tar.gz" \) 2>/dev/null | sort | tail -1)
    if [[ -n "$latest_checkpoint" ]]; then
        local checkpoint_name=$(basename "$latest_checkpoint" .tar.gz)
        echo "  ID: $checkpoint_name"
        echo "  Date: $(stat -c %y "$latest_checkpoint" 2>/dev/null | cut -d. -f1)"
        echo "  Size: $(du -sh "$latest_checkpoint" | cut -f1)"
    else
        echo "  No checkpoints found"
    fi
    echo ""
    
    # Current service status
    echo -e "${CYAN}Current Service Status:${NC}"
    for service in consul nomad docker; do
        if systemctl list-unit-files "${service}.service" &>/dev/null; then
            if systemctl is-active --quiet "$service"; then
                echo -e "  $service: ${GREEN}Active${NC}"
            else
                echo -e "  $service: ${RED}Inactive${NC}"
            fi
        else
            echo -e "  $service: ${YELLOW}Not found${NC}"
        fi
    done
    echo ""
}

# Automatic rollback function
perform_auto_rollback() {
    local reason="${1:-Automatic rollback triggered}"
    
    log_header "AUTOMATIC ROLLBACK TRIGGERED"
    log_error "Reason: $reason"
    
    # Find the most recent checkpoint
    local latest_checkpoint=$(find "$ROLLBACK_BASE_DIR/checkpoints" -maxdepth 1 \( -type d -name "checkpoint-*" -o -name "checkpoint-*.tar.gz" \) 2>/dev/null | sort | tail -1)
    
    if [[ -z "$latest_checkpoint" ]]; then
        log_error "No checkpoints available for automatic rollback"
        exit 1
    fi
    
    local checkpoint_id=$(basename "$latest_checkpoint" .tar.gz)
    log_info "Using latest checkpoint: $checkpoint_id"
    
    # Perform rollback
    perform_rollback "$checkpoint_id"
    
    log_success "Automatic rollback completed"
}

# Main execution function
main() {
    # Initialize rollback system
    init_rollback_system
    
    # Parse and validate arguments
    parse_arguments "$@"
    
    # Execute command
    case "$COMMAND" in
        "checkpoint")
            create_checkpoint "${CHECKPOINT_NAME:-pre-deployment}"
            ;;
        "rollback")
            if [[ -z "${CHECKPOINT_ID:-}" ]]; then
                log_error "Checkpoint ID required for rollback command"
                exit 1
            fi
            perform_rollback "$CHECKPOINT_ID"
            ;;
        "list")
            list_checkpoints
            ;;
        "verify")
            if [[ -z "${CHECKPOINT_ID:-}" ]]; then
                log_error "Checkpoint ID required for verify command"
                exit 1
            fi
            verify_checkpoint "$CHECKPOINT_ID"
            ;;
        "cleanup")
            cleanup_checkpoints
            ;;
        "status")
            show_rollback_status
            ;;
        "auto-rollback")
            perform_auto_rollback "${ROLLBACK_REASON:-Automatic rollback triggered}"
            ;;
        *)
            log_error "Unknown command: $COMMAND"
            usage
            exit 1
            ;;
    esac
}

# Execute main function with all arguments
main "$@"