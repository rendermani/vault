# Cloudya Infrastructure

Production-ready infrastructure deployment for Cloudya with comprehensive local testing, remote deployment, monitoring, and disaster recovery capabilities.

## 🚀 Quick Start

### Local Development

1. **Setup Local Environment**:
   ```bash
   cd infrastructure
   cp config/local.env.template local.env
   # Edit local.env if needed
   ```

2. **Start Local Stack**:
   ```bash
   docker-compose -f docker-compose.local.yml --env-file local.env up -d
   ```

3. **Access Services**:
   - Traefik Dashboard: http://localhost:8080
   - Vault UI: http://localhost:8200 (token: `dev-only-token`)
   - Nomad UI: http://localhost:4646
   - Grafana: http://localhost:3000 (admin/admin)
   - Prometheus: http://localhost:9090

4. **Stop Local Stack**:
   ```bash
   docker-compose -f docker-compose.local.yml down
   ```

### Production Deployment

1. **Provision Server** (one-time setup):
   ```bash
   ./scripts/provision-server.sh root@cloudya.net --verbose
   ```

2. **Configure Environment**:
   ```bash
   cp config/production.env.template production.env
   # Edit production.env with secure values (see security section)
   ```

3. **Deploy Infrastructure**:
   ```bash
   ./scripts/remote-deploy.sh --verbose
   ```

4. **Verify Deployment**:
   - Check https://vault.cloudya.net
   - Check https://nomad.cloudya.net  
   - Check https://grafana.cloudya.net
   - Review monitoring dashboards

## 📁 Project Structure

```
infrastructure/
├── config/                          # Configuration templates
│   ├── production.env.template       # Production environment variables
│   └── local.env.template           # Local development variables
├── docs/                            # Documentation
│   └── DEPLOYMENT_ARCHITECTURE.md   # Architecture documentation
├── monitoring/                      # Monitoring stack
│   ├── docker-compose.monitoring.yml # Monitoring services
│   └── prometheus/config/           # Prometheus configuration
├── scripts/                         # Deployment automation
│   ├── remote-deploy.sh             # Main deployment script
│   ├── provision-server.sh          # Server provisioning
│   └── backup-restore.sh            # Backup and recovery
├── docker-compose.local.yml         # Local development stack
├── Makefile                         # Build automation
└── README.md                        # This file
```

## 🔧 Available Scripts

### Server Provisioning
```bash
./scripts/provision-server.sh [SERVER] [OPTIONS]

Options:
  -d, --dry-run       Preview changes without applying
  -f, --force         Skip confirmation prompts
  -v, --verbose       Enable debug output
  -s, --skip-security Skip security hardening
  -m, --no-monitoring Skip monitoring setup
  -c, --no-docker     Skip Docker installation
  -w, --no-firewall   Skip firewall configuration
```

### Remote Deployment
```bash
./scripts/remote-deploy.sh [OPTIONS]

Options:
  -d, --dry-run           Preview deployment
  -f, --force-deploy      Skip safety checks
  -b, --skip-backup       Skip backup creation
  -v, --verbose           Enable debug output
  -c, --components COMP   Deploy specific components
  -r, --no-rollback       Disable rollback on failure
  -m, --no-monitoring     Skip monitoring setup
```

### Backup and Recovery
```bash
./scripts/backup-restore.sh <command> [options]

Commands:
  backup                  Create a backup
  restore <backup_id>     Restore from backup
  list                    List available backups
  verify <backup_id>      Verify backup integrity
  cleanup                 Remove old backups
  status                  Show backup system status

Backup Options:
  -t, --type TYPE         Backup type: full, incremental, config
  -r, --retention DAYS    Retention period in days
  -c, --compression LEVEL Compression level 1-9
  -e, --no-encryption     Disable backup encryption
```

### Makefile Commands
```bash
make help              # Show available commands
make bootstrap         # Bootstrap infrastructure
make deploy            # Deploy all components
make test              # Run integration tests
make status            # Check system status
make clean             # Clean up resources
make backup            # Create backup
make monitor           # Open monitoring dashboards
```

## 🔒 Security Configuration

### Production Environment Variables

**CRITICAL**: Replace all `REPLACE_WITH_*` values in `production.env`:

```bash
# Generate secure passwords
openssl rand -base64 32

# Generate encryption keys
openssl rand -hex 32

# Create htpasswd hashes
htpasswd -nb username password
```

**Required Secure Values**:
- `TRAEFIK_DASHBOARD_PASSWORD` - Traefik dashboard password
- `GRAFANA_ADMIN_PASSWORD` - Grafana admin password
- `POSTGRES_PASSWORD` - Database password
- `REDIS_PASSWORD` - Redis password
- `MINIO_ROOT_PASSWORD` - MinIO admin password
- `BACKUP_ENCRYPTION_KEY` - Backup encryption key
- `JWT_SECRET` - JWT signing secret
- `SESSION_SECRET` - Session encryption secret

### SSH Key Setup

1. **Generate SSH Key** (if needed):
   ```bash
   ssh-keygen -t ed25519 -f ~/.ssh/cloudya_deploy -C "cloudya-deployment"
   ```

2. **Add Public Key to Server**:
   ```bash
   ssh-copy-id -i ~/.ssh/cloudya_deploy.pub root@cloudya.net
   ```

3. **Test Connection**:
   ```bash
   ssh -i ~/.ssh/cloudya_deploy root@cloudya.net
   ```

### SSL Certificates

