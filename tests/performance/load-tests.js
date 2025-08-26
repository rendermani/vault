#!/usr/bin/env node

const axios = require('axios');
const https = require('https');
const fs = require('fs');
const path = require('path');
const config = require('../config/test-config');

class LoadTester {
  constructor() {
    this.results = [];
    this.startTime = new Date();
    
    this.client = axios.create({
      timeout: config.TEST_TIMEOUT,
      httpsAgent: new https.Agent({
        rejectUnauthorized: false,
        keepAlive: true,
        maxSockets: 100
      }),
      validateStatus: () => true
    });
  }

  async runLoadTests() {
    console.log('⚡ Starting Performance Load Testing...\n');
    
    const testScenarios = [
      { name: 'Single Request Baseline', concurrent: 1, requests: 5 },
      { name: 'Light Load', concurrent: 5, requests: 25 },
      { name: 'Medium Load', concurrent: 10, requests: 50 },
      { name: 'Heavy Load', concurrent: 20, requests: 100 }
    ];

    for (const scenario of testScenarios) {
      console.log(`Running ${scenario.name} (${scenario.concurrent} concurrent, ${scenario.requests} total requests)`);
      
      for (const [service, endpoint] of Object.entries(config.ENDPOINTS)) {
        try {
          const result = await this.runLoadScenario(endpoint, service, scenario);
          this.results.push(result);
          this.printResult(result);
        } catch (error) {
          const errorResult = {
            service,
            endpoint,
            scenario: scenario.name,
            status: 'ERROR',
            error: error.message,
            timestamp: new Date().toISOString()
          };
          this.results.push(errorResult);
          this.printResult(errorResult);
        }
      }
      console.log('');
    }

    await this.generateReport();
    return this.results;
  }

  async runLoadScenario(endpoint, serviceName, scenario) {
    const startTime = Date.now();
    const results = [];
    const errors = [];
    
    // Create batches of concurrent requests
    const batches = Math.ceil(scenario.requests / scenario.concurrent);
    
    for (let batch = 0; batch < batches; batch++) {
      const batchSize = Math.min(scenario.concurrent, scenario.requests - (batch * scenario.concurrent));
      const promises = [];
      
      // Create concurrent requests for this batch
      for (let i = 0; i < batchSize; i++) {
        promises.push(this.makeRequest(endpoint).catch(error => ({ error: error.message })));
      }
      
      const batchResults = await Promise.all(promises);
      
      // Separate successful results from errors
      batchResults.forEach(result => {
        if (result.error) {
          errors.push(result.error);
        } else {
          results.push(result);
        }
      });
    }
    
    const endTime = Date.now();
    const totalDuration = endTime - startTime;
    
    // Calculate statistics
    const responseTimes = results.map(r => r.responseTime).filter(rt => rt !== undefined);
    const statusCodes = results.map(r => r.statusCode).filter(sc => sc !== undefined);
    
    const stats = {
      service: serviceName,
      endpoint,
      scenario: scenario.name,
      timestamp: new Date().toISOString(),
      
      // Request statistics
      total_requests: scenario.requests,
      successful_requests: results.length,
      failed_requests: errors.length,
      success_rate: ((results.length / scenario.requests) * 100).toFixed(2) + '%',
      
      // Timing statistics
      total_duration_ms: totalDuration,
      average_response_time: responseTimes.length > 0 ? Math.round(responseTimes.reduce((a, b) => a + b, 0) / responseTimes.length) : 0,
      min_response_time: responseTimes.length > 0 ? Math.min(...responseTimes) : 0,
      max_response_time: responseTimes.length > 0 ? Math.max(...responseTimes) : 0,
      requests_per_second: scenario.requests / (totalDuration / 1000),
      
      // Performance analysis
      performance_analysis: {
        meets_response_time_threshold: responseTimes.every(rt => rt < config.PERFORMANCE_THRESHOLDS.responseTime),
        average_under_threshold: responseTimes.length > 0 ? 
          (responseTimes.reduce((a, b) => a + b, 0) / responseTimes.length) < config.PERFORMANCE_THRESHOLDS.responseTime : false,
        no_timeouts: errors.filter(e => e.includes('timeout')).length === 0,
        stable_performance: this.calculatePerformanceStability(responseTimes)
      },
      
      // HTTP status analysis
      status_codes: this.analyzeStatusCodes(statusCodes),
      
      // Error analysis
      errors: errors.slice(0, 10), // Keep first 10 errors for analysis
      error_types: this.analyzeErrors(errors)
    };
    
    // Overall performance rating
    stats.performance_rating = this.calculatePerformanceRating(stats);
    
    return stats;
  }

