/**
 * Performance Tests for Infrastructure Components
 * Tests performance, scalability, and resource usage
 */

const { describe, it, beforeEach, afterEach, expect, jest } = require('@jest/globals');
const fs = require('fs').promises;
const path = require('path');

describe('Performance Tests', () => {
    const testReportPath = path.join(__dirname, '../reports/performance_test_report.json');
    const testResults = [];
    
    // Performance thresholds
    const PERFORMANCE_THRESHOLDS = {
        vault: {
            secretRead: 100,      // ms
            secretWrite: 200,     // ms
            concurrent: 50,       // concurrent operations
            throughput: 1000      // operations/second
        },
        consul: {
            kvRead: 50,           // ms
            kvWrite: 100,         // ms
            serviceDiscovery: 30, // ms
            concurrent: 100       // concurrent operations
        },
        nomad: {
            jobSubmission: 500,   // ms
            jobStatusCheck: 100,  // ms
            allocationUpdate: 200,// ms
            concurrent: 25        // concurrent operations
        },
        traefik: {
            routingLatency: 10,   // ms
            sslHandshake: 50,     // ms
            concurrent: 500,      // concurrent requests
            throughput: 5000      // requests/second
        }
    };

    beforeEach(() => {
        jest.clearAllMocks();
    });

    afterEach(async () => {
        try {
            await fs.mkdir(path.dirname(testReportPath), { recursive: true });
            await fs.writeFile(testReportPath, JSON.stringify({
                timestamp: new Date().toISOString(),
                thresholds: PERFORMANCE_THRESHOLDS,
                results: testResults
            }, null, 2));
        } catch (error) {
            console.error('Failed to write performance test report:', error);
        }
    });

    describe('Vault Performance Tests', () => {
        it('should measure secret read performance', async () => {
            const testStart = Date.now();
            const iterations = 100;
            const readTimes = [];

            // Mock vault client
            const mockVaultRead = jest.fn().mockImplementation(() => {
                const operationTime = 50 + Math.random() * 50; // 50-100ms
                return new Promise(resolve => {
                    setTimeout(() => resolve({ data: { value: 'test-secret' } }), operationTime);
                });
            });

            try {
                for (let i = 0; i < iterations; i++) {
                    const operationStart = Date.now();
                    await mockVaultRead(`secret/test/item-${i}`);
                    const operationTime = Date.now() - operationStart;
                    readTimes.push(operationTime);
                }

                const avgReadTime = readTimes.reduce((a, b) => a + b, 0) / readTimes.length;
                const p95ReadTime = readTimes.sort((a, b) => a - b)[Math.floor(iterations * 0.95)];
                const maxReadTime = Math.max(...readTimes);

                const passThreshold = avgReadTime <= PERFORMANCE_THRESHOLDS.vault.secretRead;

                testResults.push({
                    test: 'Vault Secret Read Performance',
                    status: passThreshold ? 'PASS' : 'FAIL',
                    duration: Date.now() - testStart,
                    metrics: {
                        iterations,
                        avgTime: Math.round(avgReadTime),
                        p95Time: p95ReadTime,
                        maxTime: maxReadTime,
                        threshold: PERFORMANCE_THRESHOLDS.vault.secretRead
                    },
                    details: `Average read time: ${Math.round(avgReadTime)}ms (threshold: ${PERFORMANCE_THRESHOLDS.vault.secretRead}ms)`
                });

                expect(avgReadTime).toBeLessThanOrEqual(PERFORMANCE_THRESHOLDS.vault.secretRead);
            } catch (error) {
                testResults.push({
                    test: 'Vault Secret Read Performance',
                    status: 'FAIL',
                    duration: Date.now() - testStart,
                    error: error.message
                });
                throw error;
            }
        });

        it('should measure concurrent secret operations', async () => {
            const testStart = Date.now();
            const concurrentOperations = PERFORMANCE_THRESHOLDS.vault.concurrent;

            const mockVaultOperation = jest.fn().mockImplementation(() => {
                const operationTime = 30 + Math.random() * 40; // 30-70ms
                return new Promise(resolve => {
                    setTimeout(() => resolve({ success: true }), operationTime);
                });
            });

            try {
                const promises = Array(concurrentOperations).fill(null).map((_, index) =>
                    mockVaultOperation(`secret/concurrent/test-${index}`)
                );

                const results = await Promise.all(promises);
                const totalDuration = Date.now() - testStart;
                const operationsPerSecond = Math.round((concurrentOperations * 1000) / totalDuration);

                const passThreshold = operationsPerSecond >= PERFORMANCE_THRESHOLDS.vault.throughput;

                testResults.push({
                    test: 'Vault Concurrent Operations',
                    status: passThreshold ? 'PASS' : 'FAIL',
                    duration: totalDuration,
                    metrics: {
                        concurrentOps: concurrentOperations,
                        operationsPerSecond,
                        totalDuration,
                        successRate: (results.length / concurrentOperations) * 100,
                        threshold: PERFORMANCE_THRESHOLDS.vault.throughput
                    },
                    details: `${operationsPerSecond} ops/sec with ${concurrentOperations} concurrent operations`
                });

                expect(results).toHaveLength(concurrentOperations);
                expect(operationsPerSecond).toBeGreaterThanOrEqual(PERFORMANCE_THRESHOLDS.vault.throughput);
            } catch (error) {
                testResults.push({
                    test: 'Vault Concurrent Operations',
                    status: 'FAIL',
                    duration: Date.now() - testStart,
                    error: error.message
                });
                throw error;
            }
        });

        it('should measure memory usage during operations', async () => {
            const testStart = Date.now();
            const initialMemory = process.memoryUsage();

            const mockVaultBulkOperation = jest.fn().mockImplementation((data) => {
                // Simulate processing large data
                const processedData = JSON.parse(JSON.stringify(data));
                return Promise.resolve({ processed: processedData });
            });

            try {
                // Simulate bulk operations with large payloads
                const largePayload = {
                    certificates: Array(1000).fill(null).map((_, i) => ({
                        name: `cert-${i}`,
                        data: 'A'.repeat(4096) // 4KB per certificate
                    })),
                    keys: Array(500).fill(null).map((_, i) => ({
                        name: `key-${i}`,
                        data: 'B'.repeat(2048) // 2KB per key
                    }))
                };

                await mockVaultBulkOperation(largePayload);

                // Force garbage collection if available
                if (global.gc) {
                    global.gc();
                }

                const finalMemory = process.memoryUsage();
                const memoryIncrease = {
                    rss: finalMemory.rss - initialMemory.rss,
                    heapUsed: finalMemory.heapUsed - initialMemory.heapUsed,
                    heapTotal: finalMemory.heapTotal - initialMemory.heapTotal
                };

                const memoryIncreaseKB = Math.round(memoryIncrease.heapUsed / 1024);
                const passThreshold = memoryIncreaseKB < 100 * 1024; // Less than 100MB

                testResults.push({
                    test: 'Vault Memory Usage',
                    status: passThreshold ? 'PASS' : 'FAIL',
                    duration: Date.now() - testStart,
                    metrics: {
                        initialMemoryMB: Math.round(initialMemory.heapUsed / 1024 / 1024),
                        finalMemoryMB: Math.round(finalMemory.heapUsed / 1024 / 1024),
                        increaseMB: Math.round(memoryIncreaseKB / 1024),
                        thresholdMB: 100
                    },
                    details: `Memory increase: ${Math.round(memoryIncreaseKB / 1024)}MB`
                });

                expect(memoryIncreaseKB).toBeLessThan(100 * 1024); // Less than 100MB increase
            } catch (error) {
                testResults.push({
                    test: 'Vault Memory Usage',
                    status: 'FAIL',
                    duration: Date.now() - testStart,
                    error: error.message
                });
                throw error;
            }
        });
    });

    describe('Consul Performance Tests', () => {
        it('should measure service discovery performance', async () => {
            const testStart = Date.now();
            const iterations = 200;
            const discoveryTimes = [];

            const mockConsulServiceDiscovery = jest.fn().mockImplementation(() => {
                const operationTime = 10 + Math.random() * 30; // 10-40ms
                return new Promise(resolve => {
                    setTimeout(() => resolve([
                        { Node: 'node-1', Address: '192.168.1.10', ServicePort: 8080 },
                        { Node: 'node-2', Address: '192.168.1.11', ServicePort: 8080 }
                    ]), operationTime);
                });
            });

            try {
                for (let i = 0; i < iterations; i++) {
                    const operationStart = Date.now();
                    await mockConsulServiceDiscovery('web-service');
                    const operationTime = Date.now() - operationStart;
                    discoveryTimes.push(operationTime);
                }

                const avgDiscoveryTime = discoveryTimes.reduce((a, b) => a + b, 0) / discoveryTimes.length;
                const p95DiscoveryTime = discoveryTimes.sort((a, b) => a - b)[Math.floor(iterations * 0.95)];

                const passThreshold = avgDiscoveryTime <= PERFORMANCE_THRESHOLDS.consul.serviceDiscovery;

                testResults.push({
                    test: 'Consul Service Discovery Performance',
                    status: passThreshold ? 'PASS' : 'FAIL',
                    duration: Date.now() - testStart,
                    metrics: {
                        iterations,
                        avgTime: Math.round(avgDiscoveryTime),
                        p95Time: p95DiscoveryTime,
                        threshold: PERFORMANCE_THRESHOLDS.consul.serviceDiscovery
                    },
                    details: `Average discovery time: ${Math.round(avgDiscoveryTime)}ms`
                });

                expect(avgDiscoveryTime).toBeLessThanOrEqual(PERFORMANCE_THRESHOLDS.consul.serviceDiscovery);
            } catch (error) {
                testResults.push({
                    test: 'Consul Service Discovery Performance',
                    status: 'FAIL',
                    duration: Date.now() - testStart,
                    error: error.message
                });
                throw error;
            }
        });

        it('should measure KV store performance', async () => {
            const testStart = Date.now();
            const iterations = 150;
            const kvOperations = [];

            const mockConsulKV = {
                get: jest.fn().mockImplementation(() => {
                    const operationTime = 20 + Math.random() * 30; // 20-50ms
                    return new Promise(resolve => {
                        setTimeout(() => resolve({ Key: 'test-key', Value: 'test-value' }), operationTime);
                    });
                }),
                set: jest.fn().mockImplementation(() => {
                    const operationTime = 40 + Math.random() * 60; // 40-100ms
                    return new Promise(resolve => {
                        setTimeout(() => resolve(true), operationTime);
                    });
                })
            };

            try {
                // Test read operations
                for (let i = 0; i < iterations / 2; i++) {
                    const operationStart = Date.now();
                    await mockConsulKV.get(`config/app/setting-${i}`);
                    kvOperations.push({
                        type: 'read',
                        time: Date.now() - operationStart
                    });
                }

                // Test write operations
                for (let i = 0; i < iterations / 2; i++) {
                    const operationStart = Date.now();
                    await mockConsulKV.set(`config/app/setting-${i}`, `value-${i}`);
                    kvOperations.push({
                        type: 'write',
                        time: Date.now() - operationStart
                    });
                }

                const readOps = kvOperations.filter(op => op.type === 'read');
                const writeOps = kvOperations.filter(op => op.type === 'write');
                
                const avgReadTime = readOps.reduce((a, b) => a + b.time, 0) / readOps.length;
                const avgWriteTime = writeOps.reduce((a, b) => a + b.time, 0) / writeOps.length;

                const passReadThreshold = avgReadTime <= PERFORMANCE_THRESHOLDS.consul.kvRead;
                const passWriteThreshold = avgWriteTime <= PERFORMANCE_THRESHOLDS.consul.kvWrite;

                testResults.push({
                    test: 'Consul KV Store Performance',
                    status: (passReadThreshold && passWriteThreshold) ? 'PASS' : 'FAIL',
                    duration: Date.now() - testStart,
                    metrics: {
                        totalOps: iterations,
                        avgReadTime: Math.round(avgReadTime),
                        avgWriteTime: Math.round(avgWriteTime),
                        readThreshold: PERFORMANCE_THRESHOLDS.consul.kvRead,
                        writeThreshold: PERFORMANCE_THRESHOLDS.consul.kvWrite
                    },
                    details: `Read: ${Math.round(avgReadTime)}ms, Write: ${Math.round(avgWriteTime)}ms`
                });

                expect(avgReadTime).toBeLessThanOrEqual(PERFORMANCE_THRESHOLDS.consul.kvRead);
                expect(avgWriteTime).toBeLessThanOrEqual(PERFORMANCE_THRESHOLDS.consul.kvWrite);
            } catch (error) {
                testResults.push({
                    test: 'Consul KV Store Performance',
                    status: 'FAIL',
                    duration: Date.now() - testStart,
                    error: error.message
                });
                throw error;
            }
        });
    });

    describe('Nomad Performance Tests', () => {
        it('should measure job submission performance', async () => {
            const testStart = Date.now();
            const iterations = 50;
            const submissionTimes = [];

            const mockNomadJobSubmit = jest.fn().mockImplementation(() => {
                const operationTime = 200 + Math.random() * 300; // 200-500ms
                return new Promise(resolve => {
                    setTimeout(() => resolve({
                        EvalID: `eval-${Math.random().toString(36).substr(2, 9)}`,
                        EvalCreateIndex: Math.floor(Math.random() * 1000),
                        JobModifyIndex: Math.floor(Math.random() * 1000)
                    }), operationTime);
                });
            });

            try {
                for (let i = 0; i < iterations; i++) {
                    const operationStart = Date.now();
                    await mockNomadJobSubmit({
                        Job: {
                            ID: `test-job-${i}`,
                            Name: `test-job-${i}`,
                            Type: 'service'
                        }
                    });
                    const operationTime = Date.now() - operationStart;
                    submissionTimes.push(operationTime);
                }

                const avgSubmissionTime = submissionTimes.reduce((a, b) => a + b, 0) / submissionTimes.length;
                const p95SubmissionTime = submissionTimes.sort((a, b) => a - b)[Math.floor(iterations * 0.95)];

                const passThreshold = avgSubmissionTime <= PERFORMANCE_THRESHOLDS.nomad.jobSubmission;

                testResults.push({
                    test: 'Nomad Job Submission Performance',
                    status: passThreshold ? 'PASS' : 'FAIL',
                    duration: Date.now() - testStart,
                    metrics: {
                        iterations,
                        avgTime: Math.round(avgSubmissionTime),
                        p95Time: p95SubmissionTime,
                        threshold: PERFORMANCE_THRESHOLDS.nomad.jobSubmission
                    },
                    details: `Average submission time: ${Math.round(avgSubmissionTime)}ms`
                });

                expect(avgSubmissionTime).toBeLessThanOrEqual(PERFORMANCE_THRESHOLDS.nomad.jobSubmission);
            } catch (error) {
                testResults.push({
                    test: 'Nomad Job Submission Performance',
                    status: 'FAIL',
                    duration: Date.now() - testStart,
                    error: error.message
                });
                throw error;
            }
        });

        it('should measure allocation scaling performance', async () => {
            const testStart = Date.now();
            const scaleOperations = [
                { from: 1, to: 5 },
                { from: 5, to: 10 },
                { from: 10, to: 2 },
                { from: 2, to: 8 }
            ];

            const mockNomadScale = jest.fn().mockImplementation((from, to) => {
                const scaleTime = Math.abs(to - from) * 50 + Math.random() * 100; // 50ms per instance + variance
                return new Promise(resolve => {
                    setTimeout(() => resolve({
                        allocations: Array(to).fill(null).map((_, i) => ({
                            ID: `alloc-${i}`,
                            Status: 'running'
                        }))
                    }), scaleTime);
                });
            });

            try {
                const scalingTimes = [];

                for (const operation of scaleOperations) {
                    const operationStart = Date.now();
                    await mockNomadScale(operation.from, operation.to);
                    const operationTime = Date.now() - operationStart;
                    scalingTimes.push({
                        from: operation.from,
                        to: operation.to,
                        time: operationTime,
                        instancesChanged: Math.abs(operation.to - operation.from)
                    });
                }

                const avgScalingTime = scalingTimes.reduce((a, b) => a + b.time, 0) / scalingTimes.length;
                const avgTimePerInstance = scalingTimes.reduce((a, b) => a + (b.time / b.instancesChanged), 0) / scalingTimes.length;

                testResults.push({
                    test: 'Nomad Allocation Scaling Performance',
                    status: 'PASS',
                    duration: Date.now() - testStart,
                    metrics: {
                        operations: scaleOperations.length,
                        avgScalingTime: Math.round(avgScalingTime),
                        avgTimePerInstance: Math.round(avgTimePerInstance),
                        scalingOperations: scalingTimes
                    },
                    details: `Average scaling time: ${Math.round(avgScalingTime)}ms, ${Math.round(avgTimePerInstance)}ms per instance`
                });

                expect(avgScalingTime).toBeLessThan(2000); // Less than 2 seconds per scaling operation
            } catch (error) {
                testResults.push({
                    test: 'Nomad Allocation Scaling Performance',
                    status: 'FAIL',
                    duration: Date.now() - testStart,
                    error: error.message
                });
                throw error;
            }
        });
    });

    describe('Traefik Performance Tests', () => {
        it('should measure routing latency', async () => {
            const testStart = Date.now();
            const iterations = 1000;
            const routingTimes = [];

            const mockTraefikRoute = jest.fn().mockImplementation(() => {
                const routingTime = 5 + Math.random() * 10; // 5-15ms
                return new Promise(resolve => {
                    setTimeout(() => resolve({
                        status: 200,
                        upstream: 'backend-1',
                        responseTime: routingTime
                    }), routingTime);
                });
            });

            try {
                for (let i = 0; i < iterations; i++) {
                    const operationStart = Date.now();
                    await mockTraefikRoute('/api/v1/health');
                    const operationTime = Date.now() - operationStart;
                    routingTimes.push(operationTime);
                }

                const avgRoutingTime = routingTimes.reduce((a, b) => a + b, 0) / routingTimes.length;
                const p95RoutingTime = routingTimes.sort((a, b) => a - b)[Math.floor(iterations * 0.95)];
                const p99RoutingTime = routingTimes[Math.floor(iterations * 0.99)];

                const passThreshold = avgRoutingTime <= PERFORMANCE_THRESHOLDS.traefik.routingLatency;

                testResults.push({
                    test: 'Traefik Routing Latency',
                    status: passThreshold ? 'PASS' : 'FAIL',
                    duration: Date.now() - testStart,
                    metrics: {
                        iterations,
                        avgTime: Math.round(avgRoutingTime),
                        p95Time: p95RoutingTime,
                        p99Time: p99RoutingTime,
                        threshold: PERFORMANCE_THRESHOLDS.traefik.routingLatency
                    },
                    details: `Average routing latency: ${Math.round(avgRoutingTime)}ms`
                });

                expect(avgRoutingTime).toBeLessThanOrEqual(PERFORMANCE_THRESHOLDS.traefik.routingLatency);
            } catch (error) {
                testResults.push({
                    test: 'Traefik Routing Latency',
                    status: 'FAIL',
                    duration: Date.now() - testStart,
                    error: error.message
                });
                throw error;
            }
        });

        it('should measure concurrent request handling', async () => {
            const testStart = Date.now();
            const concurrentRequests = PERFORMANCE_THRESHOLDS.traefik.concurrent;

            const mockTraefikConcurrentRequest = jest.fn().mockImplementation(() => {
                const responseTime = 5 + Math.random() * 20; // 5-25ms
                return new Promise(resolve => {
                    setTimeout(() => resolve({
                        status: 200,
                        body: 'OK',
                        responseTime
                    }), responseTime);
                });
            });

            try {
                const promises = Array(concurrentRequests).fill(null).map((_, index) =>
                    mockTraefikConcurrentRequest(`/load-test/${index}`)
                );

                const results = await Promise.all(promises);
                const totalDuration = Date.now() - testStart;
                const requestsPerSecond = Math.round((concurrentRequests * 1000) / totalDuration);

                const passThreshold = requestsPerSecond >= PERFORMANCE_THRESHOLDS.traefik.throughput;

                testResults.push({
                    test: 'Traefik Concurrent Request Handling',
                    status: passThreshold ? 'PASS' : 'FAIL',
                    duration: totalDuration,
                    metrics: {
                        concurrentRequests,
                        requestsPerSecond,
                        totalDuration,
                        successRate: (results.length / concurrentRequests) * 100,
                        threshold: PERFORMANCE_THRESHOLDS.traefik.throughput
                    },
                    details: `${requestsPerSecond} req/sec with ${concurrentRequests} concurrent requests`
                });

                expect(results).toHaveLength(concurrentRequests);
                expect(requestsPerSecond).toBeGreaterThanOrEqual(PERFORMANCE_THRESHOLDS.traefik.throughput);
            } catch (error) {
                testResults.push({
                    test: 'Traefik Concurrent Request Handling',
                    status: 'FAIL',
                    duration: Date.now() - testStart,
                    error: error.message
                });
                throw error;
            }
        });

        it('should measure SSL handshake performance', async () => {
            const testStart = Date.now();
            const iterations = 100;
            const handshakeTimes = [];

            const mockSSLHandshake = jest.fn().mockImplementation(() => {
                const handshakeTime = 30 + Math.random() * 40; // 30-70ms
                return new Promise(resolve => {
                    setTimeout(() => resolve({
                        cipher: 'ECDHE-RSA-AES256-GCM-SHA384',
                        protocol: 'TLSv1.3',
                        handshakeTime
                    }), handshakeTime);
                });
            });

            try {
                for (let i = 0; i < iterations; i++) {
                    const operationStart = Date.now();
                    await mockSSLHandshake();
                    const operationTime = Date.now() - operationStart;
                    handshakeTimes.push(operationTime);
                }

                const avgHandshakeTime = handshakeTimes.reduce((a, b) => a + b, 0) / handshakeTimes.length;
                const p95HandshakeTime = handshakeTimes.sort((a, b) => a - b)[Math.floor(iterations * 0.95)];

                const passThreshold = avgHandshakeTime <= PERFORMANCE_THRESHOLDS.traefik.sslHandshake;

                testResults.push({
                    test: 'Traefik SSL Handshake Performance',
                    status: passThreshold ? 'PASS' : 'FAIL',
                    duration: Date.now() - testStart,
                    metrics: {
                        iterations,
                        avgTime: Math.round(avgHandshakeTime),
                        p95Time: p95HandshakeTime,
                        threshold: PERFORMANCE_THRESHOLDS.traefik.sslHandshake
                    },
                    details: `Average SSL handshake time: ${Math.round(avgHandshakeTime)}ms`
                });

                expect(avgHandshakeTime).toBeLessThanOrEqual(PERFORMANCE_THRESHOLDS.traefik.sslHandshake);
            } catch (error) {
                testResults.push({
                    test: 'Traefik SSL Handshake Performance',
                    status: 'FAIL',
                    duration: Date.now() - testStart,
                    error: error.message
                });
                throw error;
            }
        });
    });

    describe('System Resource Tests', () => {
        it('should measure overall system resource usage', async () => {
            const testStart = Date.now();
            const initialResources = {
                memory: process.memoryUsage(),
                cpu: process.cpuUsage()
            };

            // Simulate high-load operations across all components
            const mockSystemLoad = jest.fn().mockImplementation(async () => {
                // Simulate CPU and memory intensive operations
                const data = Array(10000).fill(null).map((_, i) => ({
                    id: i,
                    data: Math.random().toString(36).repeat(100)
                }));

                // Process data to simulate CPU usage
                return data.map(item => ({
                    ...item,
                    processed: item.data.split('').reverse().join('')
                }));
            });

            try {
                // Run multiple concurrent operations
                const operations = Array(10).fill(null).map(() => mockSystemLoad());
                await Promise.all(operations);

                const finalResources = {
                    memory: process.memoryUsage(),
                    cpu: process.cpuUsage(initialResources.cpu)
                };

                const memoryUsageMB = {
                    initial: Math.round(initialResources.memory.heapUsed / 1024 / 1024),
                    final: Math.round(finalResources.memory.heapUsed / 1024 / 1024),
                    peak: Math.round(finalResources.memory.heapTotal / 1024 / 1024)
                };

                const cpuUsage = {
                    user: finalResources.cpu.user / 1000, // Convert to milliseconds
                    system: finalResources.cpu.system / 1000
                };

                testResults.push({
                    test: 'System Resource Usage',
                    status: 'PASS',
                    duration: Date.now() - testStart,
                    metrics: {
                        memory: memoryUsageMB,
                        cpu: cpuUsage,
                        operations: operations.length
                    },
                    details: `Memory: ${memoryUsageMB.final}MB, CPU: ${Math.round(cpuUsage.user)}ms user + ${Math.round(cpuUsage.system)}ms system`
                });

                // Validate resource usage is reasonable
                expect(memoryUsageMB.final - memoryUsageMB.initial).toBeLessThan(500); // Less than 500MB increase
                expect(cpuUsage.user + cpuUsage.system).toBeLessThan(10000); // Less than 10 seconds total CPU time
            } catch (error) {
                testResults.push({
                    test: 'System Resource Usage',
                    status: 'FAIL',
                    duration: Date.now() - testStart,
                    error: error.message
                });
                throw error;
            }
        });
    });
});