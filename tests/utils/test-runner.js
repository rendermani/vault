#!/usr/bin/env node

const SSLValidator = require('../ssl/ssl-validator');
const EndpointTester = require('../integration/endpoint-tests');
const DeploymentValidator = require('../e2e/deployment-validation');
const fs = require('fs');
const path = require('path');

class TestRunner {
  constructor() {
    this.startTime = new Date();
    this.results = {
      ssl: null,
      endpoints: null,
      deployment: null
    };
  }

  async runAllTests() {
    console.log('🧪 Starting Comprehensive Test Suite for Cloudya Vault Deployment\n');
    console.log('=' .repeat(80));
    console.log('');

    try {
      // Run SSL validation
      console.log('🔐 Phase 1: SSL Certificate Validation');
      console.log('-'.repeat(50));
      const sslValidator = new SSLValidator();
      this.results.ssl = await sslValidator.validateAllEndpoints();
      
      console.log('\n' + '=' .repeat(80));
      
      // Run endpoint tests
      console.log('🌐 Phase 2: Endpoint Health Validation');
      console.log('-'.repeat(50));
      const endpointTester = new EndpointTester();
      this.results.endpoints = await endpointTester.testAllEndpoints();
      
      console.log('\n' + '=' .repeat(80));
      
      // Run deployment validation
      console.log('🚀 Phase 3: End-to-End Deployment Validation');
      console.log('-'.repeat(50));
      const deploymentValidator = new DeploymentValidator();
      this.results.deployment = await deploymentValidator.validateDeployment();
      
      console.log('\n' + '=' .repeat(80));

      // Generate comprehensive report
      await this.generateComprehensiveReport();
      
    } catch (error) {
      console.error('❌ Test suite execution failed:', error);
      process.exit(1);
    }
  }

  async generateComprehensiveReport() {
    const endTime = new Date();
    const totalDuration = endTime - this.startTime;
    
    // Analyze results
    const sslResults = this.results.ssl || [];
    const endpointResults = this.results.endpoints || [];
    const deploymentResults = this.results.deployment || [];
    
    const sslValid = sslResults.filter(r => r.valid).length;
    const endpointsHealthy = endpointResults.filter(r => r.healthy).length;
    const deploymentStepsPassed = deploymentResults.filter(r => r.success).length;
    
    const overallStatus = this.calculateOverallStatus();
    
    const comprehensiveReport = {
      test_run_summary: {
        overall_status: overallStatus,
        execution_time: Math.round(totalDuration / 1000) + ' seconds',
        timestamp: endTime.toISOString(),
        test_phases: {
          ssl_validation: {
            total_certificates: sslResults.length,
            valid_certificates: sslValid,
            success_rate: sslResults.length > 0 ? ((sslValid / sslResults.length) * 100).toFixed(1) + '%' : '0%'
          },
          endpoint_testing: {
            total_endpoints: endpointResults.length,
            healthy_endpoints: endpointsHealthy,
            success_rate: endpointResults.length > 0 ? ((endpointsHealthy / endpointResults.length) * 100).toFixed(1) + '%' : '0%'
          },
          deployment_validation: {
            total_steps: deploymentResults.length,
            passed_steps: deploymentStepsPassed,
            success_rate: deploymentResults.length > 0 ? ((deploymentStepsPassed / deploymentResults.length) * 100).toFixed(1) + '%' : '0%'
          }
        }
      },
      detailed_results: {
        ssl_validation: sslResults,
        endpoint_testing: endpointResults,
        deployment_validation: deploymentResults
      },
      critical_issues: this.identifyCriticalIssues(),
      recommendations: this.generateOverallRecommendations(),
      production_readiness: this.assessProductionReadiness()
    };

    // Save comprehensive report
    const reportPath = path.join(__dirname, '../../test-results/reports/comprehensive-test-report.json');
    await fs.promises.writeFile(reportPath, JSON.stringify(comprehensiveReport, null, 2));
    
    // Generate executive summary
    await this.generateExecutiveSummary(comprehensiveReport);
    
    // Print summary to console
    this.printFinalSummary(comprehensiveReport);
    
    return comprehensiveReport;
  }

  calculateOverallStatus() {
    const sslResults = this.results.ssl || [];
    const endpointResults = this.results.endpoints || [];
    const deploymentResults = this.results.deployment || [];
    
    const sslPassed = sslResults.every(r => r.valid);
    const endpointsPassed = endpointResults.every(r => r.healthy);
    const deploymentPassed = deploymentResults.every(r => r.success);
    
    if (sslPassed && endpointsPassed && deploymentPassed) {
      return 'PASSED';
    } else if (sslResults.length === 0 && endpointResults.length === 0 && deploymentResults.length === 0) {
      return 'NO_TESTS_RUN';
    } else {
      return 'FAILED';
    }
  }

  identifyCriticalIssues() {
    const issues = [];
    
    // SSL Issues
    const invalidSSL = (this.results.ssl || []).filter(r => !r.valid);
    if (invalidSSL.length > 0) {
      issues.push({
        severity: 'CRITICAL',
        category: 'SSL',
        issue: 'Invalid SSL certificates detected',
        affected_services: invalidSSL.map(r => r.service),
        impact: 'Browser warnings, security vulnerabilities, user trust issues'
      });
    }
    
    // Default Traefik certificates
    const defaultCerts = (this.results.ssl || []).filter(r => 
      r.checks && r.checks.not_default_traefik === false
    );
    if (defaultCerts.length > 0) {
      issues.push({
        severity: 'CRITICAL',
        category: 'SSL',
        issue: 'Default Traefik certificates in use',
        affected_services: defaultCerts.map(r => r.service),
        impact: 'Insecure connections, certificate warnings, production deployment blocker'
      });
    }
    
    // Service Health Issues
    const unhealthyServices = (this.results.endpoints || []).filter(r => !r.healthy);
    if (unhealthyServices.length > 0) {
      issues.push({
        severity: 'HIGH',
        category: 'Service Health',
        issue: 'Unhealthy services detected',
        affected_services: unhealthyServices.map(r => r.service),
        impact: 'Service unavailability, functionality loss, user experience degradation'
      });
    }
    
    // Deployment Issues
    const failedDeploymentSteps = (this.results.deployment || []).filter(r => !r.success);
    if (failedDeploymentSteps.length > 0) {
      issues.push({
        severity: 'HIGH',
        category: 'Deployment',
        issue: 'Deployment validation steps failed',
        failed_steps: failedDeploymentSteps.map(r => r.step),
        impact: 'Incomplete deployment, potential system instability, production readiness concerns'
      });
    }
    
    return issues;
  }

  generateOverallRecommendations() {
    const recommendations = [];
    const criticalIssues = this.identifyCriticalIssues();
    
    if (criticalIssues.some(i => i.category === 'SSL')) {
      recommendations.push({
        priority: 'IMMEDIATE',
        action: 'Fix SSL certificate configuration',
        details: 'Configure Let\'s Encrypt or proper certificate provisioning. Remove default Traefik certificates.',
        urgency: 'Must be resolved before production deployment'
      });
    }
    
    if (criticalIssues.some(i => i.category === 'Service Health')) {
      recommendations.push({
        priority: 'HIGH',
        action: 'Investigate and fix unhealthy services',
        details: 'Check service logs, configuration, and dependencies. Ensure proper startup sequence.',
        urgency: 'Required for system functionality'
      });
    }
    
    if (criticalIssues.length === 0) {
      recommendations.push({
        priority: 'MAINTENANCE',
        action: 'Monitor and maintain',
        details: 'All tests passed. Continue monitoring and maintain regular testing schedule.',
        urgency: 'Ongoing operational requirement'
      });
    }
    
    return recommendations;
  }

  assessProductionReadiness() {
    const criticalIssues = this.identifyCriticalIssues();
    const highSeverityIssues = criticalIssues.filter(i => 
      i.severity === 'CRITICAL' || i.severity === 'HIGH'
    );
    
    if (highSeverityIssues.length === 0) {
      return {
        status: 'READY',
        confidence: 'HIGH',
        message: 'All critical tests passed. System appears ready for production deployment.',
        blockers: []
      };
    } else {
      return {
        status: 'NOT_READY',
        confidence: 'LOW',
        message: 'Critical issues detected that must be resolved before production deployment.',
        blockers: highSeverityIssues.map(i => i.issue)
      };
    }
  }

