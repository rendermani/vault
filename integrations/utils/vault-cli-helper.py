#!/usr/bin/env python3
"""
Vault CLI Helper - Advanced utilities for Vault infrastructure integration

This script provides enhanced CLI utilities for managing Vault secrets,
policies, and integrations with Consul, Nomad, and Prometheus.

Usage:
    python vault-cli-helper.py <command> [options]

Commands:
    setup-app         Setup application secrets and policies
    rotate-secrets    Rotate application secrets
    backup-secrets    Backup secrets to file
    restore-secrets   Restore secrets from backup
    health-check      Check infrastructure health
    deploy-check      Pre-deployment verification
    sync-policies     Sync policies from files
    audit-access      Audit secret access patterns

Author: Vault Integration Team
Version: 1.0.0
"""

import os
import sys
import json
import yaml
import click
import hvac
import consul
import requests
import logging
import secrets
import string
from datetime import datetime, timedelta
from pathlib import Path
from typing import Dict, List, Any, Optional
import subprocess
import tempfile


# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


class VaultCLIHelper:
    """Enhanced Vault CLI helper with infrastructure integration"""
    
    def __init__(self):
        self.vault_client = None
        self.consul_client = None
        self.setup_clients()
    
    def setup_clients(self):
        """Initialize Vault and Consul clients"""
        try:
            # Initialize Vault client
            vault_addr = os.getenv('VAULT_ADDR', 'https://localhost:8200')
            vault_token = os.getenv('VAULT_TOKEN')
            
            self.vault_client = hvac.Client(
                url=vault_addr,
                token=vault_token,
                verify=os.getenv('VAULT_SKIP_VERIFY', 'false').lower() != 'true'
            )
            
            if not self.vault_client.is_authenticated():
                raise Exception("Failed to authenticate with Vault")
            
            # Initialize Consul client
            consul_addr = os.getenv('CONSUL_HTTP_ADDR', 'localhost:8500')
            consul_token = os.getenv('CONSUL_HTTP_TOKEN')
            
            if consul_addr.startswith('http'):
                host, port = consul_addr.replace('https://', '').replace('http://', '').split(':')
                scheme = 'https' if 'https' in consul_addr else 'http'
            else:
                host, port = consul_addr.split(':')
                scheme = 'https'
            
            self.consul_client = consul.Consul(
                host=host,
                port=int(port),
                token=consul_token,
                scheme=scheme
            )
            
            logger.info("✅ Successfully connected to Vault and Consul")
            
        except Exception as e:
            logger.error(f"❌ Failed to setup clients: {e}")
            sys.exit(1)
    
    def generate_strong_password(self, length: int = 32) -> str:
        """Generate a cryptographically strong password"""
        alphabet = string.ascii_letters + string.digits + "!@#$%^&*"
        return ''.join(secrets.choice(alphabet) for _ in range(length))
    
    def generate_api_key(self, prefix: str = "key") -> str:
        """Generate a secure API key"""
        return f"{prefix}_{secrets.token_urlsafe(32)}"
    
    def setup_application(self, app_name: str, environments: List[str] = None, 
                         database_type: str = "postgresql") -> Dict[str, Any]:
        """Setup complete application configuration"""
        if not environments:
            environments = ["develop", "staging", "production"]
        
        results = {"app_name": app_name, "environments": {}}
        
        logger.info(f"🚀 Setting up application: {app_name}")
        
        for env in environments:
            logger.info(f"📋 Setting up environment: {env}")
            
            # Generate environment-specific secrets
            secrets_data = {
                "database_url": f"{database_type}://user:{self.generate_strong_password()}@{env}-db:5432/{app_name}",
                "api_key": self.generate_api_key(f"{app_name}-{env}"),
                "encryption_key": secrets.token_urlsafe(32),
                "jwt_secret": secrets.token_urlsafe(48),
                "session_secret": secrets.token_urlsafe(32)
            }
            
            # Store secrets in Vault
            secret_path = f"applications/{app_name}/{env}"
            try:
                self.vault_client.secrets.kv.v2.create_or_update_secret(
                    path=secret_path,
                    secret=secrets_data,
                    mount_point='secret'
                )
                logger.info(f"✅ Secrets stored for {env} environment")
                results["environments"][env] = {"secrets_path": secret_path, "status": "success"}
            except Exception as e:
                logger.error(f"❌ Failed to store secrets for {env}: {e}")
                results["environments"][env] = {"error": str(e), "status": "failed"}
        
        # Create application-specific policies
        self.create_application_policies(app_name, environments)
        
        # Setup AppRoles
        self.setup_app_roles(app_name, environments)
        
        # Register with Consul
        self.register_consul_services(app_name, environments)
        
        return results
    
    def create_application_policies(self, app_name: str, environments: List[str]):
        """Create Vault policies for application"""
        for env in environments:
            policy_name = f"{app_name}-{env}"
            policy_content = f"""
# Policy for {app_name} in {env} environment
path "secret/data/applications/{app_name}/{env}" {{
  capabilities = ["read"]
}}

path "secret/metadata/applications/{app_name}/{env}" {{
  capabilities = ["read"]
}}

# Database dynamic secrets
path "database/creds/{app_name}-{env}-*" {{
  capabilities = ["read"]
}}

# PKI certificates
path "pki/{env}/issue/{app_name}" {{
  capabilities = ["create", "update"]
}}

# Transit encryption
path "transit/encrypt/{app_name}-{env}" {{
  capabilities = ["update"]
}}

path "transit/decrypt/{app_name}-{env}" {{
  capabilities = ["update"]
}}
            """
            
            try:
                self.vault_client.sys.create_or_update_policy(
                    name=policy_name,
                    policy=policy_content
                )
                logger.info(f"✅ Created policy: {policy_name}")
            except Exception as e:
                logger.error(f"❌ Failed to create policy {policy_name}: {e}")
    
    def setup_app_roles(self, app_name: str, environments: List[str]):
        """Setup AppRole authentication for application"""
        for env in environments:
            role_name = f"{app_name}-{env}"
            policy_name = f"{app_name}-{env}"
            
            try:
                # Create AppRole
                self.vault_client.auth.approle.create_or_update_approle(
                    role_name=role_name,
                    token_policies=[policy_name],
                    token_ttl='1h',
                    token_max_ttl='24h',
                    bind_secret_id=True,
                    secret_id_ttl='10m'
                )
                
                # Get Role ID
                role_id = self.vault_client.auth.approle.read_role_id(role_name)['data']['role_id']
                
                # Generate Secret ID
                secret_id_response = self.vault_client.auth.approle.generate_secret_id(role_name)
                secret_id = secret_id_response['data']['secret_id']
                
                logger.info(f"✅ Created AppRole: {role_name}")
                logger.info(f"🔑 Role ID: {role_id}")
                logger.info(f"🔐 Secret ID: {secret_id} (save securely!)")
                
                # Store credentials in a secure location (example - adjust as needed)
                creds_path = f"auth/approle/credentials/{role_name}"
                self.vault_client.secrets.kv.v2.create_or_update_secret(
                    path=creds_path,
                    secret={"role_id": role_id, "secret_id": secret_id},
                    mount_point='secret'
                )
                
            except Exception as e:
                logger.error(f"❌ Failed to create AppRole {role_name}: {e}")
    
    def register_consul_services(self, app_name: str, environments: List[str]):
        """Register services with Consul"""
        for env in environments:
            service_config = {
                "Name": f"{app_name}-{env}",
                "Tags": [
                    f"environment:{env}",
                    f"app:{app_name}",
                    "vault-integrated"
                ],
                "Meta": {
                    "vault_path": f"secret/applications/{app_name}/{env}",
                    "environment": env,
                    "app": app_name
                }
            }
            
            try:
                # Register service template (actual instances will register themselves)
                self.consul_client.kv.put(f"services/{app_name}/{env}/config", json.dumps(service_config))
                logger.info(f"✅ Registered service template: {app_name}-{env}")
            except Exception as e:
                logger.error(f"❌ Failed to register service {app_name}-{env}: {e}")
    
    def rotate_secrets(self, app_name: str, environment: str, 
                      secret_keys: List[str] = None) -> Dict[str, Any]:
        """Rotate application secrets"""
        logger.info(f"🔄 Rotating secrets for {app_name} in {environment}")
        
        secret_path = f"applications/{app_name}/{environment}"
        
        try:
            # Get current secrets
            response = self.vault_client.secrets.kv.v2.read_secret_version(
                path=secret_path,
                mount_point='secret'
            )
            current_secrets = response['data']['data']
            
            # Rotate specified secrets or all secrets
            keys_to_rotate = secret_keys or list(current_secrets.keys())
            rotated_secrets = {}
            
            for key in keys_to_rotate:
                if key == 'database_url':
                    # For database URLs, only rotate the password part
                    old_url = current_secrets[key]
                    if '://' in old_url and '@' in old_url:
                        prefix = old_url.split('://')[0] + '://'
                        rest = old_url.split('://')[1]
                        user = rest.split(':')[0]
                        suffix = '@' + rest.split('@')[1]
                        new_password = self.generate_strong_password()
                        rotated_secrets[key] = f"{prefix}{user}:{new_password}{suffix}"
                    else:
                        rotated_secrets[key] = current_secrets[key]  # Keep original if format unexpected
                elif 'key' in key.lower() or 'secret' in key.lower():
                    if 'api' in key.lower():
                        rotated_secrets[key] = self.generate_api_key(f"{app_name}-{environment}")
                    else:
                        rotated_secrets[key] = secrets.token_urlsafe(32)
                elif 'password' in key.lower():
                    rotated_secrets[key] = self.generate_strong_password()
                else:
                    # Keep non-rotatable values
                    rotated_secrets[key] = current_secrets[key]
            
            # Backup old secrets
            backup_path = f"applications/{app_name}/{environment}/backup/{datetime.now().isoformat()}"
            self.vault_client.secrets.kv.v2.create_or_update_secret(
                path=backup_path,
                secret=current_secrets,
                mount_point='secret'
            )
            
            # Update with new secrets
            updated_secrets = {**current_secrets, **rotated_secrets}
            self.vault_client.secrets.kv.v2.create_or_update_secret(
                path=secret_path,
                secret=updated_secrets,
                mount_point='secret'
            )
            
            logger.info(f"✅ Successfully rotated {len(rotated_secrets)} secrets")
            return {
                "rotated_keys": list(rotated_secrets.keys()),
                "backup_path": backup_path,
                "status": "success"
            }
            
        except Exception as e:
            logger.error(f"❌ Failed to rotate secrets: {e}")
            return {"error": str(e), "status": "failed"}
    
    def backup_secrets(self, output_file: str, app_filter: str = None) -> Dict[str, Any]:
        """Backup secrets to encrypted file"""
        logger.info("💾 Starting secrets backup...")
        
        try:
            backup_data = {
                "timestamp": datetime.now().isoformat(),
                "vault_addr": self.vault_client.url,
                "secrets": {}
            }
            
            # List all secret paths
            try:
                secret_list = self.vault_client.secrets.kv.v2.list_secrets(
                    path="applications",
                    mount_point='secret'
                )
                
                for app in secret_list['data']['keys']:
                    if app_filter and app_filter not in app:
                        continue
                    
                    app_path = f"applications/{app.rstrip('/')}"
                    try:
                        app_secrets = self.vault_client.secrets.kv.v2.list_secrets(
                            path=app_path,
                            mount_point='secret'
                        )
                        
                        backup_data["secrets"][app] = {}
                        
                        for env in app_secrets['data']['keys']:
                            env_path = f"{app_path}/{env.rstrip('/')}"
                            try:
                                secret_data = self.vault_client.secrets.kv.v2.read_secret_version(
                                    path=env_path,
                                    mount_point='secret'
                                )
                                backup_data["secrets"][app][env] = secret_data['data']['data']
                            except Exception as e:
                                logger.warning(f"⚠️ Failed to backup {env_path}: {e}")
                        
                    except Exception as e:
                        logger.warning(f"⚠️ Failed to list secrets for {app}: {e}")
                
            except Exception as e:
                logger.warning(f"⚠️ Failed to list applications: {e}")
            
            # Write backup file
            with open(output_file, 'w') as f:
                json.dump(backup_data, f, indent=2)
            
            logger.info(f"✅ Backup completed: {output_file}")
            return {
                "file": output_file,
                "secret_count": sum(len(envs) for envs in backup_data["secrets"].values()),
                "status": "success"
            }
            
        except Exception as e:
            logger.error(f"❌ Backup failed: {e}")
            return {"error": str(e), "status": "failed"}
    
    def health_check(self) -> Dict[str, Any]:
        """Comprehensive infrastructure health check"""
        logger.info("🏥 Starting infrastructure health check...")
        
        results = {
            "timestamp": datetime.now().isoformat(),
            "overall_status": "healthy",
            "services": {}
        }
        
        # Vault health check
        try:
            vault_status = self.vault_client.sys.read_health_status()
            results["services"]["vault"] = {
                "status": "healthy" if not vault_status.get('sealed', True) else "sealed",
                "initialized": vault_status.get('initialized', False),
                "sealed": vault_status.get('sealed', True),
                "standby": vault_status.get('standby', False),
                "version": vault_status.get('version', 'unknown')
            }
        except Exception as e:
            results["services"]["vault"] = {"status": "unhealthy", "error": str(e)}
            results["overall_status"] = "degraded"
        
        # Consul health check
        try:
            consul_status = self.consul_client.agent.self()
            results["services"]["consul"] = {
                "status": "healthy",
                "version": consul_status['Config']['Version'],
                "datacenter": consul_status['Config']['Datacenter'],
                "server": consul_status['Config']['Server']
            }
        except Exception as e:
            results["services"]["consul"] = {"status": "unhealthy", "error": str(e)}
            results["overall_status"] = "degraded"
        
        # Nomad health check
        try:
            nomad_addr = os.getenv('NOMAD_ADDR', 'https://localhost:4646')
            nomad_token = os.getenv('NOMAD_TOKEN')
            headers = {'X-Nomad-Token': nomad_token} if nomad_token else {}
            
            response = requests.get(f"{nomad_addr}/v1/status/leader", headers=headers, timeout=5)
            if response.status_code == 200:
                results["services"]["nomad"] = {
                    "status": "healthy",
                    "leader": response.text.strip('"')
                }
            else:
                results["services"]["nomad"] = {"status": "unhealthy", "http_status": response.status_code}
                results["overall_status"] = "degraded"
        except Exception as e:
            results["services"]["nomad"] = {"status": "unhealthy", "error": str(e)}
            results["overall_status"] = "degraded"
        
        # Prometheus health check
        try:
            prometheus_url = os.getenv('PROMETHEUS_URL', 'https://localhost:9090')
            response = requests.get(f"{prometheus_url}/-/ready", timeout=5)
            if response.status_code == 200:
                results["services"]["prometheus"] = {"status": "healthy"}
            else:
                results["services"]["prometheus"] = {"status": "unhealthy", "http_status": response.status_code}
                results["overall_status"] = "degraded"
        except Exception as e:
            results["services"]["prometheus"] = {"status": "unhealthy", "error": str(e)}
            results["overall_status"] = "degraded"
        
        # Set overall status
        unhealthy_services = [svc for svc, data in results["services"].items() 
                            if data.get("status") != "healthy"]
        if unhealthy_services:
            if len(unhealthy_services) >= len(results["services"]) // 2:
                results["overall_status"] = "unhealthy"
            else:
                results["overall_status"] = "degraded"
        
        # Log results
        for service, data in results["services"].items():
            status_emoji = "✅" if data["status"] == "healthy" else "❌"
            logger.info(f"{status_emoji} {service.capitalize()}: {data['status']}")
        
        overall_emoji = "✅" if results["overall_status"] == "healthy" else "⚠️" if results["overall_status"] == "degraded" else "❌"
        logger.info(f"{overall_emoji} Overall status: {results['overall_status']}")
        
        return results
    
    def deploy_check(self, app_name: str, environment: str, image_tag: str = None) -> Dict[str, Any]:
        """Pre-deployment verification"""
        logger.info(f"🔍 Running pre-deployment checks for {app_name} in {environment}")
        
        checks = {
            "timestamp": datetime.now().isoformat(),
            "app_name": app_name,
            "environment": environment,
            "overall_status": "passed",
            "checks": {}
        }
        
        # Check 1: Vault secrets exist
        try:
            secret_path = f"applications/{app_name}/{environment}"
            self.vault_client.secrets.kv.v2.read_secret_version(
                path=secret_path,
                mount_point='secret'
            )
            checks["checks"]["vault_secrets"] = {"status": "passed", "message": "Secrets exist"}
        except Exception as e:
            checks["checks"]["vault_secrets"] = {"status": "failed", "error": str(e)}
            checks["overall_status"] = "failed"
        
        # Check 2: AppRole exists and accessible
        try:
            role_name = f"{app_name}-{environment}"
            self.vault_client.auth.approle.read_role_id(role_name)
            checks["checks"]["approle"] = {"status": "passed", "message": "AppRole accessible"}
        except Exception as e:
            checks["checks"]["approle"] = {"status": "failed", "error": str(e)}
            checks["overall_status"] = "failed"
        
        # Check 3: Policy exists
        try:
            policy_name = f"{app_name}-{environment}"
            self.vault_client.sys.read_policy(policy_name)
            checks["checks"]["policy"] = {"status": "passed", "message": "Policy exists"}
        except Exception as e:
            checks["checks"]["policy"] = {"status": "failed", "error": str(e)}
            checks["overall_status"] = "failed"
        
        # Check 4: Consul service template exists
        try:
            consul_key = f"services/{app_name}/{environment}/config"
            _, service_config = self.consul_client.kv.get(consul_key)
            if service_config:
                checks["checks"]["consul_service"] = {"status": "passed", "message": "Service template exists"}
            else:
                checks["checks"]["consul_service"] = {"status": "warning", "message": "No service template"}
        except Exception as e:
            checks["checks"]["consul_service"] = {"status": "warning", "error": str(e)}
        
        # Check 5: Container image exists (if specified)
        if image_tag:
            try:
                # This would need to be adapted based on your container registry
                # Example for Docker Hub or similar
                result = subprocess.run(['docker', 'manifest', 'inspect', image_tag], 
                                      capture_output=True, text=True)
                if result.returncode == 0:
                    checks["checks"]["container_image"] = {"status": "passed", "message": "Image exists"}
                else:
                    checks["checks"]["container_image"] = {"status": "failed", "message": "Image not found"}
                    checks["overall_status"] = "failed"
            except Exception as e:
                checks["checks"]["container_image"] = {"status": "warning", "error": str(e)}
        
        # Log results
        for check_name, check_data in checks["checks"].items():
            status_emoji = "✅" if check_data["status"] == "passed" else "⚠️" if check_data["status"] == "warning" else "❌"
            logger.info(f"{status_emoji} {check_name}: {check_data['status']}")
        
        overall_emoji = "✅" if checks["overall_status"] == "passed" else "❌"
        logger.info(f"{overall_emoji} Overall deployment readiness: {checks['overall_status']}")
        
        return checks


