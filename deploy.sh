#!/usr/bin/env bash
#
# 🚀 CLOUDYA VAULT INFRASTRUCTURE DEPLOYMENT SCRIPT 🚀
#
# This script orchestrates the complete deployment of the Cloudya Vault infrastructure
# using GitHub Actions workflows for proper IaC practices.
#
# Author: Claude Code Resolution Architect
# Version: 1.0.0
# Date: $(date +%Y-%m-%d)
#

set -euo pipefail

# ===============================================
# CONFIGURATION & CONSTANTS
# ===============================================

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT="$SCRIPT_DIR"
readonly LOG_FILE="/tmp/cloudya-deploy-$(date +%Y%m%d-%H%M%S).log"
readonly GITHUB_API_BASE="https://api.github.com"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly PURPLE='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly WHITE='\033[1;37m'
readonly NC='\033[0m' # No Color

# Default configuration
DEFAULT_ENVIRONMENT="develop"
DEFAULT_DEPLOYMENT_PHASES="all"
DEFAULT_TIMEOUT_MINUTES=60
DEFAULT_MAX_RETRIES=3
DEFAULT_RETRY_DELAY=30

# ===============================================
# UTILITY FUNCTIONS
# ===============================================

log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case "$level" in
        "INFO")  echo -e "${GREEN}[INFO]${NC}  ${timestamp} - $message" | tee -a "$LOG_FILE" ;;
        "WARN")  echo -e "${YELLOW}[WARN]${NC}  ${timestamp} - $message" | tee -a "$LOG_FILE" ;;
        "ERROR") echo -e "${RED}[ERROR]${NC} ${timestamp} - $message" | tee -a "$LOG_FILE" ;;
        "DEBUG") echo -e "${BLUE}[DEBUG]${NC} ${timestamp} - $message" | tee -a "$LOG_FILE" ;;
        "SUCCESS") echo -e "${GREEN}[SUCCESS]${NC} ${timestamp} - $message" | tee -a "$LOG_FILE" ;;
        *) echo -e "${WHITE}[$level]${NC} ${timestamp} - $message" | tee -a "$LOG_FILE" ;;
    esac
}

banner() {
    local text="$1"
    local color="${2:-$CYAN}"
    echo -e "\n${color}════════════════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${color}  $text${NC}"
    echo -e "${color}════════════════════════════════════════════════════════════════════════════════${NC}\n"
}

check_prerequisites() {
    log "INFO" "Checking prerequisites..."
    
    # Check if we're in a Git repository
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        log "ERROR" "Not in a Git repository. Please run from the repository root."
        exit 1
    fi
    
    # Check required tools
    local tools=("gh" "curl" "jq")
    for tool in "${tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            log "ERROR" "Required tool '$tool' is not installed."
            case "$tool" in
                "gh") log "ERROR" "Install GitHub CLI: https://cli.github.com/" ;;
                "jq") log "ERROR" "Install jq: https://stedolan.github.io/jq/" ;;
            esac
            exit 1
        fi
    done
    
    # Check GitHub authentication
    if ! gh auth status &> /dev/null; then
        log "ERROR" "GitHub CLI is not authenticated. Run 'gh auth login' first."
        exit 1
    fi
    
    # Check if we can access the repository
    local repo_info
    if ! repo_info=$(gh repo view --json owner,name 2>/dev/null); then
        log "ERROR" "Cannot access GitHub repository. Check your permissions."
        exit 1
    fi
    
    local repo_owner=$(echo "$repo_info" | jq -r '.owner.login')
    local repo_name=$(echo "$repo_info" | jq -r '.name')
    log "INFO" "Repository: $repo_owner/$repo_name"
    
    log "SUCCESS" "All prerequisites satisfied."
}

