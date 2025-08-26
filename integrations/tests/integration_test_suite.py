#!/usr/bin/env python3
"""
Comprehensive Integration Test Suite for Vault Infrastructure

This test suite validates the complete integration between applications
and the Vault infrastructure stack (Vault, Consul, Nomad, Prometheus).

Features:
- Vault secrets management testing
- Consul service discovery testing
- Nomad job deployment testing
- Prometheus metrics collection testing
- End-to-end application deployment testing
- Security and authentication testing
- Performance and load testing

Author: Vault Integration Team
Version: 1.0.0
"""

import os
import sys
import time
import json
import pytest
import requests
import asyncio
import logging
from datetime import datetime, timedelta
from typing import Dict, List, Any, Optional
import tempfile
import subprocess
from pathlib import Path

# Add SDK to path
sys.path.append(os.path.join(os.path.dirname(__file__), '../python'))
from vault_integration_sdk import VaultInfrastructureSDK, ServiceConfig

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


class VaultInfrastructureTestSuite:
    """Comprehensive test suite for Vault infrastructure integration"""
    
    def __init__(self, config_file: Optional[str] = None):
        self.sdk = None
        self.test_app_name = f"test-app-{int(time.time())}"
        self.test_results = {}
        
        # Load configuration
        if config_file and os.path.exists(config_file):
            with open(config_file, 'r') as f:
                config = json.load(f)
        else:
            config = self._get_test_config()
        
        try:
            self.sdk = VaultInfrastructureSDK(config_dict=config)
            logger.info("✅ Test SDK initialized successfully")
        except Exception as e:
            logger.error(f"❌ Failed to initialize test SDK: {e}")
            raise
    
    def _get_test_config(self) -> Dict[str, Any]:
        """Get test configuration from environment variables"""
        return {
            'vault': {
                'host': os.getenv('VAULT_ADDR', 'localhost').replace('https://', '').replace('http://', ''),
                'port': int(os.getenv('VAULT_PORT', 8200)),
                'token': os.getenv('VAULT_TOKEN'),
                'protocol': 'https' if 'https' in os.getenv('VAULT_ADDR', '') else 'http',
                'verify_ssl': os.getenv('VAULT_SKIP_VERIFY', 'false').lower() != 'true'
            },
            'consul': {
                'host': os.getenv('CONSUL_HOST', 'localhost'),
                'port': int(os.getenv('CONSUL_PORT', 8500)),
                'token': os.getenv('CONSUL_TOKEN'),
                'protocol': 'https'
            },
            'nomad': {
                'host': os.getenv('NOMAD_HOST', 'localhost'),
                'port': int(os.getenv('NOMAD_PORT', 4646)),
                'token': os.getenv('NOMAD_TOKEN'),
                'protocol': 'https'
            },
            'prometheus': {
                'host': os.getenv('PROMETHEUS_HOST', 'localhost'),
                'port': int(os.getenv('PROMETHEUS_PORT', 9090)),
                'protocol': 'https'
            }
        }
    
    async def run_all_tests(self) -> Dict[str, Any]:
        """Run the complete test suite"""
        logger.info("🚀 Starting Vault Infrastructure Integration Test Suite")
        
        test_results = {
            'timestamp': datetime.utcnow().isoformat(),
            'test_app': self.test_app_name,
            'overall_status': 'passed',
            'tests': {}
        }
        
        # Test categories
        test_categories = [
            ('health_check', self.test_infrastructure_health),
            ('vault_secrets', self.test_vault_secrets_management),
            ('vault_auth', self.test_vault_authentication),
            ('consul_discovery', self.test_consul_service_discovery),
            ('nomad_deployment', self.test_nomad_job_deployment),
            ('prometheus_metrics', self.test_prometheus_metrics),
            ('integration_flow', self.test_end_to_end_integration),
            ('security', self.test_security_features),
            ('performance', self.test_performance_characteristics)
        ]
        
        for test_name, test_func in test_categories:
            logger.info(f"🧪 Running test: {test_name}")
            try:
                result = await test_func()
                test_results['tests'][test_name] = result
                
                if result.get('status') != 'passed':
                    test_results['overall_status'] = 'failed'
                    logger.error(f"❌ Test {test_name} failed: {result.get('error', 'Unknown error')}")
                else:
                    logger.info(f"✅ Test {test_name} passed")
                    
            except Exception as e:
                logger.error(f"❌ Test {test_name} encountered an exception: {e}")
                test_results['tests'][test_name] = {
                    'status': 'error',
                    'error': str(e),
                    'timestamp': datetime.utcnow().isoformat()
                }
                test_results['overall_status'] = 'failed'
        
        # Cleanup test resources
        await self.cleanup_test_resources()
        
        logger.info(f"📊 Test Suite Complete - Overall Status: {test_results['overall_status'].upper()}")
        return test_results
    
    async def test_infrastructure_health(self) -> Dict[str, Any]:
        """Test infrastructure component health"""
        try:
            health_results = await self.sdk.health_check_all()
            
            failed_services = [service for service, healthy in health_results.items() if not healthy]
            
            return {
                'status': 'passed' if not failed_services else 'failed',
                'services': health_results,
                'failed_services': failed_services,
                'timestamp': datetime.utcnow().isoformat()
            }
            
        except Exception as e:
            return {
                'status': 'error',
                'error': str(e),
                'timestamp': datetime.utcnow().isoformat()
            }
    
    async def test_vault_secrets_management(self) -> Dict[str, Any]:
        """Test Vault secrets management operations"""
        test_secret_path = f"test/integration/{self.test_app_name}"
        test_data = {
            'database_url': 'postgresql://testuser:testpass@localhost:5432/testdb',
            'api_key': 'test-api-key-12345',
            'encryption_key': 'test-encryption-key-67890'
        }
        
        try:
            # Test 1: Write secret
            write_success = self.sdk.vault.write_secret(test_secret_path, test_data)
            if not write_success:
                return {'status': 'failed', 'error': 'Failed to write test secret'}
            
            # Test 2: Read secret
            retrieved_data = self.sdk.vault.get_secret(test_secret_path)
            if not retrieved_data:
                return {'status': 'failed', 'error': 'Failed to read test secret'}
            
            # Test 3: Verify data integrity
            for key, value in test_data.items():
                if retrieved_data.get(key) != value:
                    return {'status': 'failed', 'error': f'Data integrity check failed for key: {key}'}
            
            # Test 4: Update secret
            updated_data = {**test_data, 'new_field': 'new_value'}
            update_success = self.sdk.vault.write_secret(test_secret_path, updated_data)
            if not update_success:
                return {'status': 'failed', 'error': 'Failed to update test secret'}
            
            # Test 5: Verify update
            final_data = self.sdk.vault.get_secret(test_secret_path)
            if final_data.get('new_field') != 'new_value':
                return {'status': 'failed', 'error': 'Secret update verification failed'}
            
            return {
                'status': 'passed',
                'operations_tested': ['write', 'read', 'update', 'verify'],
                'test_path': test_secret_path,
                'timestamp': datetime.utcnow().isoformat()
            }
            
        except Exception as e:
            return {
                'status': 'error',
                'error': str(e),
                'timestamp': datetime.utcnow().isoformat()
            }
    
    async def test_vault_authentication(self) -> Dict[str, Any]:
        """Test Vault authentication mechanisms"""
        try:
            # Test token-based authentication (already authenticated)
            if not self.sdk.vault.client.is_authenticated():
                return {'status': 'failed', 'error': 'Initial token authentication failed'}
            
            # Test token renewal
            renewal_success = self.sdk.vault.renew_token()
            
            return {
                'status': 'passed' if renewal_success else 'failed',
                'auth_methods_tested': ['token', 'token_renewal'],
                'error': 'Token renewal failed' if not renewal_success else None,
                'timestamp': datetime.utcnow().isoformat()
            }
            
        except Exception as e:
            return {
                'status': 'error',
                'error': str(e),
                'timestamp': datetime.utcnow().isoformat()
            }
    
    async def test_consul_service_discovery(self) -> Dict[str, Any]:
        """Test Consul service registration and discovery"""
        test_service_config = {
            'name': f"{self.test_app_name}-service",
            'id': f"{self.test_app_name}-service-{int(time.time())}",
            'address': '127.0.0.1',
            'port': 8080,
            'tags': ['test', 'integration'],
            'health_check_url': 'http://127.0.0.1:8080/health',
            'health_check_interval': '10s'
        }
        
        try:
            if not self.sdk.consul:
                return {'status': 'skipped', 'reason': 'Consul client not configured'}
            
            # Test 1: Register service
            register_success = self.sdk.consul.register_service(test_service_config)
            if not register_success:
                return {'status': 'failed', 'error': 'Failed to register test service'}
            
            # Wait for registration to propagate
            await asyncio.sleep(2)
            
            # Test 2: Discover service
            services = self.sdk.consul.discover_service(test_service_config['name'])
            
            # Test 3: Verify service registration
            service_found = any(
                svc['id'] == test_service_config['id'] 
                for svc in services
            )
            
            if not service_found:
                return {'status': 'failed', 'error': 'Registered service not found in discovery'}
            
            # Test 4: Test KV operations
            test_key = f"test/{self.test_app_name}/config"
            test_value = "test configuration value"
            
            kv_set_success = self.sdk.consul.set_kv_value(test_key, test_value)
            if not kv_set_success:
                return {'status': 'failed', 'error': 'Failed to set KV value'}
            
            retrieved_value = self.sdk.consul.get_kv_value(test_key)
            if retrieved_value != test_value:
                return {'status': 'failed', 'error': 'KV value retrieval failed'}
            
            return {
                'status': 'passed',
                'operations_tested': ['register', 'discover', 'kv_set', 'kv_get'],
                'service_id': test_service_config['id'],
                'discovered_services': len(services),
                'timestamp': datetime.utcnow().isoformat()
            }
            
        except Exception as e:
            return {
                'status': 'error',
                'error': str(e),
                'timestamp': datetime.utcnow().isoformat()
            }
    
    async def test_nomad_job_deployment(self) -> Dict[str, Any]:
        """Test Nomad job submission and management"""
        test_job_spec = {
            "ID": f"{self.test_app_name}-job",
            "Name": f"{self.test_app_name}-job",
            "Type": "batch",
            "Priority": 50,
            "TaskGroups": [
                {
                    "Name": "test-group",
                    "Count": 1,
                    "Tasks": [
                        {
                            "Name": "test-task",
                            "Driver": "raw_exec",
                            "Config": {
                                "command": "echo",
                                "args": ["Integration test job completed successfully"]
                            },
                            "Resources": {
                                "CPU": 100,
                                "MemoryMB": 128
                            }
                        }
                    ]
                }
            ]
        }
        
        try:
            if not self.sdk.nomad:
                return {'status': 'skipped', 'reason': 'Nomad client not configured'}
            
            # Test 1: Submit job
            submit_result = self.sdk.nomad.submit_job(test_job_spec)
            if not submit_result:
                return {'status': 'failed', 'error': 'Failed to submit test job'}
            
            # Test 2: Check job status
            await asyncio.sleep(5)  # Allow time for job to process
            job_status = self.sdk.nomad.get_job_status(test_job_spec["ID"])
            
            if not job_status:
                return {'status': 'failed', 'error': 'Failed to retrieve job status'}
            
            # Test 3: Wait for job completion (batch job should complete)
            max_wait = 60  # seconds
            wait_time = 0
            
            while wait_time < max_wait:
                status = self.sdk.nomad.get_job_status(test_job_spec["ID"])
                if status.get("Status") in ["complete", "dead"]:
                    break
                await asyncio.sleep(5)
                wait_time += 5
            
            return {
                'status': 'passed',
                'operations_tested': ['submit', 'status_check'],
                'job_id': test_job_spec["ID"],
                'final_status': status.get("Status"),
                'timestamp': datetime.utcnow().isoformat()
            }
            
        except Exception as e:
            return {
                'status': 'error',
                'error': str(e),
                'timestamp': datetime.utcnow().isoformat()
            }
    
    async def test_prometheus_metrics(self) -> Dict[str, Any]:
        """Test Prometheus metrics collection"""
        try:
            if not self.sdk.prometheus:
                return {'status': 'skipped', 'reason': 'Prometheus client not configured'}
            
            # Test 1: Query basic metrics
            query_result = self.sdk.prometheus.query_metric("up")
            
            if not query_result or query_result.get("status") != "success":
                return {'status': 'failed', 'error': 'Failed to query basic metrics'}
            
            # Test 2: Push custom metric (if push gateway available)
            push_success = True
            try:
                push_success = self.sdk.prometheus.push_metric(
                    job_name="integration-test",
                    metric_name="test_metric",
                    metric_value=1.0,
                    labels={"test": "integration", "app": self.test_app_name}
                )
            except Exception as e:
                logger.warning(f"⚠️ Push gateway not available: {e}")
                push_success = None  # Optional feature
            
            # Test 3: Query range
            end_time = int(time.time())
            start_time = end_time - 3600  # 1 hour ago
            
            range_result = self.sdk.prometheus.query_range(
                query="up",
                start=start_time,
                end=end_time,
                step="300s"
            )
            
            return {
                'status': 'passed',
                'operations_tested': ['query', 'query_range'] + (['push'] if push_success else []),
                'metrics_available': len(query_result.get("data", {}).get("result", [])),
                'range_data_points': len(range_result.get("data", {}).get("result", [])),
                'push_gateway_available': push_success is not None,
                'timestamp': datetime.utcnow().isoformat()
            }
            
        except Exception as e:
            return {
                'status': 'error',
                'error': str(e),
                'timestamp': datetime.utcnow().isoformat()
            }
    
    async def test_end_to_end_integration(self) -> Dict[str, Any]:
        """Test complete application deployment workflow"""
        try:
            # Test 1: Setup application secrets
            app_secrets = {
                'database_url': 'postgresql://app:secret@db:5432/appdb',
                'api_key': 'integration-test-api-key',
                'encryption_key': 'integration-test-encryption-key'
            }
            
            setup_success = self.sdk.setup_application_secrets(self.test_app_name, app_secrets)
            if not setup_success:
                return {'status': 'failed', 'error': 'Failed to setup application secrets'}
            
            # Test 2: Create test job with Vault integration
            test_job = {
                "ID": f"{self.test_app_name}-e2e",
                "Name": f"{self.test_app_name}-e2e",
                "Type": "batch",
                "Priority": 50,
                "TaskGroups": [
                    {
                        "Name": "app-group",
                        "Count": 1,
                        "Tasks": [
                            {
                                "Name": "app-task",
                                "Driver": "raw_exec",
                                "Config": {
                                    "command": "env",
                                    "args": []
                                },
                                "Resources": {
                                    "CPU": 100,
                                    "MemoryMB": 128
                                }
                            }
                        ]
                    }
                ]
            }
            
            # Test 3: Deploy with integrated secrets
            deployment_result = self.sdk.deploy_application(
                test_job, 
                f"applications/{self.test_app_name}"
            )
            
            return {
                'status': 'passed',
                'workflow_steps': ['secrets_setup', 'job_creation', 'deployment'],
                'app_name': self.test_app_name,
                'deployment_id': deployment_result.get('EvalID'),
                'timestamp': datetime.utcnow().isoformat()
            }
            
        except Exception as e:
            return {
                'status': 'error',
                'error': str(e),
                'timestamp': datetime.utcnow().isoformat()
            }
    
    async def test_security_features(self) -> Dict[str, Any]:
        """Test security features and access controls"""
        try:
            security_tests = {}
            
            # Test 1: Token permissions
            if self.sdk.vault.client.is_authenticated():
                security_tests['token_auth'] = 'passed'
            else:
                security_tests['token_auth'] = 'failed'
            
            # Test 2: Secret path access control
            try:
                # Try to access a restricted path (should fail with proper policies)
                restricted_secret = self.sdk.vault.get_secret("sys/policies/acl/root")
                if restricted_secret:
                    security_tests['access_control'] = 'warning'  # Should be restricted
                else:
                    security_tests['access_control'] = 'passed'  # Properly restricted
            except Exception:
                security_tests['access_control'] = 'passed'  # Access properly denied
            
            # Test 3: TLS/SSL connections
            security_tests['tls_vault'] = 'passed' if 'https' in self.sdk.vault.config.url else 'warning'
            if self.sdk.consul:
                security_tests['tls_consul'] = 'passed' if 'https' in self.sdk.consul.config.url else 'warning'
            if self.sdk.nomad:
                security_tests['tls_nomad'] = 'passed' if 'https' in self.sdk.nomad.config.url else 'warning'
            
            # Overall security status
            failed_tests = [test for test, status in security_tests.items() if status == 'failed']
            warning_tests = [test for test, status in security_tests.items() if status == 'warning']
            
            overall_status = 'failed' if failed_tests else ('warning' if warning_tests else 'passed')
            
            return {
                'status': overall_status,
                'security_tests': security_tests,
                'failed_tests': failed_tests,
                'warning_tests': warning_tests,
                'timestamp': datetime.utcnow().isoformat()
            }
            
        except Exception as e:
            return {
                'status': 'error',
                'error': str(e),
                'timestamp': datetime.utcnow().isoformat()
            }
    
    async def test_performance_characteristics(self) -> Dict[str, Any]:
        """Test performance characteristics of the integration"""
        try:
            performance_metrics = {}
            
            # Test 1: Secret retrieval performance
            secret_path = f"test/performance/{self.test_app_name}"
            test_data = {'key': 'value' * 100}  # Moderately sized secret
            
            # Setup test data
            self.sdk.vault.write_secret(secret_path, test_data)
            
            # Time secret retrieval
            retrieval_times = []
            for _ in range(10):
                start_time = time.time()
                self.sdk.vault.get_secret(secret_path)
                end_time = time.time()
                retrieval_times.append(end_time - start_time)
            
            performance_metrics['secret_retrieval'] = {
                'avg_time': sum(retrieval_times) / len(retrieval_times),
                'max_time': max(retrieval_times),
                'min_time': min(retrieval_times)
            }
            
            # Test 2: Consul service lookup performance
            if self.sdk.consul:
                lookup_times = []
                for _ in range(5):
                    start_time = time.time()
                    self.sdk.consul.discover_service("consul")  # Consul should always be available
                    end_time = time.time()
                    lookup_times.append(end_time - start_time)
                
                performance_metrics['service_lookup'] = {
                    'avg_time': sum(lookup_times) / len(lookup_times) if lookup_times else 0,
                    'max_time': max(lookup_times) if lookup_times else 0,
                    'min_time': min(lookup_times) if lookup_times else 0
                }
            
            # Performance criteria (adjust based on your requirements)
            issues = []
            if performance_metrics['secret_retrieval']['avg_time'] > 1.0:  # 1 second
                issues.append('Secret retrieval too slow')
            
            if performance_metrics.get('service_lookup', {}).get('avg_time', 0) > 2.0:  # 2 seconds
                issues.append('Service lookup too slow')
            
            return {
                'status': 'passed' if not issues else 'warning',
                'performance_metrics': performance_metrics,
                'issues': issues,
                'timestamp': datetime.utcnow().isoformat()
            }
            
        except Exception as e:
            return {
                'status': 'error',
                'error': str(e),
                'timestamp': datetime.utcnow().isoformat()
            }
    
    async def cleanup_test_resources(self):
        """Clean up test resources"""
        logger.info("🧹 Cleaning up test resources...")
        
        try:
            # Clean up Vault test secrets
            if self.sdk.vault:
                test_paths = [
                    f"test/integration/{self.test_app_name}",
                    f"test/performance/{self.test_app_name}",
                    f"applications/{self.test_app_name}"
                ]
                
                for path in test_paths:
                    try:
                        # Note: This would need a delete method in the SDK
                        logger.info(f"Would clean up Vault path: {path}")
                    except Exception as e:
                        logger.warning(f"⚠️ Failed to clean up Vault path {path}: {e}")
            
            # Clean up Consul test services and KV
            if self.sdk.consul:
                try:
                    # Deregister test services and clean KV
                    logger.info("Would clean up Consul test resources")
                except Exception as e:
                    logger.warning(f"⚠️ Failed to clean up Consul resources: {e}")
            
            # Clean up Nomad test jobs
            if self.sdk.nomad:
                test_jobs = [
                    f"{self.test_app_name}-job",
                    f"{self.test_app_name}-e2e"
                ]
                
                for job_id in test_jobs:
                    try:
                        self.sdk.nomad.stop_job(job_id, purge=True)
                        logger.info(f"✅ Cleaned up Nomad job: {job_id}")
                    except Exception as e:
                        logger.warning(f"⚠️ Failed to clean up Nomad job {job_id}: {e}")
            
            logger.info("✅ Test resource cleanup completed")
            
        except Exception as e:
            logger.error(f"❌ Error during cleanup: {e}")