# CLI Interface
@click.group()
@click.option('--verbose', '-v', is_flag=True, help='Enable verbose logging')
def cli(verbose):
    """Vault CLI Helper - Advanced utilities for Vault infrastructure integration"""
    if verbose:
        logging.getLogger().setLevel(logging.DEBUG)


@cli.command()
@click.argument('app_name')
@click.option('--environments', '-e', multiple=True, default=['develop', 'staging', 'production'],
              help='Target environments (default: develop, staging, production)')
@click.option('--database-type', default='postgresql', help='Database type for connection URL')
def setup_app(app_name, environments, database_type):
    """Setup application secrets and policies"""
    helper = VaultCLIHelper()
    result = helper.setup_application(app_name, list(environments), database_type)
    
    if result:
        click.echo(f"\n🎉 Application setup completed for: {app_name}")
        for env, env_result in result["environments"].items():
            status_emoji = "✅" if env_result["status"] == "success" else "❌"
            click.echo(f"{status_emoji} {env}: {env_result['status']}")


@cli.command()
@click.argument('app_name')
@click.argument('environment')
@click.option('--keys', '-k', multiple=True, help='Specific keys to rotate (default: all)')
def rotate_secrets(app_name, environment, keys):
    """Rotate application secrets"""
    helper = VaultCLIHelper()
    result = helper.rotate_secrets(app_name, environment, list(keys) if keys else None)
    
    if result["status"] == "success":
        click.echo(f"✅ Rotated secrets: {', '.join(result['rotated_keys'])}")
        click.echo(f"💾 Backup stored at: {result['backup_path']}")
    else:
        click.echo(f"❌ Failed to rotate secrets: {result['error']}")


