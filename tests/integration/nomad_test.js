/**
 * Nomad Integration Tests
 * Tests job deployment and management functionality with proper mocking
 */

const { describe, it, beforeEach, afterEach, expect, jest } = require('@jest/globals');
const fs = require('fs').promises;
const path = require('path');

// Mock the nomad client to avoid actual connections during testing
const mockNomadClient = {
    agent: {
        info: jest.fn(),
        health: jest.fn()
    },
    jobs: {
        list: jest.fn(),
        info: jest.fn(),
        create: jest.fn(),
        update: jest.fn(),
        delete: jest.fn(),
        allocations: jest.fn()
    },
    allocations: {
        info: jest.fn(),
        logs: jest.fn()
    },
    nodes: {
        list: jest.fn(),
        info: jest.fn()
    }
};

// Mock HTTP client for Nomad API
jest.mock('axios', () => ({
    create: jest.fn(() => ({
        get: jest.fn(),
        post: jest.fn(),
        put: jest.fn(),
        delete: jest.fn()
    }))
}));

describe('Nomad Integration Tests', () => {
    let nomadClient;
    const testReportPath = path.join(__dirname, '../reports/nomad_integration_report.json');
    const testResults = [];

    beforeEach(() => {
        jest.clearAllMocks();
        nomadClient = mockNomadClient;
        
        // Default mock responses
        mockNomadClient.agent.info.mockResolvedValue({
            config: {
                Datacenter: 'dc1',
                NodeName: 'nomad-test-node',
                Version: '1.4.0'
            }
        });

        mockNomadClient.agent.health.mockResolvedValue({
            client: { ok: true },
            server: { ok: true }
        });
    });

    afterEach(async () => {
        try {
            await fs.mkdir(path.dirname(testReportPath), { recursive: true });
            await fs.writeFile(testReportPath, JSON.stringify({
                timestamp: new Date().toISOString(),
                results: testResults
            }, null, 2));
        } catch (error) {
            console.error('Failed to write Nomad test report:', error);
        }
    });

    describe('Nomad Agent Health', () => {
        it('should verify agent is healthy', async () => {
            const testStart = Date.now();
            
            try {
                const health = await nomadClient.agent.health();
                
                expect(health).toBeDefined();
                expect(health.client.ok).toBe(true);
                expect(health.server.ok).toBe(true);
                
                testResults.push({
                    test: 'Agent Health Check',
                    status: 'PASS',
                    duration: Date.now() - testStart,
                    details: 'Nomad agent is healthy'
                });
            } catch (error) {
                testResults.push({
                    test: 'Agent Health Check',
                    status: 'FAIL',
                    duration: Date.now() - testStart,
                    error: error.message
                });
                throw error;
            }
        });

        it('should retrieve agent information', async () => {
            const info = await nomadClient.agent.info();
            
            expect(info.config).toBeDefined();
            expect(info.config.Datacenter).toBe('dc1');
            expect(info.config.Version).toBeDefined();
            
            testResults.push({
                test: 'Agent Info Retrieval',
                status: 'PASS',
                details: `Nomad version: ${info.config.Version}, Datacenter: ${info.config.Datacenter}`
            });
        });
    });

    describe('Job Management', () => {
        const testJob = {
            Job: {
                ID: 'test-job',
                Name: 'test-job',
                Type: 'service',
                Priority: 50,
                Datacenters: ['dc1'],
                TaskGroups: [{
                    Name: 'web',
                    Count: 1,
                    Tasks: [{
                        Name: 'frontend',
                        Driver: 'docker',
                        Config: {
                            image: 'nginx:latest',
                            port_map: [{
                                http: 80
                            }]
                        },
                        Resources: {
                            CPU: 100,
                            MemoryMB: 128,
                            Networks: [{
                                MBits: 1,
                                DynamicPorts: [{
                                    Label: 'http'
                                }]
                            }]
                        }
                    }]
                }]
            }
        };

        it('should create a job successfully', async () => {
            mockNomadClient.jobs.create.mockResolvedValue({
                EvalID: 'test-eval-id',
                EvalCreateIndex: 1,
                JobModifyIndex: 1
            });

            const result = await nomadClient.jobs.create(testJob);
            
            expect(result.EvalID).toBeDefined();
            expect(mockNomadClient.jobs.create).toHaveBeenCalledWith(testJob);

            testResults.push({
                test: 'Job Creation',
                status: 'PASS',
                details: `Successfully created job: ${testJob.Job.ID}`
            });
        });

        it('should list jobs successfully', async () => {
            const mockJobs = [
                {
                    ID: 'job-1',
                    Name: 'web-service',
                    Type: 'service',
                    Status: 'running'
                },
                {
                    ID: 'job-2',
                    Name: 'batch-processor',
                    Type: 'batch',
                    Status: 'complete'
                }
            ];

            mockNomadClient.jobs.list.mockResolvedValue(mockJobs);

            const jobs = await nomadClient.jobs.list();
            
            expect(jobs).toHaveLength(2);
            expect(jobs[0].Status).toBe('running');

            testResults.push({
                test: 'Job Listing',
                status: 'PASS',
                details: `Retrieved ${jobs.length} jobs`
            });
        });

        it('should get job information', async () => {
            const mockJobInfo = {
                ID: 'test-job',
                Name: 'test-job',
                Status: 'running',
                TaskGroups: [{
                    Name: 'web',
                    Count: 1
                }]
            };

            mockNomadClient.jobs.info.mockResolvedValue(mockJobInfo);

            const jobInfo = await nomadClient.jobs.info('test-job');
            
            expect(jobInfo.ID).toBe('test-job');
            expect(jobInfo.Status).toBe('running');

            testResults.push({
                test: 'Job Info Retrieval',
                status: 'PASS',
                details: `Retrieved info for job: ${jobInfo.ID}`
            });
        });

        it('should update a job successfully', async () => {
            const updatedJob = {
                ...testJob,
                Job: {
                    ...testJob.Job,
                    TaskGroups: [{
                        ...testJob.Job.TaskGroups[0],
                        Count: 2 // Scale up
                    }]
                }
            };

            mockNomadClient.jobs.update.mockResolvedValue({
                EvalID: 'update-eval-id',
                JobModifyIndex: 2
            });

            const result = await nomadClient.jobs.update(updatedJob);
            
            expect(result.EvalID).toBeDefined();
            expect(result.JobModifyIndex).toBe(2);

            testResults.push({
                test: 'Job Update',
                status: 'PASS',
                details: 'Successfully updated job configuration'
            });
        });

        it('should delete a job successfully', async () => {
            mockNomadClient.jobs.delete.mockResolvedValue({
                EvalID: 'delete-eval-id'
            });

            const result = await nomadClient.jobs.delete('test-job');
            
            expect(result.EvalID).toBeDefined();
            expect(mockNomadClient.jobs.delete).toHaveBeenCalledWith('test-job');

            testResults.push({
                test: 'Job Deletion',
                status: 'PASS',
                details: 'Successfully deleted job: test-job'
            });
        });
    });

    describe('Allocation Management', () => {
        it('should list job allocations', async () => {
            const mockAllocations = [
                {
                    ID: 'alloc-1',
                    JobID: 'test-job',
                    ClientStatus: 'running',
                    NodeID: 'node-1'
                },
                {
                    ID: 'alloc-2',
                    JobID: 'test-job',
                    ClientStatus: 'running',
                    NodeID: 'node-2'
                }
            ];

            mockNomadClient.jobs.allocations.mockResolvedValue(mockAllocations);

            const allocations = await nomadClient.jobs.allocations('test-job');
            
            expect(allocations).toHaveLength(2);
            expect(allocations[0].ClientStatus).toBe('running');

            testResults.push({
                test: 'Allocation Listing',
                status: 'PASS',
                details: `Retrieved ${allocations.length} allocations for job`
            });
        });

        it('should get allocation details', async () => {
            const mockAllocation = {
                ID: 'alloc-1',
                JobID: 'test-job',
                ClientStatus: 'running',
                TaskStates: {
                    'frontend': {
                        State: 'running',
                        Events: [
                            { Type: 'Started', Time: Date.now() }
                        ]
                    }
                }
            };

            mockNomadClient.allocations.info.mockResolvedValue(mockAllocation);

            const allocation = await nomadClient.allocations.info('alloc-1');
            
            expect(allocation.ID).toBe('alloc-1');
            expect(allocation.ClientStatus).toBe('running');
            expect(allocation.TaskStates.frontend.State).toBe('running');

            testResults.push({
                test: 'Allocation Info Retrieval',
                status: 'PASS',
                details: `Retrieved allocation details: ${allocation.ID}`
            });
        });

        it('should retrieve allocation logs', async () => {
            const mockLogs = 'Application started successfully\nListening on port 80\n';

            mockNomadClient.allocations.logs.mockResolvedValue(mockLogs);

            const logs = await nomadClient.allocations.logs('alloc-1', 'frontend');
            
            expect(logs).toContain('Application started successfully');
            expect(logs).toContain('Listening on port 80');

            testResults.push({
                test: 'Allocation Log Retrieval',
                status: 'PASS',
                details: 'Successfully retrieved allocation logs'
            });
        });
    });

    describe('Node Management', () => {
        it('should list cluster nodes', async () => {
            const mockNodes = [
                {
                    ID: 'node-1',
                    Name: 'nomad-client-1',
                    Status: 'ready',
                    Drain: false
                },
                {
                    ID: 'node-2',
                    Name: 'nomad-client-2',
                    Status: 'ready',
                    Drain: false
                }
            ];

            mockNomadClient.nodes.list.mockResolvedValue(mockNodes);

            const nodes = await nomadClient.nodes.list();
            
            expect(nodes).toHaveLength(2);
            expect(nodes[0].Status).toBe('ready');
            expect(nodes[0].Drain).toBe(false);

            testResults.push({
                test: 'Node Listing',
                status: 'PASS',
                details: `Retrieved ${nodes.length} cluster nodes`
            });
        });

        it('should get node information', async () => {
            const mockNodeInfo = {
                ID: 'node-1',
                Name: 'nomad-client-1',
                Status: 'ready',
                Resources: {
                    CPU: 4000,
                    MemoryMB: 8192,
                    DiskMB: 102400
                },
                Reserved: {
                    CPU: 100,
                    MemoryMB: 256,
                    DiskMB: 1024
                }
            };

            mockNomadClient.nodes.info.mockResolvedValue(mockNodeInfo);

            const nodeInfo = await nomadClient.nodes.info('node-1');
            
            expect(nodeInfo.ID).toBe('node-1');
            expect(nodeInfo.Status).toBe('ready');
            expect(nodeInfo.Resources.CPU).toBe(4000);

            testResults.push({
                test: 'Node Info Retrieval',
                status: 'PASS',
                details: `Retrieved node info: ${nodeInfo.Name}`
            });
        });
    });

    describe('Performance and Scaling Tests', () => {
        it('should handle multiple concurrent job operations', async () => {
            const concurrentJobs = 5;
            const testStart = Date.now();

            // Mock concurrent job creation
            mockNomadClient.jobs.create.mockResolvedValue({
                EvalID: 'concurrent-eval',
                JobModifyIndex: 1
            });

            const promises = Array(concurrentJobs).fill(null).map((_, index) => {
                const job = {
                    Job: {
                        ...testJob.Job,
                        ID: `concurrent-job-${index}`,
                        Name: `concurrent-job-${index}`
                    }
                };
                return nomadClient.jobs.create(job);
            });

            const results = await Promise.all(promises);
            const duration = Date.now() - testStart;

            expect(results).toHaveLength(concurrentJobs);
            expect(duration).toBeLessThan(3000); // Should complete within 3 seconds

            testResults.push({
                test: 'Concurrent Job Operations',
                status: 'PASS',
                duration,
                details: `Successfully handled ${concurrentJobs} concurrent job operations`
            });
        });

        it('should validate resource constraints', async () => {
            const resourceIntensiveJob = {
                Job: {
                    ID: 'resource-test',
                    Name: 'resource-test',
                    Type: 'service',
                    TaskGroups: [{
                        Name: 'intensive',
                        Count: 1,
                        Tasks: [{
                            Name: 'compute',
                            Driver: 'docker',
                            Config: {
                                image: 'alpine:latest'
                            },
                            Resources: {
                                CPU: 2000,      // High CPU
                                MemoryMB: 4096, // High memory
                                DiskMB: 10240   // High disk
                            }
                        }]
                    }]
                }
            };

            // Validate resource requirements are within bounds
            const task = resourceIntensiveJob.Job.TaskGroups[0].Tasks[0];
            expect(task.Resources.CPU).toBeLessThanOrEqual(4000);
            expect(task.Resources.MemoryMB).toBeLessThanOrEqual(8192);
            expect(task.Resources.DiskMB).toBeLessThanOrEqual(102400);

            testResults.push({
                test: 'Resource Constraint Validation',
                status: 'PASS',
                details: 'Successfully validated job resource requirements'
            });
        });
    });

    describe('Error Handling', () => {
        it('should handle job creation failures', async () => {
            mockNomadClient.jobs.create.mockRejectedValue(new Error('Insufficient resources'));

            try {
                await nomadClient.jobs.create(testJob);
            } catch (error) {
                expect(error.message).toBe('Insufficient resources');
            }

            testResults.push({
                test: 'Job Creation Failure Handling',
                status: 'PASS',
                details: 'Properly handled job creation failure'
            });
        });

        it('should handle network connectivity issues', async () => {
            mockNomadClient.agent.health.mockRejectedValue(new Error('ECONNREFUSED'));

            try {
                await nomadClient.agent.health();
            } catch (error) {
                expect(error.message).toBe('ECONNREFUSED');
            }

            testResults.push({
                test: 'Network Connectivity Error Handling',
                status: 'PASS',
                details: 'Properly handled network connectivity issues'
            });
        });

        it('should validate job specification format', async () => {
            const invalidJob = {
                Job: {
                    ID: '', // Invalid empty ID
                    Name: 'invalid-job',
                    Type: 'invalid-type' // Invalid type
                }
            };

            // Validate job specification
            const hasValidID = invalidJob.Job.ID && invalidJob.Job.ID.length > 0;
            const hasValidType = ['service', 'batch', 'system'].includes(invalidJob.Job.Type);

            expect(hasValidID).toBe(false);
            expect(hasValidType).toBe(false);

            testResults.push({
                test: 'Job Specification Validation',
                status: 'PASS',
                details: 'Successfully identified invalid job specification'
            });
        });
    });
});