show_usage() {
    cat << EOF

🚀 CLOUDYA VAULT INFRASTRUCTURE DEPLOYMENT SCRIPT

USAGE:
    $0 [OPTIONS]

OPTIONS:
    -e, --environment ENV       Target environment (develop|staging|production) [default: $DEFAULT_ENVIRONMENT]
    -p, --phases PHASES         Deployment phases to execute [default: $DEFAULT_DEPLOYMENT_PHASES]
                               Options: all, bootstrap-only, terraform-only, nomad-packs-only, 
                                       infrastructure-only, custom
    --custom-phases PHASES      Custom phases for 'custom' option (e.g., phase1,phase3,phase6)
    -f, --force-bootstrap       Force complete system bootstrap (DESTRUCTIVE)
    -a, --auto-approve          Auto-approve all deployment steps (use with caution)
    -d, --dry-run              Perform dry run without actual changes
    -c, --continue-on-failure   Continue execution even if a phase fails
    -t, --timeout MINUTES      Deployment timeout in minutes [default: $DEFAULT_TIMEOUT_MINUTES]
    -r, --max-retries COUNT     Maximum retries on failure [default: $DEFAULT_MAX_RETRIES]
    -w, --wait                  Wait for deployment completion
    --rollback                  Rollback to previous deployment state
    --status                    Show deployment status
    --logs                      Show deployment logs
    -h, --help                  Show this help message
    -v, --verbose               Enable verbose logging

PHASES:
    all                        Execute all deployment phases (Phase 1 + 3 + 6)
    bootstrap-only             Execute only Ansible bootstrap (Phase 1)
    terraform-only             Execute only Terraform configuration (Phase 3)
    nomad-packs-only           Execute only Nomad Pack deployment (Phase 6)
    infrastructure-only        Execute bootstrap and terraform (Phase 1 + 3)
    custom                     Execute custom phases specified with --custom-phases

EXAMPLES:
    # Full production deployment (USE WITH EXTREME CAUTION)
    $0 --environment production --phases all --wait

    # Development environment with auto-approval
    $0 --environment develop --auto-approve --wait

    # Dry run for staging
    $0 --environment staging --dry-run

    # Bootstrap only for new server
    $0 --environment develop --phases bootstrap-only --force-bootstrap

    # Deploy applications only (assumes infrastructure exists)
    $0 --environment staging --phases nomad-packs-only

    # Custom deployment: bootstrap + applications (skip terraform)
    $0 --phases custom --custom-phases phase1,phase6

    # Check deployment status
    $0 --status

    # Rollback production deployment
    $0 --environment production --rollback

EOF
}

get_repo_info() {
    local repo_info
    repo_info=$(gh repo view --json owner,name 2>/dev/null) || {
        log "ERROR" "Failed to get repository information"
        exit 1
    }
    
    REPO_OWNER=$(echo "$repo_info" | jq -r '.owner.login')
    REPO_NAME=$(echo "$repo_info" | jq -r '.name')
}

trigger_workflow() {
    local workflow_file="$1"
    local inputs="$2"
    local environment="$3"
    
    log "INFO" "Triggering workflow: $workflow_file"
    log "DEBUG" "Inputs: $inputs"
    
    local run_id
    run_id=$(gh workflow run "$workflow_file" --ref main --json "$inputs" 2>/dev/null | jq -r '.id' 2>/dev/null) || {
        # Fallback method using curl
        local response
        response=$(curl -s -X POST \
            -H "Authorization: token $(gh auth token)" \
            -H "Accept: application/vnd.github.v3+json" \
            "$GITHUB_API_BASE/repos/$REPO_OWNER/$REPO_NAME/actions/workflows/$workflow_file/dispatches" \
            -d "{\"ref\":\"main\",\"inputs\":$inputs}")
        
        if echo "$response" | jq -e '.message' > /dev/null 2>&1; then
            log "ERROR" "Failed to trigger workflow: $(echo "$response" | jq -r '.message')"
            return 1
        fi
        
        # Get the latest run ID (GitHub doesn't return run ID in dispatch response)
        sleep 5
        run_id=$(gh run list --workflow="$workflow_file" --limit=1 --json databaseId --jq '.[0].databaseId')
    }
    
    if [[ -n "$run_id" && "$run_id" != "null" ]]; then
        log "SUCCESS" "Workflow triggered successfully. Run ID: $run_id"
        echo "$run_id"
        return 0
    else
        log "ERROR" "Failed to get workflow run ID"
        return 1
    fi
}

