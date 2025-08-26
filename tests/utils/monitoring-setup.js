#!/usr/bin/env node

const fs = require('fs');
const path = require('path');
const config = require('../config/test-config');

class MonitoringSetup {
  constructor() {
    this.alerts = [];
    this.metrics = [];
    this.startTime = new Date();
  }

  async setupMonitoring() {
    console.log('📊 Setting up Automated Monitoring and Alerting...\n');
    
    try {
      // Create monitoring configuration
      await this.createMonitoringConfig();
      
      // Setup health check schedules
      await this.setupHealthCheckSchedule();
      
      // Configure alerting rules
      await this.configureAlertingRules();
      
      // Create monitoring dashboard
      await this.createMonitoringDashboard();
      
      // Setup log monitoring
      await this.setupLogMonitoring();
      
      console.log('✅ Monitoring setup completed successfully');
      
    } catch (error) {
      console.error('❌ Monitoring setup failed:', error);
      throw error;
    }
  }

  async createMonitoringConfig() {
    const monitoringConfig = {
      version: "1.0",
      services: Object.keys(config.ENDPOINTS).map(service => ({
        name: service,
        endpoint: config.ENDPOINTS[service],
        health_path: config.HEALTH_PATHS[service],
        check_interval: "30s",
        timeout: "10s",
        retries: 3,
        expected_status: [200, 201, 202],
        alerts: {
          response_time: {
            threshold: config.PERFORMANCE_THRESHOLDS.responseTime,
            severity: "warning"
          },
          availability: {
            threshold: config.PERFORMANCE_THRESHOLDS.availability,
            severity: "critical"
          },
          ssl_expiry: {
            threshold: config.SSL_VALIDATION.minValidDays,
            severity: "warning"
          }
        }
      })),
      global_settings: {
        notification_channels: [
          {
            name: "console",
            type: "console",
            enabled: true
          },
          {
            name: "file",
            type: "file",
            path: "/Users/mlautenschlager/cloudya/vault/test-results/logs/alerts.log",
            enabled: true
          }
        ],
        dashboard: {
          enabled: true,
          refresh_interval: "5s",
          port: 8080
        }
      }
    };

    const configPath = path.join(__dirname, '../../test-results/monitoring-config.json');
    await fs.promises.writeFile(configPath, JSON.stringify(monitoringConfig, null, 2));
    
    console.log('✓ Monitoring configuration created');
    return monitoringConfig;
  }

  async setupHealthCheckSchedule() {
    const scheduleScript = `#!/bin/bash

# Cloudya Vault Health Check Schedule
# This script runs automated health checks at regular intervals

SCRIPT_DIR="$(cd "$(dirname "\${BASH_SOURCE[0]}")" && pwd)"
TEST_DIR="$SCRIPT_DIR/../tests"
RESULTS_DIR="$SCRIPT_DIR/../test-results"

# Ensure results directory exists
mkdir -p "$RESULTS_DIR/logs"
mkdir -p "$RESULTS_DIR/reports"

# Function to log with timestamp
log_with_timestamp() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$RESULTS_DIR/logs/health-check.log"
}

# Function to run health checks
run_health_checks() {
    log_with_timestamp "Starting scheduled health checks"
    
    # Run SSL validation
    log_with_timestamp "Running SSL validation..."
    node "$TEST_DIR/ssl/ssl-validator.js" >> "$RESULTS_DIR/logs/ssl-check.log" 2>&1
    SSL_EXIT=$?
    
    # Run endpoint tests
    log_with_timestamp "Running endpoint health tests..."
    node "$TEST_DIR/integration/endpoint-tests.js" >> "$RESULTS_DIR/logs/endpoint-check.log" 2>&1
    ENDPOINT_EXIT=$?
    
    # Check results and alert if needed
    if [ $SSL_EXIT -ne 0 ] || [ $ENDPOINT_EXIT -ne 0 ]; then
        log_with_timestamp "ALERT: Health checks failed - SSL: $SSL_EXIT, Endpoints: $ENDPOINT_EXIT"
        echo "$(date '+%Y-%m-%d %H:%M:%S') - CRITICAL: Health check failure detected" >> "$RESULTS_DIR/logs/alerts.log"
    else
        log_with_timestamp "Health checks completed successfully"
    fi
}

# Function to run performance tests (less frequent)
run_performance_tests() {
    log_with_timestamp "Starting performance tests"
    node "$TEST_DIR/performance/load-tests.js" >> "$RESULTS_DIR/logs/performance.log" 2>&1
    PERF_EXIT=$?
    
    if [ $PERF_EXIT -ne 0 ]; then
        log_with_timestamp "ALERT: Performance tests failed with exit code $PERF_EXIT"
        echo "$(date '+%Y-%m-%d %H:%M:%S') - WARNING: Performance degradation detected" >> "$RESULTS_DIR/logs/alerts.log"
    fi
}

# Main execution
case "$1" in
    "health")
        run_health_checks
        ;;
    "performance") 
        run_performance_tests
        ;;
    "full")
        run_health_checks
        run_performance_tests
        ;;
    *)
        echo "Usage: $0 {health|performance|full}"
        exit 1
        ;;
esac
`;

    const schedulePath = path.join(__dirname, '../../test-results/health-check-schedule.sh');
    await fs.promises.writeFile(schedulePath, scheduleScript);
    await fs.promises.chmod(schedulePath, '755');
    
    // Create cron job configuration
    const cronConfig = `# Cloudya Vault Automated Monitoring Cron Jobs
# Run health checks every 5 minutes
*/5 * * * * ${schedulePath} health

# Run performance tests every hour
0 * * * * ${schedulePath} performance

# Run full test suite daily at 2 AM
0 2 * * * ${schedulePath} full
`;

    const cronPath = path.join(__dirname, '../../test-results/monitoring-crontab.txt');
    await fs.promises.writeFile(cronPath, cronConfig);
    
    console.log('✓ Health check schedule created');
    console.log(`  - Schedule script: ${schedulePath}`);
    console.log(`  - Cron configuration: ${cronPath}`);
    console.log('  - To enable: crontab < ' + cronPath);
  }

