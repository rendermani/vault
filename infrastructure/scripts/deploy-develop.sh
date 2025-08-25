#!/bin/bash

# Development Environment Deployment Script
# Quick deployment script for development environment with sensible defaults

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "🚀 Deploying to Development Environment"
echo "======================================"
echo ""
echo "This will deploy:"
echo "  • Nomad cluster (single node)"
echo "  • Vault (development mode with auto-unseal)"
echo "  • Traefik (with dashboard enabled)"
echo ""
echo "All services will be accessible on localhost:"
echo "  • Nomad UI: http://localhost:4646"
echo "  • Vault UI: http://localhost:8200"
echo "  • Traefik Dashboard: http://localhost:8080"
echo ""

# Parse arguments
FORCE_BOOTSTRAP=false
DRY_RUN=false
VERBOSE=false

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
        -h|--help)
            echo "Usage: $0 [--force-bootstrap] [--dry-run] [--verbose]"
            echo ""
            echo "Options:"
            echo "  --force-bootstrap    Force complete bootstrap (destroys existing data)"
            echo "  --dry-run           Perform dry run without actual deployment"
            echo "  --verbose           Enable verbose debug output"
            echo "  --help              Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Build arguments for unified bootstrap script
ARGS="--environment develop"

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