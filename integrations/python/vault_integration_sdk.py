#!/usr/bin/env python3
"""
Vault Infrastructure Integration SDK for Python

A comprehensive SDK for integrating Python applications with the Vault infrastructure
including Vault, Consul, Nomad, and Prometheus services.

Author: Vault Integration Team
Version: 1.0.0
"""

import os
import json
import time
import logging
import asyncio
import requests
import hvac
from typing import Dict, List, Optional, Any, Union
from dataclasses import dataclass
from urllib.parse import urljoin
import consul
import prometheus_client
from prometheus_client.parser import text_string_to_metric_families


# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


@dataclass
class ServiceConfig:
    """Service configuration container"""
    host: str
    port: int
    protocol: str = "https"
    token: Optional[str] = None
    ca_cert: Optional[str] = None
    verify_ssl: bool = True
    timeout: int = 30

    @property
    def url(self) -> str:
        return f"{self.protocol}://{self.host}:{self.port}"


class VaultClient:
    """Enhanced Vault client with advanced features"""
    
    def __init__(self, config: ServiceConfig):
        self.config = config
        self.client = hvac.Client(
            url=config.url,
            token=config.token,
            verify=config.ca_cert or config.verify_ssl,
            timeout=config.timeout
        )
    
    def authenticate_approle(self, role_id: str, secret_id: str) -> Dict[str, Any]:
        """Authenticate using AppRole method"""
        try:
            auth_response = self.client.auth.approle.login(
                role_id=role_id,
                secret_id=secret_id
            )
            self.client.token = auth_response['auth']['client_token']
            logger.info("Successfully authenticated with AppRole")
            return auth_response
        except Exception as e:
            logger.error(f"AppRole authentication failed: {e}")
            raise
    
    def get_secret(self, path: str, mount_point: str = "secret") -> Optional[Dict[str, Any]]:
        """Retrieve secret from Vault"""
        try:
            response = self.client.secrets.kv.v2.read_secret_version(
                path=path,
                mount_point=mount_point
            )
            return response['data']['data']
        except Exception as e:
            logger.error(f"Failed to retrieve secret from {path}: {e}")
            return None
    
    def write_secret(self, path: str, secret_data: Dict[str, Any], 
                     mount_point: str = "secret") -> bool:
        """Write secret to Vault"""
        try:
            self.client.secrets.kv.v2.create_or_update_secret(
                path=path,
                secret=secret_data,
                mount_point=mount_point
            )
            logger.info(f"Successfully wrote secret to {path}")
            return True
        except Exception as e:
            logger.error(f"Failed to write secret to {path}: {e}")
            return False
    
    def setup_database_dynamic_secrets(self, db_config: Dict[str, Any]) -> bool:
        """Configure database dynamic secrets engine"""
        try:
            # Enable database secrets engine
            self.client.sys.enable_secrets_engine(
                backend_type='database',
                path='database'
            )
            
            # Configure database connection
            self.client.secrets.database.configure(
                name=db_config['name'],
                plugin_name=db_config.get('plugin', 'mysql-database-plugin'),
                connection_url=db_config['connection_url'],
                allowed_roles=db_config.get('allowed_roles', []),
                username=db_config.get('username'),
                password=db_config.get('password')
            )
            
            logger.info(f"Database secrets engine configured for {db_config['name']}")
            return True
        except Exception as e:
            logger.error(f"Failed to setup database secrets: {e}")
            return False
    
    def get_database_credentials(self, role_name: str) -> Optional[Dict[str, str]]:
        """Generate dynamic database credentials"""
        try:
            response = self.client.secrets.database.generate_credentials(
                name=role_name
            )
            return {
                'username': response['data']['username'],
                'password': response['data']['password']
            }
        except Exception as e:
            logger.error(f"Failed to generate database credentials: {e}")
            return None
    
    def renew_token(self) -> bool:
        """Renew the current token"""
        try:
            self.client.auth.token.renew_self()
            logger.info("Token renewed successfully")
            return True
        except Exception as e:
            logger.error(f"Failed to renew token: {e}")
            return False