wait_for_workflow() {
    local run_id="$1"
    local timeout_minutes="${2:-$DEFAULT_TIMEOUT_MINUTES}"
    local workflow_name="$3"
    
    log "INFO" "Waiting for workflow completion (timeout: ${timeout_minutes}m): $workflow_name"
    log "INFO" "Run ID: $run_id"
    log "INFO" "You can monitor progress at: https://github.com/$REPO_OWNER/$REPO_NAME/actions/runs/$run_id"
    
    local start_time=$(date +%s)
    local timeout_seconds=$((timeout_minutes * 60))
    local last_status=""
    local status_check_interval=30
    
    while true; do
        local current_time=$(date +%s)
        local elapsed=$((current_time - start_time))
        
        if [[ $elapsed -gt $timeout_seconds ]]; then
            log "ERROR" "Workflow timed out after ${timeout_minutes} minutes"
            return 1
        fi
        
        local run_info
        run_info=$(gh run view "$run_id" --json status,conclusion 2>/dev/null) || {
            log "WARN" "Failed to get workflow status, retrying..."
            sleep $status_check_interval
            continue
        }
        
        local status=$(echo "$run_info" | jq -r '.status')
        local conclusion=$(echo "$run_info" | jq -r '.conclusion')
        
        if [[ "$status" != "$last_status" ]]; then
            log "INFO" "Workflow status: $status"
            last_status="$status"
        fi
        
        case "$status" in
            "completed")
                case "$conclusion" in
                    "success")
                        log "SUCCESS" "Workflow completed successfully!"
                        return 0
                        ;;
                    "failure")
                        log "ERROR" "Workflow failed!"
                        return 1
                        ;;
                    "cancelled")
                        log "WARN" "Workflow was cancelled"
                        return 1
                        ;;
                    "timed_out")
                        log "ERROR" "Workflow timed out"
                        return 1
                        ;;
                    *)
                        log "WARN" "Workflow completed with unknown conclusion: $conclusion"
                        return 1
                        ;;
                esac
                ;;
            "in_progress"|"queued")
                # Show progress indicator
                local progress_chars="|/-\\"
                local progress_char=${progress_chars:$((elapsed % 4)):1}
                printf "\r${BLUE}[INFO]${NC}  $(date '+%Y-%m-%d %H:%M:%S') - Workflow in progress... ${progress_char} (${elapsed}s elapsed)"
                sleep $status_check_interval
                ;;
            *)
                log "WARN" "Unknown workflow status: $status"
                sleep $status_check_interval
                ;;
        esac
    done
}

show_deployment_status() {
    log "INFO" "Fetching deployment status..."
    
    local workflows=("unified-deployment-orchestration.yml" "phase1-ansible-bootstrap.yml" "phase3-terraform-config.yml" "phase6-nomad-pack-deploy.yml")
    
    echo -e "\n${CYAN}RECENT WORKFLOW RUNS:${NC}"
    echo -e "════════════════════════════════════════════════════════════════"
    
    for workflow in "${workflows[@]}"; do
        local runs
        runs=$(gh run list --workflow="$workflow" --limit=3 --json status,conclusion,createdAt,databaseId 2>/dev/null) || continue
        
        if [[ $(echo "$runs" | jq '. | length') -gt 0 ]]; then
            echo -e "\n${YELLOW}Workflow: $workflow${NC}"
            echo "$runs" | jq -r '.[] | "  \(.databaseId) - \(.status) (\(.conclusion // "running")) - \(.createdAt)"'
        fi
    done
    
    echo -e "\n${CYAN}You can view detailed logs with: gh run view <run-id> --log${NC}\n"
}

