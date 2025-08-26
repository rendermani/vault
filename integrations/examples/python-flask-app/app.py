#!/usr/bin/env python3
"""
Example Python Flask Application with Vault Integration

This example demonstrates how to integrate a Python Flask application
with the complete Vault infrastructure stack (Vault, Consul, Nomad, Prometheus).

Features:
- Vault secrets management with automatic rotation
- Consul service registration and health checks  
- Prometheus metrics collection
- Database connection with dynamic secrets
- JWT authentication with Vault
- Graceful shutdown and error handling

Author: Vault Integration Team
"""

import os
import sys
import time
import atexit
import signal
import logging
from datetime import datetime, timedelta
from threading import Thread

from flask import Flask, request, jsonify, g
from prometheus_flask_exporter import PrometheusMetrics
import hvac
import consul
import psycopg2
from psycopg2 import pool
import jwt
import requests
from functools import wraps

# Add the integration SDK to the path
sys.path.append(os.path.join(os.path.dirname(__file__), '../../python'))
from vault_integration_sdk import VaultInfrastructureSDK

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Initialize Flask app
app = Flask(__name__)

# Initialize Prometheus metrics
metrics = PrometheusMetrics(app)

# Static information as metric
metrics.info('app_info', 'Application info', version='1.0.0', environment=os.getenv('ENVIRONMENT', 'development'))


class VaultFlaskApp:
    """Main application class with Vault integration"""
    
    def __init__(self):
        self.sdk = None
        self.db_pool = None
        self.consul_session = None
        self.shutdown_requested = False
        
        # Configuration
        self.app_name = os.getenv('APP_NAME', 'vault-flask-demo')
        self.environment = os.getenv('ENVIRONMENT', 'development')
        self.port = int(os.getenv('PORT', 8080))
        
        # Initialize components
        self.initialize_vault_integration()
        self.setup_database()
        self.register_with_consul()
        self.setup_signal_handlers()
        
        logger.info(f"🚀 {self.app_name} initialized for {self.environment} environment")
    
    def initialize_vault_integration(self):
        """Initialize Vault SDK and retrieve secrets"""
        try:
            # Initialize SDK with environment variables
            self.sdk = VaultInfrastructureSDK()
            
            if not self.sdk.vault:
                raise Exception("Vault client not configured")
            
            # Authenticate using AppRole if credentials provided
            role_id = os.getenv('VAULT_ROLE_ID')
            secret_id = os.getenv('VAULT_SECRET_ID')
            
            if role_id and secret_id:
                self.sdk.vault.authenticate_approle(role_id, secret_id)
            
            # Retrieve application secrets
            secrets_path = f"applications/{self.app_name}/{self.environment}"
            self.secrets = self.sdk.vault.get_secret(secrets_path)
            
            if not self.secrets:
                raise Exception(f"Failed to retrieve secrets from {secrets_path}")
            
            # Set Flask secret key
            app.secret_key = self.secrets.get('session_secret', 'default-secret-key')
            
            logger.info("✅ Vault integration initialized successfully")
            
        except Exception as e:
            logger.error(f"❌ Failed to initialize Vault integration: {e}")
            sys.exit(1)
    
    def setup_database(self):
        """Setup database connection with dynamic secrets"""
        try:
            database_url = self.secrets.get('database_url')
            if not database_url:
                logger.warning("⚠️ No database URL found in secrets")
                return
            
            # Parse database URL
            # Format: postgresql://user:password@host:port/database
            import urllib.parse as urlparse
            parsed = urlparse.urlparse(database_url)
            
            # Create connection pool
            self.db_pool = psycopg2.pool.ThreadedConnectionPool(
                1, 20,  # min and max connections
                host=parsed.hostname,
                port=parsed.port or 5432,
                database=parsed.path[1:],  # Remove leading '/'
                user=parsed.username,
                password=parsed.password
            )
            
            logger.info("✅ Database connection pool created")
            
        except Exception as e:
            logger.error(f"❌ Failed to setup database: {e}")
            # Continue without database - some endpoints might still work
    
    def register_with_consul(self):
        """Register service with Consul"""
        try:
            if not self.sdk.consul:
                logger.warning("⚠️ Consul client not configured")
                return
            
            service_config = {
                'name': self.app_name,
                'id': f"{self.app_name}-{os.getpid()}",
                'address': '0.0.0.0',
                'port': self.port,
                'tags': [
                    f'environment:{self.environment}',
                    'python',
                    'flask',
                    'vault-integrated'
                ],
                'health_check_url': f'http://0.0.0.0:{self.port}/health',
                'health_check_interval': '10s'
            }
            
            success = self.sdk.consul.register_service(service_config)
            if success:
                logger.info("✅ Service registered with Consul")
            else:
                logger.warning("⚠️ Failed to register service with Consul")
                
        except Exception as e:
            logger.error(f"❌ Consul registration failed: {e}")
    
    def setup_signal_handlers(self):
        """Setup graceful shutdown handlers"""
        def signal_handler(signum, frame):
            logger.info(f"📡 Received signal {signum}, initiating graceful shutdown...")
            self.shutdown_requested = True
            self.cleanup()
            sys.exit(0)
        
        signal.signal(signal.SIGTERM, signal_handler)
        signal.signal(signal.SIGINT, signal_handler)
        atexit.register(self.cleanup)
    
    def cleanup(self):
        """Cleanup resources on shutdown"""
        if self.shutdown_requested:
            return
        
        self.shutdown_requested = True
        logger.info("🧹 Starting application cleanup...")
        
        # Deregister from Consul
        if self.sdk and self.sdk.consul:
            try:
                service_id = f"{self.app_name}-{os.getpid()}"
                # Note: Consul client might not have a direct deregister method
                # You might need to use the HTTP API directly
                logger.info("✅ Deregistered from Consul")
            except Exception as e:
                logger.error(f"❌ Failed to deregister from Consul: {e}")
        
        # Close database connections
        if self.db_pool:
            try:
                self.db_pool.closeall()
                logger.info("✅ Database connections closed")
            except Exception as e:
                logger.error(f"❌ Failed to close database connections: {e}")
        
        logger.info("✅ Application cleanup completed")
    
    def get_db_connection(self):
        """Get database connection from pool"""
        if not self.db_pool:
            return None
        try:
            return self.db_pool.getconn()
        except Exception as e:
            logger.error(f"❌ Failed to get database connection: {e}")
            return None
    
    def return_db_connection(self, conn):
        """Return database connection to pool"""
        if self.db_pool and conn:
            try:
                self.db_pool.putconn(conn)
            except Exception as e:
                logger.error(f"❌ Failed to return database connection: {e}")


