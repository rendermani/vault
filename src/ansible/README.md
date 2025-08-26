# Ansible Infrastructure Bootstrap - Phase 1

This Ansible configuration provides complete infrastructure bootstrap for HashiCorp Vault, Consul, and Nomad stack with security hardening.

## Quick Start

1. Update inventory with your server details:
   ```bash
   vi inventory/production
   ```

2. Update server IP and SSH key path:
   ```ini
   [vault_servers]
   vault-prod-01 ansible_host=YOUR_SERVER_IP ansible_user=ubuntu
   
   [all:vars]
   ansible_ssh_private_key_file=~/.ssh/your-key.pem
   ```

3. Run the complete bootstrap:
   ```bash
   ansible-playbook site.yml
   ```

## What Gets Installed

### System Hardening (`playbooks/system-hardening.yml`)
- Security updates and base packages
- SSH hardening (no root login, key-based auth only)
- Fail2ban for intrusion prevention
- NTP time synchronization
- System security parameters

### Firewall (`playbooks/firewall.yml`)
- UFW configured with minimal ports:
  - Port 22 (SSH)
  - Port 80 (HTTP)
  - Port 443 (HTTPS)
- Localhost traffic allowed for service communication

### Docker (`playbooks/docker.yml`)
- Docker CE with security configuration
- Docker Compose
- Users added to docker group
- Logging limits and daemon optimization

### Consul (`playbooks/consul.yml`)
- Single-node Consul server
- Localhost-only binding for security
- UI enabled on 127.0.0.1:8500
- Service discovery and Connect enabled
- Encryption key auto-generated

### Nomad (`playbooks/nomad.yml`)
- Nomad server and client on same node
- Consul integration for service discovery
- Docker plugin enabled with security limits
- UI enabled on 127.0.0.1:4646
- **NO vault{} block** (Phase 2 requirement)

## Directory Structure

```
src/ansible/
├── ansible.cfg          # Ansible configuration
├── site.yml            # Main orchestration playbook
├── inventory/
│   └── production      # Production server inventory
├── group_vars/
│   └── all.yml         # Global variables
├── playbooks/          # Individual component playbooks
│   ├── system-hardening.yml
│   ├── firewall.yml
│   ├── docker.yml
│   ├── consul.yml
│   └── nomad.yml
└── templates/
    └── ntp.conf.j2     # NTP configuration template
```

## Post-Installation Access

- **Consul UI**: http://YOUR_SERVER_IP:8500
- **Nomad UI**: http://YOUR_SERVER_IP:4646

## Security Features

- Minimal attack surface (only ports 22, 80, 443 open)
- Service hardening with dedicated users
- No privileged Docker containers
- Encrypted Consul communication
- SSH key-based authentication only
- Automated security updates
- Fail2ban intrusion prevention

## Next Steps (Phase 2)

After successful bootstrap:
1. Initialize and unseal Vault
2. Configure Vault integration with Nomad
3. Enable Nomad vault{} block
4. Deploy Traefik load balancer

## Troubleshooting

Check service status:
```bash
ansible all -m systemd -a "name=consul state=started"
ansible all -m systemd -a "name=nomad state=started" 
ansible all -m systemd -a "name=docker state=started"
```

View logs:
```bash
ansible all -m command -a "journalctl -u consul --no-pager -n 50"
ansible all -m command -a "journalctl -u nomad --no-pager -n 50"
```

## Variables

Key variables in `group_vars/all.yml`:
- `consul_version`: Consul version to install
- `nomad_version`: Nomad version to install  
- `docker_version`: Docker version to install
- `timezone`: System timezone
- `consul_datacenter`: Consul datacenter name
- `nomad_datacenter`: Nomad datacenter name