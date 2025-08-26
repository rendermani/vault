#!/usr/bin/env node

/**
 * Test Report Generator
 * Aggregates all test results and generates comprehensive reports
 */

const fs = require('fs').promises;
const path = require('path');

const REPORTS_DIR = path.join(__dirname, 'reports');
const OUTPUT_FILE = path.join(REPORTS_DIR, 'comprehensive_test_report.html');

async function loadTestResults() {
    const reportFiles = [
        'ssl_test_report.log',
        'vault_integration_report.json',
        'nomad_integration_report.json',
        'consul_integration_report.json',
        'traefik_integration_report.json',
        'credential_security_report.json',
        'acl_security_report.json',
        'tls_ssl_security_report.json',
        'performance_test_report.json',
        'automation_test_report.json',
        'monitoring_test_report.json'
    ];

    const results = {
        timestamp: new Date().toISOString(),
        reports: {}
    };

    for (const reportFile of reportFiles) {
        const filePath = path.join(REPORTS_DIR, reportFile);
        try {
            const content = await fs.readFile(filePath, 'utf8');
            const reportName = reportFile.replace(/\.(json|log)$/, '');
            
            if (reportFile.endsWith('.json')) {
                try {
                    results.reports[reportName] = JSON.parse(content);
                } catch (parseError) {
                    results.reports[reportName] = { error: 'Failed to parse JSON', content };
                }
            } else {
                results.reports[reportName] = { content };
            }
        } catch (error) {
            console.warn(`Warning: Could not load ${reportFile}: ${error.message}`);
            results.reports[reportFile.replace(/\.(json|log)$/, '')] = {
                error: error.message,
                status: 'NOT_FOUND'
            };
        }
    }

    return results;
}

function calculateOverallStats(results) {
    const stats = {
        total: 0,
        passed: 0,
        failed: 0,
        skipped: 0,
        warnings: 0,
        categories: {
            integration: { total: 0, passed: 0, failed: 0 },
            security: { total: 0, passed: 0, failed: 0 },
            performance: { total: 0, passed: 0, failed: 0 },
            monitoring: { total: 0, passed: 0, failed: 0 },
            ssl: { total: 0, passed: 0, failed: 0 },
            automation: { total: 0, passed: 0, failed: 0 }
        }
    };

    for (const [reportName, report] of Object.entries(results.reports)) {
        if (report.results && Array.isArray(report.results)) {
            for (const result of report.results) {
                stats.total++;
                
                switch (result.status?.toLowerCase()) {
                    case 'pass':
                        stats.passed++;
                        break;
                    case 'fail':
                        stats.failed++;
                        break;
                    case 'skip':
                        stats.skipped++;
                        break;
                    case 'warn':
                        stats.warnings++;
                        break;
                }

                // Categorize by test type
                if (reportName.includes('integration')) {
                    stats.categories.integration.total++;
                    if (result.status?.toLowerCase() === 'pass') stats.categories.integration.passed++;
                    if (result.status?.toLowerCase() === 'fail') stats.categories.integration.failed++;
                } else if (reportName.includes('security')) {
                    stats.categories.security.total++;
                    if (result.status?.toLowerCase() === 'pass') stats.categories.security.passed++;
                    if (result.status?.toLowerCase() === 'fail') stats.categories.security.failed++;
                } else if (reportName.includes('performance')) {
                    stats.categories.performance.total++;
                    if (result.status?.toLowerCase() === 'pass') stats.categories.performance.passed++;
                    if (result.status?.toLowerCase() === 'fail') stats.categories.performance.failed++;
                } else if (reportName.includes('monitoring')) {
                    stats.categories.monitoring.total++;
                    if (result.status?.toLowerCase() === 'pass') stats.categories.monitoring.passed++;
                    if (result.status?.toLowerCase() === 'fail') stats.categories.monitoring.failed++;
                }
            }
        } else if (report.summary) {
            // Handle reports with summary format
            stats.total += report.summary.total || 0;
            stats.passed += report.summary.passed || 0;
            stats.failed += report.summary.failed || 0;
            stats.skipped += report.summary.skipped || 0;
        }
    }

    return stats;
}

