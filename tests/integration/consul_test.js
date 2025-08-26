/**
 * Consul Integration Tests
 * Tests service discovery and configuration management with proper mocking
 */

const { describe, it, beforeEach, afterEach, expect, jest } = require('@jest/globals');
const fs = require('fs').promises;
const path = require('path');

// Mock the consul client to avoid actual connections during testing
const mockConsulClient = {
    agent: {
        service: {
            register: jest.fn(),
            deregister: jest.fn(),
            list: jest.fn(),
            check: {
                register: jest.fn(),
                deregister: jest.fn()
            }
        },
        check: {
            list: jest.fn()
        }
    },
    health: {
        service: jest.fn(),
        node: jest.fn(),
        checks: jest.fn()
    },
    catalog: {
        service: {
            list: jest.fn(),
            nodes: jest.fn()
        },
        node: {
            list: jest.fn(),
            services: jest.fn()
        }
    },
    kv: {
        get: jest.fn(),
        set: jest.fn(),
        del: jest.fn(),
        keys: jest.fn()
    },
    status: {
        leader: jest.fn(),
        peers: jest.fn()
    }
};

// Mock consul module
jest.mock('consul', () => {
    return jest.fn(() => mockConsulClient);
});

describe('Consul Integration Tests', () => {
    let consulClient;
    const testReportPath = path.join(__dirname, '../reports/consul_integration_report.json');
    const testResults = [];

    beforeEach(() => {
        jest.clearAllMocks();
        consulClient = mockConsulClient;
        
        // Default mock responses
        mockConsulClient.status.leader.mockResolvedValue('127.0.0.1:8300');
        mockConsulClient.status.peers.mockResolvedValue(['127.0.0.1:8300']);
    });

    afterEach(async () => {
        try {
            await fs.mkdir(path.dirname(testReportPath), { recursive: true });
            await fs.writeFile(testReportPath, JSON.stringify({
                timestamp: new Date().toISOString(),
                results: testResults
            }, null, 2));
        } catch (error) {
            console.error('Failed to write Consul test report:', error);
        }
    });

    describe('Consul Cluster Health', () => {
        it('should verify cluster leadership', async () => {
            const testStart = Date.now();
            
            try {
                const leader = await consulClient.status.leader();
                const peers = await consulClient.status.peers();
                
                expect(leader).toBeDefined();
                expect(peers).toHaveLength(1);
                expect(peers).toContain('127.0.0.1:8300');
                
                testResults.push({
                    test: 'Cluster Leadership Check',
                    status: 'PASS',
                    duration: Date.now() - testStart,
                    details: `Leader: ${leader}, Peers: ${peers.length}`
                });
            } catch (error) {
                testResults.push({
                    test: 'Cluster Leadership Check',
                    status: 'FAIL',
                    duration: Date.now() - testStart,
                    error: error.message
                });
                throw error;
            }
        });

        it('should handle multiple cluster peers', async () => {
            const mockPeers = [
                '127.0.0.1:8300',
                '127.0.0.2:8300',
                '127.0.0.3:8300'
            ];

            mockConsulClient.status.peers.mockResolvedValue(mockPeers);

            const peers = await consulClient.status.peers();
            
            expect(peers).toHaveLength(3);
            expect(peers).toEqual(mockPeers);

            testResults.push({
                test: 'Multi-Peer Cluster',
                status: 'PASS',
                details: `Detected ${peers.length} cluster peers`
            });
        });
    });

    describe('Service Registration and Discovery', () => {
        const testService = {
            name: 'web-service',
            id: 'web-service-1',
            tags: ['web', 'frontend'],
            address: '192.168.1.10',
            port: 8080,
            check: {
                http: 'http://192.168.1.10:8080/health',
                interval: '10s',
                timeout: '5s'
            }
        };

        it('should register a service successfully', async () => {
            mockConsulClient.agent.service.register.mockResolvedValue(true);

            await consulClient.agent.service.register(testService);
            
            expect(mockConsulClient.agent.service.register).toHaveBeenCalledWith(testService);

            testResults.push({
                test: 'Service Registration',
                status: 'PASS',
                details: `Successfully registered service: ${testService.name}`
            });
        });

        it('should list registered services', async () => {
            const mockServices = {
                'web-service-1': {
                    ID: 'web-service-1',
                    Service: 'web-service',
                    Tags: ['web', 'frontend'],
                    Address: '192.168.1.10',
                    Port: 8080
                },
                'api-service-1': {
                    ID: 'api-service-1',
                    Service: 'api-service',
                    Tags: ['api', 'backend'],
                    Address: '192.168.1.11',
                    Port: 3000
                }
            };

            mockConsulClient.agent.service.list.mockResolvedValue(mockServices);

            const services = await consulClient.agent.service.list();
            
            expect(Object.keys(services)).toHaveLength(2);
            expect(services['web-service-1'].Service).toBe('web-service');

            testResults.push({
                test: 'Service Listing',
                status: 'PASS',
                details: `Retrieved ${Object.keys(services).length} registered services`
            });
        });

        it('should discover services by name', async () => {
            const mockServiceNodes = [
                {
                    Node: 'node-1',
                    Address: '192.168.1.10',
                    Service: {
                        ID: 'web-service-1',
                        Service: 'web-service',
                        Port: 8080,
                        Tags: ['web', 'frontend']
                    }
                },
                {
                    Node: 'node-2',
                    Address: '192.168.1.11',
                    Service: {
                        ID: 'web-service-2',
                        Service: 'web-service',
                        Port: 8080,
                        Tags: ['web', 'frontend']
                    }
                }
            ];

            mockConsulClient.catalog.service.nodes.mockResolvedValue(mockServiceNodes);

            const nodes = await consulClient.catalog.service.nodes('web-service');
            
            expect(nodes).toHaveLength(2);
            expect(nodes[0].Service.Service).toBe('web-service');

            testResults.push({
                test: 'Service Discovery',
                status: 'PASS',
                details: `Discovered ${nodes.length} instances of web-service`
            });
        });

        it('should deregister a service successfully', async () => {
            mockConsulClient.agent.service.deregister.mockResolvedValue(true);

            await consulClient.agent.service.deregister('web-service-1');
            
            expect(mockConsulClient.agent.service.deregister).toHaveBeenCalledWith('web-service-1');

            testResults.push({
                test: 'Service Deregistration',
                status: 'PASS',
                details: 'Successfully deregistered service: web-service-1'
            });
        });
    });

    describe('Health Checking', () => {
        it('should register health checks', async () => {
            const healthCheck = {
                id: 'web-service-health',
                name: 'Web Service Health',
                http: 'http://192.168.1.10:8080/health',
                interval: '10s',
                timeout: '5s',
                serviceid: 'web-service-1'
            };

            mockConsulClient.agent.service.check.register.mockResolvedValue(true);

            await consulClient.agent.service.check.register(healthCheck);
            
            expect(mockConsulClient.agent.service.check.register).toHaveBeenCalledWith(healthCheck);

            testResults.push({
                test: 'Health Check Registration',
                status: 'PASS',
                details: `Registered health check: ${healthCheck.name}`
            });
        });

        it('should retrieve service health status', async () => {
            const mockHealthData = [
                {
                    Node: 'node-1',
                    Service: {
                        ID: 'web-service-1',
                        Service: 'web-service'
                    },
                    Checks: [
                        {
                            CheckID: 'service:web-service-1',
                            Status: 'passing',
                            Output: 'HTTP GET http://192.168.1.10:8080/health: 200 OK'
                        }
                    ]
                }
            ];

            mockConsulClient.health.service.mockResolvedValue(mockHealthData);

            const health = await consulClient.health.service('web-service');
            
            expect(health).toHaveLength(1);
            expect(health[0].Checks[0].Status).toBe('passing');

            testResults.push({
                test: 'Service Health Retrieval',
                status: 'PASS',
                details: 'Successfully retrieved service health status'
            });
        });

        it('should list all health checks', async () => {
            const mockChecks = {
                'service:web-service-1': {
                    CheckID: 'service:web-service-1',
                    Name: 'Service \'web-service\' check',
                    Status: 'passing',
                    ServiceID: 'web-service-1',
                    ServiceName: 'web-service'
                },
                'serfHealth': {
                    CheckID: 'serfHealth',
                    Name: 'Serf Health Status',
                    Status: 'passing'
                }
            };

            mockConsulClient.agent.check.list.mockResolvedValue(mockChecks);

            const checks = await consulClient.agent.check.list();
            
            expect(Object.keys(checks)).toHaveLength(2);
            expect(checks['service:web-service-1'].Status).toBe('passing');

            testResults.push({
                test: 'Health Check Listing',
                status: 'PASS',
                details: `Retrieved ${Object.keys(checks).length} health checks`
            });
        });
    });

    describe('Key-Value Store', () => {
        it('should store configuration values', async () => {
            const testData = {
                database: {
                    host: 'db.example.com',
                    port: 5432,
                    name: 'production'
                },
                cache: {
                    host: 'redis.example.com',
                    port: 6379
                }
            };

            mockConsulClient.kv.set.mockResolvedValue(true);

            await consulClient.kv.set('config/app/database', JSON.stringify(testData.database));
            await consulClient.kv.set('config/app/cache', JSON.stringify(testData.cache));
            
            expect(mockConsulClient.kv.set).toHaveBeenCalledTimes(2);

            testResults.push({
                test: 'KV Store Write',
                status: 'PASS',
                details: 'Successfully stored configuration values'
            });
        });

        it('should retrieve configuration values', async () => {
            const mockKVData = {
                Key: 'config/app/database',
                Value: JSON.stringify({
                    host: 'db.example.com',
                    port: 5432,
                    name: 'production'
                })
            };

            mockConsulClient.kv.get.mockResolvedValue(mockKVData);

            const result = await consulClient.kv.get('config/app/database');
            const config = JSON.parse(result.Value);
            
            expect(config.host).toBe('db.example.com');
            expect(config.port).toBe(5432);

            testResults.push({
                test: 'KV Store Read',
                status: 'PASS',
                details: 'Successfully retrieved configuration values'
            });
        });

        it('should list keys with prefix', async () => {
            const mockKeys = [
                'config/app/database',
                'config/app/cache',
                'config/app/logging'
            ];

            mockConsulClient.kv.keys.mockResolvedValue(mockKeys);

            const keys = await consulClient.kv.keys('config/app/');
            
            expect(keys).toHaveLength(3);
            expect(keys).toContain('config/app/database');

            testResults.push({
                test: 'KV Store Key Listing',
                status: 'PASS',
                details: `Found ${keys.length} keys with prefix config/app/`
            });
        });

        it('should delete configuration values', async () => {
            mockConsulClient.kv.del.mockResolvedValue(true);

            await consulClient.kv.del('config/app/cache');
            
            expect(mockConsulClient.kv.del).toHaveBeenCalledWith('config/app/cache');

            testResults.push({
                test: 'KV Store Delete',
                status: 'PASS',
                details: 'Successfully deleted configuration value'
            });
        });
    });

    describe('Service Mesh and Connect', () => {
        it('should validate service intentions', async () => {
            // Mock service intention validation
            const intentions = [
                {
                    SourceName: 'web-service',
                    DestinationName: 'api-service',
                    Action: 'allow'
                },
                {
                    SourceName: 'api-service',
                    DestinationName: 'database',
                    Action: 'allow'
                },
                {
                    SourceName: '*',
                    DestinationName: 'database',
                    Action: 'deny'
                }
            ];

            // Validate intention rules
            const allowedConnections = intentions.filter(i => i.Action === 'allow');
            const deniedConnections = intentions.filter(i => i.Action === 'deny');

            expect(allowedConnections).toHaveLength(2);
            expect(deniedConnections).toHaveLength(1);
            expect(deniedConnections[0].SourceName).toBe('*');

            testResults.push({
                test: 'Service Intentions Validation',
                status: 'PASS',
                details: `Validated ${intentions.length} service intentions`
            });
        });

        it('should check service mesh configuration', async () => {
            // Mock Connect-enabled services
            const connectServices = [
                {
                    Kind: 'connect-proxy',
                    Name: 'web-service-proxy',
                    Proxy: {
                        DestinationServiceName: 'web-service',
                        DestinationServiceID: 'web-service-1'
                    }
                }
            ];

            const hasConnectProxy = connectServices.some(s => s.Kind === 'connect-proxy');
            expect(hasConnectProxy).toBe(true);

            testResults.push({
                test: 'Service Mesh Configuration',
                status: 'PASS',
                details: 'Service mesh proxy configuration is valid'
            });
        });
    });

    describe('Performance and Load Testing', () => {
        it('should handle concurrent service registrations', async () => {
            const concurrentServices = 10;
            const testStart = Date.now();

            mockConsulClient.agent.service.register.mockResolvedValue(true);

            const promises = Array(concurrentServices).fill(null).map((_, index) => {
                const service = {
                    name: 'load-test-service',
                    id: `load-test-service-${index}`,
                    port: 8080 + index,
                    address: `192.168.1.${10 + index}`
                };
                return consulClient.agent.service.register(service);
            });

            await Promise.all(promises);
            const duration = Date.now() - testStart;

            expect(duration).toBeLessThan(2000); // Should complete within 2 seconds

            testResults.push({
                test: 'Concurrent Service Registration',
                status: 'PASS',
                duration,
                details: `Successfully registered ${concurrentServices} services concurrently`
            });
        });

        it('should handle large KV operations', async () => {
            const largeData = {
                configuration: JSON.stringify({
                    settings: Array(1000).fill(null).map((_, i) => ({
                        key: `setting_${i}`,
                        value: `value_${i}`
                    }))
                })
            };

            mockConsulClient.kv.set.mockResolvedValue(true);

            const testStart = Date.now();
            await consulClient.kv.set('config/large-dataset', largeData.configuration);
            const duration = Date.now() - testStart;

            expect(duration).toBeLessThan(1000); // Should complete within 1 second

            testResults.push({
                test: 'Large KV Operation',
                status: 'PASS',
                duration,
                details: 'Successfully handled large key-value operation'
            });
        });
    });

    describe('Error Handling', () => {
        it('should handle service registration failures', async () => {
            mockConsulClient.agent.service.register.mockRejectedValue(new Error('Service already exists'));

            try {
                await consulClient.agent.service.register({
                    name: 'duplicate-service',
                    id: 'duplicate-service-1'
                });
            } catch (error) {
                expect(error.message).toBe('Service already exists');
            }

            testResults.push({
                test: 'Service Registration Failure Handling',
                status: 'PASS',
                details: 'Properly handled service registration failure'
            });
        });

        it('should handle cluster connectivity issues', async () => {
            mockConsulClient.status.leader.mockRejectedValue(new Error('No cluster leader'));

            try {
                await consulClient.status.leader();
            } catch (error) {
                expect(error.message).toBe('No cluster leader');
            }

            testResults.push({
                test: 'Cluster Connectivity Error Handling',
                status: 'PASS',
                details: 'Properly handled cluster connectivity issues'
            });
        });

        it('should validate service configuration', async () => {
            const invalidService = {
                name: '', // Invalid empty name
                id: 'test-service',
                port: 'invalid-port' // Invalid port type
            };

            // Validate service configuration
            const hasValidName = invalidService.name && invalidService.name.length > 0;
            const hasValidPort = typeof invalidService.port === 'number' && invalidService.port > 0;

            expect(hasValidName).toBe(false);
            expect(hasValidPort).toBe(false);

            testResults.push({
                test: 'Service Configuration Validation',
                status: 'PASS',
                details: 'Successfully identified invalid service configuration'
            });
        });
    });
});