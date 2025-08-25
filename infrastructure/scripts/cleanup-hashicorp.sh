#!/bin/bash

# HashiCorp Infrastructure Cleanup Script
# This script safely removes Vault, Nomad, and Consul installations
# Author: Infrastructure Team
# Version: 1.0.0
# Date: 2025-08-25

set -euo pipefail

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly BACKUP_DIR="${HOME}/hashicorp-cleanup-backup-$(date +%Y%m%d-%H%M%S)"
readonly LOG_FILE="${BACKUP_DIR}/cleanup.log"

# Service names to handle
readonly SERVICES=("vault" "nomad" "consul")

# Directories to clean up
readonly CONFIG_DIRS=("/etc/vault.d" "/etc/nomad.d" "/etc/consul.d")
readonly DATA_DIRS=("/var/lib/vault" "/var/lib/nomad" "/var/lib/consul")
readonly OPT_DIRS=("/opt/vault" "/opt/nomad" "/opt/consul")
readonly BIN_DIRS=("/usr/local/bin" "/usr/bin")

# Binary names
readonly BINARIES=("vault" "nomad" "consul")

# Repository sources
readonly APT_SOURCES=("/etc/apt/sources.list.d/hashicorp.list")
readonly YUM_REPOS=("/etc/yum.repos.d/hashicorp.repo")

# Logging function
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case "$level" in
        "INFO")  echo -e "${GREEN}[INFO]${NC} $message" | tee -a "$LOG_FILE" ;;
        "WARN")  echo -e "${YELLOW}[WARN]${NC} $message" | tee -a "$LOG_FILE" ;;
        "ERROR") echo -e "${RED}[ERROR]${NC} $message" | tee -a "$LOG_FILE" ;;
        "DEBUG") echo -e "${BLUE}[DEBUG]${NC} $message" | tee -a "$LOG_FILE" ;;
    esac
}

# Function to check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log "ERROR" "This script must be run as root (use sudo)"
        exit 1
    fi
}

# Function to create backup directory
setup_backup_dir() {
    log "INFO" "Creating backup directory: $BACKUP_DIR"
    mkdir -p "$BACKUP_DIR"
    
    # Create subdirectories for organized backups
    mkdir -p "$BACKUP_DIR"/{services,config,data,binaries,repositories}
    
    log "INFO" "Backup directory created successfully"
}

# Function to confirm action
confirm_action() {
    local action="$1"
    local default="${2:-n}"
    
    echo
    echo -e "${YELLOW}WARNING: This will $action${NC}"
    read -p "Are you sure you want to continue? [y/N]: " -n 1 -r
    echo
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log "INFO" "Operation cancelled by user"
        exit 0
    fi
}

# Function to backup file or directory
backup_item() {
    local source="$1"
    local backup_subdir="$2"
    local dest_dir="$BACKUP_DIR/$backup_subdir"
    
    if [[ -e "$source" ]]; then
        log "INFO" "Backing up: $source"
        mkdir -p "$dest_dir"
        
        if [[ -d "$source" ]]; then
            cp -r "$source" "$dest_dir/"
        else
            cp "$source" "$dest_dir/"
        fi
        
        log "INFO" "Backup completed: $source -> $dest_dir"
    else
        log "DEBUG" "Item does not exist, skipping backup: $source"
    fi
}

# Function to stop and disable systemd services
stop_services() {
    log "INFO" "Stopping and disabling HashiCorp services..."
    
    for service in "${SERVICES[@]}"; do
        if systemctl is-active --quiet "$service" 2>/dev/null; then
            log "INFO" "Stopping service: $service"
            systemctl stop "$service" || log "WARN" "Failed to stop $service"
        fi
        
        if systemctl is-enabled --quiet "$service" 2>/dev/null; then
            log "INFO" "Disabling service: $service"
            systemctl disable "$service" || log "WARN" "Failed to disable $service"
        fi
        
        # Backup service file before removal
        local service_file="/etc/systemd/system/${service}.service"
        if [[ -f "$service_file" ]]; then
            backup_item "$service_file" "services"
            log "INFO" "Removing service file: $service_file"
            rm -f "$service_file"
        fi
    done
    
    # Reload systemd daemon
    log "INFO" "Reloading systemd daemon..."
    systemctl daemon-reload
}

