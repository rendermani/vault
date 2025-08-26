#!/usr/bin/env node

const https = require('https');
const tls = require('tls');
const fs = require('fs');
const path = require('path');
const config = require('../config/test-config');

class SSLValidator {
  constructor() {
    this.results = [];
    this.startTime = new Date();
  }

  async validateAllEndpoints() {
    console.log('🔐 Starting SSL Certificate Validation...\n');
    
    for (const [service, endpoint] of Object.entries(config.ENDPOINTS)) {
      console.log(`Testing ${service}: ${endpoint}`);
      try {
        const result = await this.validateSSLCertificate(endpoint, service);
        this.results.push(result);
        this.printResult(result);
      } catch (error) {
        const errorResult = {
          service,
          endpoint,
          valid: false,
          error: error.message,
          timestamp: new Date().toISOString()
        };
        this.results.push(errorResult);
        this.printResult(errorResult);
      }
      console.log(''); // Empty line for readability
    }

    await this.generateReport();
    return this.results;
  }

  validateSSLCertificate(endpoint, serviceName) {
    return new Promise((resolve, reject) => {
      const url = new URL(endpoint);
      const options = {
        hostname: url.hostname,
        port: url.port || 443,
        method: 'HEAD',
        timeout: config.SSL_TIMEOUT,
        rejectUnauthorized: false // We'll manually validate
      };

      const req = https.request(options, (res) => {
        const cert = res.socket.getPeerCertificate(true);
        const result = this.analyzeCertificate(cert, serviceName, endpoint);
        resolve(result);
      });

      req.on('error', (error) => {
        reject(new Error(`Connection failed: ${error.message}`));
      });

      req.on('timeout', () => {
        req.destroy();
        reject(new Error('SSL handshake timeout'));
      });

      req.setTimeout(config.SSL_TIMEOUT);
      req.end();
    });
  }

  analyzeCertificate(cert, serviceName, endpoint) {
    const now = new Date();
    const validFrom = new Date(cert.valid_from);
    const validTo = new Date(cert.valid_to);
    const daysUntilExpiry = Math.floor((validTo - now) / (1000 * 60 * 60 * 24));
    
    const analysis = {
      service: serviceName,
      endpoint,
      valid: true,
      timestamp: new Date().toISOString(),
      certificate: {
        subject: cert.subject,
        issuer: cert.issuer,
        valid_from: cert.valid_from,
        valid_to: cert.valid_to,
        days_until_expiry: daysUntilExpiry,
        serial_number: cert.serialNumber,
        fingerprint: cert.fingerprint,
        fingerprint256: cert.fingerprint256,
        subject_alt_names: cert.subjectaltname
      },
      checks: {}
    };

    // Check 1: Certificate not expired
    analysis.checks.not_expired = validTo > now;
    if (!analysis.checks.not_expired) {
      analysis.valid = false;
      analysis.errors = analysis.errors || [];
      analysis.errors.push('Certificate has expired');
    }

    // Check 2: Certificate not yet valid
    analysis.checks.already_valid = validFrom <= now;
    if (!analysis.checks.already_valid) {
      analysis.valid = false;
      analysis.errors = analysis.errors || [];
      analysis.errors.push('Certificate is not yet valid');
    }

    // Check 3: Certificate expires soon
    analysis.checks.sufficient_validity = daysUntilExpiry >= config.SSL_VALIDATION.minValidDays;
    if (!analysis.checks.sufficient_validity) {
      analysis.warnings = analysis.warnings || [];
      analysis.warnings.push(`Certificate expires in ${daysUntilExpiry} days`);
    }

    // Check 4: Not a default Traefik certificate
    analysis.checks.not_default_traefik = !this.isDefaultTraefikCertificate(cert);
    if (!analysis.checks.not_default_traefik) {
      analysis.valid = false;
      analysis.errors = analysis.errors || [];
      analysis.errors.push('Using default Traefik certificate - SSL not properly configured');
    }

    // Check 5: Proper issuer (Let's Encrypt expected)
    analysis.checks.proper_issuer = cert.issuer.O && 
      (cert.issuer.O.includes("Let's Encrypt") || cert.issuer.O.includes('ZeroSSL'));
    if (!analysis.checks.proper_issuer) {
      analysis.warnings = analysis.warnings || [];
      analysis.warnings.push(`Unexpected issuer: ${cert.issuer.O || 'Unknown'}`);
    }

    // Check 6: Subject Alternative Names include expected domain
    const hostname = new URL(endpoint).hostname;
    analysis.checks.correct_san = cert.subjectaltname && 
      cert.subjectaltname.includes(`DNS:${hostname}`);
    if (!analysis.checks.correct_san) {
      analysis.valid = false;
      analysis.errors = analysis.errors || [];
      analysis.errors.push(`Certificate SAN does not include ${hostname}`);
    }

    return analysis;
  }

