#!/usr/bin/env python3
"""
Vault Integration Helper
Advanced Python utility for secure secret management and Vault operations
"""

import os
import sys
import json
import logging
import argparse
import requests
import hashlib
import base64
import time
import subprocess
from typing import Dict, List, Optional, Any
from datetime import datetime, timedelta
from urllib.parse import urljoin
import hvac
import yaml

class VaultIntegrationHelper:
    """
    Comprehensive Vault integration utility for CloudYa infrastructure
    """
    
    def __init__(self, vault_addr: str = None, token: str = None):
        """Initialize Vault client with configuration"""
        self.vault_addr = vault_addr or os.getenv('VAULT_ADDR', 'https://vault.cloudya.net:8200')
        self.token = token or os.getenv('VAULT_TOKEN')
        self.namespace = os.getenv('VAULT_NAMESPACE')
        
        # Initialize logging
        logging.basicConfig(
            level=logging.INFO,
            format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
        )
        self.logger = logging.getLogger('VaultIntegrationHelper')
        
        # Initialize Vault client
        try:
            self.client = hvac.Client(
                url=self.vault_addr,
                token=self.token,
                namespace=self.namespace
            )
            
            if not self.client.is_authenticated():
                raise Exception("Vault authentication failed")
                
            self.logger.info(f"Successfully connected to Vault at {self.vault_addr}")
            
        except Exception as e:
            self.logger.error(f"Failed to initialize Vault client: {e}")
            sys.exit(1)
    
    def setup_secret_engines(self) -> bool:
        """Setup and configure Vault secret engines"""
        self.logger.info("Setting up Vault secret engines...")
        
        engines = {
            'cloudya-secrets': {
                'type': 'kv-v2',
                'description': 'CloudYa application secrets'
            },
            'database': {
                'type': 'database',
                'description': 'Database credential management'
            },
            'pki': {
                'type': 'pki',
                'description': 'Certificate management',
                'max_lease_ttl': '87600h'
            },
            'transit': {
                'type': 'transit',
                'description': 'Encryption as a service'
            }
        }
        
        try:
            for path, config in engines.items():
                if f"{path}/" not in self.client.sys.list_mounted_secrets_engines():
                    self.client.sys.enable_secrets_engine(
                        backend_type=config['type'],
                        path=path,
                        description=config.get('description', ''),
                        max_lease_ttl=config.get('max_lease_ttl')
                    )
                    self.logger.info(f"Enabled secret engine: {path}")
                else:
                    self.logger.info(f"Secret engine already exists: {path}")
            
            return True
            
        except Exception as e:
            self.logger.error(f"Failed to setup secret engines: {e}")
            return False
    
    def create_policies(self) -> bool:
        """Create Vault policies for different access levels"""
        self.logger.info("Creating Vault policies...")
        
        policies = {
            'cloudya-app': '''
# Application policy for CloudYa services
path "cloudya-secrets/data/traefik/*" {
  capabilities = ["read"]
}

path "cloudya-secrets/data/grafana/*" {
  capabilities = ["read"]
}

path "cloudya-secrets/data/consul/*" {
  capabilities = ["read"]
}

path "cloudya-secrets/data/nomad/*" {
  capabilities = ["read"]
}

path "database/creds/cloudya-db" {
  capabilities = ["read"]
}

path "transit/encrypt/cloudya-key" {
  capabilities = ["update"]
}

path "transit/decrypt/cloudya-key" {
  capabilities = ["update"]
}

path "pki/issue/cloudya-role" {
  capabilities = ["update"]
}
''',
            'cloudya-admin': '''
# Admin policy for CloudYa infrastructure
path "cloudya-secrets/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

path "database/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

path "pki/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

path "transit/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

path "sys/policies/acl/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

path "auth/approle/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}
'''
        }
        
        try:
            for policy_name, policy_content in policies.items():
                self.client.sys.create_or_update_policy(
                    name=policy_name,
                    policy=policy_content
                )
                self.logger.info(f"Created policy: {policy_name}")
            
            return True
            
        except Exception as e:
            self.logger.error(f"Failed to create policies: {e}")
            return False
    
    def setup_approle_auth(self) -> Dict[str, str]:
        """Setup AppRole authentication method"""
        self.logger.info("Setting up AppRole authentication...")
        
        try:
            # Enable AppRole auth method
            auth_methods = self.client.sys.list_auth_methods()
            if 'approle/' not in auth_methods:
                self.client.sys.enable_auth_method('approle')
                self.logger.info("Enabled AppRole authentication method")
            
            # Create role for applications
            self.client.auth.approle.create_or_update_approle(
                role_name='cloudya-app',
                token_policies=['cloudya-app'],
                token_ttl='1h',
                token_max_ttl='4h',
                bind_secret_id=True
            )
            
            # Get role ID
            role_id_response = self.client.auth.approle.read_role_id('cloudya-app')
            role_id = role_id_response['data']['role_id']
            
            # Generate secret ID
            secret_id_response = self.client.auth.approle.generate_secret_id('cloudya-app')
            secret_id = secret_id_response['data']['secret_id']
            
            self.logger.info("AppRole authentication setup completed")
            
            return {
                'role_id': role_id,
                'secret_id': secret_id
            }
            
        except Exception as e:
            self.logger.error(f"Failed to setup AppRole auth: {e}")
            return {}
    
    def store_service_secrets(self) -> bool:
        """Store service secrets in Vault"""
        self.logger.info("Storing service secrets in Vault...")
        
        # Generate secure passwords
        secrets = {
            'traefik/auth': {
                'admin_username': 'admin',
                'admin_password': self._generate_password(24),
                'api_key': self._generate_password(32)
            },
            'grafana/auth': {
                'admin_username': 'admin',
                'admin_password': self._generate_password(24),
                'secret_key': self._generate_password(32)
            },
            'consul/config': {
                'encrypt_key': self._generate_consul_key(),
                'master_token': self._generate_password(32)
            },
            'nomad/config': {
                'encrypt_key': self._generate_password(32),
                'master_token': self._generate_password(32)
            },
            'database/config': {
                'host': 'postgres.cloudya.net',
                'port': '5432',
                'database': 'cloudya',
                'ssl_mode': 'require'
            }
        }
        
        try:
            for path, secret_data in secrets.items():
                self.client.secrets.kv.v2.create_or_update_secret(
                    path=path,
                    mount_point='cloudya-secrets',
                    secret=secret_data
                )
                self.logger.info(f"Stored secrets at cloudya-secrets/{path}")
            
            # Store password hashes for basic auth
            traefik_password = secrets['traefik/auth']['admin_password']
            password_hash = self._generate_bcrypt_hash(traefik_password)
            
            self.client.secrets.kv.v2.create_or_update_secret(
                path='traefik/auth-hash',
                mount_point='cloudya-secrets',
                secret={'admin_hash': password_hash}
            )
            
            return True
            
        except Exception as e:
            self.logger.error(f"Failed to store service secrets: {e}")
            return False
    
    def setup_pki_infrastructure(self) -> bool:
        """Setup PKI infrastructure for certificate management"""
        self.logger.info("Setting up PKI infrastructure...")
        
        try:
            # Generate root CA
            root_ca = self.client.secrets.pki.generate_root(
                type='internal',
                common_name='CloudYa Internal CA',
                ttl='87600h',
                mount_point='pki'
            )
            
            # Configure CA and CRL URLs
            self.client.secrets.pki.set_urls(
                issuing_certificates=f"{self.vault_addr}/v1/pki/ca",
                crl_distribution_points=f"{self.vault_addr}/v1/pki/crl",
                mount_point='pki'
            )
            
            # Create role for CloudYa services
            self.client.secrets.pki.create_or_update_role(
                name='cloudya-role',
                allowed_domains=['cloudya.net', '*.cloudya.net', 'localhost'],
                allow_subdomains=True,
                allow_localhost=True,
                max_ttl='720h',
                mount_point='pki'
            )
            
            self.logger.info("PKI infrastructure setup completed")
            return True
            
        except Exception as e:
            self.logger.error(f"Failed to setup PKI infrastructure: {e}")
            return False
    
    def create_transit_encryption_key(self) -> bool:
        """Create transit encryption key for data encryption"""
        self.logger.info("Creating transit encryption key...")
        
        try:
            self.client.secrets.transit.create_key(
                name='cloudya-key',
                mount_point='transit'
            )
            self.logger.info("Created transit encryption key: cloudya-key")
            return True
            
        except Exception as e:
            self.logger.error(f"Failed to create transit key: {e}")
            return False
    
    def generate_certificates(self, domain: str) -> Dict[str, str]:
        """Generate SSL certificates for a domain"""
        self.logger.info(f"Generating certificate for {domain}")
        
        try:
            cert_response = self.client.secrets.pki.generate_certificate(
                name='cloudya-role',
                common_name=domain,
                alt_names=[f"*.{domain}"] if not domain.startswith('*') else [],
                ttl='720h',
                mount_point='pki'
            )
            
            return {
                'certificate': cert_response['data']['certificate'],
                'private_key': cert_response['data']['private_key'],
                'ca_chain': cert_response['data']['ca_chain'][0] if cert_response['data']['ca_chain'] else '',
                'serial_number': cert_response['data']['serial_number']
            }
            
        except Exception as e:
            self.logger.error(f"Failed to generate certificate for {domain}: {e}")
            return {}
    
    def encrypt_data(self, plaintext: str, key_name: str = 'cloudya-key') -> str:
        """Encrypt data using Vault's transit engine"""
        try:
            encrypted = self.client.secrets.transit.encrypt_data(
                name=key_name,
                plaintext=base64.b64encode(plaintext.encode()).decode(),
                mount_point='transit'
            )
            return encrypted['data']['ciphertext']
            
        except Exception as e:
            self.logger.error(f"Failed to encrypt data: {e}")
            return ""
    
    def decrypt_data(self, ciphertext: str, key_name: str = 'cloudya-key') -> str:
        """Decrypt data using Vault's transit engine"""
        try:
            decrypted = self.client.secrets.transit.decrypt_data(
                name=key_name,
                ciphertext=ciphertext,
                mount_point='transit'
            )
            return base64.b64decode(decrypted['data']['plaintext']).decode()
            
        except Exception as e:
            self.logger.error(f"Failed to decrypt data: {e}")
            return ""
    
    def get_secret(self, path: str, mount_point: str = 'cloudya-secrets') -> Dict[str, Any]:
        """Retrieve secret from Vault"""
        try:
            response = self.client.secrets.kv.v2.read_secret_version(
                path=path,
                mount_point=mount_point
            )
            return response['data']['data']
            
        except Exception as e:
            self.logger.error(f"Failed to retrieve secret {path}: {e}")
            return {}
    
    def create_docker_compose_env(self, output_file: str = '.env') -> bool:
        """Create Docker Compose environment file from Vault secrets"""
        self.logger.info("Creating Docker Compose environment file...")
        
        try:
            # Retrieve secrets
            traefik_auth = self.get_secret('traefik/auth')
            grafana_auth = self.get_secret('grafana/auth')
            consul_config = self.get_secret('consul/config')
            
            # Create environment file content
            env_content = f"""# CloudYa Environment Variables
# Generated from Vault secrets on {datetime.now().isoformat()}

# Traefik Authentication
TRAEFIK_ADMIN_USER={traefik_auth.get('admin_username', 'admin')}
TRAEFIK_ADMIN_PASSWORD={traefik_auth.get('admin_password', '')}

# Grafana Authentication  
GRAFANA_ADMIN_USER={grafana_auth.get('admin_username', 'admin')}
GRAFANA_ADMIN_PASSWORD={grafana_auth.get('admin_password', '')}
GF_SECURITY_SECRET_KEY={grafana_auth.get('secret_key', '')}

# Consul Configuration
CONSUL_ENCRYPT_KEY={consul_config.get('encrypt_key', '')}

# Vault Configuration
VAULT_ADDR={self.vault_addr}

# Security Settings
VAULT_MANAGED=true
GENERATED_AT={datetime.now().isoformat()}
"""
            
            with open(output_file, 'w') as f:
                f.write(env_content)
            
            # Set restrictive permissions
            os.chmod(output_file, 0o600)
            
            self.logger.info(f"Environment file created: {output_file}")
            return True
            
        except Exception as e:
            self.logger.error(f"Failed to create environment file: {e}")
            return False
    
    def audit_secrets_usage(self) -> Dict[str, Any]:
        """Audit secret usage and access patterns"""
        self.logger.info("Auditing secrets usage...")
        
        audit_data = {
            'timestamp': datetime.now().isoformat(),
            'secret_engines': [],
            'policies': [],
            'auth_methods': [],
            'certificate_status': []
        }
        
        try:
            # List secret engines
            engines = self.client.sys.list_mounted_secrets_engines()
            for path, config in engines.items():
                audit_data['secret_engines'].append({
                    'path': path,
                    'type': config['type'],
                    'description': config.get('description', '')
                })
            
            # List policies
            policies = self.client.sys.list_policies()
            audit_data['policies'] = policies['policies']
            
            # List auth methods
            auth_methods = self.client.sys.list_auth_methods()
            for path, config in auth_methods.items():
                audit_data['auth_methods'].append({
                    'path': path,
                    'type': config['type'],
                    'description': config.get('description', '')
                })
            
            return audit_data
            
        except Exception as e:
            self.logger.error(f"Failed to audit secrets usage: {e}")
            return audit_data
    
    def health_check(self) -> Dict[str, Any]:
        """Perform comprehensive Vault health check"""
        self.logger.info("Performing Vault health check...")
        
        health_data = {
            'timestamp': datetime.now().isoformat(),
            'vault_status': {},
            'authentication': False,
            'secret_engines': {},
            'policies': {},
            'overall_health': 'unknown'
        }
        
        try:
            # Check Vault status
            health_data['vault_status'] = self.client.sys.read_health_status()
            
            # Check authentication
            health_data['authentication'] = self.client.is_authenticated()
            
            # Check secret engines
            engines = self.client.sys.list_mounted_secrets_engines()
            for path in ['cloudya-secrets/', 'database/', 'pki/', 'transit/']:
                health_data['secret_engines'][path] = path in engines
            
            # Check policies
            policies = self.client.sys.list_policies()
            for policy in ['cloudya-app', 'cloudya-admin']:
                health_data['policies'][policy] = policy in policies['policies']
            
            # Determine overall health
            if (health_data['authentication'] and 
                all(health_data['secret_engines'].values()) and 
                all(health_data['policies'].values())):
                health_data['overall_health'] = 'healthy'
            else:
                health_data['overall_health'] = 'degraded'
            
            return health_data
            
        except Exception as e:
            self.logger.error(f"Health check failed: {e}")
            health_data['overall_health'] = 'unhealthy'
            health_data['error'] = str(e)
            return health_data
    
    def _generate_password(self, length: int = 16) -> str:
        """Generate secure random password"""
        import secrets
        import string
        
        alphabet = string.ascii_letters + string.digits + "!@#$%^&*"
        return ''.join(secrets.choice(alphabet) for _ in range(length))
    
    def _generate_consul_key(self) -> str:
        """Generate Consul encryption key"""
        import secrets
        return base64.b64encode(secrets.token_bytes(32)).decode()
    
    def _generate_bcrypt_hash(self, password: str) -> str:
        """Generate bcrypt hash for password"""
        try:
            import bcrypt
            return bcrypt.hashpw(password.encode(), bcrypt.gensalt()).decode()
        except ImportError:
            # Fallback to htpasswd if bcrypt not available
            try:
                result = subprocess.run(
                    ['htpasswd', '-nbB', '', password],
                    capture_output=True, text=True, check=True
                )
                return result.stdout.split(':')[1].strip()
            except (subprocess.CalledProcessError, FileNotFoundError):
                self.logger.warning("Neither bcrypt nor htpasswd available, using SHA-256")
                return hashlib.sha256(password.encode()).hexdigest()

