#!/usr/bin/env bash
#
# ⚡ QUICK DEPLOY SHORTCUTS
#
# Common deployment patterns made easy
#

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly DEPLOY_SCRIPT="$SCRIPT_DIR/../deploy.sh"

readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

if [[ ! -f "$DEPLOY_SCRIPT" ]]; then
    echo "❌ Deploy script not found at: $DEPLOY_SCRIPT"
    exit 1
fi

show_usage() {
    cat << EOF

⚡ QUICK DEPLOY SHORTCUTS

USAGE: $0 <command> [options]

COMMANDS:
    dev                 Deploy to development environment
    dev-bootstrap       Bootstrap development environment (destructive)
    staging             Deploy to staging environment  
    staging-bootstrap   Bootstrap staging environment (destructive)
    production          Deploy to production environment (with safety checks)
    apps-only           Deploy only applications (skip infrastructure)
    infra-only          Deploy only infrastructure (skip applications)
    dry-run             Perform dry run in development
    status              Check deployment status
    logs                Show recent deployment logs
    health              Run health check
    rollback            Interactive rollback menu

EXAMPLES:
    $0 dev              # Quick development deployment
    $0 staging          # Deploy to staging
    $0 apps-only        # Deploy only Nomad packs
    $0 dry-run          # Test deployment without changes
    $0 health           # Check system health

EOF
}

dev() {
    echo -e "${GREEN}🚀 Quick Development Deployment${NC}"
    "$DEPLOY_SCRIPT" \
        --environment develop \
        --phases all \
        --auto-approve \
        --wait \
        "$@"
}

dev_bootstrap() {
    echo -e "${YELLOW}⚠️  Development Bootstrap (Destructive)${NC}"
    echo "This will completely rebuild the development environment!"
    read -p "Continue? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        "$DEPLOY_SCRIPT" \
            --environment develop \
            --phases all \
            --force-bootstrap \
            --auto-approve \
            --wait \
            "$@"
    fi
}

staging() {
    echo -e "${BLUE}🎯 Staging Deployment${NC}"
    "$DEPLOY_SCRIPT" \
        --environment staging \
        --phases all \
        --wait \
        "$@"
}

staging_bootstrap() {
    echo -e "${YELLOW}⚠️  Staging Bootstrap (Destructive)${NC}"
    echo "This will completely rebuild the staging environment!"
    read -p "Continue? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        "$DEPLOY_SCRIPT" \
            --environment staging \
            --phases all \
            --force-bootstrap \
            --wait \
            "$@"
    fi
}

production() {
    echo -e "${GREEN}🏭 Production Deployment${NC}"
    echo "This will deploy to PRODUCTION with all safety checks enabled."
    "$DEPLOY_SCRIPT" \
        --environment production \
        --phases all \
        --wait \
        "$@"
}

apps_only() {
    echo -e "${BLUE}📦 Applications Only Deployment${NC}"
    local env="${1:-develop}"
    shift 2>/dev/null || true
    
    "$DEPLOY_SCRIPT" \
        --environment "$env" \
        --phases nomad-packs-only \
        --wait \
        "$@"
}

infra_only() {
    echo -e "${BLUE}🏗️  Infrastructure Only Deployment${NC}"
    local env="${1:-develop}"
    shift 2>/dev/null || true
    
    "$DEPLOY_SCRIPT" \
        --environment "$env" \
        --phases infrastructure-only \
        --wait \
        "$@"
}

dry_run() {
    echo -e "${YELLOW}🔍 Dry Run (Development)${NC}"
    "$DEPLOY_SCRIPT" \
        --environment develop \
        --phases all \
        --dry-run \
        --wait \
        "$@"
}

status() {
    echo -e "${BLUE}📊 Deployment Status${NC}"
    "$DEPLOY_SCRIPT" --status
}

logs() {
    echo -e "${BLUE}📋 Deployment Logs${NC}"
    "$DEPLOY_SCRIPT" --logs "$@"
}

health() {
    echo -e "${GREEN}🔍 Health Check${NC}"
    if [[ -f "$SCRIPT_DIR/health-check.sh" ]]; then
        "$SCRIPT_DIR/health-check.sh" "$@"
    else
        echo "Health check script not found. Running basic check..."
        ssh root@cloudya.net 'systemctl status consul nomad docker --no-pager'
    fi
}

rollback() {
    echo -e "${YELLOW}🔄 Interactive Rollback${NC}"
    echo ""
    echo "Select environment to rollback:"
    echo "1) Development"
    echo "2) Staging"
    echo "3) Production"
    echo "4) Cancel"
    
    read -p "Choose (1-4): " -n 1 -r
    echo
    
    case $REPLY in
        1)
            "$DEPLOY_SCRIPT" --environment develop --rollback
            ;;
        2)
            "$DEPLOY_SCRIPT" --environment staging --rollback
            ;;
        3)
            "$DEPLOY_SCRIPT" --environment production --rollback
            ;;
        4|*)
            echo "Rollback cancelled."
            ;;
    esac
}

main() {
    if [[ $# -eq 0 ]]; then
        show_usage
        exit 1
    fi
    
    local command="$1"
    shift
    
    case "$command" in
        dev)
            dev "$@"
            ;;
        dev-bootstrap)
            dev_bootstrap "$@"
            ;;
        staging)
            staging "$@"
            ;;
        staging-bootstrap)
            staging_bootstrap "$@"
            ;;
        production)
            production "$@"
            ;;
        apps-only)
            apps_only "$@"
            ;;
        infra-only)
            infra_only "$@"
            ;;
        dry-run)
            dry_run "$@"
            ;;
        status)
            status "$@"
            ;;
        logs)
            logs "$@"
            ;;
        health)
            health "$@"
            ;;
        rollback)
            rollback "$@"
            ;;
        -h|--help|help)
            show_usage
            ;;
        *)
            echo "❌ Unknown command: $command"
            show_usage
            exit 1
            ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi