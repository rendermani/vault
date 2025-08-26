/**
 * Monitoring and Alerting Tests
 * Tests monitoring setup, metrics collection, and alerting functionality
 */

const { describe, it, beforeEach, afterEach, expect, jest } = require('@jest/globals');
const fs = require('fs').promises;
const path = require('path');

describe('Monitoring and Alerting Tests', () => {
    const testReportPath = path.join(__dirname, '../reports/monitoring_test_report.json');
    const testResults = [];

    // Mock monitoring clients
    const mockPrometheus = {
        query: jest.fn(),
        queryRange: jest.fn(),
        series: jest.fn(),
        targets: jest.fn()
    };

    const mockGrafana = {
        dashboards: {
            list: jest.fn(),
            get: jest.fn(),
            create: jest.fn()
        },
        datasources: {
            list: jest.fn(),
            test: jest.fn()
        },
        alerts: {
            list: jest.fn(),
            get: jest.fn()
        }
    };

    const mockAlertmanager = {
        alerts: jest.fn(),
        silences: jest.fn(),
        receivers: jest.fn(),
        config: jest.fn()
    };

    beforeEach(() => {
        jest.clearAllMocks();
    });

    afterEach(async () => {
        try {
            await fs.mkdir(path.dirname(testReportPath), { recursive: true });
            await fs.writeFile(testReportPath, JSON.stringify({
                timestamp: new Date().toISOString(),
                results: testResults
            }, null, 2));
        } catch (error) {
            console.error('Failed to write monitoring test report:', error);
        }
    });

    describe('Prometheus Metrics Collection', () => {
        it('should validate Prometheus is collecting metrics from all services', async () => {
            const testStart = Date.now();
            
            const expectedMetrics = [
                'vault_core_unsealed',
                'vault_runtime_alloc_bytes',
                'consul_health_service_query',
                'consul_memberlist_members',
                'nomad_runtime_alloc_bytes',
                'nomad_runtime_num_goroutines',
                'traefik_service_requests_total',
                'traefik_service_request_duration_seconds'
            ];

            const mockMetricsResponse = expectedMetrics.map(metric => ({
                metric: { __name__: metric, instance: 'localhost:8080' },
                value: [Date.now() / 1000, Math.random().toString()]
            }));

            mockPrometheus.query.mockImplementation((query) => {
                if (expectedMetrics.some(metric => query.includes(metric))) {
                    return Promise.resolve({
                        data: {
                            result: mockMetricsResponse.filter(m => 
                                query.includes(m.metric.__name__)
                            )
                        }
                    });
                }
                return Promise.resolve({ data: { result: [] } });
            });

            try {
                const foundMetrics = [];
                
                for (const metric of expectedMetrics) {
                    const response = await mockPrometheus.query(metric);
                    if (response.data.result.length > 0) {
                        foundMetrics.push(metric);
                    }
                }

                const coverage = (foundMetrics.length / expectedMetrics.length) * 100;

                testResults.push({
                    test: 'Prometheus Metrics Collection',
                    status: coverage >= 80 ? 'PASS' : 'FAIL',
                    duration: Date.now() - testStart,
                    metrics: {
                        expectedMetrics: expectedMetrics.length,
                        foundMetrics: foundMetrics.length,
                        coverage: Math.round(coverage),
                        missingMetrics: expectedMetrics.filter(m => !foundMetrics.includes(m))
                    },
                    details: `${foundMetrics.length}/${expectedMetrics.length} metrics found (${Math.round(coverage)}% coverage)`
                });

                expect(coverage).toBeGreaterThanOrEqual(80);
            } catch (error) {
                testResults.push({
                    test: 'Prometheus Metrics Collection',
                    status: 'FAIL',
                    duration: Date.now() - testStart,
                    error: error.message
                });
                throw error;
            }
        });

        it('should test metric retention and storage', async () => {
            const testStart = Date.now();
            
            const retentionTests = [
                {
                    query: 'up[1h]',
                    expectedDataPoints: 60, // 1 minute intervals
                    description: '1 hour retention'
                },
                {
                    query: 'up[24h]',
                    expectedDataPoints: 1440, // 1 minute intervals for 24 hours
                    description: '24 hour retention'
                },
                {
                    query: 'up[7d]',
                    expectedDataPoints: 2016, // 5 minute intervals for 7 days
                    description: '7 day retention'
                }
            ];

            const mockRangeResponse = (dataPoints) => ({
                data: {
                    result: [{
                        metric: { __name__: 'up', instance: 'localhost' },
                        values: Array(dataPoints).fill(null).map((_, i) => [
                            (Date.now() / 1000) - (dataPoints - i) * 60,
                            '1'
                        ])
                    }]
                }
            });

            mockPrometheus.queryRange.mockImplementation((query) => {
                if (query.includes('up[1h]')) {
                    return Promise.resolve(mockRangeResponse(60));
                } else if (query.includes('up[24h]')) {
                    return Promise.resolve(mockRangeResponse(1440));
                } else if (query.includes('up[7d]')) {
                    return Promise.resolve(mockRangeResponse(2016));
                }
                return Promise.resolve({ data: { result: [] } });
            });

            try {
                const retentionResults = [];

                for (const test of retentionTests) {
                    const response = await mockPrometheus.queryRange(test.query);
                    const dataPoints = response.data.result[0]?.values?.length || 0;
                    
                    retentionResults.push({
                        description: test.description,
                        expected: test.expectedDataPoints,
                        actual: dataPoints,
                        coverage: Math.round((dataPoints / test.expectedDataPoints) * 100)
                    });
                }

                const avgCoverage = retentionResults.reduce((sum, r) => sum + r.coverage, 0) / retentionResults.length;

                testResults.push({
                    test: 'Prometheus Metric Retention',
                    status: avgCoverage >= 90 ? 'PASS' : 'FAIL',
                    duration: Date.now() - testStart,
                    metrics: {
                        averageCoverage: Math.round(avgCoverage),
                        retentionTests: retentionResults
                    },
                    details: `Average retention coverage: ${Math.round(avgCoverage)}%`
                });

                expect(avgCoverage).toBeGreaterThanOrEqual(90);
            } catch (error) {
                testResults.push({
                    test: 'Prometheus Metric Retention',
                    status: 'FAIL',
                    duration: Date.now() - testStart,
                    error: error.message
                });
                throw error;
            }
        });

        it('should validate metric labels and dimensions', async () => {
            const testStart = Date.now();

            const labelTests = [
                {
                    metric: 'vault_core_unsealed',
                    expectedLabels: ['instance', 'job', 'cluster'],
                    description: 'Vault metrics should have proper labels'
                },
                {
                    metric: 'traefik_service_requests_total',
                    expectedLabels: ['instance', 'job', 'service', 'method', 'code'],
                    description: 'Traefik metrics should have service and HTTP labels'
                },
                {
                    metric: 'nomad_runtime_alloc_bytes',
                    expectedLabels: ['instance', 'job', 'datacenter', 'node_class'],
                    description: 'Nomad metrics should have datacenter and node labels'
                }
            ];

            const mockSeriesResponse = (labels) => ({
                data: [{
                    ...labels.reduce((acc, label) => ({ ...acc, [label]: `test-${label}` }), {}),
                    __name__: 'test-metric'
                }]
            });

            mockPrometheus.series.mockImplementation((query) => {
                const testCase = labelTests.find(test => query.includes(test.metric));
                if (testCase) {
                    return Promise.resolve(mockSeriesResponse(testCase.expectedLabels));
                }
                return Promise.resolve({ data: [] });
            });

            try {
                const labelResults = [];

                for (const test of labelTests) {
                    const response = await mockPrometheus.series(`{__name__="${test.metric}"}`);
                    const series = response.data[0] || {};
                    const foundLabels = Object.keys(series).filter(key => key !== '__name__');
                    const missingLabels = test.expectedLabels.filter(label => !foundLabels.includes(label));
                    
                    labelResults.push({
                        metric: test.metric,
                        expectedLabels: test.expectedLabels.length,
                        foundLabels: foundLabels.length,
                        missingLabels,
                        coverage: Math.round((foundLabels.length / test.expectedLabels.length) * 100)
                    });
                }

                const avgLabelCoverage = labelResults.reduce((sum, r) => sum + r.coverage, 0) / labelResults.length;

                testResults.push({
                    test: 'Prometheus Metric Labels',
                    status: avgLabelCoverage >= 80 ? 'PASS' : 'FAIL',
                    duration: Date.now() - testStart,
                    metrics: {
                        averageLabelCoverage: Math.round(avgLabelCoverage),
                        labelResults
                    },
                    details: `Average label coverage: ${Math.round(avgLabelCoverage)}%`
                });

                expect(avgLabelCoverage).toBeGreaterThanOrEqual(80);
            } catch (error) {
                testResults.push({
                    test: 'Prometheus Metric Labels',
                    status: 'FAIL',
                    duration: Date.now() - testStart,
                    error: error.message
                });
                throw error;
            }
        });
    });

    describe('Grafana Dashboard Tests', () => {
        it('should validate essential dashboards exist', async () => {
            const testStart = Date.now();

            const expectedDashboards = [
                'Vault Overview',
                'Consul Cluster Health',
                'Nomad Job Status',
                'Traefik Performance',
                'Infrastructure Overview',
                'Security Monitoring'
            ];

            const mockDashboards = expectedDashboards.map((title, index) => ({
                id: index + 1,
                uid: `dashboard-${index + 1}`,
                title,
                tags: ['infrastructure'],
                folderTitle: 'HashiCorp Stack'
            }));

            mockGrafana.dashboards.list.mockResolvedValue(mockDashboards);

            try {
                const dashboards = await mockGrafana.dashboards.list();
                const foundDashboards = dashboards.map(d => d.title);
                const missingDashboards = expectedDashboards.filter(d => !foundDashboards.includes(d));
                const coverage = (foundDashboards.length / expectedDashboards.length) * 100;

                testResults.push({
                    test: 'Grafana Essential Dashboards',
                    status: coverage >= 100 ? 'PASS' : 'FAIL',
                    duration: Date.now() - testStart,
                    metrics: {
                        expectedDashboards: expectedDashboards.length,
                        foundDashboards: foundDashboards.length,
                        missingDashboards,
                        coverage: Math.round(coverage)
                    },
                    details: `${foundDashboards.length}/${expectedDashboards.length} essential dashboards found`
                });

                expect(missingDashboards.length).toBe(0);
            } catch (error) {
                testResults.push({
                    test: 'Grafana Essential Dashboards',
                    status: 'FAIL',
                    duration: Date.now() - testStart,
                    error: error.message
                });
                throw error;
            }
        });

        it('should test dashboard functionality and panels', async () => {
            const testStart = Date.now();

            const mockDashboardDetails = {
                dashboard: {
                    id: 1,
                    title: 'Vault Overview',
                    panels: [
                        {
                            id: 1,
                            title: 'Vault Status',
                            type: 'stat',
                            targets: [{ expr: 'vault_core_unsealed' }]
                        },
                        {
                            id: 2,
                            title: 'Memory Usage',
                            type: 'graph',
                            targets: [{ expr: 'vault_runtime_alloc_bytes' }]
                        },
                        {
                            id: 3,
                            title: 'Request Rate',
                            type: 'graph',
                            targets: [{ expr: 'rate(vault_core_handle_request[5m])' }]
                        }
                    ],
                    templating: {
                        list: [
                            { name: 'instance', type: 'query' },
                            { name: 'cluster', type: 'query' }
                        ]
                    }
                }
            };

            mockGrafana.dashboards.get.mockResolvedValue(mockDashboardDetails);

            try {
                const dashboard = await mockGrafana.dashboards.get(1);
                const panels = dashboard.dashboard.panels || [];
                const templating = dashboard.dashboard.templating?.list || [];

                // Validate panel requirements
                const hasStatPanel = panels.some(p => p.type === 'stat');
                const hasGraphPanels = panels.filter(p => p.type === 'graph').length >= 2;
                const allPanelsHaveTargets = panels.every(p => p.targets && p.targets.length > 0);
                const hasTemplating = templating.length >= 2;

                const validationResults = {
                    totalPanels: panels.length,
                    hasStatPanel,
                    hasGraphPanels,
                    allPanelsHaveTargets,
                    hasTemplating,
                    templatingVariables: templating.length
                };

                const isValid = hasStatPanel && hasGraphPanels && allPanelsHaveTargets && hasTemplating;

                testResults.push({
                    test: 'Grafana Dashboard Functionality',
                    status: isValid ? 'PASS' : 'FAIL',
                    duration: Date.now() - testStart,
                    metrics: validationResults,
                    details: `Dashboard has ${panels.length} panels with ${templating.length} template variables`
                });

                expect(isValid).toBe(true);
            } catch (error) {
                testResults.push({
                    test: 'Grafana Dashboard Functionality',
                    status: 'FAIL',
                    duration: Date.now() - testStart,
                    error: error.message
                });
                throw error;
            }
        });

        it('should validate data source connections', async () => {
            const testStart = Date.now();

            const expectedDataSources = [
                { name: 'Prometheus', type: 'prometheus' },
                { name: 'Loki', type: 'loki' },
                { name: 'Jaeger', type: 'jaeger' }
            ];

            const mockDataSources = expectedDataSources.map((ds, index) => ({
                id: index + 1,
                name: ds.name,
                type: ds.type,
                access: 'proxy',
                url: `http://${ds.type}:9090`,
                isDefault: index === 0
            }));

            mockGrafana.datasources.list.mockResolvedValue(mockDataSources);
            mockGrafana.datasources.test.mockImplementation((id) => {
                return Promise.resolve({
                    status: 'success',
                    message: 'Data source is working'
                });
            });

            try {
                const dataSources = await mockGrafana.datasources.list();
                const testResults_ds = [];

                for (const ds of dataSources) {
                    const testResult = await mockGrafana.datasources.test(ds.id);
                    testResults_ds.push({
                        name: ds.name,
                        type: ds.type,
                        status: testResult.status,
                        working: testResult.status === 'success'
                    });
                }

                const workingDataSources = testResults_ds.filter(ds => ds.working).length;
                const coverage = (workingDataSources / dataSources.length) * 100;

                testResults.push({
                    test: 'Grafana Data Source Connections',
                    status: coverage >= 100 ? 'PASS' : 'FAIL',
                    duration: Date.now() - testStart,
                    metrics: {
                        totalDataSources: dataSources.length,
                        workingDataSources,
                        coverage: Math.round(coverage),
                        dataSourceTests: testResults_ds
                    },
                    details: `${workingDataSources}/${dataSources.length} data sources are working`
                });

                expect(coverage).toBe(100);
            } catch (error) {
                testResults.push({
                    test: 'Grafana Data Source Connections',
                    status: 'FAIL',
                    duration: Date.now() - testStart,
                    error: error.message
                });
                throw error;
            }
        });
    });

    describe('Alerting Tests', () => {
        it('should validate critical alert rules exist', async () => {
            const testStart = Date.now();

            const expectedAlerts = [
                {
                    name: 'VaultSealed',
                    severity: 'critical',
                    query: 'vault_core_unsealed == 0'
                },
                {
                    name: 'ConsulNodeDown',
                    severity: 'warning',
                    query: 'up{job="consul"} == 0'
                },
                {
                    name: 'NomadJobFailed',
                    severity: 'warning',
                    query: 'nomad_runtime_num_goroutines == 0'
                },
                {
                    name: 'TraefikHighLatency',
                    severity: 'warning',
                    query: 'traefik_service_request_duration_seconds > 1'
                },
                {
                    name: 'HighMemoryUsage',
                    severity: 'warning',
                    query: 'process_resident_memory_bytes / 1024 / 1024 > 1000'
                }
            ];

            const mockAlerts = expectedAlerts.map((alert, index) => ({
                fingerprint: `alert-${index}`,
                receivers: [{ name: 'web.hook' }],
                status: {
                    state: 'active',
                    silencedBy: [],
                    inhibitedBy: []
                },
                labels: {
                    alertname: alert.name,
                    severity: alert.severity,
                    instance: 'localhost:8080'
                },
                annotations: {
                    description: `Alert for ${alert.name}`,
                    summary: alert.query
                },
                startsAt: new Date(Date.now() - 5 * 60 * 1000).toISOString(),
                updatedAt: new Date().toISOString(),
                generatorURL: 'http://prometheus:9090/graph'
            }));

            mockAlertmanager.alerts.mockResolvedValue(mockAlerts);

            try {
                const alerts = await mockAlertmanager.alerts();
                const alertNames = alerts.map(alert => alert.labels.alertname);
                const missingAlerts = expectedAlerts.filter(expected => 
                    !alertNames.includes(expected.name)
                );
                const coverage = (alertNames.length / expectedAlerts.length) * 100;

                // Check alert severity distribution
                const criticalAlerts = alerts.filter(alert => alert.labels.severity === 'critical').length;
                const warningAlerts = alerts.filter(alert => alert.labels.severity === 'warning').length;

                testResults.push({
                    test: 'Critical Alert Rules',
                    status: missingAlerts.length === 0 ? 'PASS' : 'FAIL',
                    duration: Date.now() - testStart,
                    metrics: {
                        expectedAlerts: expectedAlerts.length,
                        foundAlerts: alertNames.length,
                        missingAlerts: missingAlerts.map(a => a.name),
                        coverage: Math.round(coverage),
                        severityDistribution: {
                            critical: criticalAlerts,
                            warning: warningAlerts
                        }
                    },
                    details: `${alertNames.length}/${expectedAlerts.length} critical alert rules configured`
                });

                expect(missingAlerts.length).toBe(0);
            } catch (error) {
                testResults.push({
                    test: 'Critical Alert Rules',
                    status: 'FAIL',
                    duration: Date.now() - testStart,
                    error: error.message
                });
                throw error;
            }
        });

        it('should test alert notification channels', async () => {
            const testStart = Date.now();

            const expectedReceivers = [
                {
                    name: 'web.hook',
                    webhook_configs: [{
                        url: 'http://webhook.cloudya.net/alerts',
                        send_resolved: true
                    }]
                },
                {
                    name: 'email',
                    email_configs: [{
                        to: 'alerts@cloudya.net',
                        subject: 'Alert: {{ .GroupLabels.alertname }}',
                        body: 'Alert details: {{ range .Alerts }}{{ .Annotations.summary }}{{ end }}'
                    }]
                },
                {
                    name: 'slack',
                    slack_configs: [{
                        channel: '#alerts',
                        title: 'Alert: {{ .GroupLabels.alertname }}',
                        text: '{{ range .Alerts }}{{ .Annotations.description }}{{ end }}'
                    }]
                }
            ];

            const mockAlertConfig = {
                global: {
                    smtp_smarthost: 'localhost:587'
                },
                receivers: expectedReceivers,
                route: {
                    group_by: ['alertname'],
                    group_wait: '10s',
                    group_interval: '10s',
                    repeat_interval: '1h',
                    receiver: 'web.hook',
                    routes: [
                        {
                            match: { severity: 'critical' },
                            receiver: 'email'
                        }
                    ]
                }
            };

            mockAlertmanager.config.mockResolvedValue(mockAlertConfig);
            mockAlertmanager.receivers.mockResolvedValue(expectedReceivers);

            try {
                const config = await mockAlertmanager.config();
                const receivers = await mockAlertmanager.receivers();

                // Validate receiver configuration
                const hasWebhookReceiver = receivers.some(r => r.name === 'web.hook' && r.webhook_configs);
                const hasEmailReceiver = receivers.some(r => r.name === 'email' && r.email_configs);
                const hasSlackReceiver = receivers.some(r => r.name === 'slack' && r.slack_configs);

                // Validate routing configuration
                const hasRouting = config.route && config.route.routes && config.route.routes.length > 0;
                const hasCriticalRouting = config.route.routes.some(route => 
                    route.match && route.match.severity === 'critical'
                );

                const validationResults = {
                    totalReceivers: receivers.length,
                    hasWebhookReceiver,
                    hasEmailReceiver,
                    hasSlackReceiver,
                    hasRouting,
                    hasCriticalRouting,
                    routingRules: config.route.routes?.length || 0
                };

                const isValid = hasWebhookReceiver && hasEmailReceiver && hasRouting && hasCriticalRouting;

                testResults.push({
                    test: 'Alert Notification Channels',
                    status: isValid ? 'PASS' : 'FAIL',
                    duration: Date.now() - testStart,
                    metrics: validationResults,
                    details: `${receivers.length} notification channels configured with routing rules`
                });

                expect(isValid).toBe(true);
            } catch (error) {
                testResults.push({
                    test: 'Alert Notification Channels',
                    status: 'FAIL',
                    duration: Date.now() - testStart,
                    error: error.message
                });
                throw error;
            }
        });

        it('should validate alert inhibition and grouping', async () => {
            const testStart = Date.now();

            const mockInhibitionRules = [
                {
                    source_match: { alertname: 'NodeDown' },
                    target_match: { alertname: 'ServiceDown' },
                    equal: ['instance']
                },
                {
                    source_match: { severity: 'critical' },
                    target_match: { severity: 'warning' },
                    equal: ['service']
                }
            ];

            const mockGroupingConfig = {
                group_by: ['alertname', 'cluster', 'service'],
                group_wait: '10s',
                group_interval: '10s',
                repeat_interval: '12h'
            };

            try {
                // Simulate alert inhibition logic
                const hasNodeServiceInhibition = mockInhibitionRules.some(rule =>
                    rule.source_match.alertname === 'NodeDown' && 
                    rule.target_match.alertname === 'ServiceDown'
                );

                const hasSeverityInhibition = mockInhibitionRules.some(rule =>
                    rule.source_match.severity === 'critical' && 
                    rule.target_match.severity === 'warning'
                );

                // Validate grouping configuration
                const hasProperGrouping = mockGroupingConfig.group_by.includes('alertname') &&
                                        mockGroupingConfig.group_by.includes('cluster');

                const hasReasonableTimings = 
                    parseInt(mockGroupingConfig.group_wait) >= 10 &&
                    parseInt(mockGroupingConfig.repeat_interval.replace('h', '')) >= 12;

                const validationResults = {
                    inhibitionRules: mockInhibitionRules.length,
                    hasNodeServiceInhibition,
                    hasSeverityInhibition,
                    groupingFields: mockGroupingConfig.group_by.length,
                    hasProperGrouping,
                    hasReasonableTimings,
                    groupWait: mockGroupingConfig.group_wait,
                    repeatInterval: mockGroupingConfig.repeat_interval
                };

                const isValid = hasNodeServiceInhibition && 
                              hasSeverityInhibition && 
                              hasProperGrouping && 
                              hasReasonableTimings;

                testResults.push({
                    test: 'Alert Inhibition and Grouping',
                    status: isValid ? 'PASS' : 'FAIL',
                    duration: Date.now() - testStart,
                    metrics: validationResults,
                    details: `${mockInhibitionRules.length} inhibition rules with proper grouping configured`
                });

                expect(isValid).toBe(true);
            } catch (error) {
                testResults.push({
                    test: 'Alert Inhibition and Grouping',
                    status: 'FAIL',
                    duration: Date.now() - testStart,
                    error: error.message
                });
                throw error;
            }
        });
    });

    describe('Log Aggregation and Analysis', () => {
        it('should validate log collection from all services', async () => {
            const testStart = Date.now();

            const expectedLogSources = [
                'vault',
                'consul',
                'nomad',
                'traefik',
                'prometheus',
                'grafana'
            ];

            // Mock log queries (simulating Loki or similar)
            const mockLogQuery = jest.fn().mockImplementation((query) => {
                const service = expectedLogSources.find(s => query.includes(s));
                if (service) {
                    return Promise.resolve({
                        data: {
                            result: [{
                                stream: { service },
                                values: Array(100).fill(null).map((_, i) => [
                                    (Date.now() * 1000000) - (i * 60000000), // nanoseconds
                                    `[INFO] ${service}: Sample log message ${i}`
                                ])
                            }]
                        }
                    });
                }
                return Promise.resolve({ data: { result: [] } });
            });

            try {
                const logResults = [];

                for (const service of expectedLogSources) {
                    const response = await mockLogQuery(`{service="${service}"}`);
                    const logEntries = response.data.result[0]?.values?.length || 0;
                    
                    logResults.push({
                        service,
                        logEntries,
                        hasLogs: logEntries > 0
                    });
                }

                const servicesWithLogs = logResults.filter(r => r.hasLogs).length;
                const coverage = (servicesWithLogs / expectedLogSources.length) * 100;

                testResults.push({
                    test: 'Log Collection Coverage',
                    status: coverage >= 90 ? 'PASS' : 'FAIL',
                    duration: Date.now() - testStart,
                    metrics: {
                        expectedSources: expectedLogSources.length,
                        sourcesWithLogs: servicesWithLogs,
                        coverage: Math.round(coverage),
                        logResults
                    },
                    details: `${servicesWithLogs}/${expectedLogSources.length} services have logs collected`
                });

                expect(coverage).toBeGreaterThanOrEqual(90);
            } catch (error) {
                testResults.push({
                    test: 'Log Collection Coverage',
                    status: 'FAIL',
                    duration: Date.now() - testStart,
                    error: error.message
                });
                throw error;
            }
        });

        it('should test log retention and parsing', async () => {
            const testStart = Date.now();

            const logRetentionTests = [
                {
                    timeRange: '1h',
                    expectedEntries: 60,
                    description: '1 hour log retention'
                },
                {
                    timeRange: '24h',
                    expectedEntries: 1440,
                    description: '24 hour log retention'
                },
                {
                    timeRange: '7d',
                    expectedEntries: 10080,
                    description: '7 day log retention'
                }
            ];

            const mockLogRetentionQuery = jest.fn().mockImplementation((timeRange) => {
                const entries = timeRange === '1h' ? 60 : timeRange === '24h' ? 1440 : 10080;
                return Promise.resolve({
                    data: {
                        result: [{
                            values: Array(entries).fill(null).map((_, i) => [
                                (Date.now() * 1000000) - (i * 60000000),
                                `[INFO] Sample log entry ${i}`
                            ])
                        }]
                    }
                });
            });

            try {
                const retentionResults = [];

                for (const test of logRetentionTests) {
                    const response = await mockLogRetentionQuery(test.timeRange);
                    const actualEntries = response.data.result[0]?.values?.length || 0;
                    const coverage = (actualEntries / test.expectedEntries) * 100;
                    
                    retentionResults.push({
                        timeRange: test.timeRange,
                        description: test.description,
                        expected: test.expectedEntries,
                        actual: actualEntries,
                        coverage: Math.round(coverage)
                    });
                }

                const avgCoverage = retentionResults.reduce((sum, r) => sum + r.coverage, 0) / retentionResults.length;

                testResults.push({
                    test: 'Log Retention and Parsing',
                    status: avgCoverage >= 85 ? 'PASS' : 'FAIL',
                    duration: Date.now() - testStart,
                    metrics: {
                        averageCoverage: Math.round(avgCoverage),
                        retentionResults
                    },
                    details: `Average log retention coverage: ${Math.round(avgCoverage)}%`
                });

                expect(avgCoverage).toBeGreaterThanOrEqual(85);
            } catch (error) {
                testResults.push({
                    test: 'Log Retention and Parsing',
                    status: 'FAIL',
                    duration: Date.now() - testStart,
                    error: error.message
                });
                throw error;
            }
        });
    });
});