def main():
    """Main CLI interface"""
    parser = argparse.ArgumentParser(description='Vault Integration Helper for CloudYa')
    parser.add_argument('--vault-addr', help='Vault server address')
    parser.add_argument('--token', help='Vault authentication token')
    
    subparsers = parser.add_subparsers(dest='command', help='Available commands')
    
    # Setup command
    setup_parser = subparsers.add_parser('setup', help='Complete Vault setup')
    
    # Individual setup commands
    subparsers.add_parser('setup-engines', help='Setup secret engines')
    subparsers.add_parser('create-policies', help='Create policies')
    subparsers.add_parser('setup-approle', help='Setup AppRole authentication')
    subparsers.add_parser('store-secrets', help='Store service secrets')
    subparsers.add_parser('setup-pki', help='Setup PKI infrastructure')
    
    # Utility commands
    subparsers.add_parser('health-check', help='Perform health check')
    subparsers.add_parser('audit', help='Audit secrets usage')
    
    # Secret management
    get_parser = subparsers.add_parser('get-secret', help='Get secret from Vault')
    get_parser.add_argument('path', help='Secret path')
    get_parser.add_argument('--mount-point', default='cloudya-secrets', help='Mount point')
    
    # Environment file generation
    env_parser = subparsers.add_parser('create-env', help='Create environment file')
    env_parser.add_argument('--output', default='.env', help='Output file')
    
    # Certificate generation
    cert_parser = subparsers.add_parser('generate-cert', help='Generate certificate')
    cert_parser.add_argument('domain', help='Domain name')
    
    args = parser.parse_args()
    
    if not args.command:
        parser.print_help()
        sys.exit(1)
    
    # Initialize Vault helper
    vault_helper = VaultIntegrationHelper(args.vault_addr, args.token)
    
    # Execute command
    if args.command == 'setup':
        print("Setting up complete Vault integration...")
        success = (
            vault_helper.setup_secret_engines() and
            vault_helper.create_policies() and
            vault_helper.setup_approle_auth() and
            vault_helper.store_service_secrets() and
            vault_helper.setup_pki_infrastructure() and
            vault_helper.create_transit_encryption_key()
        )
        if success:
            print("✅ Vault setup completed successfully!")
        else:
            print("❌ Vault setup failed!")
            sys.exit(1)
    
    elif args.command == 'setup-engines':
        if vault_helper.setup_secret_engines():
            print("✅ Secret engines setup completed!")
        else:
            sys.exit(1)
    
    elif args.command == 'create-policies':
        if vault_helper.create_policies():
            print("✅ Policies created successfully!")
        else:
            sys.exit(1)
    
    elif args.command == 'setup-approle':
        credentials = vault_helper.setup_approle_auth()
        if credentials:
            print("✅ AppRole authentication setup completed!")
            print(f"Role ID: {credentials['role_id']}")
            print(f"Secret ID: {credentials['secret_id']}")
        else:
            sys.exit(1)
    
    elif args.command == 'store-secrets':
        if vault_helper.store_service_secrets():
            print("✅ Service secrets stored successfully!")
        else:
            sys.exit(1)
    
    elif args.command == 'setup-pki':
        if vault_helper.setup_pki_infrastructure():
            print("✅ PKI infrastructure setup completed!")
        else:
            sys.exit(1)
    
    elif args.command == 'health-check':
        health = vault_helper.health_check()
        print(json.dumps(health, indent=2))
        if health['overall_health'] != 'healthy':
            sys.exit(1)
    
    elif args.command == 'audit':
        audit = vault_helper.audit_secrets_usage()
        print(json.dumps(audit, indent=2))
    
    elif args.command == 'get-secret':
        secret = vault_helper.get_secret(args.path, args.mount_point)
        if secret:
            print(json.dumps(secret, indent=2))
        else:
            sys.exit(1)
    
    elif args.command == 'create-env':
        if vault_helper.create_docker_compose_env(args.output):
            print(f"✅ Environment file created: {args.output}")
        else:
            sys.exit(1)
    
    elif args.command == 'generate-cert':
        cert = vault_helper.generate_certificates(args.domain)
        if cert:
            print(f"✅ Certificate generated for {args.domain}")
            print(json.dumps({
                'certificate': cert['certificate'][:100] + '...',
                'private_key': '[PRIVATE KEY GENERATED]',
                'serial_number': cert['serial_number']
            }, indent=2))
        else:
            sys.exit(1)

if __name__ == '__main__':
    main()