function generateHTMLReport(results, stats) {
    const successRate = stats.total > 0 ? Math.round((stats.passed / stats.total) * 100) : 0;
    const statusColor = successRate >= 90 ? '#28a745' : successRate >= 70 ? '#ffc107' : '#dc3545';

    return `
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Cloudya Vault Infrastructure - Test Report</title>
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }
        
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', system-ui, sans-serif;
            background: #f8f9fa;
            color: #333;
            line-height: 1.6;
        }
        
        .container {
            max-width: 1200px;
            margin: 0 auto;
            padding: 2rem;
        }
        
        .header {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            padding: 2rem;
            border-radius: 12px;
            margin-bottom: 2rem;
            text-align: center;
        }
        
        .header h1 {
            font-size: 2.5rem;
            margin-bottom: 0.5rem;
        }
        
        .header p {
            font-size: 1.1rem;
            opacity: 0.9;
        }
        
        .stats-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(250px, 1fr));
            gap: 1.5rem;
            margin-bottom: 3rem;
        }
        
        .stat-card {
            background: white;
            padding: 1.5rem;
            border-radius: 12px;
            box-shadow: 0 4px 6px rgba(0, 0, 0, 0.1);
            border-left: 4px solid ${statusColor};
        }
        
        .stat-number {
            font-size: 2.5rem;
            font-weight: bold;
            color: ${statusColor};
        }
        
        .stat-label {
            color: #666;
            font-size: 0.9rem;
            text-transform: uppercase;
            letter-spacing: 0.5px;
        }
        
        .success-rate {
            font-size: 3rem;
            font-weight: bold;
            color: ${statusColor};
            text-align: center;
        }
        
        .categories-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
            gap: 1.5rem;
            margin-bottom: 3rem;
        }
        
        .category-card {
            background: white;
            padding: 1.5rem;
            border-radius: 12px;
            box-shadow: 0 4px 6px rgba(0, 0, 0, 0.1);
        }
        
        .category-header {
            font-size: 1.2rem;
            font-weight: bold;
            margin-bottom: 1rem;
            color: #333;
        }
        
        .progress-bar {
            background: #e9ecef;
            border-radius: 10px;
            height: 20px;
            overflow: hidden;
            margin-bottom: 0.5rem;
        }
        
        .progress-fill {
            background: linear-gradient(90deg, #28a745, #20c997);
            height: 100%;
            transition: width 0.3s ease;
        }
        
        .progress-text {
            font-size: 0.9rem;
            color: #666;
        }
        
        .test-results {
            background: white;
            border-radius: 12px;
            overflow: hidden;
            box-shadow: 0 4px 6px rgba(0, 0, 0, 0.1);
        }
        
        .test-results h2 {
            background: #f8f9fa;
            padding: 1.5rem;
            margin: 0;
            border-bottom: 1px solid #dee2e6;
        }
        
        .test-category {
            border-bottom: 1px solid #dee2e6;
        }
        
        .test-category:last-child {
            border-bottom: none;
        }
        
        .test-category-header {
            background: #f1f3f4;
            padding: 1rem 1.5rem;
            font-weight: bold;
            color: #495057;
            cursor: pointer;
            display: flex;
            justify-content: space-between;
            align-items: center;
        }
        
        .test-category-content {
            padding: 1rem 1.5rem;
        }
        
        .test-item {
            display: flex;
            align-items: center;
            padding: 0.75rem 0;
            border-bottom: 1px solid #f8f9fa;
        }
        
        .test-item:last-child {
            border-bottom: none;
        }
        
        .test-status {
            width: 20px;
            height: 20px;
            border-radius: 50%;
            margin-right: 1rem;
            flex-shrink: 0;
        }
        
        .status-pass { background: #28a745; }
        .status-fail { background: #dc3545; }
        .status-skip { background: #6c757d; }
        .status-warn { background: #ffc107; }
        
        .test-name {
            flex-grow: 1;
            font-weight: 500;
        }
        
        .test-duration {
            color: #666;
            font-size: 0.9rem;
        }
        
        .test-details {
            font-size: 0.9rem;
            color: #666;
            margin-top: 0.25rem;
            margin-left: 2rem;
        }
        
        .footer {
            text-align: center;
            margin-top: 3rem;
            padding-top: 2rem;
            border-top: 1px solid #dee2e6;
            color: #666;
        }
        
        .expand-toggle {
            background: none;
            border: none;
            font-size: 1.2rem;
            cursor: pointer;
            color: #666;
        }
        
        @media (max-width: 768px) {
            .container {
                padding: 1rem;
            }
            
            .header h1 {
                font-size: 2rem;
            }
            
            .stats-grid {
                grid-template-columns: 1fr;
            }
        }
    </style>
</head>
<body>
    <div class="container">
        <header class="header">
            <h1>🔐 Cloudya Vault Infrastructure</h1>
            <p>Comprehensive Test Report - ${new Date(results.timestamp).toLocaleString()}</p>
        </header>
        
        <section class="stats-grid">
            <div class="stat-card">
                <div class="stat-number">${stats.total}</div>
                <div class="stat-label">Total Tests</div>
            </div>
            
            <div class="stat-card">
                <div class="stat-number">${stats.passed}</div>
                <div class="stat-label">Passed</div>
            </div>
            
            <div class="stat-card">
                <div class="stat-number">${stats.failed}</div>
                <div class="stat-label">Failed</div>
            </div>
            
            <div class="stat-card">
                <div class="success-rate">${successRate}%</div>
                <div class="stat-label">Success Rate</div>
            </div>
        </section>
        
        <section class="categories-grid">
            ${Object.entries(stats.categories).map(([category, data]) => {
                const categoryRate = data.total > 0 ? Math.round((data.passed / data.total) * 100) : 0;
                return `
                <div class="category-card">
                    <div class="category-header">${category.charAt(0).toUpperCase() + category.slice(1)} Tests</div>
                    <div class="progress-bar">
                        <div class="progress-fill" style="width: ${categoryRate}%"></div>
                    </div>
                    <div class="progress-text">${data.passed}/${data.total} passed (${categoryRate}%)</div>
                </div>
                `;
            }).join('')}
        </section>
        
        <section class="test-results">
            <h2>📋 Detailed Test Results</h2>
            
            ${Object.entries(results.reports).map(([reportName, report]) => {
                if (!report.results || !Array.isArray(report.results)) {
                    return `
                    <div class="test-category">
                        <div class="test-category-header">
                            ${reportName.replace(/_/g, ' ').toUpperCase()}
                            <span class="expand-toggle">−</span>
                        </div>
                        <div class="test-category-content">
                            <div class="test-item">
                                <div class="test-status ${report.error ? 'status-fail' : 'status-skip'}"></div>
                                <div class="test-name">
                                    ${report.error ? 'Error: ' + report.error : 'No test results available'}
                                </div>
                            </div>
                        </div>
                    </div>
                    `;
                }
                
                return `
                <div class="test-category">
                    <div class="test-category-header">
                        ${reportName.replace(/_/g, ' ').toUpperCase()}
                        <span class="expand-toggle">−</span>
                    </div>
                    <div class="test-category-content">
                        ${report.results.map(result => `
                        <div class="test-item">
                            <div class="test-status status-${result.status?.toLowerCase() || 'skip'}"></div>
                            <div>
                                <div class="test-name">${result.test || 'Unknown Test'}</div>
                                ${result.details ? `<div class="test-details">${result.details}</div>` : ''}
                            </div>
                            ${result.duration ? `<div class="test-duration">${result.duration}ms</div>` : ''}
                        </div>
                        `).join('')}
                    </div>
                </div>
                `;
            }).join('')}
        </section>
        
        <footer class="footer">
            <p>Generated by Cloudya Vault Infrastructure Test Suite</p>
            <p>Report generated on ${new Date().toLocaleString()}</p>
        </footer>
    </div>
    
    <script>
        // Toggle category sections
        document.querySelectorAll('.test-category-header').forEach(header => {
            header.addEventListener('click', () => {
                const content = header.nextElementSibling;
                const toggle = header.querySelector('.expand-toggle');
                
                if (content.style.display === 'none') {
                    content.style.display = 'block';
                    toggle.textContent = '−';
                } else {
                    content.style.display = 'none';
                    toggle.textContent = '+';
                }
            });
        });
    </script>
</body>
</html>
    `;
}

