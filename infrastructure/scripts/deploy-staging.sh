#!/bin/bash

# Staging Environment Deployment Script
# Production-like deployment for staging environment with enhanced security

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "🔒 Deploying to Staging Environment"
echo "=================================="
echo ""
echo "This will deploy:"
echo "  • Nomad cluster (3 nodes)"
echo "  • Vault (HA mode with manual initialization)"
echo "  • Traefik (with TLS enabled)"
echo ""
echo "⚠️  SECURITY NOTICE:"
echo "  • Vault will require manual initialization"
echo "  • Recovery keys must be secured immediately"
echo "  • All services use HTTPS with self-signed certificates"
echo ""

# Parse arguments
FORCE_BOOTSTRAP=false
DRY_RUN=false
VERBOSE=false
COMPONENTS="all"

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
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --force-bootstrap    Force complete bootstrap (destroys existing data)"
            echo "  --dry-run           Perform dry run without actual deployment"
            echo "  --verbose           Enable verbose debug output"
            echo "  --components COMP   Components to deploy (all|nomad|vault|traefik)"
            echo "  --help              Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0                           # Deploy all components"
            echo "  $0 --components vault        # Deploy only Vault"
            echo "  $0 --dry-run --verbose       # Dry run with verbose output"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Confirmation prompt for staging
if [[ "$FORCE_BOOTSTRAP" == "true" && "$DRY_RUN" != "true" ]]; then
    echo ""
    echo "⚠️  WARNING: This will DESTROY existing staging data!"
    echo "⚠️  All secrets, configurations, and persistent data will be lost!"
    echo ""
    read -p "Are you absolutely sure you want to continue? Type 'YES' to confirm: " -r
    if [[ "$REPLY" != "YES" ]]; then
        echo "Deployment cancelled"
        exit 0
    fi
fi

# Build arguments for unified bootstrap script
ARGS="--environment staging --components $COMPONENTS"

if [[ "$FORCE_BOOTSTRAP" == "true" ]]; then
    ARGS="$ARGS --force-bootstrap"
fi

if [[ "$DRY_RUN" == "true" ]]; then
    ARGS="$ARGS --dry-run"
fi

if [[ "$VERBOSE" == "true" ]]; then
    ARGS="$ARGS --verbose"
fi

# Execute unified bootstrap script
exec "$SCRIPT_DIR/unified-bootstrap.sh" $ARGS