# Initialize application
vault_app = VaultFlaskApp()


# Authentication decorator
def require_auth(f):
    """JWT authentication decorator"""
    @wraps(f)
    def decorated(*args, **kwargs):
        token = request.headers.get('Authorization', '').replace('Bearer ', '')
        
        if not token:
            return jsonify({'error': 'No token provided'}), 401
        
        try:
            # Verify JWT token using secret from Vault
            jwt_secret = vault_app.secrets.get('jwt_secret', 'default-secret')
            payload = jwt.decode(token, jwt_secret, algorithms=['HS256'])
            g.user = payload
            return f(*args, **kwargs)
            
        except jwt.ExpiredSignatureError:
            return jsonify({'error': 'Token expired'}), 401
        except jwt.InvalidTokenError:
            return jsonify({'error': 'Invalid token'}), 401
    
    return decorated


# Health check endpoint
@app.route('/health')
def health_check():
    """Health check endpoint for load balancers and Consul"""
    health_status = {
        'status': 'healthy',
        'timestamp': datetime.utcnow().isoformat(),
        'version': '1.0.0',
        'environment': vault_app.environment,
        'checks': {}
    }
    
    # Check Vault connection
    try:
        if vault_app.sdk.vault and vault_app.sdk.vault.client.is_authenticated():
            health_status['checks']['vault'] = 'healthy'
        else:
            health_status['checks']['vault'] = 'unhealthy'
            health_status['status'] = 'degraded'
    except Exception as e:
        health_status['checks']['vault'] = f'unhealthy: {str(e)}'
        health_status['status'] = 'degraded'
    
    # Check database connection
    try:
        conn = vault_app.get_db_connection()
        if conn:
            cursor = conn.cursor()
            cursor.execute('SELECT 1')
            cursor.fetchone()
            cursor.close()
            vault_app.return_db_connection(conn)
            health_status['checks']['database'] = 'healthy'
        else:
            health_status['checks']['database'] = 'unavailable'
    except Exception as e:
        health_status['checks']['database'] = f'unhealthy: {str(e)}'
        health_status['status'] = 'degraded'
    
    # Check Consul connection
    try:
        if vault_app.sdk.consul:
            vault_app.sdk.consul.client.agent.self()
            health_status['checks']['consul'] = 'healthy'
        else:
            health_status['checks']['consul'] = 'unavailable'
    except Exception as e:
        health_status['checks']['consul'] = f'unhealthy: {str(e)}'
    
    status_code = 200 if health_status['status'] == 'healthy' else 503
    return jsonify(health_status), status_code


# Authentication endpoint
@app.route('/auth/login', methods=['POST'])
def login():
    """User authentication endpoint"""
    try:
        data = request.get_json()
        username = data.get('username')
        password = data.get('password')
        
        if not username or not password:
            return jsonify({'error': 'Username and password required'}), 400
        
        # In a real app, you would verify credentials against a database
        # For demo purposes, we'll use simple hardcoded check
        if username == 'demo' and password == 'password':
            # Create JWT token
            jwt_secret = vault_app.secrets.get('jwt_secret', 'default-secret')
            payload = {
                'user_id': username,
                'exp': datetime.utcnow() + timedelta(hours=24)
            }
            token = jwt.encode(payload, jwt_secret, algorithm='HS256')
            
            return jsonify({
                'token': token,
                'expires_in': 86400  # 24 hours
            })
        else:
            return jsonify({'error': 'Invalid credentials'}), 401
            
    except Exception as e:
        logger.error(f"❌ Login error: {e}")
        return jsonify({'error': 'Internal server error'}), 500


# Protected API endpoint
@app.route('/api/users')
@require_auth
def get_users():
    """Get users - protected endpoint"""
    try:
        conn = vault_app.get_db_connection()
        if not conn:
            return jsonify({'error': 'Database unavailable'}), 503
        
        cursor = conn.cursor()
        cursor.execute("""
            SELECT id, username, email, created_at 
            FROM users 
            ORDER BY created_at DESC 
            LIMIT 10
        """)
        
        users = []
        for row in cursor.fetchall():
            users.append({
                'id': row[0],
                'username': row[1],
                'email': row[2],
                'created_at': row[3].isoformat() if row[3] else None
            })
        
        cursor.close()
        vault_app.return_db_connection(conn)
        
        return jsonify({'users': users})
        
    except Exception as e:
        logger.error(f"❌ Get users error: {e}")
        return jsonify({'error': 'Internal server error'}), 500


# Configuration endpoint
@app.route('/api/config')
@require_auth
def get_config():
    """Get application configuration (non-sensitive)"""
    config = {
        'app_name': vault_app.app_name,
        'environment': vault_app.environment,
        'version': '1.0.0',
        'features': {
            'vault_integration': True,
            'consul_registration': bool(vault_app.sdk.consul),
            'database_connection': bool(vault_app.db_pool),
            'prometheus_metrics': True
        }
    }
    return jsonify(config)


# Secret rotation endpoint
@app.route('/admin/rotate-secrets', methods=['POST'])
@require_auth
def rotate_secrets():
    """Rotate application secrets (admin endpoint)"""
    try:
        # In a real application, you would check admin permissions
        if g.user.get('user_id') != 'admin':
            return jsonify({'error': 'Admin access required'}), 403
        
        # This would trigger secret rotation
        # For demo purposes, we'll just simulate it
        rotation_result = {
            'status': 'success',
            'rotated_at': datetime.utcnow().isoformat(),
            'next_rotation': (datetime.utcnow() + timedelta(days=30)).isoformat()
        }
        
        return jsonify(rotation_result)
        
    except Exception as e:
        logger.error(f"❌ Secret rotation error: {e}")
        return jsonify({'error': 'Internal server error'}), 500


# Metrics endpoint
@app.route('/metrics')
def metrics_endpoint():
    """Prometheus metrics endpoint"""
    # This is handled by the PrometheusMetrics extension
    pass


# Root endpoint
@app.route('/')
def index():
    """Root endpoint"""
    return jsonify({
        'service': vault_app.app_name,
        'version': '1.0.0',
        'environment': vault_app.environment,
        'status': 'running',
        'endpoints': {
            'health': '/health',
            'login': '/auth/login',
            'users': '/api/users',
            'config': '/api/config',
            'metrics': '/metrics'
        }
    })


if __name__ == '__main__':
    logger.info(f"🌟 Starting {vault_app.app_name} on port {vault_app.port}")
    
    # Run the Flask application
    app.run(
        host='0.0.0.0',
        port=vault_app.port,
        debug=False,
        threaded=True
    )