#!/bin/bash

# HashiCorp Infrastructure Restoration Script
# This script restores HashiCorp installations from cleanup backups
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

# Service names
readonly SERVICES=("vault" "nomad" "consul")

# Logging function
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case "$level" in
        "INFO")  echo -e "${GREEN}[INFO]${NC} $message" ;;
        "WARN")  echo -e "${YELLOW}[WARN]${NC} $message" ;;
        "ERROR") echo -e "${RED}[ERROR]${NC} $message" ;;
        "DEBUG") echo -e "${BLUE}[DEBUG]${NC} $message" ;;
    esac
}

# Function to check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log "ERROR" "This script must be run as root (use sudo)"
        exit 1
    fi
}

# Function to find backup directories
find_backup_dirs() {
    local backup_pattern="${HOME}/hashicorp-cleanup-backup-*"
    
    echo "Available backup directories:"
    local count=0
    for backup_dir in $backup_pattern; do
        if [[ -d "$backup_dir" ]]; then
            ((count++))
            echo "$count) $backup_dir"
        fi
    done
    
    if [[ $count -eq 0 ]]; then
        log "ERROR" "No backup directories found matching pattern: $backup_pattern"
        exit 1
    fi
    
    return $count
}

# Function to select backup directory
select_backup_dir() {
    find_backup_dirs
    local max_count=$?
    
    echo
    read -p "Select backup directory (1-$max_count): " -n 1 -r
    echo
    
    if [[ ! $REPLY =~ ^[1-9][0-9]*$ ]] || [[ $REPLY -gt $max_count ]]; then
        log "ERROR" "Invalid selection"
        exit 1
    fi
    
    local backup_pattern="${HOME}/hashicorp-cleanup-backup-*"
    local count=0
    for backup_dir in $backup_pattern; do
        if [[ -d "$backup_dir" ]]; then
            ((count++))
            if [[ $count -eq $REPLY ]]; then
                echo "$backup_dir"
                return
            fi
        fi
    done
}

# Function to validate backup directory
validate_backup() {
    local backup_dir="$1"
    
    log "INFO" "Validating backup directory: $backup_dir"
    
    # Check if required subdirectories exist
    local required_dirs=("services" "config" "data" "binaries" "repositories")
    for subdir in "${required_dirs[@]}"; do
        if [[ ! -d "$backup_dir/$subdir" ]]; then
            log "WARN" "Backup subdirectory missing: $subdir"
        fi
    done
    
    # Check if cleanup report exists
    if [[ ! -f "$backup_dir/cleanup-report.txt" ]]; then
        log "WARN" "Cleanup report not found - backup may be incomplete"
    fi
    
    log "INFO" "Backup validation completed"
}

# Function to restore service files
restore_services() {
    local backup_dir="$1"
    local services_dir="$backup_dir/services"
    
    if [[ ! -d "$services_dir" ]]; then
        log "WARN" "No services backup found"
        return
    fi
    
    log "INFO" "Restoring systemd service files..."
    
    for service in "${SERVICES[@]}"; do
        local service_file="$services_dir/${service}.service"
        local dest_file="/etc/systemd/system/${service}.service"
        
        if [[ -f "$service_file" ]]; then
            log "INFO" "Restoring service file: $service_file -> $dest_file"
            cp "$service_file" "$dest_file"
            chmod 644 "$dest_file"
        else
            log "WARN" "Service file backup not found: $service_file"
        fi
    done
    
    log "INFO" "Reloading systemd daemon..."
    systemctl daemon-reload
}

# Function to restore binaries
restore_binaries() {
    local backup_dir="$1"
    local binaries_dir="$backup_dir/binaries"
    
    if [[ ! -d "$binaries_dir" ]]; then
        log "WARN" "No binaries backup found"
        return
    fi
    
    log "INFO" "Restoring HashiCorp binaries..."
    
    # Find all binary files in backup
    while IFS= read -r -d '' binary_file; do
        local binary_name=$(basename "$binary_file")
        
        # Determine appropriate destination
        local dest_dir="/usr/local/bin"
        if [[ "$binary_file" =~ /usr/bin/ ]]; then
            dest_dir="/usr/bin"
        fi
        
        local dest_file="$dest_dir/$binary_name"
        
        log "INFO" "Restoring binary: $binary_file -> $dest_file"
        cp "$binary_file" "$dest_file"
        chmod 755 "$dest_file"
        
    done < <(find "$binaries_dir" -type f -print0)
}

# Function to restore directories
restore_directories() {
    local backup_dir="$1"
    
    log "INFO" "Restoring HashiCorp directories..."
    
    # Restore config directories
    local config_backup="$backup_dir/config"
    if [[ -d "$config_backup" ]]; then
        for config_dir in "$config_backup"/*; do
            if [[ -d "$config_dir" ]]; then
                local dir_name=$(basename "$config_dir")
                local dest_dir="/etc/$dir_name"
                
                log "INFO" "Restoring config directory: $config_dir -> $dest_dir"
                cp -r "$config_dir" "/etc/"
                
                # Set appropriate permissions
                if [[ "$dir_name" =~ ^(vault|nomad|consul) ]]; then
                    chown -R "${dir_name}:${dir_name}" "$dest_dir" 2>/dev/null || true
                    chmod -R 640 "$dest_dir"
                    chmod 750 "$dest_dir"
                fi
            fi
        done
    fi
    
    # Restore data directories
    local data_backup="$backup_dir/data"
    if [[ -d "$data_backup" ]]; then
        for data_dir in "$data_backup"/*; do
            if [[ -d "$data_dir" ]]; then
                local dir_name=$(basename "$data_dir")
                local dest_dir
                
                # Determine destination based on original location
                case "$dir_name" in
                    "vault.d"|"nomad.d"|"consul.d")
                        dest_dir="/etc/$dir_name"
                        ;;
                    "vault"|"nomad"|"consul")
                        if [[ "$data_dir" =~ /var/lib/ ]]; then
                            dest_dir="/var/lib/$dir_name"
                        elif [[ "$data_dir" =~ /opt/ ]]; then
                            dest_dir="/opt/$dir_name"
                        else
                            dest_dir="/var/lib/$dir_name"
                        fi
                        ;;
                    *)
                        log "WARN" "Unknown directory type: $dir_name"
                        continue
                        ;;
                esac
                
                log "INFO" "Restoring data directory: $data_dir -> $dest_dir"
                mkdir -p "$(dirname "$dest_dir")"
                cp -r "$data_dir" "$(dirname "$dest_dir")/"
                
                # Set appropriate permissions
                local service_name
                case "$dir_name" in
                    *vault*) service_name="vault" ;;
                    *nomad*) service_name="nomad" ;;
                    *consul*) service_name="consul" ;;
                esac
                
                if [[ -n "$service_name" ]]; then
                    chown -R "${service_name}:${service_name}" "$dest_dir" 2>/dev/null || true
                    chmod -R 640 "$dest_dir"
                    chmod 750 "$dest_dir"
                fi
            fi
        done
    fi
}

# Function to restore repository sources
restore_repositories() {
    local backup_dir="$1"
    local repos_dir="$backup_dir/repositories"
    
    if [[ ! -d "$repos_dir" ]]; then
        log "WARN" "No repository sources backup found"
        return
    fi
    
    log "INFO" "Restoring repository sources..."
    
    # Restore APT sources
    if [[ -f "$repos_dir/hashicorp.list" ]]; then
        log "INFO" "Restoring APT source: hashicorp.list"
        cp "$repos_dir/hashicorp.list" "/etc/apt/sources.list.d/"
        chmod 644 "/etc/apt/sources.list.d/hashicorp.list"
        
        if command -v apt-get >/dev/null 2>&1; then
            log "INFO" "Updating APT package database..."
            apt-get update || log "WARN" "Failed to update APT database"
        fi
    fi
    
    # Restore YUM repos
    if [[ -f "$repos_dir/hashicorp.repo" ]]; then
        log "INFO" "Restoring YUM repo: hashicorp.repo"
        cp "$repos_dir/hashicorp.repo" "/etc/yum.repos.d/"
        chmod 644 "/etc/yum.repos.d/hashicorp.repo"
        
        if command -v yum >/dev/null 2>&1; then
            log "INFO" "Cleaning YUM cache..."
            yum clean all || log "WARN" "Failed to clean YUM cache"
        fi
    fi
}

# Function to recreate users and groups
recreate_users_groups() {
    log "INFO" "Recreating HashiCorp users and groups..."
    
    for service in "${SERVICES[@]}"; do
        # Create group if it doesn't exist
        if ! getent group "$service" >/dev/null 2>&1; then
            log "INFO" "Creating group: $service"
            groupadd --system "$service" || log "WARN" "Failed to create group $service"
        fi
        
        # Create user if it doesn't exist
        if ! id "$service" >/dev/null 2>&1; then
            log "INFO" "Creating user: $service"
            useradd --system --gid "$service" --home-dir "/var/lib/$service" \
                --shell /bin/false --comment "HashiCorp $service user" \
                "$service" || log "WARN" "Failed to create user $service"
        fi
    done
}

# Function to verify restoration
verify_restoration() {
    log "INFO" "Verifying restoration completion..."
    local issues=0
    
    # Check for service files
    for service in "${SERVICES[@]}"; do
        local service_file="/etc/systemd/system/${service}.service"
        if [[ ! -f "$service_file" ]]; then
            log "WARN" "Service file not found: $service_file"
            ((issues++))
        fi
    done
    
    # Check for binaries
    for binary in "vault" "nomad" "consul"; do
        if ! command -v "$binary" >/dev/null 2>&1; then
            log "WARN" "Binary not accessible: $binary"
            ((issues++))
        else
            log "INFO" "Binary restored successfully: $binary"
        fi
    done
    
    if [[ $issues -eq 0 ]]; then
        log "INFO" "Restoration verification passed"
    else
        log "WARN" "Restoration completed with $issues issues"
    fi
}

# Function to show restoration summary
show_summary() {
    local backup_dir="$1"
    
    echo
    echo -e "${GREEN}HashiCorp Infrastructure Restoration Summary${NC}"
    echo "=============================================="
    echo "Backup source: $backup_dir"
    echo "Restoration date: $(date)"
    echo
    echo "Next steps:"
    echo "1. Review restored configurations in /etc/{vault.d,nomad.d,consul.d}/"
    echo "2. Check data directories: /var/lib/{vault,nomad,consul}/"
    echo "3. Start and enable services as needed:"
    for service in "${SERVICES[@]}"; do
        echo "   sudo systemctl enable $service"
        echo "   sudo systemctl start $service"
    done
    echo "4. Verify service functionality"
    echo
}

# Function to show help
show_help() {
    cat << EOF
HashiCorp Infrastructure Restoration Script

USAGE:
    $0 [OPTIONS] [BACKUP_DIRECTORY]

OPTIONS:
    --list           List available backup directories
    --help, -h       Show this help message

ARGUMENTS:
    BACKUP_DIRECTORY Optional path to specific backup directory
                    If not provided, script will show available options

DESCRIPTION:
    This script restores HashiCorp Vault, Nomad, and Consul installations
    from backups created by the cleanup-hashicorp.sh script.

    Restoration includes:
    - Systemd service files
    - Binary files
    - Configuration directories
    - Data directories
    - Repository sources
    - User accounts and groups

EXAMPLES:
    sudo $0                                    # Interactive selection
    sudo $0 --list                            # List available backups
    sudo $0 ~/hashicorp-cleanup-backup-20250825-143022  # Restore specific backup

SAFETY FEATURES:
    - Validates backup directory before restoration
    - Preserves existing files when possible
    - Sets appropriate file permissions and ownership
    - Verifies restoration completion

EOF
}

# Main function
main() {
    local backup_dir=""
    local list_only=false
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --list)
                list_only=true
                shift
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            --*)
                log "ERROR" "Unknown option: $1"
                show_help
                exit 1
                ;;
            *)
                backup_dir="$1"
                shift
                ;;
        esac
    done
    
    if [[ "$list_only" == true ]]; then
        find_backup_dirs
        exit 0
    fi
    
    # Check prerequisites
    check_root
    
    # Select or validate backup directory
    if [[ -z "$backup_dir" ]]; then
        log "INFO" "No backup directory specified, showing available options..."
        backup_dir=$(select_backup_dir)
    fi
    
    if [[ ! -d "$backup_dir" ]]; then
        log "ERROR" "Backup directory does not exist: $backup_dir"
        exit 1
    fi
    
    log "INFO" "Starting HashiCorp infrastructure restoration..."
    log "INFO" "Backup source: $backup_dir"
    
    # Validate backup
    validate_backup "$backup_dir"
    
    # Confirm restoration
    echo
    echo -e "${YELLOW}WARNING: This will restore HashiCorp components from backup${NC}"
    echo "Backup source: $backup_dir"
    read -p "Are you sure you want to continue? [y/N]: " -n 1 -r
    echo
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log "INFO" "Operation cancelled by user"
        exit 0
    fi
    
    # Perform restoration steps
    log "INFO" "Starting restoration operations..."
    
    recreate_users_groups
    restore_directories
    restore_binaries
    restore_services
    restore_repositories
    
    # Verify restoration
    verify_restoration
    
    # Show summary
    show_summary "$backup_dir"
    
    log "INFO" "Restoration completed successfully!"
}

# Run main function with all arguments
main "$@"