  async configureAlertingRules() {
    const alertingRules = {
      rules: [
        {
          name: "ssl_certificate_expiry",
          condition: "ssl_days_until_expiry < 30",
          severity: "warning",
          message: "SSL certificate expires in less than 30 days",
          actions: ["log", "console"]
        },
        {
          name: "default_traefik_certificate",
          condition: "using_default_traefik_cert == true",
          severity: "critical", 
          message: "Default Traefik certificate detected - SSL not properly configured",
          actions: ["log", "console"]
        },
        {
          name: "service_unavailable",
          condition: "service_health == false",
          severity: "critical",
          message: "Service is not responding or unhealthy",
          actions: ["log", "console"]
        },
        {
          name: "high_response_time",
          condition: `response_time > ${config.PERFORMANCE_THRESHOLDS.responseTime}`,
          severity: "warning",
          message: "Service response time exceeds threshold",
          actions: ["log"]
        },
        {
          name: "low_availability",
          condition: `availability < ${config.PERFORMANCE_THRESHOLDS.availability}`,
          severity: "critical",
          message: "Service availability below acceptable threshold", 
          actions: ["log", "console"]
        },
        {
          name: "ssl_handshake_slow",
          condition: `ssl_handshake_time > ${config.PERFORMANCE_THRESHOLDS.ssl_handshake}`,
          severity: "warning",
          message: "SSL handshake time exceeds threshold",
          actions: ["log"]
        }
      ],
      notification_settings: {
        console: {
          enabled: true,
          format: "timestamp + severity + service + message"
        },
        file: {
          enabled: true,
          path: "/Users/mlautenschlager/cloudya/vault/test-results/logs/alerts.log",
          format: "json"
        }
      }
    };

    const alertsPath = path.join(__dirname, '../../test-results/alerting-rules.json');
    await fs.promises.writeFile(alertsPath, JSON.stringify(alertingRules, null, 2));
    
    console.log('✓ Alerting rules configured');
  }

  async createMonitoringDashboard() {
    const dashboardHTML = `<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Cloudya Vault - Monitoring Dashboard</title>
    <style>
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            margin: 0;
            padding: 20px;
            background: #f5f5f5;
        }
        .header {
            background: #2c3e50;
            color: white;
            padding: 20px;
            margin: -20px -20px 20px -20px;
            text-align: center;
        }
        .services-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
            gap: 20px;
            margin-bottom: 30px;
        }
        .service-card {
            background: white;
            padding: 20px;
            border-radius: 8px;
            box-shadow: 0 2px 10px rgba(0,0,0,0.1);
            border-left: 4px solid #3498db;
        }
        .service-card.healthy {
            border-left-color: #27ae60;
        }
        .service-card.warning {
            border-left-color: #f39c12;
        }
        .service-card.critical {
            border-left-color: #e74c3c;
        }
        .service-name {
            font-size: 1.2em;
            font-weight: bold;
            margin-bottom: 10px;
            text-transform: capitalize;
        }
        .service-status {
            display: flex;
            justify-content: space-between;
            margin: 5px 0;
        }
        .status-indicator {
            padding: 2px 8px;
            border-radius: 12px;
            font-size: 0.8em;
            font-weight: bold;
        }
        .status-healthy { background: #d5f4e6; color: #27ae60; }
        .status-warning { background: #ffeaa7; color: #f39c12; }
        .status-critical { background: #fab1a0; color: #e74c3c; }
        .metrics-section {
            background: white;
            padding: 20px;
            border-radius: 8px;
            box-shadow: 0 2px 10px rgba(0,0,0,0.1);
            margin-bottom: 20px;
        }
        .refresh-info {
            text-align: center;
            color: #7f8c8d;
            margin-top: 20px;
        }
        .alert-log {
            background: #2c3e50;
            color: white;
            padding: 15px;
            border-radius: 8px;
            font-family: monospace;
            font-size: 0.9em;
            max-height: 200px;
            overflow-y: auto;
        }
    </style>
    <script>
        // Auto-refresh dashboard every 30 seconds
        setTimeout(() => {
            location.reload();
        }, 30000);

        // Simulated real-time data (would be replaced with actual API calls)
        function updateDashboard() {
            const services = ['vault', 'consul', 'nomad', 'traefik'];
            services.forEach(service => {
                // This would fetch real data from monitoring endpoints
                updateServiceCard(service);
            });
        }

        function updateServiceCard(service) {
            // Placeholder for real-time updates
            console.log('Updating', service);
        }

        // Update dashboard on load
        document.addEventListener('DOMContentLoaded', updateDashboard);
    </script>
</head>
<body>
    <div class="header">
        <h1>🛡️ Cloudya Vault - System Monitoring</h1>
        <p>Real-time monitoring dashboard for HashiCorp stack deployment</p>
    </div>

    <div class="services-grid">
        <div class="service-card healthy" id="vault-card">
            <div class="service-name">Vault</div>
            <div class="service-status">
                <span>Status:</span>
                <span class="status-indicator status-healthy">Healthy</span>
            </div>
            <div class="service-status">
                <span>Response Time:</span>
                <span id="vault-response">Loading...</span>
            </div>
            <div class="service-status">
                <span>SSL Status:</span>
                <span id="vault-ssl">Loading...</span>
            </div>
            <div class="service-status">
                <span>Last Check:</span>
                <span id="vault-lastcheck">Loading...</span>
            </div>
        </div>

        <div class="service-card healthy" id="consul-card">
            <div class="service-name">Consul</div>
            <div class="service-status">
                <span>Status:</span>
                <span class="status-indicator status-healthy">Healthy</span>
            </div>
            <div class="service-status">
                <span>Response Time:</span>
                <span id="consul-response">Loading...</span>
            </div>
            <div class="service-status">
                <span>SSL Status:</span>
                <span id="consul-ssl">Loading...</span>
            </div>
            <div class="service-status">
                <span>Last Check:</span>
                <span id="consul-lastcheck">Loading...</span>
            </div>
        </div>

        <div class="service-card healthy" id="nomad-card">
            <div class="service-name">Nomad</div>
            <div class="service-status">
                <span>Status:</span>
                <span class="status-indicator status-healthy">Healthy</span>
            </div>
            <div class="service-status">
                <span>Response Time:</span>
                <span id="nomad-response">Loading...</span>
            </div>
            <div class="service-status">
                <span>SSL Status:</span>
                <span id="nomad-ssl">Loading...</span>
            </div>
            <div class="service-status">
                <span>Last Check:</span>
                <span id="nomad-lastcheck">Loading...</span>
            </div>
        </div>

        <div class="service-card healthy" id="traefik-card">
            <div class="service-name">Traefik</div>
            <div class="service-status">
                <span>Status:</span>
                <span class="status-indicator status-healthy">Healthy</span>
            </div>
            <div class="service-status">
                <span>Response Time:</span>
                <span id="traefik-response">Loading...</span>
            </div>
            <div class="service-status">
                <span>SSL Status:</span>
                <span id="traefik-ssl">Loading...</span>
            </div>
            <div class="service-status">
                <span>Last Check:</span>
                <span id="traefik-lastcheck">Loading...</span>
            </div>
        </div>
    </div>

    <div class="metrics-section">
        <h3>📊 System Metrics</h3>
        <div class="service-status">
            <span>Overall System Health:</span>
            <span class="status-indicator status-healthy" id="overall-health">Healthy</span>
        </div>
        <div class="service-status">
            <span>Average Response Time:</span>
            <span id="avg-response">Loading...</span>
        </div>
        <div class="service-status">
            <span>System Uptime:</span>
            <span id="system-uptime">Loading...</span>
        </div>
        <div class="service-status">
            <span>SSL Certificates Valid:</span>
            <span id="ssl-summary">Loading...</span>
        </div>
    </div>

    <div class="metrics-section">
        <h3>🚨 Recent Alerts</h3>
        <div class="alert-log" id="alert-log">
            No recent alerts
        </div>
    </div>

    <div class="refresh-info">
        Last updated: <span id="last-update">${new Date().toLocaleString()}</span> | 
        Auto-refresh: Every 30 seconds
    </div>

    <script>
        document.getElementById('last-update').textContent = new Date().toLocaleString();
    </script>
</body>
</html>`;

    const dashboardPath = path.join(__dirname, '../../test-results/monitoring-dashboard.html');
    await fs.promises.writeFile(dashboardPath, dashboardHTML);
    
    console.log('✓ Monitoring dashboard created');
    console.log(`  - Open: file://${dashboardPath}`);
  }