  async makeRequest(endpoint) {
    const startTime = Date.now();
    
    try {
      const response = await this.client.get(endpoint);
      const responseTime = Date.now() - startTime;
      
      return {
        statusCode: response.status,
        responseTime,
        contentLength: response.headers['content-length'] || 0,
        success: response.status >= 200 && response.status < 400
      };
    } catch (error) {
      const responseTime = Date.now() - startTime;
      return {
        error: error.message,
        responseTime,
        success: false
      };
    }
  }

  analyzeStatusCodes(statusCodes) {
    const distribution = {};
    statusCodes.forEach(code => {
      distribution[code] = (distribution[code] || 0) + 1;
    });
    
    return {
      distribution,
      success_codes: Object.keys(distribution).filter(code => code >= 200 && code < 400).length,
      client_errors: Object.keys(distribution).filter(code => code >= 400 && code < 500).length,
      server_errors: Object.keys(distribution).filter(code => code >= 500).length
    };
  }

  analyzeErrors(errors) {
    const errorTypes = {};
    
    errors.forEach(error => {
      if (error.includes('timeout')) {
        errorTypes.timeouts = (errorTypes.timeouts || 0) + 1;
      } else if (error.includes('ECONNRESET') || error.includes('ECONNREFUSED')) {
        errorTypes.connection_errors = (errorTypes.connection_errors || 0) + 1;
      } else if (error.includes('ENOTFOUND')) {
        errorTypes.dns_errors = (errorTypes.dns_errors || 0) + 1;
      } else {
        errorTypes.other = (errorTypes.other || 0) + 1;
      }
    });
    
    return errorTypes;
  }

  calculatePerformanceStability(responseTimes) {
    if (responseTimes.length < 2) return false;
    
    const mean = responseTimes.reduce((a, b) => a + b, 0) / responseTimes.length;
    const variance = responseTimes.reduce((a, b) => a + Math.pow(b - mean, 2), 0) / responseTimes.length;
    const stdDev = Math.sqrt(variance);
    const coefficientOfVariation = stdDev / mean;
    
    // Performance is considered stable if CV is less than 0.3 (30%)
    return coefficientOfVariation < 0.3;
  }

  calculatePerformanceRating(stats) {
    let score = 100;
    
    // Deduct points for failures
    const failureRate = parseFloat(stats.success_rate.replace('%', ''));
    if (failureRate < 100) {
      score -= (100 - failureRate) * 2; // 2 points per % failure
    }
    
    // Deduct points for slow response times
    if (stats.average_response_time > config.PERFORMANCE_THRESHOLDS.responseTime) {
      score -= 20;
    }
    
    // Deduct points for instability
    if (!stats.performance_analysis.stable_performance) {
      score -= 10;
    }
    
    // Deduct points for errors
    if (stats.failed_requests > 0) {
      score -= Math.min(stats.failed_requests * 2, 30);
    }
    
    // Rate performance
    if (score >= 90) return 'EXCELLENT';
    if (score >= 80) return 'GOOD';
    if (score >= 70) return 'ACCEPTABLE';
    if (score >= 60) return 'POOR';
    return 'UNACCEPTABLE';
  }

  printResult(result) {
    if (result.status === 'ERROR') {
      console.log(`   ❌ ${result.service}: ${result.error}`);
      return;
    }
    
    const rating = result.performance_rating;
    const ratingEmoji = {
      'EXCELLENT': '🟢',
      'GOOD': '🟡', 
      'ACCEPTABLE': '🟠',
      'POOR': '🔴',
      'UNACCEPTABLE': '⚫'
    };
    
    console.log(`   ${ratingEmoji[rating] || '⚪'} ${result.service}`);
    console.log(`      Success Rate: ${result.success_rate}`);
    console.log(`      Avg Response: ${result.average_response_time}ms`);
    console.log(`      Req/sec: ${result.requests_per_second.toFixed(2)}`);
    console.log(`      Performance: ${rating}`);
  }

  async generateReport() {
    const endTime = new Date();
    const duration = endTime - this.startTime;
    
    // Aggregate results by service
    const serviceResults = {};
    this.results.forEach(result => {
      if (!serviceResults[result.service]) {
        serviceResults[result.service] = [];
      }
      serviceResults[result.service].push(result);
    });
    
    // Calculate overall performance metrics
    const overallMetrics = this.calculateOverallMetrics();
    
    const report = {
      summary: {
        test_duration: Math.round(duration / 1000) + ' seconds',
        total_test_scenarios: this.results.length,
        services_tested: Object.keys(serviceResults).length,
        overall_performance: overallMetrics.rating,
        average_success_rate: overallMetrics.avgSuccessRate + '%',
        average_response_time: Math.round(overallMetrics.avgResponseTime) + 'ms',
        timestamp: endTime.toISOString()
      },
      service_results: serviceResults,
      detailed_results: this.results,
      performance_analysis: {
        bottlenecks: this.identifyBottlenecks(),
        recommendations: this.generatePerformanceRecommendations()
      }
    };

    const reportPath = path.join(__dirname, '../../test-results/reports/performance-test-report.json');
    await fs.promises.writeFile(reportPath, JSON.stringify(report, null, 2));
    
    console.log('\n📊 Performance Test Summary:');
    console.log(`   Overall Performance: ${overallMetrics.rating}`);
    console.log(`   Average Success Rate: ${report.summary.average_success_rate}`);
    console.log(`   Average Response Time: ${report.summary.average_response_time}`);
    console.log(`   Services Tested: ${report.summary.services_tested}`);
    console.log(`   Report saved to: ${reportPath}`);
  }