# Pytest integration
@pytest.mark.asyncio
async def test_vault_infrastructure_integration():
    """Run the complete integration test suite"""
    test_suite = VaultInfrastructureTestSuite()
    results = await test_suite.run_all_tests()
    
    # Assert overall success
    assert results['overall_status'] != 'failed', f"Integration tests failed: {results}"
    
    # Print detailed results
    print(f"\n{'='*60}")
    print("VAULT INFRASTRUCTURE INTEGRATION TEST RESULTS")
    print(f"{'='*60}")
    print(f"Overall Status: {results['overall_status'].upper()}")
    print(f"Test Application: {results['test_app']}")
    print(f"Timestamp: {results['timestamp']}")
    print(f"{'='*60}")
    
    for test_name, test_result in results['tests'].items():
        status_emoji = "✅" if test_result['status'] == 'passed' else "⚠️" if test_result['status'] == 'warning' else "❌"
        print(f"{status_emoji} {test_name.replace('_', ' ').title()}: {test_result['status'].upper()}")
        
        if test_result['status'] in ['failed', 'error'] and 'error' in test_result:
            print(f"   Error: {test_result['error']}")


# CLI interface for standalone execution
if __name__ == "__main__":
    import argparse
    
    parser = argparse.ArgumentParser(description='Vault Infrastructure Integration Test Suite')
    parser.add_argument('--config', help='Configuration file path')
    parser.add_argument('--output', help='Output results to JSON file')
    parser.add_argument('--verbose', '-v', action='store_true', help='Verbose logging')
    
    args = parser.parse_args()
    
    if args.verbose:
        logging.getLogger().setLevel(logging.DEBUG)
    
    async def main():
        try:
            test_suite = VaultInfrastructureTestSuite(args.config)
            results = await test_suite.run_all_tests()
            
            # Output results
            if args.output:
                with open(args.output, 'w') as f:
                    json.dump(results, f, indent=2)
                logger.info(f"📄 Results written to: {args.output}")
            else:
                print(json.dumps(results, indent=2))
            
            # Exit with appropriate code
            sys.exit(0 if results['overall_status'] != 'failed' else 1)
            
        except Exception as e:
            logger.error(f"❌ Test suite execution failed: {e}")
            sys.exit(1)
    
    # Run the async main function
    asyncio.run(main())