  async setupLogMonitoring() {
    const logMonitorScript = `#!/usr/bin/env node

const fs = require('fs');
const path = require('path');

class LogMonitor {
  constructor() {
    this.logPaths = [
      '/Users/mlautenschlager/cloudya/vault/test-results/logs/health-check.log',
      '/Users/mlautenschlager/cloudya/vault/test-results/logs/ssl-check.log',
      '/Users/mlautenschlager/cloudya/vault/test-results/logs/endpoint-check.log',
      '/Users/mlautenschlager/cloudya/vault/test-results/logs/performance.log'
    ];
    this.patterns = {
      error: /ERROR|CRITICAL|FAILED/i,
      warning: /WARNING|WARN/i,
      ssl_issue: /default.*traefik.*cert|ssl.*invalid|certificate.*expired/i,
      performance: /slow|timeout|performance.*degraded/i
    };
  }

  async startMonitoring() {
    console.log('📋 Starting log monitoring...');
    
    // Ensure log directory exists
    const logDir = path.dirname(this.logPaths[0]);
    if (!fs.existsSync(logDir)) {
      fs.mkdirSync(logDir, { recursive: true });
    }

    // Watch each log file
    this.logPaths.forEach(logPath => {
      if (fs.existsSync(logPath)) {
        this.watchLogFile(logPath);
      }
    });

    // Keep the process running
    setInterval(() => {
      this.checkLogRotation();
    }, 60000); // Check every minute
  }

  watchLogFile(logPath) {
    const filename = path.basename(logPath);
    console.log(\`Watching \${filename}...\`);

    fs.watchFile(logPath, { interval: 1000 }, (curr, prev) => {
      if (curr.mtime > prev.mtime) {
        this.processNewLogEntries(logPath, prev.size, curr.size);
      }
    });
  }

  async processNewLogEntries(logPath, prevSize, currentSize) {
    try {
      const data = fs.readFileSync(logPath);
      const newData = data.slice(prevSize);
      const newLines = newData.toString().split('\\n').filter(line => line.trim());

      newLines.forEach(line => {
        this.analyzeLine(line, path.basename(logPath));
      });
    } catch (error) {
      console.error(\`Error reading log file \${logPath}:\`, error.message);
    }
  }

  analyzeLine(line, source) {
    const timestamp = new Date().toISOString();
    
    Object.entries(this.patterns).forEach(([type, pattern]) => {
      if (pattern.test(line)) {
        this.createAlert({
          timestamp,
          type,
          source,
          message: line.trim(),
          severity: this.getSeverityForType(type)
        });
      }
    });
  }

  getSeverityForType(type) {
    const severityMap = {
      error: 'critical',
      warning: 'warning', 
      ssl_issue: 'critical',
      performance: 'warning'
    };
    return severityMap[type] || 'info';
  }

  createAlert(alert) {
    // Log to alerts file
    const alertsPath = '/Users/mlautenschlager/cloudya/vault/test-results/logs/alerts.log';
    const alertLine = \`\${alert.timestamp} - \${alert.severity.toUpperCase()}: [\${alert.source}] \${alert.message}\\n\`;
    
    fs.appendFileSync(alertsPath, alertLine);
    
    // Console output for immediate visibility
    const emoji = alert.severity === 'critical' ? '🚨' : '⚠️';
    console.log(\`\${emoji} ALERT [\${alert.source}]: \${alert.message}\`);
  }

  checkLogRotation() {
    // Implement log rotation if files get too large
    this.logPaths.forEach(logPath => {
      if (fs.existsSync(logPath)) {
        const stats = fs.statSync(logPath);
        if (stats.size > 10 * 1024 * 1024) { // 10MB
          this.rotateLog(logPath);
        }
      }
    });
  }

  rotateLog(logPath) {
    const rotatedPath = logPath + '.' + new Date().toISOString().split('T')[0];
    fs.renameSync(logPath, rotatedPath);
    fs.writeFileSync(logPath, ''); // Create new empty log
    console.log(\`Rotated log: \${logPath} -> \${rotatedPath}\`);
  }
}

// Start monitoring
const monitor = new LogMonitor();
monitor.startMonitoring().catch(error => {
  console.error('Log monitoring failed:', error);
  process.exit(1);
});
`;

    const monitorPath = path.join(__dirname, '../../test-results/log-monitor.js');
    await fs.promises.writeFile(monitorPath, logMonitorScript);
    
    console.log('✓ Log monitoring setup completed');
    console.log(`  - Log monitor: ${monitorPath}`);
    console.log('  - Start with: node ' + monitorPath);
  }