  async generateExecutiveSummary(report) {
    const summary = `
# Cloudya Vault Deployment Test Results

## Executive Summary
**Overall Status:** ${report.test_run_summary.overall_status}
**Production Ready:** ${report.production_readiness.status}
**Test Execution Time:** ${report.test_run_summary.execution_time}
**Timestamp:** ${report.test_run_summary.timestamp}

## Test Results Overview

### SSL Certificate Validation
- **Status:** ${report.test_run_summary.test_phases.ssl_validation.success_rate} success rate
- **Valid Certificates:** ${report.test_run_summary.test_phases.ssl_validation.valid_certificates}/${report.test_run_summary.test_phases.ssl_validation.total_certificates}

### Endpoint Health Testing
- **Status:** ${report.test_run_summary.test_phases.endpoint_testing.success_rate} success rate  
- **Healthy Endpoints:** ${report.test_run_summary.test_phases.endpoint_testing.healthy_endpoints}/${report.test_run_summary.test_phases.endpoint_testing.total_endpoints}

### Deployment Validation
- **Status:** ${report.test_run_summary.test_phases.deployment_validation.success_rate} success rate
- **Passed Steps:** ${report.test_run_summary.test_phases.deployment_validation.passed_steps}/${report.test_run_summary.test_phases.deployment_validation.total_steps}

## Critical Issues
${report.critical_issues.length === 0 ? 'None detected ✅' : 
  report.critical_issues.map(issue => `- **${issue.severity}:** ${issue.issue} (${issue.affected_services?.join(', ') || issue.failed_steps?.join(', ') || 'Multiple areas'})`).join('\n')}

## Recommendations
${report.recommendations.map(rec => `- **${rec.priority}:** ${rec.action}`).join('\n')}

## Production Readiness Assessment
${report.production_readiness.message}

${report.production_readiness.blockers.length > 0 ? 
  '**Deployment Blockers:**\n' + report.production_readiness.blockers.map(b => `- ${b}`).join('\n') : 
  '**No deployment blockers detected.**'}
`;

    const summaryPath = path.join(__dirname, '../../test-results/executive-summary.md');
    await fs.promises.writeFile(summaryPath, summary);
    
    console.log(`\n📋 Executive summary saved to: ${summaryPath}`);
  }

  printFinalSummary(report) {
    console.log('\n🏁 FINAL TEST SUMMARY');
    console.log('=' .repeat(80));
    console.log(`Overall Status: ${report.test_run_summary.overall_status === 'PASSED' ? '✅ PASSED' : '❌ FAILED'}`);
    console.log(`Production Ready: ${report.production_readiness.status === 'READY' ? '✅ YES' : '❌ NO'}`);
    console.log(`Execution Time: ${report.test_run_summary.execution_time}`);
    console.log('');
    
    if (report.critical_issues.length > 0) {
      console.log('🚨 Critical Issues Found:');
      report.critical_issues.forEach(issue => {
        console.log(`   - ${issue.issue} (${issue.severity})`);
      });
      console.log('');
    }
    
    console.log('📊 Test Phase Results:');
    console.log(`   SSL Validation: ${report.test_run_summary.test_phases.ssl_validation.success_rate}`);
    console.log(`   Endpoint Testing: ${report.test_run_summary.test_phases.endpoint_testing.success_rate}`);
    console.log(`   Deployment Validation: ${report.test_run_summary.test_phases.deployment_validation.success_rate}`);
    console.log('');
    
    console.log('📁 Reports Generated:');
    console.log('   - /Users/mlautenschlager/cloudya/vault/test-results/reports/comprehensive-test-report.json');
    console.log('   - /Users/mlautenschlager/cloudya/vault/test-results/executive-summary.md');
    console.log('   - Individual test reports in test-results/reports/');
    console.log('');
    
    if (report.production_readiness.status === 'READY') {
      console.log('🎉 Deployment automation validation PASSED! System ready for production.');
    } else {
      console.log('⚠️  Issues detected. Address blockers before production deployment.');
    }
  }
}

// Run if called directly
if (require.main === module) {
  const runner = new TestRunner();
  runner.runAllTests()
    .then(() => {
      process.exit(0);
    })
    .catch((error) => {
      console.error('Test suite failed:', error);
      process.exit(1);
    });
}

module.exports = TestRunner;