# Function to remove binaries
remove_binaries() {
    log "INFO" "Removing HashiCorp binaries..."
    
    for binary in "${BINARIES[@]}"; do
        for bin_dir in "${BIN_DIRS[@]}"; do
            local binary_path="$bin_dir/$binary"
            if [[ -f "$binary_path" ]]; then
                backup_item "$binary_path" "binaries"
                log "INFO" "Removing binary: $binary_path"
                rm -f "$binary_path"
            fi
        done
    done
}

# Function to clean up directories
cleanup_directories() {
    log "INFO" "Cleaning up HashiCorp directories..."
    
    # Config directories
    for config_dir in "${CONFIG_DIRS[@]}"; do
        if [[ -d "$config_dir" ]]; then
            backup_item "$config_dir" "config"
            log "INFO" "Removing config directory: $config_dir"
            rm -rf "$config_dir"
        fi
    done
    
    # Data directories
    for data_dir in "${DATA_DIRS[@]}"; do
        if [[ -d "$data_dir" ]]; then
            backup_item "$data_dir" "data"
            log "INFO" "Removing data directory: $data_dir"
            rm -rf "$data_dir"
        fi
    done
    
    # Opt directories
    for opt_dir in "${OPT_DIRS[@]}"; do
        if [[ -d "$opt_dir" ]]; then
            backup_item "$opt_dir" "data"
            log "INFO" "Removing opt directory: $opt_dir"
            rm -rf "$opt_dir"
        fi
    done
}

# Function to remove repository sources
remove_repositories() {
    log "INFO" "Removing HashiCorp repository sources..."
    
    # APT sources (Debian/Ubuntu)
    for apt_source in "${APT_SOURCES[@]}"; do
        if [[ -f "$apt_source" ]]; then
            backup_item "$apt_source" "repositories"
            log "INFO" "Removing APT source: $apt_source"
            rm -f "$apt_source"
        fi
    done
    
    # YUM repos (RHEL/CentOS)
    for yum_repo in "${YUM_REPOS[@]}"; do
        if [[ -f "$yum_repo" ]]; then
            backup_item "$yum_repo" "repositories"
            log "INFO" "Removing YUM repo: $yum_repo"
            rm -f "$yum_repo"
        fi
    done
    
    # Update package databases
    if command -v apt-get >/dev/null 2>&1; then
        log "INFO" "Updating APT package database..."
        apt-get update || log "WARN" "Failed to update APT database"
    fi
    
    if command -v yum >/dev/null 2>&1; then
        log "INFO" "Cleaning YUM cache..."
        yum clean all || log "WARN" "Failed to clean YUM cache"
    fi
}

# Function to remove users and groups
remove_users_groups() {
    log "INFO" "Removing HashiCorp users and groups..."
    
    for service in "${SERVICES[@]}"; do
        if id "$service" >/dev/null 2>&1; then
            log "INFO" "Removing user: $service"
            userdel "$service" || log "WARN" "Failed to remove user $service"
        fi
        
        if getent group "$service" >/dev/null 2>&1; then
            log "INFO" "Removing group: $service"
            groupdel "$service" || log "WARN" "Failed to remove group $service"
        fi
    done
}