  async generateSetupReport() {
    const report = {
      setup_completed: new Date().toISOString(),
      components: [
        {
          name: 'monitoring_config',
          status: 'created',
          path: '/Users/mlautenschlager/cloudya/vault/test-results/monitoring-config.json'
        },
        {
          name: 'health_check_schedule',
          status: 'created', 
          path: '/Users/mlautenschlager/cloudya/vault/test-results/health-check-schedule.sh'
        },
        {
          name: 'cron_configuration',
          status: 'created',
          path: '/Users/mlautenschlager/cloudya/vault/test-results/monitoring-crontab.txt'
        },
        {
          name: 'alerting_rules',
          status: 'created',
          path: '/Users/mlautenschlager/cloudya/vault/test-results/alerting-rules.json'
        },
        {
          name: 'monitoring_dashboard',
          status: 'created',
          path: '/Users/mlautenschlager/cloudya/vault/test-results/monitoring-dashboard.html'
        },
        {
          name: 'log_monitor',
          status: 'created',
          path: '/Users/mlautenschlager/cloudya/vault/test-results/log-monitor.js'
        }
      ],
      next_steps: [
        'Enable cron jobs: crontab < /Users/mlautenschlager/cloudya/vault/test-results/monitoring-crontab.txt',
        'Start log monitoring: node /Users/mlautenschlager/cloudya/vault/test-results/log-monitor.js',
        'Open dashboard: file:///Users/mlautenschlager/cloudya/vault/test-results/monitoring-dashboard.html',
        'Monitor alerts: tail -f /Users/mlautenschlager/cloudya/vault/test-results/logs/alerts.log'
      ]
    };

    const reportPath = path.join(__dirname, '../../test-results/reports/monitoring-setup-report.json');
    await fs.promises.writeFile(reportPath, JSON.stringify(report, null, 2));
    
    console.log('\n📋 Monitoring setup report:');
    console.log(`   Components created: ${report.components.length}`);
    console.log(`   Report saved to: ${reportPath}`);
    
    return report;
  }
}

// Run if called directly
if (require.main === module) {
  const setup = new MonitoringSetup();
  setup.setupMonitoring()
    .then(() => setup.generateSetupReport())
    .then(() => {
      console.log('\n✅ Monitoring and alerting setup completed successfully!');
      process.exit(0);
    })
    .catch((error) => {
      console.error('Monitoring setup failed:', error);
      process.exit(1);
    });
}

module.exports = MonitoringSetup;