class ConsulClient:
    """Enhanced Consul client for service discovery and configuration"""
    
    def __init__(self, config: ServiceConfig):
        self.config = config
        self.client = consul.Consul(
            host=config.host,
            port=config.port,
            token=config.token,
            scheme=config.protocol,
            verify=config.verify_ssl,
            timeout=config.timeout
        )
    
    def register_service(self, service_config: Dict[str, Any]) -> bool:
        """Register a service with Consul"""
        try:
            self.client.agent.service.register(
                name=service_config['name'],
                service_id=service_config.get('id'),
                address=service_config.get('address'),
                port=service_config.get('port'),
                tags=service_config.get('tags', []),
                check=consul.Check.http(
                    service_config.get('health_check_url'),
                    interval=service_config.get('health_check_interval', '10s')
                ) if service_config.get('health_check_url') else None
            )
            logger.info(f"Service {service_config['name']} registered successfully")
            return True
        except Exception as e:
            logger.error(f"Failed to register service: {e}")
            return False
    
    def discover_service(self, service_name: str) -> List[Dict[str, Any]]:
        """Discover service instances"""
        try:
            _, services = self.client.health.service(service_name, passing=True)
            return [
                {
                    'id': service['Service']['ID'],
                    'address': service['Service']['Address'],
                    'port': service['Service']['Port'],
                    'tags': service['Service']['Tags']
                }
                for service in services
            ]
        except Exception as e:
            logger.error(f"Failed to discover service {service_name}: {e}")
            return []
    
    def get_kv_value(self, key: str) -> Optional[str]:
        """Get value from Consul KV store"""
        try:
            _, data = self.client.kv.get(key)
            return data['Value'].decode('utf-8') if data else None
        except Exception as e:
            logger.error(f"Failed to get KV value for {key}: {e}")
            return None
    
    def set_kv_value(self, key: str, value: str) -> bool:
        """Set value in Consul KV store"""
        try:
            result = self.client.kv.put(key, value)
            logger.info(f"KV value set for {key}")
            return result
        except Exception as e:
            logger.error(f"Failed to set KV value for {key}: {e}")
            return False


class NomadClient:
    """Enhanced Nomad client for job management"""
    
    def __init__(self, config: ServiceConfig):
        self.config = config
        self.base_url = config.url
        self.headers = {
            'Content-Type': 'application/json'
        }
        if config.token:
            self.headers['X-Nomad-Token'] = config.token
    
    def submit_job(self, job_spec: Dict[str, Any]) -> Dict[str, Any]:
        """Submit a job to Nomad"""
        try:
            response = requests.post(
                f"{self.base_url}/v1/jobs",
                json={"Job": job_spec},
                headers=self.headers,
                verify=self.config.verify_ssl,
                timeout=self.config.timeout
            )
            response.raise_for_status()
            logger.info(f"Job {job_spec['ID']} submitted successfully")
            return response.json()
        except Exception as e:
            logger.error(f"Failed to submit job: {e}")
            raise
    
    def get_job_status(self, job_id: str) -> Dict[str, Any]:
        """Get job status"""
        try:
            response = requests.get(
                f"{self.base_url}/v1/job/{job_id}",
                headers=self.headers,
                verify=self.config.verify_ssl,
                timeout=self.config.timeout
            )
            response.raise_for_status()
            return response.json()
        except Exception as e:
            logger.error(f"Failed to get job status: {e}")
            raise
    
    def stop_job(self, job_id: str, purge: bool = False) -> Dict[str, Any]:
        """Stop a Nomad job"""
        try:
            params = {'purge': 'true'} if purge else {}
            response = requests.delete(
                f"{self.base_url}/v1/job/{job_id}",
                headers=self.headers,
                params=params,
                verify=self.config.verify_ssl,
                timeout=self.config.timeout
            )
            response.raise_for_status()
            logger.info(f"Job {job_id} stopped successfully")
            return response.json()
        except Exception as e:
            logger.error(f"Failed to stop job {job_id}: {e}")
            raise
    
    def scale_job(self, job_id: str, group_name: str, count: int) -> Dict[str, Any]:
        """Scale a job group"""
        try:
            payload = {
                "Target": {
                    "Group": group_name
                },
                "Count": count
            }
            response = requests.post(
                f"{self.base_url}/v1/job/{job_id}/scale",
                json=payload,
                headers=self.headers,
                verify=self.config.verify_ssl,
                timeout=self.config.timeout
            )
            response.raise_for_status()
            logger.info(f"Job {job_id} group {group_name} scaled to {count}")
            return response.json()
        except Exception as e:
            logger.error(f"Failed to scale job: {e}")
            raise


