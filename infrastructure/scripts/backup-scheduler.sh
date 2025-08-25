#!/bin/bash

# Backup Scheduler Script
# Automates backup scheduling, validation, and recovery testing

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_DIR="$(dirname "$SCRIPT_DIR")"
BACKUP_BASE_DIR="${BACKUP_BASE_DIR:-/var/backups/cloudya}"
RETENTION_DAYS="${RETENTION_DAYS:-30}"
ENVIRONMENT="${ENVIRONMENT:-production}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[BACKUP]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "${YELLOW}[STEP]${NC} $1"; }

# Create backup directories
create_backup_structure() {
    log_step "Creating backup directory structure..."
    
    mkdir -p "$BACKUP_BASE_DIR"/{vault,nomad,consul,traefik,monitoring,scripts,configs}
    mkdir -p "$BACKUP_BASE_DIR"/logs
    mkdir -p /etc/backup-scripts
    
    # Set permissions
    chmod 755 "$BACKUP_BASE_DIR"
    chmod 700 "$BACKUP_BASE_DIR"/{vault,nomad,consul}
    
    log_success "Backup directory structure created"
}

# Create Vault backup script
create_vault_backup_script() {
    log_step "Creating Vault backup script..."
    
    cat > /etc/backup-scripts/backup-vault.sh <<'EOF'
#!/bin/bash
set -euo pipefail

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="/var/backups/cloudya/vault"
VAULT_ADDR="${VAULT_ADDR:-http://localhost:8200}"

export VAULT_ADDR

log() { echo "[$(date)] VAULT BACKUP: $1"; }

# Check Vault status
if ! vault status >/dev/null 2>&1; then
    log "ERROR: Vault is not accessible"
    exit 1
fi

log "Starting Vault backup..."

# Create backup directory
mkdir -p "$BACKUP_DIR/$TIMESTAMP"

# Export secrets (requires appropriate token)
if [ ! -z "${VAULT_TOKEN:-}" ]; then
    log "Backing up KV secrets..."
    
    # List all KV mounts
    vault secrets list -format=json > "$BACKUP_DIR/$TIMESTAMP/secret-mounts.json"
    
    # Backup KV v2 secrets
    for mount in $(vault secrets list -format=json | jq -r 'to_entries[] | select(.value.type == "kv") | .key'); do
        mount_clean=$(echo "$mount" | sed 's/\/$//')
        log "Backing up mount: $mount_clean"
        
        mkdir -p "$BACKUP_DIR/$TIMESTAMP/kv/$mount_clean"
        
        # List all secrets in this mount
        vault kv list -format=json "$mount" > "$BACKUP_DIR/$TIMESTAMP/kv/$mount_clean/list.json" 2>/dev/null || true
        
        # Export individual secrets
        if [ -s "$BACKUP_DIR/$TIMESTAMP/kv/$mount_clean/list.json" ]; then
            cat "$BACKUP_DIR/$TIMESTAMP/kv/$mount_clean/list.json" | jq -r '.[]' | while read -r secret; do
                if [ ! -z "$secret" ]; then
                    vault kv get -format=json "$mount$secret" > "$BACKUP_DIR/$TIMESTAMP/kv/$mount_clean/${secret}.json" 2>/dev/null || true
                fi
            done
        fi
    done
    
    # Backup policies
    log "Backing up policies..."
    vault policy list > "$BACKUP_DIR/$TIMESTAMP/policies-list.txt"
    mkdir -p "$BACKUP_DIR/$TIMESTAMP/policies"
    
    while read -r policy; do
        if [ "$policy" != "default" ] && [ "$policy" != "root" ]; then
            vault policy read "$policy" > "$BACKUP_DIR/$TIMESTAMP/policies/$policy.hcl" 2>/dev/null || true
        fi
    done < "$BACKUP_DIR/$TIMESTAMP/policies-list.txt"
    
    # Backup auth methods
    log "Backing up auth methods..."
    vault auth list -format=json > "$BACKUP_DIR/$TIMESTAMP/auth-methods.json"
    
else
    log "WARNING: No VAULT_TOKEN provided, skipping secrets backup"
fi

# Backup configuration files if available
if [ -d "/opt/vault/config" ]; then
    log "Backing up configuration files..."
    cp -r /opt/vault/config "$BACKUP_DIR/$TIMESTAMP/"
fi

# Create backup manifest
cat > "$BACKUP_DIR/$TIMESTAMP/manifest.json" <<MANIFEST
{
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "type": "vault",
  "environment": "${ENVIRONMENT:-unknown}",
  "vault_version": "$(vault version | head -1 | cut -d' ' -f2)",
  "backup_size": "$(du -sh $BACKUP_DIR/$TIMESTAMP | cut -f1)"
}
MANIFEST

# Compress backup
log "Compressing backup..."
cd "$BACKUP_DIR"
tar czf "$TIMESTAMP.tar.gz" "$TIMESTAMP"
rm -rf "$TIMESTAMP"

log "Vault backup completed: $BACKUP_DIR/$TIMESTAMP.tar.gz"

# Cleanup old backups
find "$BACKUP_DIR" -name "*.tar.gz" -mtime +30 -delete
log "Old backups cleaned up"
EOF
    
    chmod +x /etc/backup-scripts/backup-vault.sh
    log_success "Vault backup script created"
}

