#!/usr/bin/env node

const axios = require('axios');
const https = require('https');
const fs = require('fs');
const path = require('path');
const config = require('../config/test-config');

class EndpointTester {
  constructor() {
    this.results = [];
    this.startTime = new Date();
    
    // Create axios instance with SSL verification disabled for testing
    this.client = axios.create({
      timeout: config.TEST_TIMEOUT,
      httpsAgent: new https.Agent({
        rejectUnauthorized: false // We validate SSL separately
      }),
      validateStatus: () => true // Don't throw on HTTP error status
    });
  }

  async testAllEndpoints() {
    console.log('🌐 Starting Endpoint Validation...\n');
    
    for (const [service, endpoint] of Object.entries(config.ENDPOINTS)) {
      console.log(`Testing ${service}: ${endpoint}`);
      
      const healthPath = config.HEALTH_PATHS[service] || '/';
      const fullUrl = endpoint + healthPath;
      
      try {
        const result = await this.testEndpoint(fullUrl, service);
        this.results.push(result);
        this.printResult(result);
      } catch (error) {
        const errorResult = {
          service,
          endpoint,
          health_path: healthPath,
          status: 'ERROR',
          error: error.message,
          timestamp: new Date().toISOString()
        };
        this.results.push(errorResult);
        this.printResult(errorResult);
      }
      console.log('');
    }

    await this.generateReport();
    return this.results;
  }

  async testEndpoint(url, serviceName) {
    const startTime = Date.now();
    
    try {
      const response = await this.client.get(url);
      const responseTime = Date.now() - startTime;
      
      const result = {
        service: serviceName,
        endpoint: url,
        status: 'SUCCESS',
        timestamp: new Date().toISOString(),
        response: {
          status_code: response.status,
          status_text: response.statusText,
          response_time_ms: responseTime,
          content_length: response.headers['content-length'] || 0,
          content_type: response.headers['content-type'] || 'unknown',
          server: response.headers.server || 'unknown'
        },
        checks: {}
      };

      // Service-specific health checks
      result.checks = await this.performHealthChecks(response, serviceName);
      
      // Performance checks
      result.checks.response_time_ok = responseTime < config.PERFORMANCE_THRESHOLDS.responseTime;
      
      // Overall health assessment
      result.healthy = Object.values(result.checks).every(check => check === true);
      
      return result;
      
    } catch (error) {
      const responseTime = Date.now() - startTime;
      return {
        service: serviceName,
        endpoint: url,
        status: 'ERROR',
        timestamp: new Date().toISOString(),
        error: error.message,
        response_time_ms: responseTime,
        healthy: false
      };
    }
  }

  async performHealthChecks(response, serviceName) {
    const checks = {};
    
    // Basic HTTP checks
    checks.http_success = response.status >= 200 && response.status < 400;
    checks.has_response_body = response.data && Object.keys(response.data).length > 0;
    
    try {
      // Service-specific health checks
      switch (serviceName) {
        case 'vault':
          await this.checkVaultHealth(response, checks);
          break;
          
        case 'consul':
          await this.checkConsulHealth(response, checks);
          break;
          
        case 'nomad':
          await this.checkNomadHealth(response, checks);
          break;
          
        case 'traefik':
          await this.checkTraefikHealth(response, checks);
          break;
      }
    } catch (error) {
      checks.service_health_check_error = error.message;
    }
    
    return checks;
  }

  async checkVaultHealth(response, checks) {
    if (response.data) {
      // Vault health endpoint returns specific status indicators
      checks.vault_initialized = response.data.initialized === true;
      checks.vault_sealed = response.data.sealed === false;
      checks.vault_standby = response.data.standby !== undefined;
      
      // Check cluster status
      if (response.data.replication_performance_mode) {
        checks.vault_replication_available = true;
      }
      
      // Vault should return 200 when healthy and unsealed
      checks.vault_operational = response.status === 200 && !response.data.sealed;
    }
  }

  async checkConsulHealth(response, checks) {
    if (response.data) {
      // Consul leader endpoint should return IP:port of leader
      checks.consul_has_leader = typeof response.data === 'string' && 
                                response.data.match(/^\d+\.\d+\.\d+\.\d+:\d+$/);
      checks.consul_responding = response.status === 200;
    }
  }

  async checkNomadHealth(response, checks) {
    if (response.data) {
      // Nomad leader endpoint should return leader address
      checks.nomad_has_leader = typeof response.data === 'string' && 
                               response.data.includes(':');
      checks.nomad_responding = response.status === 200;
    }
  }

