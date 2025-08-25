#!/bin/bash
#
# Quick Command Reference for Pre-Migration Backup
# This script provides the exact commands to execute the backup
#

set -euo pipefail

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo ""
echo "=================================="
echo "  PRE-MIGRATION BACKUP COMMANDS"
echo "=================================="
echo ""

echo -e "${BLUE}1. Make backup script executable:${NC}"
echo "chmod +x ./scripts/pre-migration-backup.sh"
echo ""

echo -e "${BLUE}2. Run backup with default settings (root@cloudya.net, /root/backups):${NC}"
echo "./scripts/pre-migration-backup.sh"
echo ""

echo -e "${BLUE}3. Run backup with custom parameters:${NC}"
echo "./scripts/pre-migration-backup.sh root@cloudya.net /opt/backups"
echo ""

echo -e "${BLUE}4. View help and options:${NC}"
echo "./scripts/pre-migration-backup.sh --help"
echo ""

echo -e "${YELLOW}Quick Start Commands:${NC}"
echo -e "${GREEN}# Execute all commands at once${NC}"
cat << 'EOF'
cd /Users/mlautenschlager/cloudya/vault/infrastructure
chmod +x ./scripts/pre-migration-backup.sh
./scripts/pre-migration-backup.sh

# To check backup afterwards:
ssh root@cloudya.net 'ls -la /root/backups/'
ssh root@cloudya.net 'cat /root/backups/pre-migration-*/backup-manifest.txt'
EOF

echo ""
echo "=================================="
echo "         BACKUP CONTENTS"
echo "=================================="
echo "The backup will include:"
echo "  ✓ Vault data: /opt/vault/data, /var/lib/vault"
echo "  ✓ Nomad data: /opt/nomad/data, /var/lib/nomad"
echo "  ✓ Configurations: /etc/vault.d, /etc/nomad.d"
echo "  ✓ TLS certificates and keys"
echo "  ✓ System service files"
echo "  ✓ Recent logs (last 30 days)"
echo "  ✓ Service status and process information"
echo "  ✓ Network and disk usage information"
echo ""

echo "The backup will be timestamped and stored at:"
echo "  /root/backups/pre-migration-YYYYMMDD-HHMMSS/"
echo ""

echo "=================================="