# Create Nomad backup script
create_nomad_backup_script() {
    log_step "Creating Nomad backup script..."
    
    cat > /etc/backup-scripts/backup-nomad.sh <<'EOF'
#!/bin/bash
set -euo pipefail

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="/var/backups/cloudya/nomad"
NOMAD_ADDR="${NOMAD_ADDR:-http://localhost:4646}"

export NOMAD_ADDR

log() { echo "[$(date)] NOMAD BACKUP: $1"; }

# Check Nomad status
if ! nomad status >/dev/null 2>&1; then
    log "ERROR: Nomad is not accessible"
    exit 1
fi

log "Starting Nomad backup..."

# Create backup directory
mkdir -p "$BACKUP_DIR/$TIMESTAMP"

# Backup job definitions
log "Backing up job definitions..."
nomad job list -json > "$BACKUP_DIR/$TIMESTAMP/jobs.json"

# Export individual job definitions
mkdir -p "$BACKUP_DIR/$TIMESTAMP/jobs"
nomad job list -t '{{range .}}{{.ID}}{{"\n"}}{{end}}' | while read -r job; do
    if [ ! -z "$job" ]; then
        nomad job inspect "$job" > "$BACKUP_DIR/$TIMESTAMP/jobs/$job.json"
    fi
done

# Backup ACL tokens and policies (if available)
if nomad acl policy list >/dev/null 2>&1; then
    log "Backing up ACL policies..."
    mkdir -p "$BACKUP_DIR/$TIMESTAMP/acl"
    nomad acl policy list -json > "$BACKUP_DIR/$TIMESTAMP/acl/policies.json"
    
    # Export individual policies
    nomad acl policy list -t '{{range .}}{{.Name}}{{"\n"}}{{end}}' | while read -r policy; do
        if [ ! -z "$policy" ]; then
            nomad acl policy info "$policy" -json > "$BACKUP_DIR/$TIMESTAMP/acl/$policy.json"
        fi
    done
fi

# Backup node information
log "Backing up node information..."
nomad node list -json > "$BACKUP_DIR/$TIMESTAMP/nodes.json"

# Backup namespace information
nomad namespace list -json > "$BACKUP_DIR/$TIMESTAMP/namespaces.json" 2>/dev/null || echo "[]" > "$BACKUP_DIR/$TIMESTAMP/namespaces.json"

# Backup configuration files if available
if [ -d "/opt/nomad/config" ]; then
    log "Backing up configuration files..."
    cp -r /opt/nomad/config "$BACKUP_DIR/$TIMESTAMP/"
fi

# Create backup manifest
cat > "$BACKUP_DIR/$TIMESTAMP/manifest.json" <<MANIFEST
{
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "type": "nomad",
  "environment": "${ENVIRONMENT:-unknown}",
  "nomad_version": "$(nomad version | head -1 | cut -d' ' -f2)",
  "backup_size": "$(du -sh $BACKUP_DIR/$TIMESTAMP | cut -f1)"
}
MANIFEST

# Compress backup
log "Compressing backup..."
cd "$BACKUP_DIR"
tar czf "$TIMESTAMP.tar.gz" "$TIMESTAMP"
rm -rf "$TIMESTAMP"

log "Nomad backup completed: $BACKUP_DIR/$TIMESTAMP.tar.gz"

# Cleanup old backups
find "$BACKUP_DIR" -name "*.tar.gz" -mtime +30 -delete
log "Old backups cleaned up"
EOF
    
    chmod +x /etc/backup-scripts/backup-nomad.sh
    log_success "Nomad backup script created"
}

# Create configuration backup script
create_config_backup_script() {
    log_step "Creating configuration backup script..."
    
    cat > /etc/backup-scripts/backup-configs.sh <<'EOF'
#!/bin/bash
set -euo pipefail

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="/var/backups/cloudya/configs"

log() { echo "[$(date)] CONFIG BACKUP: $1"; }

log "Starting configuration backup..."

# Create backup directory
mkdir -p "$BACKUP_DIR/$TIMESTAMP"

# Backup infrastructure code
if [ -d "/opt/infrastructure" ]; then
    log "Backing up infrastructure code..."
    cp -r /opt/infrastructure "$BACKUP_DIR/$TIMESTAMP/"
    
    # Remove any sensitive files
    find "$BACKUP_DIR/$TIMESTAMP/infrastructure" -name "*.env" -delete
    find "$BACKUP_DIR/$TIMESTAMP/infrastructure" -name "*token*" -delete
    find "$BACKUP_DIR/$TIMESTAMP/infrastructure" -name "*key*" -type f -delete
fi

# Backup systemd service files
log "Backing up systemd services..."
mkdir -p "$BACKUP_DIR/$TIMESTAMP/systemd"
for service in consul nomad vault; do
    if [ -f "/etc/systemd/system/$service.service" ]; then
        cp "/etc/systemd/system/$service.service" "$BACKUP_DIR/$TIMESTAMP/systemd/"
    fi
done

# Backup Traefik certificates (non-sensitive parts)
if [ -f "/etc/traefik/acme.json" ]; then
    log "Backing up certificate metadata..."
    mkdir -p "$BACKUP_DIR/$TIMESTAMP/traefik"
    # Extract only metadata, not actual certificates
    jq 'del(.letsencrypt.Certificates[].Certificate, .letsencrypt.Certificates[].PrivateKey)' /etc/traefik/acme.json > "$BACKUP_DIR/$TIMESTAMP/traefik/acme-metadata.json" 2>/dev/null || true
fi

# Create backup manifest
cat > "$BACKUP_DIR/$TIMESTAMP/manifest.json" <<MANIFEST
{
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "type": "configurations",
  "environment": "${ENVIRONMENT:-unknown}",
  "hostname": "$(hostname)",
  "backup_size": "$(du -sh $BACKUP_DIR/$TIMESTAMP | cut -f1)"
}
MANIFEST

# Compress backup
log "Compressing backup..."
cd "$BACKUP_DIR"
tar czf "$TIMESTAMP.tar.gz" "$TIMESTAMP"
rm -rf "$TIMESTAMP"

log "Configuration backup completed: $BACKUP_DIR/$TIMESTAMP.tar.gz"

# Cleanup old backups
find "$BACKUP_DIR" -name "*.tar.gz" -mtime +30 -delete
log "Old backups cleaned up"
EOF
    
    chmod +x /etc/backup-scripts/backup-configs.sh
    log_success "Configuration backup script created"
}

# Create master backup script
create_master_backup_script() {
    log_step "Creating master backup script..."
    
    cat > /etc/backup-scripts/backup-all.sh <<'EOF'
#!/bin/bash
set -euo pipefail

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_FILE="/var/log/backup.log"

log() { 
    echo "[$(date)] MASTER BACKUP: $1" | tee -a "$LOG_FILE"
}

log "=== Starting complete infrastructure backup ==="

# Run all backup scripts
SCRIPTS=(
    "/etc/backup-scripts/backup-vault.sh"
    "/etc/backup-scripts/backup-nomad.sh"
    "/etc/backup-scripts/backup-configs.sh"
)

FAILED=0

for script in "${SCRIPTS[@]}"; do
    if [ -f "$script" ]; then
        log "Running $(basename "$script")..."
        if "$script" >> "$LOG_FILE" 2>&1; then
            log "$(basename "$script") completed successfully"
        else
            log "ERROR: $(basename "$script") failed"
            FAILED=$((FAILED + 1))
        fi
    else
        log "WARNING: Script not found: $script"
    fi
done

# Create backup summary
BACKUP_SUMMARY="/var/backups/cloudya/backup-summary-$TIMESTAMP.json"
cat > "$BACKUP_SUMMARY" <<SUMMARY
{
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "status": "$([ $FAILED -eq 0 ] && echo "success" || echo "partial_failure")",
  "failed_scripts": $FAILED,
  "environment": "${ENVIRONMENT:-unknown}",
  "hostname": "$(hostname)",
  "total_size": "$(du -sh /var/backups/cloudya | cut -f1)"
}
SUMMARY

if [ $FAILED -eq 0 ]; then
    log "=== All backups completed successfully ==="
    exit 0
else
    log "=== Backup completed with $FAILED failures ==="
    exit 1
fi
EOF
    
    chmod +x /etc/backup-scripts/backup-all.sh
    log_success "Master backup script created"
}

# Create backup validation script
create_backup_validation_script() {
    log_step "Creating backup validation script..."
    
    cat > /etc/backup-scripts/validate-backup.sh <<'EOF'
#!/bin/bash
set -euo pipefail

BACKUP_FILE="$1"
TEMP_DIR="/tmp/backup-validation-$(date +%s)"

log() { echo "[$(date)] VALIDATION: $1"; }

if [ -z "$BACKUP_FILE" ]; then
    echo "Usage: $0 <backup-file.tar.gz>"
    exit 1
fi

if [ ! -f "$BACKUP_FILE" ]; then
    log "ERROR: Backup file not found: $BACKUP_FILE"
    exit 1
fi

log "Validating backup: $BACKUP_FILE"

# Create temporary directory
mkdir -p "$TEMP_DIR"
trap "rm -rf $TEMP_DIR" EXIT

# Extract backup
log "Extracting backup..."
cd "$TEMP_DIR"
tar xzf "$BACKUP_FILE"

# Find manifest file
MANIFEST=$(find . -name "manifest.json" | head -1)

if [ -z "$MANIFEST" ]; then
    log "ERROR: No manifest.json found in backup"
    exit 1
fi

log "Found manifest: $MANIFEST"

# Validate manifest
BACKUP_TYPE=$(jq -r '.type' "$MANIFEST")
BACKUP_TIMESTAMP=$(jq -r '.timestamp' "$MANIFEST")
BACKUP_SIZE=$(jq -r '.backup_size' "$MANIFEST")

log "Backup type: $BACKUP_TYPE"
log "Backup timestamp: $BACKUP_TIMESTAMP"
log "Backup size: $BACKUP_SIZE"

# Type-specific validation
case "$BACKUP_TYPE" in
    "vault")
        log "Validating Vault backup..."
        if [ ! -f "secret-mounts.json" ]; then
            log "WARNING: No secret mounts found"
        else
            MOUNT_COUNT=$(jq '. | length' secret-mounts.json)
            log "Found $MOUNT_COUNT secret mounts"
        fi
        
        if [ -d "policies" ]; then
            POLICY_COUNT=$(find policies -name "*.hcl" | wc -l)
            log "Found $POLICY_COUNT policies"
        fi
        ;;
        
    "nomad")
        log "Validating Nomad backup..."
        if [ ! -f "jobs.json" ]; then
            log "ERROR: No jobs.json found"
            exit 1
        fi
        
        JOB_COUNT=$(jq '. | length' jobs.json)
        log "Found $JOB_COUNT jobs"
        
        if [ -d "jobs" ]; then
            JOB_FILE_COUNT=$(find jobs -name "*.json" | wc -l)
            log "Found $JOB_FILE_COUNT job definition files"
        fi
        ;;
        
    "configurations")
        log "Validating configuration backup..."
        if [ -d "infrastructure" ]; then
            log "Infrastructure code found"
        fi
        
        if [ -d "systemd" ]; then
            SERVICE_COUNT=$(find systemd -name "*.service" | wc -l)
            log "Found $SERVICE_COUNT systemd service files"
        fi
        ;;
        
    *)
        log "WARNING: Unknown backup type: $BACKUP_TYPE"
        ;;
esac

# Check file integrity
log "Checking file integrity..."
TOTAL_FILES=$(find . -type f | wc -l)
EMPTY_FILES=$(find . -type f -empty | wc -l)

log "Total files: $TOTAL_FILES"
log "Empty files: $EMPTY_FILES"

if [ "$EMPTY_FILES" -gt 0 ]; then
    log "WARNING: Found $EMPTY_FILES empty files"
    find . -type f -empty
fi

log "Backup validation completed successfully"
EOF
    
    chmod +x /etc/backup-scripts/validate-backup.sh
    log_success "Backup validation script created"
}

# Setup cron jobs
setup_backup_schedule() {
    log_step "Setting up backup schedule..."
    
    # Create cron job for daily backups
    cat > /etc/cron.d/cloudya-backup <<EOF
# CloudYa Infrastructure Backup Schedule
SHELL=/bin/bash
PATH=/usr/local/bin:/usr/bin:/bin
ENVIRONMENT=$ENVIRONMENT

# Daily full backup at 2 AM
0 2 * * * root /etc/backup-scripts/backup-all.sh

# Weekly backup validation on Sundays at 3 AM
0 3 * * 0 root /etc/backup-scripts/validate-latest-backup.sh

# Monthly cleanup of old backups (keep 30 days)
0 4 1 * * root find /var/backups/cloudya -name "*.tar.gz" -mtime +30 -delete
EOF
    
    # Create validation wrapper script
    cat > /etc/backup-scripts/validate-latest-backup.sh <<'EOF'
#!/bin/bash
set -euo pipefail

BACKUP_DIRS="/var/backups/cloudya/vault /var/backups/cloudya/nomad /var/backups/cloudya/configs"

for dir in $BACKUP_DIRS; do
    if [ -d "$dir" ]; then
        LATEST_BACKUP=$(find "$dir" -name "*.tar.gz" -type f -printf '%T@ %p\n' | sort -n | tail -1 | cut -d' ' -f2-)
        if [ ! -z "$LATEST_BACKUP" ]; then
            echo "Validating latest backup in $dir: $(basename "$LATEST_BACKUP")"
            /etc/backup-scripts/validate-backup.sh "$LATEST_BACKUP"
        fi
    fi
done
EOF
    
    chmod +x /etc/backup-scripts/validate-latest-backup.sh
    
    log_success "Backup schedule configured"
}