  async checkTraefikHealth(response, checks) {
    if (response.data) {
      // Traefik API should return overview data
      checks.traefik_api_accessible = response.status === 200;
      checks.traefik_has_config = response.data.http !== undefined ||
                                 response.data.tcp !== undefined;
      
      // Check if dashboard is configured
      checks.traefik_dashboard_enabled = response.headers['content-type'] && 
                                        response.headers['content-type'].includes('html');
    }
  }

  printResult(result) {
    const status = result.healthy ? '✅ HEALTHY' : (result.status === 'ERROR' ? '❌ ERROR' : '⚠️ UNHEALTHY');
    console.log(`   Status: ${status}`);
    
    if (result.response) {
      console.log(`   HTTP Status: ${result.response.status_code} ${result.response.status_text}`);
      console.log(`   Response Time: ${result.response.response_time_ms}ms`);
      console.log(`   Content Type: ${result.response.content_type}`);
    }
    
    if (result.checks) {
      const passedChecks = Object.values(result.checks).filter(v => v === true).length;
      const totalChecks = Object.keys(result.checks).length;
      console.log(`   Health Checks: ${passedChecks}/${totalChecks} passed`);
      
      // Show failed checks
      const failedChecks = Object.entries(result.checks)
        .filter(([key, value]) => value !== true)
        .map(([key]) => key);
      
      if (failedChecks.length > 0) {
        console.log(`   Failed Checks: ${failedChecks.join(', ')}`);
      }
    }
    
    if (result.error) {
      console.log(`   Error: ${result.error}`);
    }
  }

  async generateReport() {
    const endTime = new Date();
    const duration = endTime - this.startTime;
    const healthyEndpoints = this.results.filter(r => r.healthy).length;
    const totalEndpoints = this.results.length;
    
    const avgResponseTime = this.results
      .filter(r => r.response && r.response.response_time_ms)
      .reduce((sum, r) => sum + r.response.response_time_ms, 0) / 
      this.results.filter(r => r.response).length || 0;

    const report = {
      summary: {
        total_endpoints: totalEndpoints,
        healthy_endpoints: healthyEndpoints,
        unhealthy_endpoints: totalEndpoints - healthyEndpoints,
        success_rate: ((healthyEndpoints / totalEndpoints) * 100).toFixed(2) + '%',
        average_response_time: Math.round(avgResponseTime) + 'ms',
        test_duration: duration + 'ms',
        timestamp: endTime.toISOString()
      },
      results: this.results,
      recommendations: this.generateRecommendations()
    };

    const reportPath = path.join(__dirname, '../../test-results/reports/endpoint-test-report.json');
    await fs.promises.writeFile(reportPath, JSON.stringify(report, null, 2));
    
    console.log('\n📊 Endpoint Test Summary:');
    console.log(`   Total Endpoints: ${totalEndpoints}`);
    console.log(`   Healthy: ${healthyEndpoints}`);
    console.log(`   Unhealthy: ${totalEndpoints - healthyEndpoints}`);
    console.log(`   Success Rate: ${report.summary.success_rate}`);
    console.log(`   Average Response Time: ${report.summary.average_response_time}`);
    console.log(`   Report saved to: ${reportPath}`);
  }

  generateRecommendations() {
    const recommendations = [];
    
    const unhealthyServices = this.results.filter(r => !r.healthy);
    if (unhealthyServices.length > 0) {
      recommendations.push({
        priority: 'HIGH',
        issue: 'Unhealthy services detected',
        action: 'Investigate service logs and configuration',
        affected_services: unhealthyServices.map(r => r.service)
      });
    }

    const slowServices = this.results.filter(r => 
      r.response && r.response.response_time_ms > config.PERFORMANCE_THRESHOLDS.responseTime
    );
    if (slowServices.length > 0) {
      recommendations.push({
        priority: 'MEDIUM',
        issue: 'Slow response times detected',
        action: 'Optimize service performance or increase timeout thresholds',
        affected_services: slowServices.map(r => r.service)
      });
    }

    const errorServices = this.results.filter(r => r.status === 'ERROR');
    if (errorServices.length > 0) {
      recommendations.push({
        priority: 'CRITICAL',
        issue: 'Services returning errors or not responding',
        action: 'Check service status, network connectivity, and firewall rules',
        affected_services: errorServices.map(r => r.service)
      });
    }

    return recommendations;
  }
}

// Run if called directly
if (require.main === module) {
  const tester = new EndpointTester();
  tester.testAllEndpoints()
    .then(() => {
      process.exit(0);
    })
    .catch((error) => {
      console.error('Endpoint testing failed:', error);
      process.exit(1);
    });
}

module.exports = EndpointTester;