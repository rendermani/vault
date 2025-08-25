#!/bin/bash

# Production Environment Deployment Script
# High-security production deployment with comprehensive safety checks

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "🔐 Production Environment Deployment"
echo "==================================="
echo ""
echo "🚨 CRITICAL PRODUCTION DEPLOYMENT 🚨"
echo ""
echo "This will deploy:"
echo "  • Nomad cluster (5 nodes with HA)"
echo "  • Vault (HA with performance standbys)"
echo "  • Traefik (production TLS with Let's Encrypt)"
echo ""
echo "🔒 MANDATORY SECURITY REQUIREMENTS:"
echo "  • Vault recovery keys MUST be secured offline immediately"
echo "  • Root tokens MUST be revoked after initial setup"
echo "  • All certificates MUST be production-grade"
echo "  • Monitoring and alerting MUST be configured"
echo "  • Backup procedures MUST be tested"
echo ""
echo "📋 PRE-DEPLOYMENT CHECKLIST:"
echo "  [ ] Security team approval obtained"
echo "  [ ] Change management ticket approved"
echo "  [ ] Rollback plan documented and tested"
echo "  [ ] Monitoring systems ready"
echo "  [ ] Recovery key custodians identified"
echo "  [ ] Emergency contact list updated"
echo ""

# Parse arguments
FORCE_BOOTSTRAP=false
DRY_RUN=false
VERBOSE=false
COMPONENTS="all"
SKIP_SAFETY_CHECKS=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --force-bootstrap)
            FORCE_BOOTSTRAP=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --verbose)
            VERBOSE=true
            shift
            ;;
        --components)
            COMPONENTS="$2"
            shift 2
            ;;
        --skip-safety-checks)
            SKIP_SAFETY_CHECKS=true
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --force-bootstrap      Force complete bootstrap (EXTREMELY DANGEROUS)"
            echo "  --dry-run             Perform dry run without actual deployment"
            echo "  --verbose             Enable verbose debug output"
            echo "  --components COMP     Components to deploy (all|nomad|vault|traefik)"
            echo "  --skip-safety-checks  Skip production safety checks (NOT RECOMMENDED)"
            echo "  --help                Show this help message"
            echo ""
            echo "⚠️  WARNING: Production deployments require extreme caution!"
            echo "⚠️  Always run with --dry-run first to validate the deployment plan"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Production safety checks
if [[ "$SKIP_SAFETY_CHECKS" != "true" && "$DRY_RUN" != "true" ]]; then
    echo ""
    echo "🔍 PRODUCTION SAFETY CHECKS"
    echo "=========================="
    echo ""
    
    # Check 1: Require explicit confirmation of readiness
    echo "SAFETY CHECK 1: Pre-deployment readiness"
    read -p "Have you completed all items in the pre-deployment checklist? [y/N]: " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "❌ Pre-deployment checklist not completed. Aborting."
        exit 1
    fi
    echo "✅ Pre-deployment checklist confirmed"
    echo ""
    
    # Check 2: Backup verification
    echo "SAFETY CHECK 2: Backup verification"
    read -p "Have you verified that all critical data is backed up? [y/N]: " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "❌ Backup verification not completed. Aborting."
        exit 1
    fi
    echo "✅ Backup verification confirmed"
    echo ""
    
    # Check 3: Change management
    echo "SAFETY CHECK 3: Change management approval"
    read -p "Do you have valid change management approval for this deployment? [y/N]: " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "❌ Change management approval not obtained. Aborting."
        exit 1
    fi
    echo "✅ Change management approval confirmed"
    echo ""
    
    # Check 4: Recovery team readiness
    echo "SAFETY CHECK 4: Recovery team readiness"
    read -p "Is the recovery team standing by and ready to respond? [y/N]: " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "❌ Recovery team not ready. Aborting."
        exit 1
    fi
    echo "✅ Recovery team readiness confirmed"
    echo ""
fi

# Bootstrap confirmation for production
if [[ "$FORCE_BOOTSTRAP" == "true" && "$DRY_RUN" != "true" ]]; then
    echo ""
    echo "🚨 EXTREME DANGER WARNING 🚨"
    echo "============================"
    echo ""
    echo "You are about to perform a BOOTSTRAP deployment in PRODUCTION!"
    echo ""
    echo "This will:"
    echo "  💥 DESTROY ALL EXISTING PRODUCTION DATA"
    echo "  💥 DELETE ALL SECRETS AND CONFIGURATIONS"
    echo "  💥 RESET ALL AUTHENTICATION TOKENS"
    echo "  💥 POTENTIALLY CAUSE SERVICE OUTAGES"
    echo ""
    echo "This operation is IRREVERSIBLE and EXTREMELY DANGEROUS!"
    echo ""
    echo "Required confirmations:"
    
    # Confirmation 1: Understanding of consequences
    read -p "Do you understand this will DESTROY ALL PRODUCTION DATA? Type 'I UNDERSTAND': " -r
    if [[ "$REPLY" != "I UNDERSTAND" ]]; then
        echo "❌ Risk not acknowledged. Deployment cancelled."
        exit 0
    fi
    
    # Confirmation 2: Authorization level
    read -p "Are you authorized to perform destructive production operations? Type 'AUTHORIZED': " -r
    if [[ "$REPLY" != "AUTHORIZED" ]]; then
        echo "❌ Authorization not confirmed. Deployment cancelled."
        exit 0
    fi
    
    # Confirmation 3: Final confirmation
    echo ""
    echo "FINAL CONFIRMATION:"
    echo "Type the EXACT phrase: 'BOOTSTRAP PRODUCTION WITH FULL DATA DESTRUCTION'"
    read -p "Confirmation: " -r
    if [[ "$REPLY" != "BOOTSTRAP PRODUCTION WITH FULL DATA DESTRUCTION" ]]; then
        echo "❌ Final confirmation failed. Deployment cancelled."
        exit 0
    fi
    
    echo ""
    echo "🚨 PRODUCTION BOOTSTRAP INITIATED 🚨"
    echo "All safety confirmations received. Proceeding with deployment..."
    echo ""
fi

# Production-specific warnings
if [[ "$DRY_RUN" != "true" ]]; then
    echo "⏰ DEPLOYMENT TIMING"
    echo "==================="
    echo "Production deployment started at: $(date)"
    echo "Expected duration: 15-30 minutes"
    echo "Monitoring required throughout deployment"
    echo ""
fi

# Build arguments for unified bootstrap script
ARGS="--environment production --components $COMPONENTS"

if [[ "$FORCE_BOOTSTRAP" == "true" ]]; then
    ARGS="$ARGS --force-bootstrap"
fi

if [[ "$DRY_RUN" == "true" ]]; then
    ARGS="$ARGS --dry-run"
fi

if [[ "$VERBOSE" == "true" ]]; then
    ARGS="$ARGS --verbose"
fi

# Log deployment start
if [[ "$DRY_RUN" != "true" ]]; then
    echo "📝 DEPLOYMENT LOG"
    echo "================"
    echo "Deployment ID: production-$(date +%Y%m%d-%H%M%S)"
    echo "Operator: $(whoami)@$(hostname)"
    echo "Components: $COMPONENTS"
    echo "Bootstrap: $FORCE_BOOTSTRAP"
    echo "Started: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
    echo ""
fi

# Execute unified bootstrap script
exec "$SCRIPT_DIR/unified-bootstrap.sh" $ARGS