# Create backup monitoring script
create_backup_monitoring() {
    log_step "Creating backup monitoring..."
    
    cat > /etc/backup-scripts/monitor-backups.sh <<'EOF'
#!/bin/bash
set -euo pipefail

BACKUP_BASE="/var/backups/cloudya"
ALERT_EMAIL="${ALERT_EMAIL:-admin@cloudya.net}"

log() { echo "[$(date)] BACKUP MONITOR: $1"; }

# Check if backups are current (less than 25 hours old)
check_backup_freshness() {
    local backup_dir="$1"
    local backup_type="$2"
    
    if [ ! -d "$backup_dir" ]; then
        log "ERROR: Backup directory not found: $backup_dir"
        return 1
    fi
    
    LATEST_BACKUP=$(find "$backup_dir" -name "*.tar.gz" -type f -printf '%T@ %p\n' | sort -n | tail -1)
    
    if [ -z "$LATEST_BACKUP" ]; then
        log "ERROR: No backups found in $backup_dir"
        return 1
    fi
    
    BACKUP_TIME=$(echo "$LATEST_BACKUP" | cut -d' ' -f1)
    CURRENT_TIME=$(date +%s)
    AGE_HOURS=$(( (CURRENT_TIME - ${BACKUP_TIME%.*}) / 3600 ))
    
    if [ $AGE_HOURS -gt 25 ]; then
        log "ERROR: $backup_type backup is $AGE_HOURS hours old (too old)"
        return 1
    else
        log "OK: $backup_type backup is $AGE_HOURS hours old"
        return 0
    fi
}

# Main monitoring check
FAILED=0

log "=== Backup Monitoring Check ==="

# Check each backup type
for backup_type in vault nomad configs; do
    if ! check_backup_freshness "$BACKUP_BASE/$backup_type" "$backup_type"; then
        FAILED=$((FAILED + 1))
    fi
done

# Check total backup size
TOTAL_SIZE=$(du -sh "$BACKUP_BASE" 2>/dev/null | cut -f1 || echo "0")
log "Total backup size: $TOTAL_SIZE"

# Generate report
REPORT_FILE="/tmp/backup-monitoring-report.txt"
cat > "$REPORT_FILE" <<REPORT
CloudYa Backup Monitoring Report
================================
Date: $(date)
Status: $([ $FAILED -eq 0 ] && echo "HEALTHY" || echo "ISSUES DETECTED")
Failed checks: $FAILED
Total backup size: $TOTAL_SIZE

REPORT

if [ $FAILED -eq 0 ]; then
    log "=== All backup checks passed ==="
    echo "All backup checks passed successfully." >> "$REPORT_FILE"
else
    log "=== $FAILED backup checks failed ==="
    echo "WARNING: $FAILED backup checks failed. Please investigate." >> "$REPORT_FILE"
    
    # Send alert email if configured
    if command -v mail >/dev/null 2>&1 && [ ! -z "$ALERT_EMAIL" ]; then
        mail -s "CloudYa Backup Alert - $FAILED Issues Detected" "$ALERT_EMAIL" < "$REPORT_FILE"
        log "Alert email sent to $ALERT_EMAIL"
    fi
fi

cat "$REPORT_FILE"
exit $FAILED
EOF
    
    chmod +x /etc/backup-scripts/monitor-backups.sh
    
    # Add monitoring to cron (run every 6 hours)
    echo "0 */6 * * * root /etc/backup-scripts/monitor-backups.sh >> /var/log/backup-monitoring.log 2>&1" >> /etc/cron.d/cloudya-backup
    
    log_success "Backup monitoring configured"
}

# Main execution
main() {
    log_info "Setting up backup automation for environment: $ENVIRONMENT"
    
    # Check if running as root
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
        exit 1
    fi
    
    create_backup_structure
    create_vault_backup_script
    create_nomad_backup_script
    create_config_backup_script
    create_master_backup_script
    create_backup_validation_script
    setup_backup_schedule
    create_backup_monitoring
    
    # Create initial backup to test
    log_step "Running initial backup test..."
    if /etc/backup-scripts/backup-all.sh; then
        log_success "Initial backup test completed successfully"
    else
        log_error "Initial backup test failed"
    fi
    
    log_success "Backup automation setup completed successfully!"
    log_info "Backup schedule:"
    log_info "  - Daily backups: 2:00 AM"
    log_info "  - Weekly validation: Sunday 3:00 AM"
    log_info "  - Monitoring checks: Every 6 hours"
    log_info "  - Cleanup: Monthly (30-day retention)"
    log_info ""
    log_info "Manual backup commands:"
    log_info "  - Full backup: /etc/backup-scripts/backup-all.sh"
    log_info "  - Validate backup: /etc/backup-scripts/validate-backup.sh <file>"
    log_info "  - Monitor status: /etc/backup-scripts/monitor-backups.sh"
    log_info ""
    log_info "Backup location: $BACKUP_BASE_DIR"
}

# Handle command line arguments
case "${1:-setup}" in
    setup)
        main
        ;;
    test)
        log_info "Running backup test..."
        /etc/backup-scripts/backup-all.sh
        ;;
    validate)
        if [ -z "${2:-}" ]; then
            log_error "Usage: $0 validate <backup-file>"
            exit 1
        fi
        /etc/backup-scripts/validate-backup.sh "$2"
        ;;
    monitor)
        /etc/backup-scripts/monitor-backups.sh
        ;;
    *)
        echo "Usage: $0 {setup|test|validate|monitor}"
        echo ""
        echo "Commands:"
        echo "  setup     - Setup backup automation (default)"
        echo "  test      - Run test backup"
        echo "  validate  - Validate a backup file"
        echo "  monitor   - Check backup status"
        exit 1
        ;;
esac