show_deployment_logs() {
    local run_id="$1"
    
    if [[ -z "$run_id" ]]; then
        # Show latest unified deployment logs
        run_id=$(gh run list --workflow="unified-deployment-orchestration.yml" --limit=1 --json databaseId --jq '.[0].databaseId')
        
        if [[ -z "$run_id" || "$run_id" == "null" ]]; then
            log "ERROR" "No recent deployment runs found"
            return 1
        fi
    fi
    
    log "INFO" "Showing logs for run ID: $run_id"
    gh run view "$run_id" --log
}

perform_rollback() {
    local environment="$1"
    
    log "WARN" "Initiating rollback for environment: $environment"
    
    if [[ "$environment" == "production" ]]; then
        banner "⚠️  PRODUCTION ROLLBACK WARNING ⚠️" "$RED"
        echo -e "${RED}You are about to rollback the PRODUCTION environment!${NC}"
        echo -e "${RED}This operation will restore the previous deployment state.${NC}"
        echo -e "\nType 'ROLLBACK PRODUCTION' to confirm:"
        read -r confirmation
        
        if [[ "$confirmation" != "ROLLBACK PRODUCTION" ]]; then
            log "INFO" "Rollback cancelled by user"
            return 1
        fi
    fi
    
    # Check if rollback workflow exists
    if gh workflow list --json name,path | jq -e '.[] | select(.path | contains("rollback"))' > /dev/null; then
        log "INFO" "Triggering rollback workflow..."
        local inputs="{\"environment\":\"$environment\"}"
        local run_id
        
        if run_id=$(trigger_workflow "rollback-management.yml" "$inputs" "$environment"); then
            if [[ "$WAIT_FOR_COMPLETION" == "true" ]]; then
                wait_for_workflow "$run_id" "$TIMEOUT_MINUTES" "Rollback"
            fi
        else
            log "ERROR" "Failed to trigger rollback workflow"
            return 1
        fi
    else
        log "WARN" "No rollback workflow found. Performing manual rollback guidance..."
        cat << EOF

MANUAL ROLLBACK STEPS:
1. SSH into the server: ssh root@cloudya.net
2. Check deployment state: cat /opt/infrastructure/state/deployment-complete
3. Stop current services: systemctl stop nomad consul vault traefik
4. Restore from backup if available
5. Restart services with previous configuration
6. Verify service health

For automated rollback, implement rollback-management.yml workflow.

EOF
    fi
}

