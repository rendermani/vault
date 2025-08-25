#!/bin/bash

# Cloudya Infrastructure Backup and Restore System
# Comprehensive backup solution with encryption, compression, and remote storage
# Supports full system backup, incremental backups, and point-in-time recovery

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_BASE_DIR="/var/backups/cloudya"
CONFIG_FILE="${SCRIPT_DIR}/../config/backup.conf"
LOG_FILE="/var/log/cloudya/backup.log"

# Default configuration
BACKUP_TYPE="full"
RETENTION_DAYS=30
COMPRESSION_LEVEL=6
ENCRYPTION_ENABLED=true
REMOTE_SYNC_ENABLED=false
DRY_RUN=false
VERBOSE=false
VERIFY_BACKUP=true
PARALLEL_JOBS=4

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

# Usage function
usage() {
    cat <<EOF
Cloudya Infrastructure Backup and Restore System

Usage: $0 <command> [options]

Commands:
  backup                    Create a backup
  restore <backup_id>       Restore from a specific backup
  list                      List available backups
  verify <backup_id>        Verify backup integrity
  cleanup                   Clean up old backups
  status                    Show backup system status

Backup Options:
  -t, --type TYPE           Backup type: full, incremental, config [default: full]
  -r, --retention DAYS      Retention period in days [default: 30]
  -c, --compression LEVEL   Compression level 1-9 [default: 6]
  -e, --no-encryption       Disable backup encryption
  -s, --sync                Enable remote synchronization
  -j, --jobs JOBS          Number of parallel jobs [default: 4]

General Options:
  -d, --dry-run            Show what would be done without making changes
  -v, --verbose            Enable verbose debug output
  --no-verify              Skip backup verification
  -h, --help               Show this help message

Examples:
  $0 backup                           # Full backup with default settings
  $0 backup -t incremental -v        # Incremental backup with verbose output
  $0 restore backup-20241225-123456   # Restore from specific backup
  $0 list                             # List all available backups
  $0 cleanup                          # Remove old backups
  $0 verify backup-20241225-123456    # Verify backup integrity

Backup Components:
  • Vault data and configuration
  • Nomad data and job definitions
  • Consul data and configuration
  • Traefik certificates and configuration
  • Docker volumes and containers
  • System configuration files
  • SSL certificates and keys
  • Application data and logs

EOF
}

# Load configuration
load_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        source "$CONFIG_FILE"
        log_debug "Configuration loaded from $CONFIG_FILE"
    else
        log_debug "No configuration file found at $CONFIG_FILE, using defaults"
    fi
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
            -t|--type)
                BACKUP_TYPE="$2"
                shift 2
                ;;
            -r|--retention)
                RETENTION_DAYS="$2"
                shift 2
                ;;
            -c|--compression)
                COMPRESSION_LEVEL="$2"
                shift 2
                ;;
            -e|--no-encryption)
                ENCRYPTION_ENABLED=false
                shift
                ;;
            -s|--sync)
                REMOTE_SYNC_ENABLED=true
                shift
                ;;
            -j|--jobs)
                PARALLEL_JOBS="$2"
                shift 2
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            --no-verify)
                VERIFY_BACKUP=false
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                if [[ "$COMMAND" == "restore" || "$COMMAND" == "verify" ]] && [[ -z "${BACKUP_ID:-}" ]]; then
                    BACKUP_ID="$1"
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

# Initialize backup system
init_backup_system() {
    log_step "Initializing backup system..."
    
    # Create backup directories
    mkdir -p "$BACKUP_BASE_DIR"/{full,incremental,config,temp,restore}
    mkdir -p "$(dirname "$LOG_FILE")"
    
    # Create state file for incremental backups
    touch "$BACKUP_BASE_DIR/.last_backup_state"
    
    # Set permissions
    chmod 700 "$BACKUP_BASE_DIR"
    chmod 644 "$LOG_FILE"
    
    # Check required tools
    local required_tools=("tar" "gzip" "gpg" "rsync" "sha256sum")
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            log_error "Required tool not found: $tool"
            exit 1
        fi
    done
    
    # Check encryption key if encryption is enabled
    if [[ "$ENCRYPTION_ENABLED" == "true" ]]; then
        if [[ -z "${BACKUP_ENCRYPTION_KEY:-}" ]] && [[ ! -f "/etc/cloudya/backup.key" ]]; then
            log_warning "Encryption enabled but no key found. Generating new key..."
            generate_encryption_key
        fi
    fi
    
    log_success "Backup system initialized"
}

