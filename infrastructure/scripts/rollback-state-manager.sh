#!/bin/bash

# Rollback State Management System
# Manages rollback state tracking, deployment history, and automatic failure detection
# Integrates with rollback-manager.sh for comprehensive rollback capabilities

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_DIR="/var/lib/cloudya/rollback-state"
LOG_FILE="/var/log/cloudya/rollback-state.log"

# Configuration
DEPLOYMENT_HISTORY_RETENTION=30
FAILURE_DETECTION_INTERVAL=30
MAX_FAILURE_CHECKS=10
DRY_RUN=false
VERBOSE=false

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
    echo -e "${BLUE}[STATE-INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') $1" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}[STATE-SUCCESS]${NC} $(date '+%Y-%m-%d %H:%M:%S') $1" | tee -a "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}[STATE-WARNING]${NC} $(date '+%Y-%m-%d %H:%M:%S') $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[STATE-ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') $1" | tee -a "$LOG_FILE"
}

log_debug() {
    if [[ "$VERBOSE" == "true" ]]; then
        echo -e "${PURPLE}[STATE-DEBUG]${NC} $(date '+%Y-%m-%d %H:%M:%S') $1" | tee -a "$LOG_FILE"
    fi
}

# Usage function
usage() {
    cat <<EOF
Rollback State Management System

Usage: $0 <command> [options]

Commands:
  init                          Initialize rollback state system
  track-deployment <id>         Track a new deployment
  mark-success <deployment_id>  Mark deployment as successful
  mark-failure <deployment_id>  Mark deployment as failed
  get-status <deployment_id>    Get deployment status
  list-deployments             List deployment history
  get-last-successful          Get last successful deployment
  monitor-health               Monitor system health and trigger rollback
  cleanup-history              Clean up old deployment history
  export-state                 Export state for backup
  import-state <file>          Import state from backup

Options:
  -d, --dry-run               Show what would be done without making changes
  -v, --verbose               Enable verbose debug output
  -i, --interval SECONDS      Health monitoring interval [default: 30]
  -c, --max-checks COUNT      Maximum failure checks before rollback [default: 10]
  -h, --help                  Show this help message

Examples:
  $0 init                                    # Initialize state system
  $0 track-deployment deployment-123         # Track new deployment
  $0 mark-success deployment-123             # Mark as successful
  $0 monitor-health --interval 60            # Monitor with 60s interval
  $0 list-deployments                        # Show deployment history

State Management Features:
  • Deployment tracking and status management
  • Automated health monitoring with failure detection
  • Integration with rollback-manager.sh for automatic rollback
  • Deployment history with success/failure tracking
  • State export/import for disaster recovery
  • Configurable failure thresholds and monitoring intervals

EOF
}

# Initialize state system
init_state_system() {
    log_info "Initializing rollback state management system..."
    
    # Create state directories
    mkdir -p "$STATE_DIR"/{deployments,health,exports}
    mkdir -p "$(dirname "$LOG_FILE")"
    
    # Set permissions
    chmod 700 "$STATE_DIR"
    chmod 644 "$LOG_FILE" 2>/dev/null || true
    
    # Create state files
    touch "$STATE_DIR/deployment_history.json"
    touch "$STATE_DIR/current_deployment.state"
    touch "$STATE_DIR/health_status.json"
    
    # Initialize JSON files if empty
    if [[ ! -s "$STATE_DIR/deployment_history.json" ]]; then
        echo '{"deployments": [], "last_updated": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"}' > "$STATE_DIR/deployment_history.json"
    fi
    
    if [[ ! -s "$STATE_DIR/health_status.json" ]]; then
        echo '{"status": "unknown", "last_check": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'", "failure_count": 0}' > "$STATE_DIR/health_status.json"
    fi
    
    log_success "Rollback state system initialized"
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
            -i|--interval)
                FAILURE_DETECTION_INTERVAL="$2"
                shift 2
                ;;
            -c|--max-checks)
                MAX_FAILURE_CHECKS="$2"
                shift 2
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                if [[ "$COMMAND" == "track-deployment" && -z "${DEPLOYMENT_ID:-}" ]]; then
                    DEPLOYMENT_ID="$1"
                    shift
                elif [[ "$COMMAND" == "mark-success" && -z "${DEPLOYMENT_ID:-}" ]]; then
                    DEPLOYMENT_ID="$1"
                    shift
                elif [[ "$COMMAND" == "mark-failure" && -z "${DEPLOYMENT_ID:-}" ]]; then
                    DEPLOYMENT_ID="$1"
                    shift
                elif [[ "$COMMAND" == "get-status" && -z "${DEPLOYMENT_ID:-}" ]]; then
                    DEPLOYMENT_ID="$1"
                    shift
                elif [[ "$COMMAND" == "import-state" && -z "${IMPORT_FILE:-}" ]]; then
                    IMPORT_FILE="$1"
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

# Track a new deployment
track_deployment() {
    local deployment_id="$1"
    
    log_info "Tracking deployment: $deployment_id"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would track deployment: $deployment_id"
        return 0
    fi
    
    # Create deployment record
    local deployment_record=$(cat <<EOF
{
    "id": "$deployment_id",
    "status": "in_progress",
    "started_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "completed_at": null,
    "success": null,
    "environment": "${ENVIRONMENT:-unknown}",
    "components": "${COMPONENTS:-unknown}",
    "checkpoint_id": "${DEPLOYMENT_CHECKPOINT_ID:-}",
    "hostname": "$(hostname -f)",
    "user": "${USER:-root}",
    "pid": $$
}
EOF
)
    
    # Add to deployment history
    local temp_file=$(mktemp)
    jq --argjson new_deployment "$deployment_record" '.deployments += [$new_deployment] | .last_updated = "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"' "$STATE_DIR/deployment_history.json" > "$temp_file"
    mv "$temp_file" "$STATE_DIR/deployment_history.json"
    
    # Set current deployment
    echo "$deployment_id" > "$STATE_DIR/current_deployment.state"
    
    log_success "Deployment tracked: $deployment_id"
}

# Mark deployment as successful
mark_deployment_success() {
    local deployment_id="$1"
    
    log_info "Marking deployment as successful: $deployment_id"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would mark deployment successful: $deployment_id"
        return 0
    fi
    
    # Update deployment record
    local temp_file=$(mktemp)
    jq --arg dep_id "$deployment_id" --arg completed_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '
        .deployments = (.deployments | map(
            if .id == $dep_id then
                .status = "completed" |
                .success = true |
                .completed_at = $completed_at
            else
                .
            end
        )) |
        .last_updated = "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"
    ' "$STATE_DIR/deployment_history.json" > "$temp_file"
    mv "$temp_file" "$STATE_DIR/deployment_history.json"
    
    # Reset failure count on successful deployment
    update_health_status "healthy" 0
    
    log_success "Deployment marked as successful: $deployment_id"
}

# Mark deployment as failed
mark_deployment_failure() {
    local deployment_id="$1"
    local failure_reason="${2:-Deployment failed}"
    
    log_error "Marking deployment as failed: $deployment_id - $failure_reason"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would mark deployment failed: $deployment_id"
        return 0
    fi
    
    # Update deployment record
    local temp_file=$(mktemp)
    jq --arg dep_id "$deployment_id" --arg completed_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg reason "$failure_reason" '
        .deployments = (.deployments | map(
            if .id == $dep_id then
                .status = "failed" |
                .success = false |
                .completed_at = $completed_at |
                .failure_reason = $reason
            else
                .
            end
        )) |
        .last_updated = "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"
    ' "$STATE_DIR/deployment_history.json" > "$temp_file"
    mv "$temp_file" "$STATE_DIR/deployment_history.json"
    
    # Trigger automatic rollback if enabled
    if [[ "${AUTO_ROLLBACK_ON_FAILURE:-true}" == "true" ]]; then
        trigger_automatic_rollback "$deployment_id" "$failure_reason"
    fi
    
    log_error "Deployment marked as failed: $deployment_id"
}