  isDefaultTraefikCertificate(cert) {
    // Default Traefik certificates have specific characteristics
    const subject = cert.subject;
    const issuer = cert.issuer;
    
    // Check for self-signed (issuer == subject)
    if (JSON.stringify(issuer) === JSON.stringify(subject)) {
      return true;
    }

    // Check for common Traefik default certificate subjects
    if (subject.CN === 'TRAEFIK DEFAULT CERT' || 
        subject.CN === 'traefik-default-cert' ||
        (subject.O === 'Traefik' && subject.OU === 'Generated')) {
      return true;
    }

    // Check serial number patterns of default certs
    if (cert.serialNumber === '1' || cert.serialNumber === '01') {
      return true;
    }

    return false;
  }

  printResult(result) {
    const status = result.valid ? '✅ VALID' : '❌ INVALID';
    console.log(`   Status: ${status}`);
    
    if (result.certificate) {
      console.log(`   Issuer: ${result.certificate.issuer.O || 'Unknown'}`);
      console.log(`   Subject: ${result.certificate.subject.CN || 'Unknown'}`);
      console.log(`   Valid Until: ${result.certificate.valid_to}`);
      console.log(`   Days Until Expiry: ${result.certificate.days_until_expiry}`);
    }

    if (result.errors && result.errors.length > 0) {
      console.log(`   ❌ Errors:`);
      result.errors.forEach(error => console.log(`      - ${error}`));
    }

    if (result.warnings && result.warnings.length > 0) {
      console.log(`   ⚠️  Warnings:`);
      result.warnings.forEach(warning => console.log(`      - ${warning}`));
    }

    if (result.error) {
      console.log(`   ❌ Error: ${result.error}`);
    }
  }

  async generateReport() {
    const endTime = new Date();
    const duration = endTime - this.startTime;
    const validCerts = this.results.filter(r => r.valid).length;
    const totalCerts = this.results.length;

    const report = {
      summary: {
        total_certificates: totalCerts,
        valid_certificates: validCerts,
        invalid_certificates: totalCerts - validCerts,
        success_rate: ((validCerts / totalCerts) * 100).toFixed(2) + '%',
        test_duration: duration + 'ms',
        timestamp: endTime.toISOString()
      },
      results: this.results,
      recommendations: this.generateRecommendations()
    };

    const reportPath = path.join(__dirname, '../../test-results/reports/ssl-validation-report.json');
    await fs.promises.writeFile(reportPath, JSON.stringify(report, null, 2));
    
    console.log('\n📊 SSL Validation Summary:');
    console.log(`   Total Certificates: ${totalCerts}`);
    console.log(`   Valid: ${validCerts}`);
    console.log(`   Invalid: ${totalCerts - validCerts}`);
    console.log(`   Success Rate: ${report.summary.success_rate}`);
    console.log(`   Report saved to: ${reportPath}`);
  }

  generateRecommendations() {
    const recommendations = [];
    
    const invalidResults = this.results.filter(r => !r.valid);
    if (invalidResults.length > 0) {
      recommendations.push({
        priority: 'HIGH',
        issue: 'Invalid SSL certificates detected',
        action: 'Review SSL configuration and certificate provisioning',
        affected_services: invalidResults.map(r => r.service)
      });
    }

    const soonExpiring = this.results.filter(r => 
      r.certificate && r.certificate.days_until_expiry < config.SSL_VALIDATION.minValidDays
    );
    if (soonExpiring.length > 0) {
      recommendations.push({
        priority: 'MEDIUM',
        issue: 'Certificates expiring soon',
        action: 'Set up automated certificate renewal',
        affected_services: soonExpiring.map(r => r.service)
      });
    }

    const defaultTraefikCerts = this.results.filter(r => 
      r.checks && !r.checks.not_default_traefik
    );
    if (defaultTraefikCerts.length > 0) {
      recommendations.push({
        priority: 'CRITICAL',
        issue: 'Default Traefik certificates in use',
        action: 'Configure Let\'s Encrypt or proper certificate provisioning',
        affected_services: defaultTraefikCerts.map(r => r.service)
      });
    }

    return recommendations;
  }
}

// Run if called directly
if (require.main === module) {
  const validator = new SSLValidator();
  validator.validateAllEndpoints()
    .then(() => {
      process.exit(0);
    })
    .catch((error) => {
      console.error('SSL Validation failed:', error);
      process.exit(1);
    });
}

module.exports = SSLValidator;