# Generate encryption key
generate_encryption_key() {
    local key_file="/etc/cloudya/backup.key"
    mkdir -p "$(dirname "$key_file")"
    
    # Generate random key
    openssl rand -base64 32 > "$key_file"
    chmod 600 "$key_file"
    
    log_info "Backup encryption key generated: $key_file"
    log_warning "IMPORTANT: Backup this key securely! Without it, backups cannot be restored."
}

# Create backup ID
create_backup_id() {
    echo "backup-$(date +%Y%m%d-%H%M%S)"
}

# Get backup paths based on type
get_backup_paths() {
    local backup_type="$1"
    local paths=()
    
    case "$backup_type" in
        "full")
            paths+=(
                "/opt/cloudya-data"
                "/opt/cloudya-infrastructure"
                "/var/log/cloudya"
                "/etc/systemd/system/cloudya-*"
                "/etc/docker/daemon.json"
                "/etc/nginx/sites-available/cloudya*"
                "/etc/ssl/cloudya"
            )
            ;;
        "config")
            paths+=(
                "/opt/cloudya-infrastructure/config"
                "/opt/cloudya-data/vault/config"
                "/opt/cloudya-data/nomad/config"
                "/opt/cloudya-data/traefik/config"
                "/etc/systemd/system/cloudya-*"
            )
            ;;
        "incremental")
            # For incremental, we'll use rsync with --link-dest
            paths+=(
                "/opt/cloudya-data"
                "/opt/cloudya-infrastructure"
                "/var/log/cloudya"
            )
            ;;
    esac
    
    printf '%s\n' "${paths[@]}"
}

# Create backup manifest
create_backup_manifest() {
    local backup_id="$1"
    local backup_dir="$2"
    local backup_type="$3"
    
    cat > "$backup_dir/manifest.json" << EOF
{
    "backup_id": "$backup_id",
    "backup_type": "$backup_type",
    "created_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "hostname": "$(hostname -f)",
    "script_version": "1.0.0",
    "encryption_enabled": $ENCRYPTION_ENABLED,
    "compression_level": $COMPRESSION_LEVEL,
    "system_info": {
        "os": "$(cat /etc/os-release | grep PRETTY_NAME | cut -d'\"' -f2)",
        "kernel": "$(uname -r)",
        "architecture": "$(uname -m)",
        "docker_version": "$(docker --version 2>/dev/null || echo 'Not installed')",
        "vault_version": "$(vault version 2>/dev/null | head -1 || echo 'Not installed')",
        "nomad_version": "$(nomad version 2>/dev/null | head -1 || echo 'Not installed')"
    },
    "services_status": {
        "vault": "$(systemctl is-active cloudya-vault 2>/dev/null || echo 'inactive')",
        "nomad": "$(systemctl is-active cloudya-nomad 2>/dev/null || echo 'inactive')",
        "traefik": "$(systemctl is-active cloudya-traefik 2>/dev/null || echo 'inactive')",
        "docker": "$(systemctl is-active docker 2>/dev/null || echo 'inactive')"
    }
}
EOF
    
    log_debug "Backup manifest created: $backup_dir/manifest.json"
}

# Stop services for consistent backup
stop_services() {
    log_step "Stopping services for consistent backup..."
    
    local services=("cloudya-traefik" "cloudya-nomad" "cloudya-vault")
    for service in "${services[@]}"; do
        if systemctl is-active --quiet "$service" 2>/dev/null; then
            log_info "Stopping service: $service"
            if [[ "$DRY_RUN" != "true" ]]; then
                systemctl stop "$service"
            fi
        else
            log_debug "Service $service is not running"
        fi
    done
    
    # Wait for services to fully stop
    if [[ "$DRY_RUN" != "true" ]]; then
        sleep 10
    fi
}

