#!/usr/bin/env bash
# Example deployment script for Traefik Nomad Pack
# This shows different deployment scenarios

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$SCRIPT_DIR"

echo "🚀 Traefik Nomad Pack Deployment Examples"
echo "=========================================="
echo

# Example 1: Development deployment
echo "📝 Example 1: Development deployment"
echo "-----------------------------------"
echo "ENVIRONMENT=development ./deploy.sh --dry-run"
echo

# Example 2: Staging deployment  
echo "📝 Example 2: Staging deployment"
echo "-------------------------------"
echo "ENVIRONMENT=staging ./deploy.sh"
echo

# Example 3: Production deployment
echo "📝 Example 3: Production deployment"
echo "----------------------------------"
echo "ENVIRONMENT=production ./deploy.sh"
echo

# Example 4: Manual deployment with custom values
echo "📝 Example 4: Manual deployment with nomad-pack"
echo "----------------------------------------------"
echo "nomad-pack run . --name traefik \\"
echo "  --var count=5 \\"
echo "  --var traefik_version=v3.2 \\"
echo "  --var environment=production \\"
echo "  -f values/production.hcl"
echo

# Example 5: Development with custom domain
echo "📝 Example 5: Development with custom settings"
echo "---------------------------------------------"
echo "nomad-pack run . --name traefik-dev \\"
echo "  --var count=1 \\"
echo "  --var environment=development \\"
echo "  --var 'domains=[\"traefik-dev.local\"]' \\"
echo "  --var api_insecure=true \\"
echo "  -f values/development.hcl"
echo

# Example 6: Validate before deploying
echo "📝 Example 6: Validation workflow"
echo "-------------------------------"
echo "./validate.sh"
echo "if [ \$? -eq 0 ]; then"
echo "  ./setup-vault-secrets.sh --non-interactive"
echo "  ./deploy.sh"
echo "else"
echo "  echo 'Validation failed - fix errors before deploying'"
echo "fi"
echo

# Example 7: Update existing deployment
echo "📝 Example 7: Update existing deployment"
echo "--------------------------------------"
echo "# Update Traefik version"
echo "nomad-pack plan . --name traefik --var traefik_version=v3.2"
echo "nomad-pack run . --name traefik --var traefik_version=v3.2"
echo

# Example 8: Multi-environment deployment
echo "📝 Example 8: Multi-environment pipeline"
echo "--------------------------------------"
echo "# Deploy to staging first"
echo "ENVIRONMENT=staging ./deploy.sh"
echo ""
echo "# Run integration tests"
echo "curl -f https://traefik-staging.cloudya.net/ping"
echo ""
echo "# Deploy to production"
echo "ENVIRONMENT=production ./deploy.sh"
echo

echo "💡 Tips:"
echo "--------"
echo "1. Always run validation first: ./validate.sh"
echo "2. Setup secrets before deployment: ./setup-vault-secrets.sh"
echo "3. Use dry-run mode to test: ./deploy.sh --dry-run"
echo "4. Monitor deployment: nomad job status traefik"
echo "5. Check logs: nomad alloc logs -job traefik -f"
echo ""

echo "🔗 Useful Commands:"
echo "------------------"
echo "# Check Traefik status"
echo "nomad job status traefik"
echo ""
echo "# View Traefik dashboard"
echo "open https://traefik.cloudya.net"
echo ""
echo "# Check SSL certificates"
echo "echo | openssl s_client -connect traefik.cloudya.net:443 -servername traefik.cloudya.net 2>/dev/null | openssl x509 -noout -dates"
echo ""
echo "# Monitor metrics"
echo "curl -s http://localhost:8082/metrics | grep traefik"
echo ""
echo "# Stop Traefik"
echo "nomad job stop traefik"
echo ""

echo "✅ Ready to deploy! Choose your deployment method above."