# Get deployment status
get_deployment_status() {
    local deployment_id="$1"
    
    if [[ ! -f "$STATE_DIR/deployment_history.json" ]]; then
        log_error "No deployment history found"
        return 1
    fi
    
    local deployment_info=$(jq -r --arg dep_id "$deployment_id" '.deployments[] | select(.id == $dep_id)' "$STATE_DIR/deployment_history.json")
    
    if [[ -z "$deployment_info" ]]; then
        log_error "Deployment not found: $deployment_id"
        return 1
    fi
    
    echo "$deployment_info" | jq .
}

# List deployment history
list_deployment_history() {
    log_info "Listing deployment history..."
    
    if [[ ! -f "$STATE_DIR/deployment_history.json" ]]; then
        log_warning "No deployment history found"
        return 0
    fi
    
    echo -e "${WHITE}Deployment History:${NC}"
    echo "==================="
    
    jq -r '.deployments[] | select(.id != null) | 
        "\(.id) | \(.status) | \(.started_at) | \(if .success then "✅" else if .success == false then "❌" else "🔄" end) | \(.environment // "unknown")"' \
        "$STATE_DIR/deployment_history.json" | \
        column -t -s '|' -N "ID,Status,Started,Result,Environment"
    
    echo ""
}

# Get last successful deployment
get_last_successful_deployment() {
    if [[ ! -f "$STATE_DIR/deployment_history.json" ]]; then
        log_warning "No deployment history found"
        return 1
    fi
    
    local last_successful=$(jq -r '.deployments[] | select(.success == true) | .id' "$STATE_DIR/deployment_history.json" | tail -1)
    
    if [[ -n "$last_successful" ]]; then
        echo "$last_successful"
    else
        log_warning "No successful deployments found"
        return 1
    fi
}

# Update health status
update_health_status() {
    local status="$1"
    local failure_count="$2"
    
    local health_record=$(cat <<EOF
{
    "status": "$status",
    "last_check": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "failure_count": $failure_count,
    "hostname": "$(hostname -f)"
}
EOF
)
    
    echo "$health_record" > "$STATE_DIR/health_status.json"
    log_debug "Health status updated: $status (failures: $failure_count)"
}