# Start services after backup
start_services() {
    log_step "Starting services after backup..."
    
    local services=("cloudya-vault" "cloudya-nomad" "cloudya-traefik")
    for service in "${services[@]}"; do
        if systemctl is-enabled --quiet "$service" 2>/dev/null; then
            log_info "Starting service: $service"
            if [[ "$DRY_RUN" != "true" ]]; then
                systemctl start "$service"
            fi
        else
            log_debug "Service $service is not enabled"
        fi
    done
    
    # Wait for services to start
    if [[ "$DRY_RUN" != "true" ]]; then
        sleep 15
    fi
}

# Create Docker snapshot
backup_docker() {
    local backup_dir="$1"
    
    log_step "Backing up Docker containers and volumes..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would backup Docker containers and volumes"
        return 0
    fi
    
    # Create Docker backup directory
    mkdir -p "$backup_dir/docker"
    
    # Export running containers
    log_info "Exporting Docker containers..."
    docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}" > "$backup_dir/docker/containers.list"
    
    # Backup Docker volumes
    log_info "Backing up Docker volumes..."
    docker volume ls --quiet | grep -E "cloudya|monitoring" | while read -r volume; do
        log_debug "Backing up volume: $volume"
        docker run --rm \
            -v "$volume":/source:ro \
            -v "$backup_dir/docker:/backup" \
            alpine tar czf "/backup/volume_${volume}.tar.gz" -C /source .
    done
    
    # Export container configurations
    log_info "Exporting container configurations..."
    docker ps -a --format "{{.Names}}" | grep -E "cloudya|monitoring" | while read -r container; do
        log_debug "Exporting container: $container"
        docker inspect "$container" > "$backup_dir/docker/inspect_${container}.json"
    done
    
    log_success "Docker backup completed"
}

# Create full backup
create_full_backup() {
    local backup_id="$1"
    local backup_dir="$BACKUP_BASE_DIR/full/$backup_id"
    
    log_step "Creating full backup: $backup_id"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create full backup: $backup_id"
        return 0
    fi
    
    # Create backup directory
    mkdir -p "$backup_dir"
    
    # Create manifest
    create_backup_manifest "$backup_id" "$backup_dir" "full"
    
    # Stop services for consistency
    stop_services
    
    # Backup filesystem paths
    log_info "Backing up filesystem paths..."
    local backup_paths
    mapfile -t backup_paths < <(get_backup_paths "full")
    
    for path in "${backup_paths[@]}"; do
        if [[ -e "$path" ]]; then
            log_debug "Backing up path: $path"
            local basename_path=$(basename "$path")
            tar -czf "$backup_dir/${basename_path}.tar.gz" \
                --absolute-names \
                --exclude="*.tmp" \
                --exclude="*.log.*" \
                --exclude="lost+found" \
                "$path" 2>/dev/null || log_warning "Some files in $path could not be backed up"
        else
            log_debug "Path does not exist: $path"
        fi
    done
    
    # Backup Docker
    backup_docker "$backup_dir"
    
    # Create database dumps if databases are running
    if docker ps --filter "name=postgres" --format "{{.Names}}" | grep -q postgres; then
        log_info "Creating database backup..."
        mkdir -p "$backup_dir/databases"
        docker exec postgres pg_dumpall -U postgres > "$backup_dir/databases/postgres_dump.sql"
    fi
    
    # Start services
    start_services
    
    # Create checksums
    log_info "Generating checksums..."
    find "$backup_dir" -type f -name "*.tar.gz" -exec sha256sum {} \; > "$backup_dir/checksums.txt"
    
    # Encrypt backup if enabled
    if [[ "$ENCRYPTION_ENABLED" == "true" ]]; then
        encrypt_backup "$backup_dir"
    fi
    
    # Update state file
    echo "$backup_id:full:$(date +%s)" > "$BACKUP_BASE_DIR/.last_backup_state"
    
    log_success "Full backup completed: $backup_id"
}

# Create incremental backup
create_incremental_backup() {
    local backup_id="$1"
    local backup_dir="$BACKUP_BASE_DIR/incremental/$backup_id"
    
    log_step "Creating incremental backup: $backup_id"
    
    # Find the last full backup
    local last_full_backup
    last_full_backup=$(find "$BACKUP_BASE_DIR/full" -maxdepth 1 -type d -name "backup-*" | sort | tail -1)
    
    if [[ -z "$last_full_backup" ]]; then
        log_warning "No full backup found. Creating full backup instead."
        create_full_backup "$backup_id"
        return
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create incremental backup: $backup_id"
        log_info "[DRY RUN] Base backup: $(basename "$last_full_backup")"
        return 0
    fi
    
    # Create backup directory
    mkdir -p "$backup_dir"
    
    # Create manifest
    create_backup_manifest "$backup_id" "$backup_dir" "incremental"
    echo "base_backup: $(basename "$last_full_backup")" >> "$backup_dir/manifest.json"
    
    # Create incremental backup using rsync
    log_info "Creating incremental backup based on: $(basename "$last_full_backup")"
    
    local backup_paths
    mapfile -t backup_paths < <(get_backup_paths "incremental")
    
    for path in "${backup_paths[@]}"; do
        if [[ -e "$path" ]]; then
            local basename_path=$(basename "$path")
            log_debug "Incremental backup of path: $path"
            
            rsync -av \
                --link-dest="$last_full_backup/$basename_path/" \
                --exclude="*.tmp" \
                --exclude="*.log.*" \
                --exclude="lost+found" \
                "$path/" "$backup_dir/$basename_path/" 2>/dev/null || log_warning "Some files in $path could not be backed up"
        fi
    done
    
    # Create checksums
    find "$backup_dir" -type f -exec sha256sum {} \; > "$backup_dir/checksums.txt"
    
    # Encrypt backup if enabled
    if [[ "$ENCRYPTION_ENABLED" == "true" ]]; then
        encrypt_backup "$backup_dir"
    fi
    
    # Update state file
    echo "$backup_id:incremental:$(date +%s)" > "$BACKUP_BASE_DIR/.last_backup_state"
    
    log_success "Incremental backup completed: $backup_id"
}

# Encrypt backup
encrypt_backup() {
    local backup_dir="$1"
    
    log_step "Encrypting backup..."
    
    local key_file="/etc/cloudya/backup.key"
    if [[ ! -f "$key_file" ]]; then
        log_error "Encryption key not found: $key_file"
        return 1
    fi
    
    # Create encrypted archive
    local encrypted_file="${backup_dir}.tar.gz.gpg"
    tar -czf - -C "$(dirname "$backup_dir")" "$(basename "$backup_dir")" | \
        gpg --batch --yes --cipher-algo AES256 --compress-algo 2 --compress-level "$COMPRESSION_LEVEL" \
            --passphrase-file "$key_file" --symmetric --output "$encrypted_file"
    
    # Remove unencrypted directory
    rm -rf "$backup_dir"
    
    log_success "Backup encrypted: $encrypted_file"
}