async function generateJSONReport(results, stats) {
    const jsonReport = {
        metadata: {
            generated: new Date().toISOString(),
            version: "1.0.0",
            infrastructure: "Cloudya Vault Stack"
        },
        summary: {
            ...stats,
            successRate: stats.total > 0 ? Math.round((stats.passed / stats.total) * 100) : 0
        },
        details: results.reports
    };

    const jsonPath = path.join(REPORTS_DIR, 'comprehensive_test_report.json');
    await fs.writeFile(jsonPath, JSON.stringify(jsonReport, null, 2));
    console.log(`✅ JSON report generated: ${jsonPath}`);
}

async function main() {
    try {
        console.log('🔄 Loading test results...');
        const results = await loadTestResults();
        
        console.log('📊 Calculating statistics...');
        const stats = calculateOverallStats(results);
        
        console.log('📝 Generating HTML report...');
        const htmlContent = generateHTMLReport(results, stats);
        await fs.writeFile(OUTPUT_FILE, htmlContent);
        
        console.log('📄 Generating JSON report...');
        await generateJSONReport(results, stats);
        
        console.log('✨ Test reports generated successfully!');
        console.log(`📈 Overall Success Rate: ${stats.total > 0 ? Math.round((stats.passed / stats.total) * 100) : 0}%`);
        console.log(`📋 Total Tests: ${stats.total} | ✅ Passed: ${stats.passed} | ❌ Failed: ${stats.failed} | ⚠️ Warnings: ${stats.warnings}`);
        console.log(`🌐 HTML Report: ${OUTPUT_FILE}`);
        
    } catch (error) {
        console.error('❌ Error generating test report:', error);
        process.exit(1);
    }
}

// Run if called directly
if (require.main === module) {
    main();
}

module.exports = { loadTestResults, calculateOverallStats, generateHTMLReport };