# Function to clean up process artifacts
cleanup_processes() {
    log "INFO" "Cleaning up process artifacts..."
    
    for service in "${SERVICES[@]}"; do
        # Kill any remaining processes
        if pgrep -f "$service" >/dev/null; then
            log "WARN" "Found running $service processes, terminating..."
            pkill -f "$service" || log "WARN" "Failed to kill $service processes"
            sleep 2
            
            # Force kill if still running
            if pgrep -f "$service" >/dev/null; then
                log "WARN" "Force killing remaining $service processes..."
                pkill -9 -f "$service" || log "WARN" "Failed to force kill $service processes"
            fi
        fi
    done
    
    # Clean up any socket files
    local socket_files=("/tmp/.vault-*" "/tmp/.nomad-*" "/tmp/.consul-*")
    for socket_pattern in "${socket_files[@]}"; do
        if ls $socket_pattern 2>/dev/null; then
            log "INFO" "Removing socket files: $socket_pattern"
            rm -f $socket_pattern
        fi
    done
}

# Function to verify cleanup
verify_cleanup() {
    log "INFO" "Verifying cleanup completion..."
    local issues=0
    
    # Check for remaining services
    for service in "${SERVICES[@]}"; do
        if systemctl is-active --quiet "$service" 2>/dev/null; then
            log "ERROR" "Service still active: $service"
            ((issues++))
        fi
        
        if systemctl list-unit-files | grep -q "^${service}.service"; then
            log "ERROR" "Service file still exists: $service"
            ((issues++))
        fi
    done
    
    # Check for remaining binaries
    for binary in "${BINARIES[@]}"; do
        if command -v "$binary" >/dev/null 2>&1; then
            log "ERROR" "Binary still accessible: $binary"
            ((issues++))
        fi
    done
    
    # Check for remaining directories
    local all_dirs=("${CONFIG_DIRS[@]}" "${DATA_DIRS[@]}" "${OPT_DIRS[@]}")
    for dir in "${all_dirs[@]}"; do
        if [[ -d "$dir" ]]; then
            log "ERROR" "Directory still exists: $dir"
            ((issues++))
        fi
    done
    
    if [[ $issues -eq 0 ]]; then
        log "INFO" "Cleanup verification passed - no issues found"
    else
        log "ERROR" "Cleanup verification failed - $issues issues found"
        return 1
    fi
}

# Function to generate cleanup report
generate_report() {
    local report_file="$BACKUP_DIR/cleanup-report.txt"
    
    log "INFO" "Generating cleanup report: $report_file"
    
    cat > "$report_file" << EOF
HashiCorp Infrastructure Cleanup Report
=======================================

Date: $(date)
Script Version: 1.0.0
Backup Location: $BACKUP_DIR

Services Removed:
$(printf '%s\n' "${SERVICES[@]}")

Binaries Removed:
$(printf '%s\n' "${BINARIES[@]}")

Config Directories Removed:
$(printf '%s\n' "${CONFIG_DIRS[@]}")

Data Directories Removed:
$(printf '%s\n' "${DATA_DIRS[@]}")

Opt Directories Removed:
$(printf '%s\n' "${OPT_DIRS[@]}")

Repository Sources Removed:
$(printf '%s\n' "${APT_SOURCES[@]}" "${YUM_REPOS[@]}")

Backup Contents:
$(find "$BACKUP_DIR" -type f | sort)

Log File: $LOG_FILE

Status: COMPLETED
EOF
    
    log "INFO" "Cleanup report generated successfully"
}

# Function to show help
show_help() {
    cat << EOF
HashiCorp Infrastructure Cleanup Script

USAGE:
    $0 [OPTIONS]

OPTIONS:
    --dry-run        Show what would be cleaned up without making changes
    --force          Skip confirmation prompts (use with caution)
    --backup-only    Only create backups without removing anything
    --help, -h       Show this help message

DESCRIPTION:
    This script safely removes HashiCorp Vault, Nomad, and Consul installations
    including:
    - Systemd services (stop, disable, remove service files)
    - Binary files from /usr/local/bin and /usr/bin
    - Configuration directories (/etc/vault.d, /etc/nomad.d, /etc/consul.d)
    - Data directories (/var/lib/vault, /var/lib/nomad, /var/lib/consul)
    - Opt directories (/opt/vault, /opt/nomad, /opt/consul)
    - APT/YUM repository sources
    - User accounts and groups

    All removed items are backed up to: $BACKUP_DIR

EXAMPLES:
    sudo $0                    # Interactive cleanup with confirmations
    sudo $0 --dry-run          # Show what would be cleaned up
    sudo $0 --force            # Cleanup without confirmations
    sudo $0 --backup-only      # Only create backups

SAFETY FEATURES:
    - Creates comprehensive backups before any removal
    - Asks for confirmation before destructive actions
    - Logs all operations
    - Verifies cleanup completion
    - Generates detailed report

EOF
}

# Main function
main() {
    local dry_run=false
    local force=false
    local backup_only=false
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --dry-run)
                dry_run=true
                shift
                ;;
            --force)
                force=true
                shift
                ;;
            --backup-only)
                backup_only=true
                shift
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                log "ERROR" "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    # Check prerequisites
    if [[ "$backup_only" != true ]]; then
        check_root
    fi
    
    # Setup backup directory
    setup_backup_dir
    
    log "INFO" "Starting HashiCorp infrastructure cleanup..."
    log "INFO" "Backup directory: $BACKUP_DIR"
    log "INFO" "Log file: $LOG_FILE"
    
    if [[ "$dry_run" == true ]]; then
        log "INFO" "DRY RUN MODE - No changes will be made"
        
        echo
        echo "The following items would be cleaned up:"
        echo "Services: ${SERVICES[*]}"
        echo "Binaries: ${BINARIES[*]}"
        echo "Config dirs: ${CONFIG_DIRS[*]}"
        echo "Data dirs: ${DATA_DIRS[*]}"
        echo "Opt dirs: ${OPT_DIRS[*]}"
        echo
        
        exit 0
    fi
    
    # Show warning and get confirmation unless forced
    if [[ "$force" != true ]]; then
        confirm_action "remove all HashiCorp infrastructure components (Vault, Nomad, Consul)"
    fi
    
    # Create backups first
    log "INFO" "Creating backups of all components..."
    
    # Backup services
    for service in "${SERVICES[@]}"; do
        backup_item "/etc/systemd/system/${service}.service" "services"
    done
    
    # Backup directories
    for dir in "${CONFIG_DIRS[@]}" "${DATA_DIRS[@]}" "${OPT_DIRS[@]}"; do
        if [[ -d "$dir" ]]; then
            backup_item "$dir" "data"
        fi
    done
    
    # Backup binaries
    for binary in "${BINARIES[@]}"; do
        for bin_dir in "${BIN_DIRS[@]}"; do
            backup_item "$bin_dir/$binary" "binaries"
        done
    done
    
    # Backup repositories
    for source in "${APT_SOURCES[@]}" "${YUM_REPOS[@]}"; do
        backup_item "$source" "repositories"
    done
    
    if [[ "$backup_only" == true ]]; then
        log "INFO" "Backup-only mode - no removal performed"
        generate_report
        log "INFO" "Backups completed successfully in: $BACKUP_DIR"
        exit 0
    fi
    
    # Perform cleanup steps
    log "INFO" "Starting cleanup operations..."
    
    cleanup_processes
    stop_services
    remove_binaries
    cleanup_directories
    remove_repositories
    remove_users_groups
    
    # Verify cleanup
    if verify_cleanup; then
        log "INFO" "Cleanup completed successfully!"
    else
        log "ERROR" "Cleanup completed with issues - check the log for details"
    fi
    
    # Generate final report
    generate_report
    
    echo
    echo -e "${GREEN}HashiCorp infrastructure cleanup completed!${NC}"
    echo -e "${BLUE}Backup location:${NC} $BACKUP_DIR"
    echo -e "${BLUE}Log file:${NC} $LOG_FILE"
    echo -e "${BLUE}Report:${NC} $BACKUP_DIR/cleanup-report.txt"
    echo
    echo "To restore any component, refer to the backup directory contents."
}

# Run main function with all arguments
main "$@"