class PrometheusClient:
    """Enhanced Prometheus client for metrics"""
    
    def __init__(self, config: ServiceConfig):
        self.config = config
        self.base_url = config.url
    
    def push_metric(self, job_name: str, metric_name: str, 
                   metric_value: float, labels: Dict[str, str] = None) -> bool:
        """Push custom metric to Prometheus Gateway"""
        try:
            registry = prometheus_client.CollectorRegistry()
            gauge = prometheus_client.Gauge(
                metric_name, 
                'Custom application metric',
                labelnames=list(labels.keys()) if labels else [],
                registry=registry
            )
            
            if labels:
                gauge.labels(**labels).set(metric_value)
            else:
                gauge.set(metric_value)
            
            prometheus_client.push_to_gateway(
                f"{self.config.host}:{self.config.port}",
                job=job_name,
                registry=registry
            )
            logger.info(f"Metric {metric_name} pushed successfully")
            return True
        except Exception as e:
            logger.error(f"Failed to push metric: {e}")
            return False
    
    def query_metric(self, query: str, timestamp: Optional[int] = None) -> Dict[str, Any]:
        """Query Prometheus for metrics"""
        try:
            params = {'query': query}
            if timestamp:
                params['time'] = timestamp
            
            response = requests.get(
                f"{self.base_url}/api/v1/query",
                params=params,
                verify=self.config.verify_ssl,
                timeout=self.config.timeout
            )
            response.raise_for_status()
            return response.json()
        except Exception as e:
            logger.error(f"Failed to query metrics: {e}")
            raise
    
    def query_range(self, query: str, start: int, end: int, step: str) -> Dict[str, Any]:
        """Query Prometheus for metrics over a time range"""
        try:
            params = {
                'query': query,
                'start': start,
                'end': end,
                'step': step
            }
            
            response = requests.get(
                f"{self.base_url}/api/v1/query_range",
                params=params,
                verify=self.config.verify_ssl,
                timeout=self.config.timeout
            )
            response.raise_for_status()
            return response.json()
        except Exception as e:
            logger.error(f"Failed to query metrics range: {e}")
            raise


class VaultInfrastructureSDK:
    """Main SDK class orchestrating all services"""
    
    def __init__(self, config_file: Optional[str] = None, config_dict: Optional[Dict] = None):
        """Initialize SDK with configuration"""
        if config_file:
            with open(config_file, 'r') as f:
                config = json.load(f)
        elif config_dict:
            config = config_dict
        else:
            config = self._load_env_config()
        
        self.vault = None
        self.consul = None
        self.nomad = None
        self.prometheus = None
        
        # Initialize clients based on configuration
        if 'vault' in config:
            vault_config = ServiceConfig(**config['vault'])
            self.vault = VaultClient(vault_config)
        
        if 'consul' in config:
            consul_config = ServiceConfig(**config['consul'])
            self.consul = ConsulClient(consul_config)
        
        if 'nomad' in config:
            nomad_config = ServiceConfig(**config['nomad'])
            self.nomad = NomadClient(nomad_config)
        
        if 'prometheus' in config:
            prometheus_config = ServiceConfig(**config['prometheus'])
            self.prometheus = PrometheusClient(prometheus_config)
    
    def _load_env_config(self) -> Dict[str, Any]:
        """Load configuration from environment variables"""
        return {
            'vault': {
                'host': os.getenv('VAULT_ADDR', 'localhost'),
                'port': int(os.getenv('VAULT_PORT', 8200)),
                'token': os.getenv('VAULT_TOKEN'),
                'ca_cert': os.getenv('VAULT_CACERT'),
                'verify_ssl': os.getenv('VAULT_SKIP_VERIFY', 'false').lower() != 'true'
            },
            'consul': {
                'host': os.getenv('CONSUL_HOST', 'localhost'),
                'port': int(os.getenv('CONSUL_PORT', 8500)),
                'token': os.getenv('CONSUL_TOKEN'),
                'protocol': os.getenv('CONSUL_SCHEME', 'https')
            },
            'nomad': {
                'host': os.getenv('NOMAD_ADDR', 'localhost'),
                'port': int(os.getenv('NOMAD_PORT', 4646)),
                'token': os.getenv('NOMAD_TOKEN'),
                'protocol': os.getenv('NOMAD_SCHEME', 'https')
            },
            'prometheus': {
                'host': os.getenv('PROMETHEUS_HOST', 'localhost'),
                'port': int(os.getenv('PROMETHEUS_PORT', 9090)),
                'protocol': os.getenv('PROMETHEUS_SCHEME', 'https')
            }
        }
    
    async def health_check_all(self) -> Dict[str, bool]:
        """Perform health checks on all configured services"""
        results = {}
        
        if self.vault:
            try:
                results['vault'] = self.vault.client.sys.is_initialized() and \
                                 not self.vault.client.sys.is_sealed()
            except:
                results['vault'] = False
        
        if self.consul:
            try:
                self.consul.client.agent.self()
                results['consul'] = True
            except:
                results['consul'] = False
        
        if self.nomad:
            try:
                response = requests.get(
                    f"{self.nomad.base_url}/v1/status/leader",
                    headers=self.nomad.headers,
                    timeout=5
                )
                results['nomad'] = response.status_code == 200
            except:
                results['nomad'] = False
        
        if self.prometheus:
            try:
                response = requests.get(
                    f"{self.prometheus.base_url}/-/ready",
                    timeout=5
                )
                results['prometheus'] = response.status_code == 200
            except:
                results['prometheus'] = False
        
        return results
    
    def setup_application_secrets(self, app_name: str, secrets: Dict[str, str]) -> bool:
        """Setup application secrets in Vault with Consul service registration"""
        if not self.vault:
            logger.error("Vault client not configured")
            return False
        
        # Store secrets in Vault
        secret_path = f"applications/{app_name}"
        if not self.vault.write_secret(secret_path, secrets):
            return False
        
        # Register with Consul if available
        if self.consul:
            service_config = {
                'name': f"{app_name}-secrets",
                'tags': ['secrets', 'vault-integrated']
            }
            self.consul.register_service(service_config)
        
        logger.info(f"Application secrets setup completed for {app_name}")
        return True
    
    def deploy_application(self, job_spec: Dict[str, Any], 
                          secrets_path: Optional[str] = None) -> Dict[str, Any]:
        """Deploy application with integrated secrets management"""
        if not self.nomad:
            raise RuntimeError("Nomad client not configured")
        
        # Inject Vault integration if secrets path provided
        if secrets_path and self.vault:
            # Add Vault template stanza to job spec
            if 'TaskGroups' not in job_spec:
                job_spec['TaskGroups'] = []
            
            for task_group in job_spec['TaskGroups']:
                if 'Tasks' not in task_group:
                    continue
                
                for task in task_group['Tasks']:
                    if 'Templates' not in task:
                        task['Templates'] = []
                    
                    # Add secret template
                    task['Templates'].append({
                        'SourcePath': "",
                        'DestPath': "secrets/app.env",
                        'EmbeddedTmpl': f"""
{{{{ with secret "{secrets_path}" }}}}
{{{{ range $key, $value := .Data.data }}}}
{{{{ $key }}}}={{{{ $value }}}}
{{{{ end }}}}
{{{{ end }}}}
                        """,
                        'ChangeMode': "restart"
                    })
        
        return self.nomad.submit_job(job_spec)