The system uses Let's Encrypt for automatic SSL certificate management. Certificates are automatically obtained and renewed for:
- `cloudya.net`
- `vault.cloudya.net`
- `nomad.cloudya.net`
- `traefik.cloudya.net`
- `grafana.cloudya.net`

## 🔍 Monitoring and Alerting

### Available Dashboards

**Production URLs**:
- Grafana: https://grafana.cloudya.net
- Prometheus: https://prometheus.cloudya.net (admin/admin)
- Traefik: https://traefik.cloudya.net (admin/password)

**Local URLs**:
- Grafana: http://localhost:3000 (admin/admin)
- Prometheus: http://localhost:9090
- Traefik: http://localhost:8080

### Key Metrics Monitored

- **System**: CPU, memory, disk usage
- **Services**: Vault, Nomad, Traefik health and performance
- **Network**: Response times, error rates, SSL certificate expiry
- **Applications**: Request rates, error rates, latency

### Alert Categories

- **Critical**: Service down, security breach, certificate expiry < 7 days
- **Warning**: High resource usage (>80%), increased error rates
- **Info**: Deployments, backup completion, maintenance events

## 💾 Backup and Recovery

### Automatic Backups

- **Full Backup**: Weekly (Sundays at 1 AM)
- **Incremental Backup**: Daily (1 AM)
- **Configuration Backup**: On changes

### Manual Backup Operations

```bash
# Create full backup
./scripts/backup-restore.sh backup --type full --verbose

# List available backups
./scripts/backup-restore.sh list

# Verify backup integrity
./scripts/backup-restore.sh verify backup-20241225-123456

# Clean up old backups
./scripts/backup-restore.sh cleanup
```

### What's Backed Up

- Vault data and configuration
- Nomad data and job definitions
- Consul data and configuration
- Traefik certificates and configuration
- Docker volumes and containers
- System configuration files
- SSL certificates and keys
- Application data and logs

## 🚨 Troubleshooting

### Common Issues

1. **Service Won't Start**:
   ```bash
   # Check service status
   systemctl status cloudya-vault
   
   # View logs
   journalctl -u cloudya-vault -f
   
   # Check configuration
   vault server -config=/opt/cloudya-data/vault/config/vault.hcl -test
   ```

2. **SSL Certificate Issues**:
   ```bash
   # Check certificate status
   curl -I https://vault.cloudya.net
   
   # Force certificate renewal
   docker exec cloudya-traefik traefik certificatesResolvers.letsencrypt.acme.caServer=https://acme-v02.api.letsencrypt.org/directory
   ```

3. **Backup Failures**:
   ```bash
   # Check backup logs
   tail -f /var/log/cloudya/backup.log
   
   # Verify backup system
   ./scripts/backup-restore.sh status
   
   # Test backup manually
   ./scripts/backup-restore.sh backup --dry-run --verbose
   ```

### Log Locations

- **System Logs**: `/var/log/cloudya/`
- **Service Logs**: `journalctl -u <service-name>`
- **Docker Logs**: `docker logs <container-name>`
- **Backup Logs**: `/var/log/cloudya/backup.log`

### Health Checks

```bash
# Check all services
make status

# Individual service checks
curl https://vault.cloudya.net/v1/sys/health
curl https://nomad.cloudya.net/v1/status/leader
curl https://traefik.cloudya.net/ping
```

## 🔄 Updates and Maintenance

### Regular Maintenance

**Daily** (automated):
- Security updates installation
- Backup verification
- Service health monitoring

**Weekly** (manual):
- Review monitoring dashboards
- Check backup integrity
- Review security logs

**Monthly** (manual):
- Full system backup test
- Security configuration review
- Performance optimization review

### Update Procedures

1. **Test in Local Environment**:
   ```bash
   # Update local configs
   docker-compose -f docker-compose.local.yml pull
   docker-compose -f docker-compose.local.yml up -d
   ```

2. **Create Backup**:
   ```bash
   ./scripts/backup-restore.sh backup --type full
   ```

3. **Deploy Updates**:
   ```bash
   ./scripts/remote-deploy.sh --components <component> --verbose
   ```

4. **Verify Deployment**:
   ```bash
   make status
   # Check monitoring dashboards
   ```

## 📚 Additional Resources

- [Deployment Architecture](docs/DEPLOYMENT_ARCHITECTURE.md) - Detailed architecture documentation
- [HashiCorp Vault](https://www.vaultproject.io/) - Secret management
- [HashiCorp Nomad](https://www.nomadproject.io/) - Workload orchestration
- [Traefik](https://traefik.io/) - Reverse proxy and load balancer
- [Prometheus](https://prometheus.io/) - Monitoring and alerting
- [Grafana](https://grafana.com/) - Visualization and dashboards

## 🤝 Contributing

1. Test changes in local environment first
2. Ensure all scripts are idempotent
3. Update documentation for any changes
4. Test backup and recovery procedures
5. Verify security configurations

## 📄 License

This infrastructure code is proprietary to Cloudya. All rights reserved.

## 🆘 Support

For infrastructure support and questions:
- Check troubleshooting section above
- Review logs in `/var/log/cloudya/`
- Check monitoring dashboards for system health
- Create backup before making changes

---

**⚠️ IMPORTANT SECURITY NOTES**:
- Never commit production.env with real secrets to version control
- Always test deployments in local environment first
- Keep SSH keys secure and rotate regularly
- Monitor security alerts and apply updates promptly
- Test backup and recovery procedures regularly