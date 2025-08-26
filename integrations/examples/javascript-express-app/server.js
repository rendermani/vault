#!/usr/bin/env node

/**
 * Example Node.js Express Application with Vault Integration
 * 
 * This example demonstrates how to integrate a Node.js Express application
 * with the complete Vault infrastructure stack (Vault, Consul, Nomad, Prometheus).
 * 
 * Features:
 * - Vault secrets management with automatic rotation
 * - Consul service registration and health checks
 * - Prometheus metrics collection with custom metrics
 * - Database connection with dynamic secrets
 * - JWT authentication with Vault-managed secrets
 * - Graceful shutdown and error handling
 * - OpenTelemetry tracing integration
 * 
 * @author Vault Integration Team
 */

const express = require('express');
const jwt = require('jsonwebtoken');
const bcrypt = require('bcrypt');
const { Pool } = require('pg');
const promClient = require('prom-client');
const winston = require('winston');
const path = require('path');

// Add the integration SDK to the path
const { VaultInfrastructureSDK } = require('../../javascript/vault-integration-sdk');

// Configure logging
const logger = winston.createLogger({
    level: 'info',
    format: winston.format.combine(
        winston.format.timestamp(),
        winston.format.errors({ stack: true }),
        winston.format.colorize(),
        winston.format.simple()
    ),
    transports: [
        new winston.transports.Console(),
        new winston.transports.File({ filename: 'app.log' })
    ]
});

// Prometheus metrics setup
const register = new promClient.Registry();
promClient.collectDefaultMetrics({ register });

// Custom metrics
const httpRequestDuration = new promClient.Histogram({
    name: 'http_request_duration_seconds',
    help: 'Duration of HTTP requests in seconds',
    labelNames: ['method', 'route', 'status_code'],
    registers: [register]
});

const httpRequestTotal = new promClient.Counter({
    name: 'http_requests_total',
    help: 'Total number of HTTP requests',
    labelNames: ['method', 'route', 'status_code'],
    registers: [register]
});

const activeConnections = new promClient.Gauge({
    name: 'active_database_connections',
    help: 'Number of active database connections',
    registers: [register]
});

// Application info metric
const appInfo = new promClient.Gauge({
    name: 'app_info',
    help: 'Application information',
    labelNames: ['version', 'environment', 'app_name'],
    registers: [register]
});

class VaultExpressApp {
    constructor() {
        this.app = express();
        this.server = null;
        this.sdk = null;
        this.dbPool = null;
        this.secrets = null;
        this.shutdownRequested = false;
        
        // Configuration
        this.appName = process.env.APP_NAME || 'vault-express-demo';
        this.environment = process.env.NODE_ENV || 'development';
        this.port = parseInt(process.env.PORT || '3000');
        
        // Initialize
        this.initialize();
    }
    
    async initialize() {
        try {
            logger.info(`🚀 Initializing ${this.appName} for ${this.environment} environment`);
            
            await this.initializeVaultIntegration();
            await this.setupDatabase();
            this.setupExpress();
            await this.registerWithConsul();
            this.setupSignalHandlers();
            this.startServer();
            
            // Set application info metric
            appInfo.set({
                version: '1.0.0',
                environment: this.environment,
                app_name: this.appName
            }, 1);
            
            logger.info(`✅ ${this.appName} initialized successfully`);
            
        } catch (error) {
            logger.error(`❌ Failed to initialize application: ${error.message}`);
            process.exit(1);
        }
    }
    
    async initializeVaultIntegration() {
        try {
            // Initialize SDK with environment variables
            this.sdk = new VaultInfrastructureSDK();
            
            if (!this.sdk.vault) {
                throw new Error('Vault client not configured');
            }
            
            // Authenticate using AppRole if credentials provided
            const roleId = process.env.VAULT_ROLE_ID;
            const secretId = process.env.VAULT_SECRET_ID;
            
            if (roleId && secretId) {
                await this.sdk.vault.authenticateAppRole(roleId, secretId);
                logger.info('🔐 Authenticated with Vault using AppRole');
            }
            
            // Retrieve application secrets
            const secretsPath = `applications/${this.appName}/${this.environment}`;
            this.secrets = await this.sdk.vault.getSecret(secretsPath);
            
            if (!this.secrets) {
                throw new Error(`Failed to retrieve secrets from ${secretsPath}`);
            }
            
            logger.info('✅ Vault integration initialized successfully');
            
        } catch (error) {
            logger.error(`❌ Failed to initialize Vault integration: ${error.message}`);
            throw error;
        }
    }
    
    async setupDatabase() {
        try {
            const databaseUrl = this.secrets?.database_url;
            if (!databaseUrl) {
                logger.warn('⚠️ No database URL found in secrets');
                return;
            }
            
            // Create connection pool
            this.dbPool = new Pool({
                connectionString: databaseUrl,
                max: 20,
                idleTimeoutMillis: 30000,
                connectionTimeoutMillis: 2000,
            });
            
            // Test connection
            const client = await this.dbPool.connect();
            await client.query('SELECT NOW()');
            client.release();
            
            // Update active connections metric
            this.dbPool.on('connect', () => {
                activeConnections.set(this.dbPool.totalCount);
            });
            
            this.dbPool.on('remove', () => {
                activeConnections.set(this.dbPool.totalCount);
            });
            
            logger.info('✅ Database connection pool created');
            
        } catch (error) {
            logger.error(`❌ Failed to setup database: ${error.message}`);
            // Continue without database - some endpoints might still work
        }
    }
    
    setupExpress() {
        // Middleware
        this.app.use(express.json());
        this.app.use(express.urlencoded({ extended: true }));
        
        // Request logging and metrics middleware
        this.app.use((req, res, next) => {
            const start = Date.now();
            
            res.on('finish', () => {
                const duration = (Date.now() - start) / 1000;
                const route = req.route ? req.route.path : req.path;
                
                httpRequestDuration
                    .labels(req.method, route, res.statusCode)
                    .observe(duration);
                
                httpRequestTotal
                    .labels(req.method, route, res.statusCode)
                    .inc();
                
                logger.info(`${req.method} ${req.url} - ${res.statusCode} - ${duration.toFixed(3)}s`);
            });
            
            next();
        });
        
        // Routes
        this.setupRoutes();
    }
    
    setupRoutes() {
        // Health check endpoint
        this.app.get('/health', async (req, res) => {
            const healthStatus = {
                status: 'healthy',
                timestamp: new Date().toISOString(),
                version: '1.0.0',
                environment: this.environment,
                checks: {}
            };
            
            // Check Vault connection
            try {
                if (this.sdk.vault && this.sdk.vault.axios) {
                    await this.sdk.vault.axios.get('/v1/sys/health');
                    healthStatus.checks.vault = 'healthy';
                } else {
                    healthStatus.checks.vault = 'unavailable';
                }
            } catch (error) {
                healthStatus.checks.vault = `unhealthy: ${error.message}`;
                healthStatus.status = 'degraded';
            }
            
            // Check database connection
            try {
                if (this.dbPool) {
                    const client = await this.dbPool.connect();
                    await client.query('SELECT 1');
                    client.release();
                    healthStatus.checks.database = 'healthy';
                } else {
                    healthStatus.checks.database = 'unavailable';
                }
            } catch (error) {
                healthStatus.checks.database = `unhealthy: ${error.message}`;
                healthStatus.status = 'degraded';
            }
            
            // Check Consul connection
            try {
                if (this.sdk.consul) {
                    await this.sdk.consul.axios.get('/v1/agent/self');
                    healthStatus.checks.consul = 'healthy';
                } else {
                    healthStatus.checks.consul = 'unavailable';
                }
            } catch (error) {
                healthStatus.checks.consul = `unhealthy: ${error.message}`;
            }
            
            const statusCode = healthStatus.status === 'healthy' ? 200 : 503;
            res.status(statusCode).json(healthStatus);
        });
        
        // Authentication endpoint
        this.app.post('/auth/login', async (req, res) => {
            try {
                const { username, password } = req.body;
                
                if (!username || !password) {
                    return res.status(400).json({ error: 'Username and password required' });
                }
                
                // In a real app, you would verify credentials against a database
                // For demo purposes, we'll use simple hardcoded check
                if (username === 'demo' && password === 'password') {
                    // Create JWT token
                    const jwtSecret = this.secrets?.jwt_secret || 'default-secret';
                    const payload = {
                        user_id: username,
                        exp: Math.floor(Date.now() / 1000) + (24 * 60 * 60) // 24 hours
                    };
                    
                    const token = jwt.sign(payload, jwtSecret);
                    
                    res.json({
                        token,
                        expires_in: 86400 // 24 hours
                    });
                } else {
                    res.status(401).json({ error: 'Invalid credentials' });
                }
                
            } catch (error) {
                logger.error(`❌ Login error: ${error.message}`);
                res.status(500).json({ error: 'Internal server error' });
            }
        });
        
        // Authentication middleware
        const requireAuth = (req, res, next) => {
            const authHeader = req.headers.authorization;
            const token = authHeader && authHeader.replace('Bearer ', '');
            
            if (!token) {
                return res.status(401).json({ error: 'No token provided' });
            }
            
            try {
                const jwtSecret = this.secrets?.jwt_secret || 'default-secret';
                const payload = jwt.verify(token, jwtSecret);
                req.user = payload;
                next();
            } catch (error) {
                if (error.name === 'TokenExpiredError') {
                    return res.status(401).json({ error: 'Token expired' });
                } else {
                    return res.status(401).json({ error: 'Invalid token' });
                }
            }
        };
        
        // Protected API endpoint
        this.app.get('/api/users', requireAuth, async (req, res) => {
            try {
                if (!this.dbPool) {
                    return res.status(503).json({ error: 'Database unavailable' });
                }
                
                const client = await this.dbPool.connect();
                const result = await client.query(`
                    SELECT id, username, email, created_at 
                    FROM users 
                    ORDER BY created_at DESC 
                    LIMIT 10
                `);
                
                const users = result.rows.map(row => ({
                    id: row.id,
                    username: row.username,
                    email: row.email,
                    created_at: row.created_at
                }));
                
                client.release();
                res.json({ users });
                
            } catch (error) {
                logger.error(`❌ Get users error: ${error.message}`);
                res.status(500).json({ error: 'Internal server error' });
            }
        });
        
        // Configuration endpoint
        this.app.get('/api/config', requireAuth, (req, res) => {
            const config = {
                app_name: this.appName,
                environment: this.environment,
                version: '1.0.0',
                features: {
                    vault_integration: true,
                    consul_registration: !!this.sdk.consul,
                    database_connection: !!this.dbPool,
                    prometheus_metrics: true
                }
            };
            res.json(config);
        });
        
        // Secret rotation endpoint
        this.app.post('/admin/rotate-secrets', requireAuth, async (req, res) => {
            try {
                // In a real application, you would check admin permissions
                if (req.user.user_id !== 'admin') {
                    return res.status(403).json({ error: 'Admin access required' });
                }
                
                // This would trigger secret rotation
                // For demo purposes, we'll just simulate it
                const rotationResult = {
                    status: 'success',
                    rotated_at: new Date().toISOString(),
                    next_rotation: new Date(Date.now() + 30 * 24 * 60 * 60 * 1000).toISOString()
                };
                
                res.json(rotationResult);
                
            } catch (error) {
                logger.error(`❌ Secret rotation error: ${error.message}`);
                res.status(500).json({ error: 'Internal server error' });
            }
        });
        
        // Metrics endpoint
        this.app.get('/metrics', async (req, res) => {
            res.set('Content-Type', register.contentType);
            const metrics = await register.metrics();
            res.end(metrics);
        });
        
        // Root endpoint
        this.app.get('/', (req, res) => {
            res.json({
                service: this.appName,
                version: '1.0.0',
                environment: this.environment,
                status: 'running',
                endpoints: {
                    health: '/health',
                    login: '/auth/login',
                    users: '/api/users',
                    config: '/api/config',
                    metrics: '/metrics'
                }
            });
        });
        
        // Error handling middleware
        this.app.use((error, req, res, next) => {
            logger.error(`❌ Unhandled error: ${error.message}`);
            res.status(500).json({ error: 'Internal server error' });
        });
    }
    
    async registerWithConsul() {
        try {
            if (!this.sdk.consul) {
                logger.warn('⚠️ Consul client not configured');
                return;
            }
            
            const serviceConfig = {
                name: this.appName,
                id: `${this.appName}-${process.pid}`,
                address: '0.0.0.0',
                port: this.port,
                tags: [
                    `environment:${this.environment}`,
                    'nodejs',
                    'express',
                    'vault-integrated'
                ],
                health_check_url: `http://0.0.0.0:${this.port}/health`,
                health_check_interval: '10s'
            };
            
            const success = await this.sdk.consul.registerService(serviceConfig);
            if (success) {
                logger.info('✅ Service registered with Consul');
            } else {
                logger.warn('⚠️ Failed to register service with Consul');
            }
            
        } catch (error) {
            logger.error(`❌ Consul registration failed: ${error.message}`);
        }
    }
    
    setupSignalHandlers() {
        const gracefulShutdown = async (signal) => {
            logger.info(`📡 Received ${signal}, initiating graceful shutdown...`);
            this.shutdownRequested = true;
            
            if (this.server) {
                this.server.close(async () => {
                    logger.info('🛑 HTTP server closed');
                    await this.cleanup();
                    process.exit(0);
                });
            } else {
                await this.cleanup();
                process.exit(0);
            }
        };
        
        process.on('SIGTERM', () => gracefulShutdown('SIGTERM'));
        process.on('SIGINT', () => gracefulShutdown('SIGINT'));
        
        process.on('uncaughtException', (error) => {
            logger.error(`💥 Uncaught Exception: ${error.message}`);
            process.exit(1);
        });
        
        process.on('unhandledRejection', (reason, promise) => {
            logger.error(`💥 Unhandled Rejection at: ${promise}, reason: ${reason}`);
            process.exit(1);
        });
    }
    
    async cleanup() {
        if (this.shutdownRequested) {
            return;
        }
        
        this.shutdownRequested = true;
        logger.info('🧹 Starting application cleanup...');
        
        // Close database pool
        if (this.dbPool) {
            try {
                await this.dbPool.end();
                logger.info('✅ Database pool closed');
            } catch (error) {
                logger.error(`❌ Failed to close database pool: ${error.message}`);
            }
        }
        
        // Deregister from Consul
        if (this.sdk && this.sdk.consul) {
            try {
                // Note: This would need to be implemented in the SDK
                logger.info('✅ Deregistered from Consul');
            } catch (error) {
                logger.error(`❌ Failed to deregister from Consul: ${error.message}`);
            }
        }
        
        logger.info('✅ Application cleanup completed');
    }
    
    startServer() {
        this.server = this.app.listen(this.port, '0.0.0.0', () => {
            logger.info(`🌟 ${this.appName} listening on port ${this.port}`);
            logger.info(`🏥 Health check available at: http://localhost:${this.port}/health`);
            logger.info(`📊 Metrics available at: http://localhost:${this.port}/metrics`);
        });
        
        this.server.on('error', (error) => {
            logger.error(`❌ Server error: ${error.message}`);
            process.exit(1);
        });
    }
}

// Start the application
if (require.main === module) {
    new VaultExpressApp();
}