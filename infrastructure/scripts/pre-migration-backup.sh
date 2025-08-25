#!/bin/bash
#
# Pre-Migration Backup Script for Vault and Nomad Infrastructure
# This script backs up existing data before migration/deployment
#
# Usage: ./pre-migration-backup.sh [remote_host] [backup_location]
# Example: ./pre-migration-backup.sh root@cloudya.net /root/backups
#

set -euo pipefail

# Configuration
REMOTE_HOST="${1:-root@cloudya.net}"
BACKUP_BASE_DIR="${2:-/root/backups}"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
BACKUP_DIR="${BACKUP_BASE_DIR}/pre-migration-${TIMESTAMP}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✓${NC} $*"
}

log_warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠${NC} $*"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ✗${NC} $*"
}

# Check if we can connect to the remote host
check_connection() {
    log "Checking connection to ${REMOTE_HOST}..."
    if ssh -o ConnectTimeout=10 -o BatchMode=yes "${REMOTE_HOST}" "echo 'Connection successful'" >/dev/null 2>&1; then
        log_success "Successfully connected to ${REMOTE_HOST}"
        return 0
    else
        log_error "Cannot connect to ${REMOTE_HOST}. Please check your SSH configuration."
        return 1
    fi
}

# Create the backup script that will run on the remote server
create_remote_backup_script() {
    log "Creating remote backup script..."
    
    cat > /tmp/remote_backup.sh << 'EOF'
#!/bin/bash
set -euo pipefail

BACKUP_DIR="$1"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $*"; }
log_success() { echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✓${NC} $*"; }
log_warning() { echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠${NC} $*"; }
log_error() { echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ✗${NC} $*"; }

# Create backup directory structure
log "Creating backup directory structure at ${BACKUP_DIR}..."
mkdir -p "${BACKUP_DIR}"/{vault,nomad,system,logs}

# Create backup manifest
MANIFEST_FILE="${BACKUP_DIR}/backup-manifest.txt"
echo "Pre-Migration Backup Manifest" > "${MANIFEST_FILE}"
echo "Backup Date: $(date)" >> "${MANIFEST_FILE}"
echo "Hostname: $(hostname)" >> "${MANIFEST_FILE}"
echo "System Info: $(uname -a)" >> "${MANIFEST_FILE}"
echo "=================================" >> "${MANIFEST_FILE}"
echo "" >> "${MANIFEST_FILE}"

# Function to backup directory if it exists
backup_directory() {
    local src_dir="$1"
    local dest_name="$2"
    local category="$3"
    
    if [ -d "${src_dir}" ]; then
        log "Backing up ${src_dir} to ${category}/${dest_name}..."
        mkdir -p "${BACKUP_DIR}/${category}"
        
        # Create tarball with compression
        tar -czf "${BACKUP_DIR}/${category}/${dest_name}.tar.gz" -C "$(dirname "${src_dir}")" "$(basename "${src_dir}")" 2>/dev/null || {
            log_warning "Failed to create tarball for ${src_dir}, copying directory instead..."
            cp -r "${src_dir}" "${BACKUP_DIR}/${category}/${dest_name}" 2>/dev/null || {
                log_error "Failed to backup ${src_dir}"
                return 1
            }
        }
        
        # Calculate size
        local size=$(du -sh "${src_dir}" 2>/dev/null | cut -f1 || echo "Unknown")
        echo "${src_dir} -> ${category}/${dest_name} (${size})" >> "${MANIFEST_FILE}"
        log_success "Successfully backed up ${src_dir} (${size})"
        return 0
    else
        log_warning "Directory ${src_dir} does not exist, skipping..."
        echo "${src_dir} -> SKIPPED (not found)" >> "${MANIFEST_FILE}"
        return 1
    fi
}

# Function to backup file if it exists
backup_file() {
    local src_file="$1"
    local dest_name="$2"
    local category="$3"
    
    if [ -f "${src_file}" ]; then
        log "Backing up ${src_file} to ${category}/${dest_name}..."
        mkdir -p "${BACKUP_DIR}/${category}"
        cp "${src_file}" "${BACKUP_DIR}/${category}/${dest_name}" 2>/dev/null || {
            log_error "Failed to backup ${src_file}"
            return 1
        }
        
        local size=$(du -sh "${src_file}" 2>/dev/null | cut -f1 || echo "Unknown")
        echo "${src_file} -> ${category}/${dest_name} (${size})" >> "${MANIFEST_FILE}"
        log_success "Successfully backed up ${src_file} (${size})"
        return 0
    else
        log_warning "File ${src_file} does not exist, skipping..."
        echo "${src_file} -> SKIPPED (not found)" >> "${MANIFEST_FILE}"
        return 1
    fi
}

# Backup Vault data directories
echo "=== VAULT DATA BACKUP ===" >> "${MANIFEST_FILE}"
backup_directory "/opt/vault/data" "opt-vault-data" "vault"
backup_directory "/var/lib/vault" "var-lib-vault" "vault"
backup_directory "/opt/vault" "opt-vault-full" "vault"

# Backup Vault configuration
echo "" >> "${MANIFEST_FILE}"
echo "=== VAULT CONFIG BACKUP ===" >> "${MANIFEST_FILE}"
backup_directory "/etc/vault.d" "etc-vault.d" "vault"
backup_file "/etc/vault/vault.hcl" "vault.hcl" "vault"
backup_file "/etc/vault.hcl" "vault-root.hcl" "vault"

# Backup Nomad data directories
echo "" >> "${MANIFEST_FILE}"
echo "=== NOMAD DATA BACKUP ===" >> "${MANIFEST_FILE}"
backup_directory "/opt/nomad/data" "opt-nomad-data" "nomad"
backup_directory "/var/lib/nomad" "var-lib-nomad" "nomad"
backup_directory "/opt/nomad" "opt-nomad-full" "nomad"

# Backup Nomad configuration
echo "" >> "${MANIFEST_FILE}"
echo "=== NOMAD CONFIG BACKUP ===" >> "${MANIFEST_FILE}"
backup_directory "/etc/nomad.d" "etc-nomad.d" "nomad"
backup_file "/etc/nomad/nomad.hcl" "nomad.hcl" "nomad"
backup_file "/etc/nomad.hcl" "nomad-root.hcl" "nomad"

# Backup TLS certificates and keys
echo "" >> "${MANIFEST_FILE}"
echo "=== TLS/SSL BACKUP ===" >> "${MANIFEST_FILE}"
backup_directory "/etc/ssl/certs/vault" "ssl-vault-certs" "system"
backup_directory "/etc/ssl/private/vault" "ssl-vault-private" "system"
backup_directory "/etc/ssl/certs/nomad" "ssl-nomad-certs" "system"
backup_directory "/etc/ssl/private/nomad" "ssl-nomad-private" "system"
backup_directory "/opt/vault/tls" "vault-tls" "vault"
backup_directory "/opt/nomad/tls" "nomad-tls" "nomad"

# Backup systemd service files
echo "" >> "${MANIFEST_FILE}"
echo "=== SYSTEMD SERVICES BACKUP ===" >> "${MANIFEST_FILE}"
backup_file "/etc/systemd/system/vault.service" "vault.service" "system"
backup_file "/etc/systemd/system/nomad.service" "nomad.service" "system"
backup_file "/lib/systemd/system/vault.service" "lib-vault.service" "system"
backup_file "/lib/systemd/system/nomad.service" "lib-nomad.service" "system"

# Backup environment files
echo "" >> "${MANIFEST_FILE}"
echo "=== ENVIRONMENT FILES BACKUP ===" >> "${MANIFEST_FILE}"
backup_file "/etc/environment" "environment" "system"
backup_file "/etc/default/vault" "default-vault" "system"
backup_file "/etc/default/nomad" "default-nomad" "system"

# Backup logs (recent only to save space)
echo "" >> "${MANIFEST_FILE}"
echo "=== LOGS BACKUP ===" >> "${MANIFEST_FILE}"
log "Backing up recent logs..."
mkdir -p "${BACKUP_DIR}/logs"

# Vault logs
if [ -d "/var/log/vault" ]; then
    find /var/log/vault -name "*.log" -mtime -30 -exec cp {} "${BACKUP_DIR}/logs/" \; 2>/dev/null || true
fi

# Nomad logs
if [ -d "/var/log/nomad" ]; then
    find /var/log/nomad -name "*.log" -mtime -30 -exec cp {} "${BACKUP_DIR}/logs/" \; 2>/dev/null || true
fi

# System logs related to Vault/Nomad
journalctl -u vault --since "30 days ago" > "${BACKUP_DIR}/logs/vault-journal.log" 2>/dev/null || true
journalctl -u nomad --since "30 days ago" > "${BACKUP_DIR}/logs/nomad-journal.log" 2>/dev/null || true

# Check if services are running
echo "" >> "${MANIFEST_FILE}"
echo "=== SERVICE STATUS ===" >> "${MANIFEST_FILE}"
systemctl is-active vault.service >> "${MANIFEST_FILE}" 2>/dev/null || echo "vault.service: inactive" >> "${MANIFEST_FILE}"
systemctl is-active nomad.service >> "${MANIFEST_FILE}" 2>/dev/null || echo "nomad.service: inactive" >> "${MANIFEST_FILE}"

# Save process information
echo "" >> "${MANIFEST_FILE}"
echo "=== PROCESS INFORMATION ===" >> "${MANIFEST_FILE}"
ps aux | grep -E "(vault|nomad)" | grep -v grep >> "${MANIFEST_FILE}" 2>/dev/null || echo "No vault/nomad processes running" >> "${MANIFEST_FILE}"

# Network information
echo "" >> "${MANIFEST_FILE}"
echo "=== NETWORK INFORMATION ===" >> "${MANIFEST_FILE}"
netstat -tlnp 2>/dev/null | grep -E "(8200|4646|8500|8600)" >> "${MANIFEST_FILE}" || echo "No relevant services listening" >> "${MANIFEST_FILE}"

# Disk usage information
echo "" >> "${MANIFEST_FILE}"
echo "=== DISK USAGE ===" >> "${MANIFEST_FILE}"
df -h >> "${MANIFEST_FILE}"

# Create backup summary
echo "" >> "${MANIFEST_FILE}"
echo "=== BACKUP SUMMARY ===" >> "${MANIFEST_FILE}"
echo "Backup completed at: $(date)" >> "${MANIFEST_FILE}"
echo "Total backup size: $(du -sh "${BACKUP_DIR}" | cut -f1)" >> "${MANIFEST_FILE}"
echo "Backup location: ${BACKUP_DIR}" >> "${MANIFEST_FILE}"

# Set proper permissions
chmod -R 600 "${BACKUP_DIR}"
chmod 700 "${BACKUP_DIR}"

log_success "Backup completed successfully!"
log "Backup location: ${BACKUP_DIR}"
log "Backup manifest: ${MANIFEST_FILE}"

# Display backup summary
echo ""
echo "=================================="
echo "       BACKUP SUMMARY"
echo "=================================="
cat "${MANIFEST_FILE}" | tail -20
echo "=================================="

exit 0
EOF

    # Make the remote script executable
    chmod +x /tmp/remote_backup.sh
}

# Transfer and execute the backup script on remote server
execute_remote_backup() {
    log "Transferring backup script to ${REMOTE_HOST}..."
    
    # Transfer the script
    if ! scp /tmp/remote_backup.sh "${REMOTE_HOST}:/tmp/remote_backup.sh"; then
        log_error "Failed to transfer backup script to remote host"
        return 1
    fi
    
    log "Executing backup on remote server..."
    
    # Execute the backup script remotely
    if ssh "${REMOTE_HOST}" "bash /tmp/remote_backup.sh '${BACKUP_DIR}'"; then
        log_success "Remote backup completed successfully"
        
        # Clean up remote script
        ssh "${REMOTE_HOST}" "rm -f /tmp/remote_backup.sh" || true
        
        # Show backup information
        log "Retrieving backup information..."
        ssh "${REMOTE_HOST}" "ls -la '${BACKUP_DIR}' 2>/dev/null || echo 'Backup directory listing failed'"
        
        return 0
    else
        log_error "Remote backup failed"
        return 1
    fi
}

# Download backup manifest for local review
download_manifest() {
    log "Downloading backup manifest for local review..."
    local local_manifest="/tmp/backup-manifest-${TIMESTAMP}.txt"
    
    if scp "${REMOTE_HOST}:${BACKUP_DIR}/backup-manifest.txt" "${local_manifest}" 2>/dev/null; then
        log_success "Backup manifest downloaded to: ${local_manifest}"
        
        echo ""
        echo "=================================="
        echo "    LOCAL BACKUP MANIFEST COPY"
        echo "=================================="
        cat "${local_manifest}"
        echo "=================================="
    else
        log_warning "Could not download backup manifest"
    fi
}

# Main execution
main() {
    echo ""
    echo "=================================="
    echo "  PRE-MIGRATION BACKUP SCRIPT"
    echo "=================================="
    echo "Remote Host: ${REMOTE_HOST}"
    echo "Backup Location: ${BACKUP_DIR}"
    echo "Timestamp: ${TIMESTAMP}"
    echo "=================================="
    echo ""
    
    # Check connection
    if ! check_connection; then
        exit 1
    fi
    
    # Create and transfer backup script
    create_remote_backup_script
    
    # Execute backup
    if execute_remote_backup; then
        # Download manifest
        download_manifest
        
        log_success "Backup process completed successfully!"
        echo ""
        echo "Next steps:"
        echo "1. Verify backup contents on remote server: ssh ${REMOTE_HOST} 'ls -la ${BACKUP_DIR}'"
        echo "2. Check backup manifest: ssh ${REMOTE_HOST} 'cat ${BACKUP_DIR}/backup-manifest.txt'"
        echo "3. Proceed with migration/deployment knowing you have a full backup"
        echo ""
        
        # Clean up local temp files
        rm -f /tmp/remote_backup.sh
        
        exit 0
    else
        log_error "Backup process failed!"
        rm -f /tmp/remote_backup.sh
        exit 1
    fi
}

# Help function
show_help() {
    echo "Pre-Migration Backup Script for Vault and Nomad Infrastructure"
    echo ""
    echo "Usage: $0 [remote_host] [backup_location]"
    echo ""
    echo "Parameters:"
    echo "  remote_host      SSH connection string (default: root@cloudya.net)"
    echo "  backup_location  Remote backup directory (default: /root/backups)"
    echo ""
    echo "Examples:"
    echo "  $0                                    # Use defaults"
    echo "  $0 root@cloudya.net                  # Custom host"
    echo "  $0 root@cloudya.net /opt/backups     # Custom host and location"
    echo ""
    echo "This script will backup:"
    echo "  - Vault data directories (/opt/vault/data, /var/lib/vault)"
    echo "  - Nomad data directories (/opt/nomad/data, /var/lib/nomad)"
    echo "  - Configuration files (/etc/vault.d, /etc/nomad.d)"
    echo "  - TLS certificates and keys"
    echo "  - Service files and logs"
    echo ""
}

# Check for help flag
if [[ "${1:-}" == "-h" ]] || [[ "${1:-}" == "--help" ]]; then
    show_help
    exit 0
fi

# Run main function
main "$@"