# Utility functions
def create_vault_policy(policy_name: str, policy_rules: List[str]) -> str:
    """Generate Vault policy HCL"""
    policy_content = f"# Policy: {policy_name}\n\n"
    for rule in policy_rules:
        policy_content += f"{rule}\n"
    return policy_content


def create_nomad_job_template(app_name: str, image: str, port: int = 8080) -> Dict[str, Any]:
    """Create basic Nomad job template"""
    return {
        "ID": app_name,
        "Name": app_name,
        "Type": "service",
        "Priority": 50,
        "TaskGroups": [
            {
                "Name": f"{app_name}-group",
                "Count": 1,
                "Tasks": [
                    {
                        "Name": app_name,
                        "Driver": "docker",
                        "Config": {
                            "image": image,
                            "port_map": [
                                {"http": port}
                            ]
                        },
                        "Services": [
                            {
                                "Name": app_name,
                                "PortLabel": "http",
                                "Checks": [
                                    {
                                        "Name": "health",
                                        "Type": "http",
                                        "Path": "/health",
                                        "Interval": 10000000000,
                                        "Timeout": 2000000000
                                    }
                                ]
                            }
                        ],
                        "Resources": {
                            "CPU": 256,
                            "MemoryMB": 512,
                            "Networks": [
                                {
                                    "ReservedPorts": [
                                        {"Label": "http", "Value": port}
                                    ]
                                }
                            ]
                        }
                    }
                ]
            }
        ]
    }


# Example usage and testing
if __name__ == "__main__":
    # Example configuration
    config = {
        "vault": {
            "host": "vault.example.com",
            "port": 8200,
            "token": "hvs.example-token"
        },
        "consul": {
            "host": "consul.example.com",
            "port": 8500,
            "token": "consul-token"
        },
        "nomad": {
            "host": "nomad.example.com",
            "port": 4646,
            "token": "nomad-token"
        },
        "prometheus": {
            "host": "prometheus.example.com",
            "port": 9090
        }
    }
    
    # Initialize SDK
    sdk = VaultInfrastructureSDK(config_dict=config)
    
    # Example: Setup application with secrets
    app_secrets = {
        "database_url": "postgresql://user:pass@db:5432/myapp",
        "api_key": "secret-api-key",
        "encryption_key": "32-char-encryption-key-here!!"
    }
    
    sdk.setup_application_secrets("my-web-app", app_secrets)
    
    # Example: Deploy application
    job_spec = create_nomad_job_template("my-web-app", "nginx:latest", 8080)
    deployment_result = sdk.deploy_application(
        job_spec, 
        secrets_path="applications/my-web-app"
    )
    
    print("Deployment result:", deployment_result)