  calculateOverallMetrics() {
    const validResults = this.results.filter(r => r.status !== 'ERROR');
    
    if (validResults.length === 0) {
      return {
        rating: 'NO_DATA',
        avgSuccessRate: 0,
        avgResponseTime: 0
      };
    }
    
    const avgSuccessRate = validResults.reduce((sum, r) => 
      sum + parseFloat(r.success_rate.replace('%', '')), 0) / validResults.length;
    
    const avgResponseTime = validResults.reduce((sum, r) => 
      sum + r.average_response_time, 0) / validResults.length;
    
    // Determine overall rating based on worst individual service rating
    const ratings = validResults.map(r => r.performance_rating);
    const ratingPriority = ['UNACCEPTABLE', 'POOR', 'ACCEPTABLE', 'GOOD', 'EXCELLENT'];
    const worstRating = ratings.reduce((worst, current) => {
      const worstIndex = ratingPriority.indexOf(worst);
      const currentIndex = ratingPriority.indexOf(current);
      return currentIndex < worstIndex ? current : worst;
    }, 'EXCELLENT');
    
    return {
      rating: worstRating,
      avgSuccessRate: avgSuccessRate.toFixed(2),
      avgResponseTime
    };
  }

  identifyBottlenecks() {
    const bottlenecks = [];
    const validResults = this.results.filter(r => r.status !== 'ERROR');
    
    // Identify slow services
    const slowServices = validResults.filter(r => 
      r.average_response_time > config.PERFORMANCE_THRESHOLDS.responseTime
    );
    
    if (slowServices.length > 0) {
      bottlenecks.push({
        type: 'SLOW_RESPONSE',
        services: slowServices.map(s => s.service),
        impact: 'High response times affecting user experience'
      });
    }
    
    // Identify services with high failure rates
    const unreliableServices = validResults.filter(r => 
      parseFloat(r.success_rate.replace('%', '')) < 95
    );
    
    if (unreliableServices.length > 0) {
      bottlenecks.push({
        type: 'HIGH_FAILURE_RATE',
        services: unreliableServices.map(s => s.service),
        impact: 'Service reliability issues causing failed requests'
      });
    }
    
    // Identify services with unstable performance
    const unstableServices = validResults.filter(r => 
      !r.performance_analysis.stable_performance
    );
    
    if (unstableServices.length > 0) {
      bottlenecks.push({
        type: 'PERFORMANCE_INSTABILITY',
        services: unstableServices.map(s => s.service),
        impact: 'Inconsistent performance may indicate resource constraints'
      });
    }
    
    return bottlenecks;
  }

  generatePerformanceRecommendations() {
    const recommendations = [];
    const bottlenecks = this.identifyBottlenecks();
    
    if (bottlenecks.some(b => b.type === 'SLOW_RESPONSE')) {
      recommendations.push({
        priority: 'HIGH',
        action: 'Optimize slow services',
        details: 'Investigate database queries, add caching, optimize algorithms, consider horizontal scaling'
      });
    }
    
    if (bottlenecks.some(b => b.type === 'HIGH_FAILURE_RATE')) {
      recommendations.push({
        priority: 'CRITICAL',
        action: 'Improve service reliability',
        details: 'Check error logs, improve error handling, implement circuit breakers, add health checks'
      });
    }
    
    if (bottlenecks.some(b => b.type === 'PERFORMANCE_INSTABILITY')) {
      recommendations.push({
        priority: 'MEDIUM',
        action: 'Stabilize performance',
        details: 'Monitor resource usage, implement proper resource limits, consider load balancing'
      });
    }
    
    if (bottlenecks.length === 0) {
      recommendations.push({
        priority: 'MAINTENANCE',
        action: 'Monitor and maintain',
        details: 'Performance is currently acceptable. Continue regular monitoring and capacity planning.'
      });
    }
    
    return recommendations;
  }
}

// Run if called directly
if (require.main === module) {
  const tester = new LoadTester();
  tester.runLoadTests()
    .then(() => {
      process.exit(0);
    })
    .catch((error) => {
      console.error('Performance testing failed:', error);
      process.exit(1);
    });
}

module.exports = LoadTester;