execute_deployment() {
    local environment="$1"
    local phases="$2"
    local custom_phases="$3"
    local force_bootstrap="$4"
    local auto_approve="$5"
    local dry_run="$6"
    local continue_on_failure="$7"
    local timeout_minutes="$8"
    
    banner "🚀 STARTING CLOUDYA VAULT DEPLOYMENT 🚀" "$GREEN"
    
    log "INFO" "Deployment Configuration:"
    log "INFO" "  Environment: $environment"
    log "INFO" "  Phases: $phases"
    log "INFO" "  Custom Phases: ${custom_phases:-none}"
    log "INFO" "  Force Bootstrap: $force_bootstrap"
    log "INFO" "  Auto Approve: $auto_approve"
    log "INFO" "  Dry Run: $dry_run"
    log "INFO" "  Continue on Failure: $continue_on_failure"
    log "INFO" "  Timeout: ${timeout_minutes}m"
    log "INFO" "  Log File: $LOG_FILE"
    
    # Production safety check
    if [[ "$environment" == "production" ]]; then
        banner "⚠️  PRODUCTION DEPLOYMENT WARNING ⚠️" "$RED"
        echo -e "${RED}You are about to deploy to the PRODUCTION environment!${NC}"
        echo -e "${RED}This operation may affect live services and data.${NC}"
        echo -e "\nDeployment details:"
        echo -e "  - Phases: $phases"
        echo -e "  - Force Bootstrap: $force_bootstrap"
        echo -e "  - Auto Approve: $auto_approve"
        echo -e "  - Dry Run: $dry_run"
        
        if [[ "$force_bootstrap" == "true" ]]; then
            echo -e "\n${RED}⚠️  DESTRUCTIVE OPERATION: Force bootstrap will destroy existing data!${NC}"
        fi
        
        echo -e "\nType 'DEPLOY TO PRODUCTION' to confirm:"
        read -r confirmation
        
        if [[ "$confirmation" != "DEPLOY TO PRODUCTION" ]]; then
            log "INFO" "Production deployment cancelled by user"
            return 1
        fi
    fi
    
    # Prepare workflow inputs
    local inputs
    inputs=$(jq -n \
        --arg env "$environment" \
        --arg phases "$phases" \
        --arg custom_phases "$custom_phases" \
        --argjson force_bootstrap "$force_bootstrap" \
        --argjson auto_approve "$auto_approve" \
        --argjson dry_run "$dry_run" \
        --argjson continue_on_failure "$continue_on_failure" \
        --argjson timeout "$timeout_minutes" \
        '{
            environment: $env,
            deployment_phases: $phases,
            custom_phases: $custom_phases,
            force_bootstrap: $force_bootstrap,
            auto_approve: $auto_approve,
            dry_run: $dry_run,
            continue_on_failure: $continue_on_failure,
            deployment_timeout: $timeout
        } | with_entries(select(.value != "" and .value != null))')
    
    log "INFO" "Triggering unified deployment workflow..."
    
    local run_id
    if run_id=$(trigger_workflow "unified-deployment-orchestration.yml" "$inputs" "$environment"); then
        log "SUCCESS" "Deployment workflow triggered successfully!"
        log "INFO" "GitHub Actions URL: https://github.com/$REPO_OWNER/$REPO_NAME/actions/runs/$run_id"
        
        if [[ "$WAIT_FOR_COMPLETION" == "true" ]]; then
            if wait_for_workflow "$run_id" "$timeout_minutes" "Unified Deployment"; then
                banner "🎉 DEPLOYMENT COMPLETED SUCCESSFULLY 🎉" "$GREEN"
                log "SUCCESS" "Deployment completed successfully!"
                
                # Show next steps
                cat << EOF

🎯 NEXT STEPS:
1. Verify services are running: ssh root@cloudya.net 'systemctl status consul nomad'
2. Check Nomad jobs: ssh root@cloudya.net 'nomad job status'
3. Access services:
   - Consul UI: http://cloudya.net:8500
   - Nomad UI: http://cloudya.net:4646
   - Vault UI: http://cloudya.net:8200 (if deployed)
4. Monitor logs: journalctl -u consul -u nomad -f

📋 MANAGEMENT:
- View deployment logs: $0 --logs
- Check status: $0 --status
- Rollback if needed: $0 --environment $environment --rollback

EOF
            else
                banner "❌ DEPLOYMENT FAILED" "$RED"
                log "ERROR" "Deployment failed! Check the workflow logs for details."
                log "INFO" "View logs with: gh run view $run_id --log"
                return 1
            fi
        else
            log "INFO" "Deployment started in background. Monitor progress at:"
            log "INFO" "  https://github.com/$REPO_OWNER/$REPO_NAME/actions/runs/$run_id"
            log "INFO" "Or use: $0 --status"
        fi
    else
        log "ERROR" "Failed to trigger deployment workflow"
        return 1
    fi
}

# ===============================================
# MAIN SCRIPT LOGIC
# ===============================================

main() {
    # Default values
    local environment="$DEFAULT_ENVIRONMENT"
    local phases="$DEFAULT_DEPLOYMENT_PHASES"
    local custom_phases=""
    local force_bootstrap="false"
    local auto_approve="false"
    local dry_run="false"
    local continue_on_failure="false"
    local timeout_minutes="$DEFAULT_TIMEOUT_MINUTES"
    local max_retries="$DEFAULT_MAX_RETRIES"
    local show_status="false"
    local show_logs="false"
    local perform_rollback="false"
    local verbose="false"
    
    # Global variables
    WAIT_FOR_COMPLETION="false"
    REPO_OWNER=""
    REPO_NAME=""
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -e|--environment)
                environment="$2"
                shift 2
                ;;
            -p|--phases)
                phases="$2"
                shift 2
                ;;
            --custom-phases)
                custom_phases="$2"
                shift 2
                ;;
            -f|--force-bootstrap)
                force_bootstrap="true"
                shift
                ;;
            -a|--auto-approve)
                auto_approve="true"
                shift
                ;;
            -d|--dry-run)
                dry_run="true"
                shift
                ;;
            -c|--continue-on-failure)
                continue_on_failure="true"
                shift
                ;;
            -t|--timeout)
                timeout_minutes="$2"
                shift 2
                ;;
            -r|--max-retries)
                max_retries="$2"
                shift 2
                ;;
            -w|--wait)
                WAIT_FOR_COMPLETION="true"
                shift
                ;;
            --rollback)
                perform_rollback="true"
                shift
                ;;
            --status)
                show_status="true"
                shift
                ;;
            --logs)
                show_logs="true"
                if [[ $# -gt 1 && $2 =~ ^[0-9]+$ ]]; then
                    log_run_id="$2"
                    shift
                fi
                shift
                ;;
            -v|--verbose)
                verbose="true"
                shift
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            *)
                log "ERROR" "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    # Validate environment
    case "$environment" in
        develop|staging|production)
            ;;
        *)
            log "ERROR" "Invalid environment: $environment"
            log "ERROR" "Valid options: develop, staging, production"
            exit 1
            ;;
    esac
    
    # Validate phases
    case "$phases" in
        all|bootstrap-only|terraform-only|nomad-packs-only|infrastructure-only|custom)
            ;;
        *)
            log "ERROR" "Invalid phases: $phases"
            log "ERROR" "Valid options: all, bootstrap-only, terraform-only, nomad-packs-only, infrastructure-only, custom"
            exit 1
            ;;
    esac
    
    # Custom phases validation
    if [[ "$phases" == "custom" && -z "$custom_phases" ]]; then
        log "ERROR" "Custom phases specified but --custom-phases not provided"
        exit 1
    fi
    
    # Initialize logging
    banner "CLOUDYA VAULT INFRASTRUCTURE DEPLOYMENT" "$PURPLE"
    log "INFO" "Starting deployment script at $(date)"
    log "INFO" "Log file: $LOG_FILE"
    
    # Check prerequisites
    check_prerequisites
    
    # Get repository information
    get_repo_info
    
    # Handle special operations
    if [[ "$show_status" == "true" ]]; then
        show_deployment_status
        exit 0
    fi
    
    if [[ "$show_logs" == "true" ]]; then
        show_deployment_logs "${log_run_id:-}"
        exit 0
    fi
    
    if [[ "$perform_rollback" == "true" ]]; then
        perform_rollback "$environment"
        exit 0
    fi
    
    # Execute deployment with retries
    local attempt=1
    while [[ $attempt -le $max_retries ]]; do
        log "INFO" "Deployment attempt $attempt/$max_retries"
        
        if execute_deployment "$environment" "$phases" "$custom_phases" "$force_bootstrap" "$auto_approve" "$dry_run" "$continue_on_failure" "$timeout_minutes"; then
            log "SUCCESS" "Deployment completed successfully!"
            exit 0
        else
            if [[ $attempt -lt $max_retries ]]; then
                log "WARN" "Deployment attempt $attempt failed. Retrying in ${DEFAULT_RETRY_DELAY}s..."
                sleep "$DEFAULT_RETRY_DELAY"
                ((attempt++))
            else
                log "ERROR" "All deployment attempts failed!"
                exit 1
            fi
        fi
    done
}

# ===============================================
# SCRIPT ENTRY POINT
# ===============================================

# Trap for cleanup
cleanup() {
    local exit_code=$?
    log "INFO" "Script execution completed with exit code: $exit_code"
    log "INFO" "Log file saved at: $LOG_FILE"
    exit $exit_code
}

trap cleanup EXIT

# Only run main if script is executed directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi