/**
 * Vault Infrastructure Integration SDK for JavaScript/Node.js
 * 
 * A comprehensive SDK for integrating JavaScript applications with the Vault infrastructure
 * including Vault, Consul, Nomad, and Prometheus services.
 * 
 * @author Vault Integration Team
 * @version 1.0.0
 */

const axios = require('axios');
const https = require('https');
const fs = require('fs');
const path = require('path');
const EventEmitter = require('events');
const winston = require('winston');

// Setup logging
const logger = winston.createLogger({
    level: 'info',
    format: winston.format.combine(
        winston.format.timestamp(),
        winston.format.errors({ stack: true }),
        winston.format.json()
    ),
    transports: [
        new winston.transports.Console({
            format: winston.format.simple()
        })
    ]
});

/**
 * Service configuration class
 */
class ServiceConfig {
    constructor({
        host,
        port,
        protocol = 'https',
        token = null,
        caCert = null,
        verifySsl = true,
        timeout = 30000
    }) {
        this.host = host;
        this.port = port;
        this.protocol = protocol;
        this.token = token;
        this.caCert = caCert;
        this.verifySsl = verifySsl;
        this.timeout = timeout;
    }

    get url() {
        return `${this.protocol}://${this.host}:${this.port}`;
    }

    get httpAgent() {
        if (this.protocol === 'https') {
            const agentOptions = {
                rejectUnauthorized: this.verifySsl
            };
            
            if (this.caCert) {
                agentOptions.ca = fs.readFileSync(this.caCert);
            }
            
            return new https.Agent(agentOptions);
        }
        return null;
    }
}

/**
 * Enhanced Vault client
 */
class VaultClient extends EventEmitter {
    constructor(config) {
        super();
        this.config = config;
        this.token = config.token;
        this.setupAxiosInstance();
    }

    setupAxiosInstance() {
        this.axios = axios.create({
            baseURL: this.config.url,
            timeout: this.config.timeout,
            httpsAgent: this.config.httpAgent
        });

        // Add token to requests
        this.axios.interceptors.request.use(config => {
            if (this.token) {
                config.headers['X-Vault-Token'] = this.token;
            }
            return config;
        });

        // Handle responses and errors
        this.axios.interceptors.response.use(
            response => response,
            error => {
                this.emit('error', error);
                return Promise.reject(error);
            }
        );
    }

    /**
     * Authenticate using AppRole method
     */
    async authenticateAppRole(roleId, secretId) {
        try {
            const response = await this.axios.post('/v1/auth/approle/login', {
                role_id: roleId,
                secret_id: secretId
            });
            
            this.token = response.data.auth.client_token;
            this.setupAxiosInstance(); // Refresh with new token
            
            logger.info('Successfully authenticated with AppRole');
            this.emit('authenticated', response.data);
            
            return response.data;
        } catch (error) {
            logger.error('AppRole authentication failed:', error.message);
            throw error;
        }
    }

    /**
     * Retrieve secret from Vault
     */
    async getSecret(path, mountPoint = 'secret') {
        try {
            const response = await this.axios.get(`/v1/${mountPoint}/data/${path}`);
            return response.data.data.data;
        } catch (error) {
            logger.error(`Failed to retrieve secret from ${path}:`, error.message);
            return null;
        }
    }

    /**
     * Write secret to Vault
     */
    async writeSecret(path, secretData, mountPoint = 'secret') {
        try {
            await this.axios.post(`/v1/${mountPoint}/data/${path}`, {
                data: secretData
            });
            
            logger.info(`Successfully wrote secret to ${path}`);
            return true;
        } catch (error) {
            logger.error(`Failed to write secret to ${path}:`, error.message);
            return false;
        }
    }

    /**
     * Configure database dynamic secrets engine
     */
    async setupDatabaseDynamicSecrets(dbConfig) {
        try {
            // Enable database secrets engine
            await this.axios.post('/v1/sys/mounts/database', {
                type: 'database'
            });

            // Configure database connection
            await this.axios.post(`/v1/database/config/${dbConfig.name}`, {
                plugin_name: dbConfig.plugin || 'mysql-database-plugin',
                connection_url: dbConfig.connectionUrl,
                allowed_roles: dbConfig.allowedRoles || [],
                username: dbConfig.username,
                password: dbConfig.password
            });

            logger.info(`Database secrets engine configured for ${dbConfig.name}`);
            return true;
        } catch (error) {
            logger.error('Failed to setup database secrets:', error.message);
            return false;
        }
    }

    /**
     * Generate dynamic database credentials
     */
    async getDatabaseCredentials(roleName) {
        try {
            const response = await this.axios.get(`/v1/database/creds/${roleName}`);
            return {
                username: response.data.data.username,
                password: response.data.data.password,
                leaseId: response.data.lease_id,
                leaseDuration: response.data.lease_duration
            };
        } catch (error) {
            logger.error('Failed to generate database credentials:', error.message);
            return null;
        }
    }

    /**
     * Renew the current token
     */
    async renewToken() {
        try {
            await this.axios.post('/v1/auth/token/renew-self');
            logger.info('Token renewed successfully');
            return true;
        } catch (error) {
            logger.error('Failed to renew token:', error.message);
            return false;
        }
    }

    /**
     * Setup auto-renewal for token
     */
    setupAutoRenewal(intervalMs = 300000) { // 5 minutes default
        this.renewalInterval = setInterval(async () => {
            try {
                await this.renewToken();
            } catch (error) {
                logger.error('Auto-renewal failed:', error.message);
                this.emit('renewalFailed', error);
            }
        }, intervalMs);
    }

    /**
     * Stop auto-renewal
     */
    stopAutoRenewal() {
        if (this.renewalInterval) {
            clearInterval(this.renewalInterval);
            this.renewalInterval = null;
        }
    }
}

/**
 * Enhanced Consul client
 */
class ConsulClient extends EventEmitter {
    constructor(config) {
        super();
        this.config = config;
        this.setupAxiosInstance();
    }

    setupAxiosInstance() {
        this.axios = axios.create({
            baseURL: this.config.url,
            timeout: this.config.timeout,
            httpsAgent: this.config.httpAgent
        });

        if (this.config.token) {
            this.axios.defaults.headers.common['X-Consul-Token'] = this.config.token;
        }
    }

    /**
     * Register a service with Consul
     */
    async registerService(serviceConfig) {
        try {
            const payload = {
                Name: serviceConfig.name,
                ID: serviceConfig.id,
                Address: serviceConfig.address,
                Port: serviceConfig.port,
                Tags: serviceConfig.tags || []
            };

            if (serviceConfig.healthCheckUrl) {
                payload.Check = {
                    HTTP: serviceConfig.healthCheckUrl,
                    Interval: serviceConfig.healthCheckInterval || '10s'
                };
            }

            await this.axios.put(`/v1/agent/service/register`, payload);
            
            logger.info(`Service ${serviceConfig.name} registered successfully`);
            this.emit('serviceRegistered', serviceConfig);
            
            return true;
        } catch (error) {
            logger.error('Failed to register service:', error.message);
            return false;
        }
    }

    /**
     * Discover service instances
     */
    async discoverService(serviceName) {
        try {
            const response = await this.axios.get(`/v1/health/service/${serviceName}?passing=true`);
            
            return response.data.map(service => ({
                id: service.Service.ID,
                address: service.Service.Address,
                port: service.Service.Port,
                tags: service.Service.Tags
            }));
        } catch (error) {
            logger.error(`Failed to discover service ${serviceName}:`, error.message);
            return [];
        }
    }

    /**
     * Get value from Consul KV store
     */
    async getKVValue(key) {
        try {
            const response = await this.axios.get(`/v1/kv/${key}`);
            if (response.data && response.data.length > 0) {
                return Buffer.from(response.data[0].Value, 'base64').toString('utf-8');
            }
            return null;
        } catch (error) {
            logger.error(`Failed to get KV value for ${key}:`, error.message);
            return null;
        }
    }

    /**
     * Set value in Consul KV store
     */
    async setKVValue(key, value) {
        try {
            await this.axios.put(`/v1/kv/${key}`, value);
            logger.info(`KV value set for ${key}`);
            return true;
        } catch (error) {
            logger.error(`Failed to set KV value for ${key}:`, error.message);
            return false;
        }
    }
}

/**
 * Enhanced Nomad client
 */
class NomadClient extends EventEmitter {
    constructor(config) {
        super();
        this.config = config;
        this.setupAxiosInstance();
    }

    setupAxiosInstance() {
        this.axios = axios.create({
            baseURL: this.config.url,
            timeout: this.config.timeout,
            httpsAgent: this.config.httpAgent
        });

        if (this.config.token) {
            this.axios.defaults.headers.common['X-Nomad-Token'] = this.config.token;
        }
    }

    /**
     * Submit a job to Nomad
     */
    async submitJob(jobSpec) {
        try {
            const response = await this.axios.post('/v1/jobs', {
                Job: jobSpec
            });
            
            logger.info(`Job ${jobSpec.ID} submitted successfully`);
            this.emit('jobSubmitted', { jobId: jobSpec.ID, response: response.data });
            
            return response.data;
        } catch (error) {
            logger.error('Failed to submit job:', error.message);
            throw error;
        }
    }

    /**
     * Get job status
     */
    async getJobStatus(jobId) {
        try {
            const response = await this.axios.get(`/v1/job/${jobId}`);
            return response.data;
        } catch (error) {
            logger.error('Failed to get job status:', error.message);
            throw error;
        }
    }

    /**
     * Stop a Nomad job
     */
    async stopJob(jobId, purge = false) {
        try {
            const params = purge ? '?purge=true' : '';
            const response = await this.axios.delete(`/v1/job/${jobId}${params}`);
            
            logger.info(`Job ${jobId} stopped successfully`);
            this.emit('jobStopped', { jobId, response: response.data });
            
            return response.data;
        } catch (error) {
            logger.error(`Failed to stop job ${jobId}:`, error.message);
            throw error;
        }
    }

    /**
     * Scale a job group
     */
    async scaleJob(jobId, groupName, count) {
        try {
            const payload = {
                Target: {
                    Group: groupName
                },
                Count: count
            };

            const response = await this.axios.post(`/v1/job/${jobId}/scale`, payload);
            
            logger.info(`Job ${jobId} group ${groupName} scaled to ${count}`);
            this.emit('jobScaled', { jobId, groupName, count, response: response.data });
            
            return response.data;
        } catch (error) {
            logger.error('Failed to scale job:', error.message);
            throw error;
        }
    }

    /**
     * Get job allocations
     */
    async getJobAllocations(jobId) {
        try {
            const response = await this.axios.get(`/v1/job/${jobId}/allocations`);
            return response.data;
        } catch (error) {
            logger.error(`Failed to get job allocations for ${jobId}:`, error.message);
            return [];
        }
    }
}

/**
 * Enhanced Prometheus client
 */
class PrometheusClient extends EventEmitter {
    constructor(config) {
        super();
        this.config = config;
        this.setupAxiosInstance();
    }

    setupAxiosInstance() {
        this.axios = axios.create({
            baseURL: this.config.url,
            timeout: this.config.timeout,
            httpsAgent: this.config.httpAgent
        });
    }

    /**
     * Query Prometheus for metrics
     */
    async queryMetric(query, timestamp = null) {
        try {
            const params = { query };
            if (timestamp) {
                params.time = timestamp;
            }

            const response = await this.axios.get('/api/v1/query', { params });
            return response.data;
        } catch (error) {
            logger.error('Failed to query metrics:', error.message);
            throw error;
        }
    }

    /**
     * Query Prometheus for metrics over a time range
     */
    async queryRange(query, start, end, step) {
        try {
            const params = {
                query,
                start,
                end,
                step
            };

            const response = await this.axios.get('/api/v1/query_range', { params });
            return response.data;
        } catch (error) {
            logger.error('Failed to query metrics range:', error.message);
            throw error;
        }
    }

    /**
     * Get current targets
     */
    async getTargets() {
        try {
            const response = await this.axios.get('/api/v1/targets');
            return response.data;
        } catch (error) {
            logger.error('Failed to get targets:', error.message);
            throw error;
        }
    }

    /**
     * Get alerts
     */
    async getAlerts() {
        try {
            const response = await this.axios.get('/api/v1/alerts');
            return response.data;
        } catch (error) {
            logger.error('Failed to get alerts:', error.message);
            throw error;
        }
    }
}

/**
 * Main SDK class orchestrating all services
 */
class VaultInfrastructureSDK extends EventEmitter {
    constructor(configFile = null, configObject = null) {
        super();
        
        let config;
        if (configFile) {
            config = JSON.parse(fs.readFileSync(configFile, 'utf-8'));
        } else if (configObject) {
            config = configObject;
        } else {
            config = this.loadEnvConfig();
        }

        // Initialize clients based on configuration
        this.vault = null;
        this.consul = null;
        this.nomad = null;
        this.prometheus = null;

        if (config.vault) {
            this.vault = new VaultClient(new ServiceConfig(config.vault));
            this.vault.on('error', (error) => this.emit('vaultError', error));
        }

        if (config.consul) {
            this.consul = new ConsulClient(new ServiceConfig(config.consul));
            this.consul.on('error', (error) => this.emit('consulError', error));
        }

        if (config.nomad) {
            this.nomad = new NomadClient(new ServiceConfig(config.nomad));
            this.nomad.on('error', (error) => this.emit('nomadError', error));
        }

        if (config.prometheus) {
            this.prometheus = new PrometheusClient(new ServiceConfig(config.prometheus));
            this.prometheus.on('error', (error) => this.emit('prometheusError', error));
        }
    }

    /**
     * Load configuration from environment variables
     */
    loadEnvConfig() {
        return {
            vault: {
                host: process.env.VAULT_ADDR || 'localhost',
                port: parseInt(process.env.VAULT_PORT || '8200'),
                token: process.env.VAULT_TOKEN,
                caCert: process.env.VAULT_CACERT,
                verifySsl: process.env.VAULT_SKIP_VERIFY !== 'true'
            },
            consul: {
                host: process.env.CONSUL_HOST || 'localhost',
                port: parseInt(process.env.CONSUL_PORT || '8500'),
                token: process.env.CONSUL_TOKEN,
                protocol: process.env.CONSUL_SCHEME || 'https'
            },
            nomad: {
                host: process.env.NOMAD_ADDR || 'localhost',
                port: parseInt(process.env.NOMAD_PORT || '4646'),
                token: process.env.NOMAD_TOKEN,
                protocol: process.env.NOMAD_SCHEME || 'https'
            },
            prometheus: {
                host: process.env.PROMETHEUS_HOST || 'localhost',
                port: parseInt(process.env.PROMETHEUS_PORT || '9090'),
                protocol: process.env.PROMETHEUS_SCHEME || 'https'
            }
        };
    }

    /**
     * Perform health checks on all configured services
     */
    async healthCheckAll() {
        const results = {};
        const promises = [];

        if (this.vault) {
            promises.push(
                this.vault.axios.get('/v1/sys/health')
                    .then(() => { results.vault = true; })
                    .catch(() => { results.vault = false; })
            );
        }

        if (this.consul) {
            promises.push(
                this.consul.axios.get('/v1/agent/self')
                    .then(() => { results.consul = true; })
                    .catch(() => { results.consul = false; })
            );
        }

        if (this.nomad) {
            promises.push(
                this.nomad.axios.get('/v1/status/leader')
                    .then(() => { results.nomad = true; })
                    .catch(() => { results.nomad = false; })
            );
        }

        if (this.prometheus) {
            promises.push(
                this.prometheus.axios.get('/-/ready')
                    .then(() => { results.prometheus = true; })
                    .catch(() => { results.prometheus = false; })
            );
        }

        await Promise.all(promises);
        return results;
    }

    /**
     * Setup application secrets in Vault with Consul service registration
     */
    async setupApplicationSecrets(appName, secrets) {
        if (!this.vault) {
            throw new Error('Vault client not configured');
        }

        // Store secrets in Vault
        const secretPath = `applications/${appName}`;
        const success = await this.vault.writeSecret(secretPath, secrets);
        
        if (!success) {
            return false;
        }

        // Register with Consul if available
        if (this.consul) {
            const serviceConfig = {
                name: `${appName}-secrets`,
                tags: ['secrets', 'vault-integrated']
            };
            await this.consul.registerService(serviceConfig);
        }

        logger.info(`Application secrets setup completed for ${appName}`);
        this.emit('secretsSetup', { appName, path: secretPath });
        
        return true;
    }

    /**
     * Deploy application with integrated secrets management
     */
    async deployApplication(jobSpec, secretsPath = null) {
        if (!this.nomad) {
            throw new Error('Nomad client not configured');
        }

        // Inject Vault integration if secrets path provided
        if (secretsPath && this.vault) {
            if (!jobSpec.TaskGroups) {
                jobSpec.TaskGroups = [];
            }

            jobSpec.TaskGroups.forEach(taskGroup => {
                if (!taskGroup.Tasks) return;

                taskGroup.Tasks.forEach(task => {
                    if (!task.Templates) {
                        task.Templates = [];
                    }

                    // Add secret template
                    task.Templates.push({
                        SourcePath: "",
                        DestPath: "secrets/app.env",
                        EmbeddedTmpl: `
{{ with secret "${secretsPath}" }}
{{ range $key, $value := .Data.data }}
{{ $key }}={{ $value }}
{{ end }}
{{ end }}
                        `.trim(),
                        ChangeMode: "restart"
                    });
                });
            });
        }

        const result = await this.nomad.submitJob(jobSpec);
        this.emit('applicationDeployed', { jobId: jobSpec.ID, secretsPath, result });
        
        return result;
    }
}

/**
 * Utility functions
 */

/**
 * Generate Vault policy HCL
 */
function createVaultPolicy(policyName, policyRules) {
    let policyContent = `# Policy: ${policyName}\n\n`;
    policyRules.forEach(rule => {
        policyContent += `${rule}\n`;
    });
    return policyContent;
}

/**
 * Create basic Nomad job template
 */
function createNomadJobTemplate(appName, image, port = 8080) {
    return {
        ID: appName,
        Name: appName,
        Type: "service",
        Priority: 50,
        TaskGroups: [
            {
                Name: `${appName}-group`,
                Count: 1,
                Tasks: [
                    {
                        Name: appName,
                        Driver: "docker",
                        Config: {
                            image: image,
                            port_map: [
                                { http: port }
                            ]
                        },
                        Services: [
                            {
                                Name: appName,
                                PortLabel: "http",
                                Checks: [
                                    {
                                        Name: "health",
                                        Type: "http",
                                        Path: "/health",
                                        Interval: 10000000000,
                                        Timeout: 2000000000
                                    }
                                ]
                            }
                        ],
                        Resources: {
                            CPU: 256,
                            MemoryMB: 512,
                            Networks: [
                                {
                                    ReservedPorts: [
                                        { Label: "http", Value: port }
                                    ]
                                }
                            ]
                        }
                    }
                ]
            }
        ]
    };
}

// Export classes and functions
module.exports = {
    VaultInfrastructureSDK,
    VaultClient,
    ConsulClient,
    NomadClient,
    PrometheusClient,
    ServiceConfig,
    createVaultPolicy,
    createNomadJobTemplate,
    logger
};

// Example usage
if (require.main === module) {
    // Example configuration
    const config = {
        vault: {
            host: 'vault.example.com',
            port: 8200,
            token: 'hvs.example-token'
        },
        consul: {
            host: 'consul.example.com',
            port: 8500,
            token: 'consul-token'
        },
        nomad: {
            host: 'nomad.example.com',
            port: 4646,
            token: 'nomad-token'
        },
        prometheus: {
            host: 'prometheus.example.com',
            port: 9090
        }
    };

    // Initialize SDK
    const sdk = new VaultInfrastructureSDK(null, config);

    // Example: Setup application with secrets
    const appSecrets = {
        database_url: 'postgresql://user:pass@db:5432/myapp',
        api_key: 'secret-api-key',
        encryption_key: '32-char-encryption-key-here!!'
    };

    (async () => {
        try {
            await sdk.setupApplicationSecrets('my-web-app', appSecrets);

            // Example: Deploy application
            const jobSpec = createNomadJobTemplate('my-web-app', 'nginx:latest', 8080);
            const deploymentResult = await sdk.deployApplication(
                jobSpec,
                'applications/my-web-app'
            );

            console.log('Deployment result:', deploymentResult);
        } catch (error) {
            console.error('Example failed:', error.message);
        }
    })();
}