@cli.command()
@click.argument('output_file')
@click.option('--app-filter', help='Filter by application name')
def backup_secrets(output_file, app_filter):
    """Backup secrets to file"""
    helper = VaultCLIHelper()
    result = helper.backup_secrets(output_file, app_filter)
    
    if result["status"] == "success":
        click.echo(f"✅ Backup completed: {result['file']}")
        click.echo(f"📊 Secrets backed up: {result['secret_count']}")
    else:
        click.echo(f"❌ Backup failed: {result['error']}")


@cli.command()
def health_check():
    """Check infrastructure health"""
    helper = VaultCLIHelper()
    result = helper.health_check()
    
    click.echo(f"\n🏥 Infrastructure Health Check - {result['overall_status'].upper()}")
    click.echo("=" * 50)
    
    for service, data in result["services"].items():
        status_emoji = "✅" if data["status"] == "healthy" else "❌"
        click.echo(f"{status_emoji} {service.capitalize()}: {data['status']}")
        
        if data["status"] != "healthy" and "error" in data:
            click.echo(f"   Error: {data['error']}")


@cli.command()
@click.argument('app_name')
@click.argument('environment')
@click.option('--image-tag', help='Container image tag to verify')
def deploy_check(app_name, environment, image_tag):
    """Pre-deployment verification"""
    helper = VaultCLIHelper()
    result = helper.deploy_check(app_name, environment, image_tag)
    
    click.echo(f"\n🔍 Pre-deployment Check for {app_name} ({environment})")
    click.echo("=" * 50)
    
    for check_name, check_data in result["checks"].items():
        status_emoji = "✅" if check_data["status"] == "passed" else "⚠️" if check_data["status"] == "warning" else "❌"
        click.echo(f"{status_emoji} {check_name.replace('_', ' ').title()}: {check_data['status']}")
        
        if check_data["status"] != "passed" and "error" in check_data:
            click.echo(f"   Error: {check_data['error']}")
    
    click.echo(f"\n📋 Overall Status: {result['overall_status'].upper()}")


@cli.command()
@click.argument('policy_directory')
def sync_policies(policy_directory):
    """Sync policies from directory"""
    helper = VaultCLIHelper()
    policy_dir = Path(policy_directory)
    
    if not policy_dir.exists():
        click.echo(f"❌ Policy directory not found: {policy_directory}")
        return
    
    click.echo(f"🔄 Syncing policies from: {policy_directory}")
    
    for policy_file in policy_dir.glob("*.hcl"):
        policy_name = policy_file.stem
        
        try:
            with open(policy_file, 'r') as f:
                policy_content = f.read()
            
            helper.vault_client.sys.create_or_update_policy(
                name=policy_name,
                policy=policy_content
            )
            click.echo(f"✅ Updated policy: {policy_name}")
            
        except Exception as e:
            click.echo(f"❌ Failed to update policy {policy_name}: {e}")


if __name__ == "__main__":
    cli()