# Check system health
check_system_health() {
    local health_score=0
    local max_score=4
    local failures=()
    
    # Check systemd services
    if systemctl is-active --quiet consul 2>/dev/null; then
        ((health_score++))
    else
        failures+=("Consul service not active")
    fi
    
    if systemctl is-active --quiet nomad 2>/dev/null; then
        ((health_score++))
    else
        failures+=("Nomad service not active")
    fi
    
    # Check API endpoints
    if curl -s http://localhost:8500/v1/status/leader > /dev/null 2>&1; then
        ((health_score++))
    else
        failures+=("Consul API not responding")
    fi
    
    if curl -s http://localhost:4646/v1/status/leader > /dev/null 2>&1; then
        ((health_score++))
    else
        failures+=("Nomad API not responding")
    fi
    
    # Determine health status
    if [[ $health_score -eq $max_score ]]; then
        echo "healthy"
    elif [[ $health_score -ge 2 ]]; then
        echo "degraded"
    else
        echo "unhealthy"
    fi
    
    # Return failure details if any
    if [[ ${#failures[@]} -gt 0 ]]; then
        log_debug "Health check failures: ${failures[*]}"
    fi
}

# Monitor system health
monitor_system_health() {
    log_info "Starting system health monitoring (interval: ${FAILURE_DETECTION_INTERVAL}s, max failures: $MAX_FAILURE_CHECKS)"
    
    local consecutive_failures=0
    
    while true; do
        local current_health=$(check_system_health)
        log_debug "Health check result: $current_health"
        
        if [[ "$current_health" == "unhealthy" ]]; then
            ((consecutive_failures++))
            log_warning "System unhealthy - consecutive failures: $consecutive_failures/$MAX_FAILURE_CHECKS"
            
            update_health_status "unhealthy" $consecutive_failures
            
            if [[ $consecutive_failures -ge $MAX_FAILURE_CHECKS ]]; then
                log_error "Maximum consecutive failures reached - triggering rollback"
                local current_deployment=$(cat "$STATE_DIR/current_deployment.state" 2>/dev/null || echo "unknown")
                trigger_automatic_rollback "$current_deployment" "System health monitoring detected $consecutive_failures consecutive failures"
                break
            fi
        else
            if [[ $consecutive_failures -gt 0 ]]; then
                log_success "System health recovered after $consecutive_failures failures"
            fi
            consecutive_failures=0
            update_health_status "$current_health" 0
        fi
        
        sleep "$FAILURE_DETECTION_INTERVAL"
    done
}

# Trigger automatic rollback
trigger_automatic_rollback() {
    local deployment_id="$1"
    local reason="$2"
    
    log_error "Triggering automatic rollback for deployment: $deployment_id"
    log_error "Reason: $reason"
    
    # Check if rollback manager exists
    if [[ ! -f "$SCRIPT_DIR/rollback-manager.sh" ]]; then
        log_error "Rollback manager not found: $SCRIPT_DIR/rollback-manager.sh"
        return 1
    fi
    
    # Get the last successful deployment's checkpoint
    local target_checkpoint=""
    if [[ -n "${DEPLOYMENT_CHECKPOINT_ID:-}" ]]; then
        target_checkpoint="$DEPLOYMENT_CHECKPOINT_ID"
    else
        # Find the most recent checkpoint
        target_checkpoint=$("$SCRIPT_DIR/rollback-manager.sh" list | grep "checkpoint-" | head -1 | awk '{print $1}' || echo "")
    fi
    
    if [[ -z "$target_checkpoint" ]]; then
        log_error "No rollback checkpoint available"
        return 1
    fi
    
    log_info "Rolling back to checkpoint: $target_checkpoint"
    
    # Execute rollback
    if "$SCRIPT_DIR/rollback-manager.sh" auto-rollback "$reason"; then
        log_success "Automatic rollback completed successfully"
        
        # Mark current deployment as failed
        mark_deployment_failure "$deployment_id" "$reason - Auto-rollback completed"
    else
        log_error "Automatic rollback failed"
        mark_deployment_failure "$deployment_id" "$reason - Auto-rollback failed"
        return 1
    fi
}

# Clean up old deployment history
cleanup_deployment_history() {
    log_info "Cleaning up deployment history (retention: $DEPLOYMENT_HISTORY_RETENTION days)"
    
    if [[ ! -f "$STATE_DIR/deployment_history.json" ]]; then
        log_debug "No deployment history to clean up"
        return 0
    fi
    
    local cutoff_date=$(date -d "$DEPLOYMENT_HISTORY_RETENTION days ago" -u +%Y-%m-%dT%H:%M:%SZ)
    
    if [[ "$DRY_RUN" == "true" ]]; then
        local count=$(jq --arg cutoff "$cutoff_date" '[.deployments[] | select(.started_at < $cutoff)] | length' "$STATE_DIR/deployment_history.json")
        log_info "[DRY RUN] Would remove $count old deployment records"
        return 0
    fi
    
    local temp_file=$(mktemp)
    jq --arg cutoff "$cutoff_date" '
        .deployments = [.deployments[] | select(.started_at >= $cutoff)] |
        .last_updated = "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"
    ' "$STATE_DIR/deployment_history.json" > "$temp_file"
    
    local old_count=$(jq '.deployments | length' "$STATE_DIR/deployment_history.json")
    local new_count=$(jq '.deployments | length' "$temp_file")
    local removed_count=$((old_count - new_count))
    
    mv "$temp_file" "$STATE_DIR/deployment_history.json"
    
    log_success "Removed $removed_count old deployment records"
}

# Export state for backup
export_state() {
    local export_file="$STATE_DIR/exports/rollback-state-$(date +%Y%m%d-%H%M%S).json"
    
    log_info "Exporting rollback state to: $export_file"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would export state to: $export_file"
        return 0
    fi
    
    # Create comprehensive state export
    local export_data=$(cat <<EOF
{
    "export_timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "hostname": "$(hostname -f)",
    "deployment_history": $(cat "$STATE_DIR/deployment_history.json"),
    "health_status": $(cat "$STATE_DIR/health_status.json"),
    "current_deployment": "$(cat "$STATE_DIR/current_deployment.state" 2>/dev/null || echo "none")",
    "system_info": {
        "os": "$(cat /etc/os-release | grep PRETTY_NAME | cut -d'\"' -f2)",
        "kernel": "$(uname -r)",
        "uptime": "$(uptime)"
    }
}
EOF
)
    
    echo "$export_data" | jq . > "$export_file"
    
    log_success "State exported to: $export_file"
    echo "$export_file"
}

# Import state from backup
import_state() {
    local import_file="$1"
    
    log_info "Importing rollback state from: $import_file"
    
    if [[ ! -f "$import_file" ]]; then
        log_error "Import file not found: $import_file"
        return 1
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would import state from: $import_file"
        return 0
    fi
    
    # Validate import file
    if ! jq empty "$import_file" 2>/dev/null; then
        log_error "Invalid JSON in import file"
        return 1
    fi
    
    # Backup current state
    local backup_file="$STATE_DIR/deployment_history.backup.$(date +%s).json"
    cp "$STATE_DIR/deployment_history.json" "$backup_file" 2>/dev/null || true
    
    # Import deployment history
    jq '.deployment_history' "$import_file" > "$STATE_DIR/deployment_history.json"
    
    # Import health status
    jq '.health_status' "$import_file" > "$STATE_DIR/health_status.json"
    
    # Import current deployment
    jq -r '.current_deployment // "none"' "$import_file" > "$STATE_DIR/current_deployment.state"
    
    log_success "State imported successfully"
    log_info "Previous state backed up to: $backup_file"
}

# Main execution function
main() {
    # Initialize state system
    init_state_system
    
    # Parse and validate arguments
    parse_arguments "$@"
    
    # Execute command
    case "$COMMAND" in
        "init")
            log_success "State system already initialized"
            ;;
        "track-deployment")
            if [[ -z "${DEPLOYMENT_ID:-}" ]]; then
                log_error "Deployment ID required for track-deployment command"
                exit 1
            fi
            track_deployment "$DEPLOYMENT_ID"
            ;;
        "mark-success")
            if [[ -z "${DEPLOYMENT_ID:-}" ]]; then
                log_error "Deployment ID required for mark-success command"
                exit 1
            fi
            mark_deployment_success "$DEPLOYMENT_ID"
            ;;
        "mark-failure")
            if [[ -z "${DEPLOYMENT_ID:-}" ]]; then
                log_error "Deployment ID required for mark-failure command"
                exit 1
            fi
            mark_deployment_failure "$DEPLOYMENT_ID" "${FAILURE_REASON:-Deployment marked as failed}"
            ;;
        "get-status")
            if [[ -z "${DEPLOYMENT_ID:-}" ]]; then
                log_error "Deployment ID required for get-status command"
                exit 1
            fi
            get_deployment_status "$DEPLOYMENT_ID"
            ;;
        "list-deployments")
            list_deployment_history
            ;;
        "get-last-successful")
            get_last_successful_deployment
            ;;
        "monitor-health")
            monitor_system_health
            ;;
        "cleanup-history")
            cleanup_deployment_history
            ;;
        "export-state")
            export_state
            ;;
        "import-state")
            if [[ -z "${IMPORT_FILE:-}" ]]; then
                log_error "Import file required for import-state command"
                exit 1
            fi
            import_state "$IMPORT_FILE"
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