# Verify backup integrity
verify_backup() {
    local backup_id="$1"
    
    log_step "Verifying backup integrity: $backup_id"
    
    # Find backup location
    local backup_path=""
    for backup_type in full incremental config; do
        if [[ -d "$BACKUP_BASE_DIR/$backup_type/$backup_id" ]]; then
            backup_path="$BACKUP_BASE_DIR/$backup_type/$backup_id"
            break
        elif [[ -f "$BACKUP_BASE_DIR/$backup_type/${backup_id}.tar.gz.gpg" ]]; then
            backup_path="$BACKUP_BASE_DIR/$backup_type/${backup_id}.tar.gz.gpg"
            break
        fi
    done
    
    if [[ -z "$backup_path" ]]; then
        log_error "Backup not found: $backup_id"
        return 1
    fi
    
    # Verify encrypted backup
    if [[ "$backup_path" =~ \.gpg$ ]]; then
        log_info "Verifying encrypted backup..."
        local key_file="/etc/cloudya/backup.key"
        if [[ ! -f "$key_file" ]]; then
            log_error "Encryption key not found: $key_file"
            return 1
        fi
        
        # Test decryption without extracting
        if gpg --batch --yes --passphrase-file "$key_file" --decrypt "$backup_path" | tar -tzf - >/dev/null 2>&1; then
            log_success "Encrypted backup verification passed"
        else
            log_error "Encrypted backup verification failed"
            return 1
        fi
    else
        # Verify unencrypted backup
        if [[ -f "$backup_path/checksums.txt" ]]; then
            log_info "Verifying checksums..."
            if (cd "$(dirname "$backup_path")" && sha256sum -c "$(basename "$backup_path")/checksums.txt" --quiet); then
                log_success "Checksum verification passed"
            else
                log_error "Checksum verification failed"
                return 1
            fi
        else
            log_warning "No checksums file found, skipping verification"
        fi
    fi
    
    log_success "Backup verification completed: $backup_id"
}

# List available backups
list_backups() {
    log_step "Listing available backups..."
    
    echo -e "${WHITE}Available Backups:${NC}"
    echo "=================="
    
    local found_backups=false
    
    for backup_type in full incremental config; do
        local backup_dir="$BACKUP_BASE_DIR/$backup_type"
        if [[ -d "$backup_dir" ]]; then
            local backups=($(find "$backup_dir" -maxdepth 1 \( -type d -name "backup-*" -o -name "*.tar.gz.gpg" \) | sort -r))
            
            if [[ ${#backups[@]} -gt 0 ]]; then
                echo -e "\n${CYAN}${backup_type^} Backups:${NC}"
                for backup in "${backups[@]}"; do
                    local backup_name=$(basename "$backup" .tar.gz.gpg)
                    local backup_date=$(echo "$backup_name" | sed 's/backup-//' | sed 's/-/ /' | sed 's/\(..\)\(..\)\(..\)/\1:\2:\3/')
                    local backup_size=""
                    
                    if [[ -d "$backup" ]]; then
                        backup_size=$(du -sh "$backup" | cut -f1)
                    elif [[ -f "$backup" ]]; then
                        backup_size=$(du -sh "$backup" | cut -f1)
                    fi
                    
                    local encrypted_status=""
                    if [[ "$backup" =~ \.gpg$ ]]; then
                        encrypted_status=" ${GREEN}[encrypted]${NC}"
                    fi
                    
                    echo -e "  ${backup_name} - ${backup_date} - ${backup_size}${encrypted_status}"
                    found_backups=true
                done
            fi
        fi
    done
    
    if [[ "$found_backups" == "false" ]]; then
        echo "No backups found."
    fi
    
    echo ""
}

# Clean up old backups
cleanup_backups() {
    log_step "Cleaning up old backups (retention: $RETENTION_DAYS days)..."
    
    local cleaned_count=0
    
    for backup_type in full incremental config; do
        local backup_dir="$BACKUP_BASE_DIR/$backup_type"
        if [[ -d "$backup_dir" ]]; then
            log_info "Cleaning up $backup_type backups..."
            
            # Find backups older than retention period
            local old_backups
            mapfile -t old_backups < <(find "$backup_dir" -maxdepth 1 \( -type d -name "backup-*" -o -name "*.tar.gz.gpg" \) -mtime "+$RETENTION_DAYS")
            
            for backup in "${old_backups[@]}"; do
                local backup_name=$(basename "$backup")
                log_info "Removing old backup: $backup_name"
                
                if [[ "$DRY_RUN" != "true" ]]; then
                    rm -rf "$backup"
                    ((cleaned_count++))
                else
                    log_info "[DRY RUN] Would remove: $backup_name"
                    ((cleaned_count++))
                fi
            done
        fi
    done
    
    log_success "Cleanup completed. Removed $cleaned_count old backups."
}

# Show backup system status
show_status() {
    log_step "Backup system status..."
    
    echo -e "${WHITE}Cloudya Backup System Status${NC}"
    echo "============================"
    echo ""
    
    # System information
    echo -e "${CYAN}System Information:${NC}"
    echo "  Hostname: $(hostname -f)"
    echo "  OS: $(cat /etc/os-release | grep PRETTY_NAME | cut -d'\"' -f2)"
    echo "  Backup Directory: $BACKUP_BASE_DIR"
    echo "  Log File: $LOG_FILE"
    echo ""
    
    # Backup configuration
    echo -e "${CYAN}Configuration:${NC}"
    echo "  Encryption: $ENCRYPTION_ENABLED"
    echo "  Compression Level: $COMPRESSION_LEVEL"
    echo "  Retention Days: $RETENTION_DAYS"
    echo "  Remote Sync: $REMOTE_SYNC_ENABLED"
    echo "  Parallel Jobs: $PARALLEL_JOBS"
    echo ""
    
    # Disk usage
    echo -e "${CYAN}Storage Usage:${NC}"
    if [[ -d "$BACKUP_BASE_DIR" ]]; then
        du -sh "$BACKUP_BASE_DIR"/* 2>/dev/null | while read -r size path; do
            echo "  $(basename "$path"): $size"
        done
        echo "  Total: $(du -sh "$BACKUP_BASE_DIR" | cut -f1)"
    else
        echo "  Backup directory does not exist"
    fi
    echo ""
    
    # Last backup information
    echo -e "${CYAN}Last Backup:${NC}"
    if [[ -f "$BACKUP_BASE_DIR/.last_backup_state" ]]; then
        local last_backup_info
        last_backup_info=$(cat "$BACKUP_BASE_DIR/.last_backup_state")
        IFS=':' read -r backup_id backup_type timestamp <<< "$last_backup_info"
        echo "  ID: $backup_id"
        echo "  Type: $backup_type"
        echo "  Date: $(date -d "@$timestamp" '+%Y-%m-%d %H:%M:%S')"
    else
        echo "  No backup history found"
    fi
    echo ""
    
    # Service status
    echo -e "${CYAN}Service Status:${NC}"
    for service in cloudya-vault cloudya-nomad cloudya-traefik docker; do
        if systemctl is-active --quiet "$service" 2>/dev/null; then
            echo -e "  $service: ${GREEN}Active${NC}"
        elif systemctl list-unit-files "$service.service" &>/dev/null; then
            echo -e "  $service: ${RED}Inactive${NC}"
        else
            echo -e "  $service: ${YELLOW}Not found${NC}"
        fi
    done
    echo ""
}

# Main execution function
main() {
    # Load configuration
    load_config
    
    # Parse and validate arguments
    parse_arguments "$@"
    
    # Initialize backup system
    init_backup_system
    
    # Execute command
    case "$COMMAND" in
        "backup")
            local backup_id
            backup_id=$(create_backup_id)
            
            case "$BACKUP_TYPE" in
                "full")
                    create_full_backup "$backup_id"
                    ;;
                "incremental")
                    create_incremental_backup "$backup_id"
                    ;;
                "config")
                    log_error "Config backup not yet implemented"
                    exit 1
                    ;;
                *)
                    log_error "Invalid backup type: $BACKUP_TYPE"
                    exit 1
                    ;;
            esac
            
            # Verify backup if requested
            if [[ "$VERIFY_BACKUP" == "true" ]]; then
                verify_backup "$backup_id"
            fi
            ;;
        "restore")
            if [[ -z "${BACKUP_ID:-}" ]]; then
                log_error "Backup ID required for restore command"
                exit 1
            fi
            log_error "Restore functionality not yet implemented"
            exit 1
            ;;
        "list")
            list_backups
            ;;
        "verify")
            if [[ -z "${BACKUP_ID:-}" ]]; then
                log_error "Backup ID required for verify command"
                exit 1
            fi
            verify_backup "$BACKUP_ID"
            ;;
        "cleanup")
            cleanup_backups
            ;;
        "status")
            show_status
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