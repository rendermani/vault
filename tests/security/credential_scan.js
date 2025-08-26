/**
 * Security Tests - Credential Scanning
 * Scans for hardcoded credentials and validates security practices
 */

const { describe, it, beforeEach, afterEach, expect } = require('@jest/globals');
const fs = require('fs').promises;
const path = require('path');
const { glob } = require('glob');

describe('Security - Credential Scanning Tests', () => {
    const testReportPath = path.join(__dirname, '../reports/credential_security_report.json');
    const testResults = [];
    const projectRoot = path.resolve(__dirname, '../../');

    afterEach(async () => {
        try {
            await fs.mkdir(path.dirname(testReportPath), { recursive: true });
            await fs.writeFile(testReportPath, JSON.stringify({
                timestamp: new Date().toISOString(),
                results: testResults
            }, null, 2));
        } catch (error) {
            console.error('Failed to write credential security test report:', error);
        }
    });

    describe('Hardcoded Credential Detection', () => {
        const dangerousPatterns = [
            { pattern: /password\s*=\s*["'].*["']/gi, type: 'Password', risk: 'HIGH' },
            { pattern: /api[_-]?key\s*=\s*["'].*["']/gi, type: 'API Key', risk: 'HIGH' },
            { pattern: /secret\s*=\s*["'].*["']/gi, type: 'Secret', risk: 'HIGH' },
            { pattern: /token\s*=\s*["'].*["']/gi, type: 'Token', risk: 'HIGH' },
            { pattern: /database[_-]?url\s*=\s*["'].*["']/gi, type: 'Database URL', risk: 'MEDIUM' },
            { pattern: /private[_-]?key\s*=\s*["'].*["']/gi, type: 'Private Key', risk: 'CRITICAL' },
            { pattern: /-----BEGIN\s+PRIVATE\s+KEY-----/gi, type: 'Private Key Block', risk: 'CRITICAL' },
            { pattern: /aws[_-]?access[_-]?key[_-]?id\s*=\s*["'].*["']/gi, type: 'AWS Access Key', risk: 'CRITICAL' },
            { pattern: /aws[_-]?secret[_-]?access[_-]?key\s*=\s*["'].*["']/gi, type: 'AWS Secret Key', risk: 'CRITICAL' },
            { pattern: /github[_-]?token\s*=\s*["'].*["']/gi, type: 'GitHub Token', risk: 'HIGH' }
        ];

        const allowedTestPatterns = [
            /test[_-]?password/gi,
            /example[_-]?key/gi,
            /mock[_-]?token/gi,
            /dummy[_-]?secret/gi,
            /placeholder/gi,
            /\$\{.*\}/g, // Environment variables
            /{{\s*.*\s*}}/g, // Template variables
            /\*\*\*\*+/g // Masked values
        ];

        it('should scan all source files for hardcoded credentials', async () => {
            const testStart = Date.now();
            const findings = [];
            
            try {
                // Get all relevant files
                const patterns = [
                    '**/*.js',
                    '**/*.ts',
                    '**/*.json',
                    '**/*.yaml',
                    '**/*.yml',
                    '**/*.env*',
                    '**/*.config.*'
                ];

                const filePaths = [];
                for (const pattern of patterns) {
                    const files = await glob(pattern, {
                        cwd: projectRoot,
                        ignore: ['node_modules/**', '.git/**', 'tests/**', '**/*.test.*', '**/test/**']
                    });
                    filePaths.push(...files.map(f => path.join(projectRoot, f)));
                }

                // Scan each file
                for (const filePath of filePaths) {
                    try {
                        const content = await fs.readFile(filePath, 'utf8');
                        const relativePath = path.relative(projectRoot, filePath);

                        for (const { pattern, type, risk } of dangerousPatterns) {
                            const matches = content.match(pattern);
                            if (matches) {
                                for (const match of matches) {
                                    // Check if it's an allowed test pattern
                                    const isAllowed = allowedTestPatterns.some(allowed => 
                                        allowed.test(match)
                                    );

                                    if (!isAllowed) {
                                        const lines = content.split('\n');
                                        const lineNumber = lines.findIndex(line => line.includes(match)) + 1;
                                        
                                        findings.push({
                                            file: relativePath,
                                            line: lineNumber,
                                            type,
                                            risk,
                                            match: match.substring(0, 50) + '...',
                                            context: lines[lineNumber - 1]?.trim()
                                        });
                                    }
                                }
                            }
                        }
                    } catch (error) {
                        // Skip files that cannot be read
                        continue;
                    }
                }

                // Evaluate results
                const criticalFindings = findings.filter(f => f.risk === 'CRITICAL');
                const highFindings = findings.filter(f => f.risk === 'HIGH');

                if (findings.length === 0) {
                    testResults.push({
                        test: 'Hardcoded Credential Scan',
                        status: 'PASS',
                        duration: Date.now() - testStart,
                        details: `Scanned ${filePaths.length} files, no hardcoded credentials found`,
                        filesScanned: filePaths.length
                    });
                } else {
                    testResults.push({
                        test: 'Hardcoded Credential Scan',
                        status: criticalFindings.length > 0 ? 'FAIL' : 'WARN',
                        duration: Date.now() - testStart,
                        details: `Found ${findings.length} potential security issues`,
                        findings,
                        summary: {
                            critical: criticalFindings.length,
                            high: highFindings.length,
                            total: findings.length
                        }
                    });
                }

                expect(criticalFindings.length).toBe(0);
                if (highFindings.length > 0) {
                    console.warn(`Warning: Found ${highFindings.length} high-risk credential patterns`);
                }

            } catch (error) {
                testResults.push({
                    test: 'Hardcoded Credential Scan',
                    status: 'FAIL',
                    duration: Date.now() - testStart,
                    error: error.message
                });
                throw error;
            }
        });

        it('should validate environment variable usage', async () => {
            const envFiles = await glob('**/.env*', {
                cwd: projectRoot,
                ignore: ['node_modules/**', '.git/**']
            });

            const envVarUsage = [];
            const configFiles = await glob('**/config/**/*.{js,json,yaml,yml}', {
                cwd: projectRoot,
                ignore: ['node_modules/**', '.git/**']
            });

            for (const configFile of configFiles) {
                try {
                    const content = await fs.readFile(path.join(projectRoot, configFile), 'utf8');
                    
                    // Look for environment variable usage patterns
                    const envPatterns = [
                        /process\.env\.(\w+)/g,
                        /\$\{(\w+)\}/g,
                        /\$(\w+)/g
                    ];

                    for (const pattern of envPatterns) {
                        const matches = content.matchAll(pattern);
                        for (const match of matches) {
                            envVarUsage.push({
                                file: configFile,
                                variable: match[1],
                                pattern: match[0]
                            });
                        }
                    }
                } catch (error) {
                    continue;
                }
            }

            testResults.push({
                test: 'Environment Variable Usage',
                status: 'PASS',
                details: `Found ${envFiles.length} env files and ${envVarUsage.length} env variable references`,
                envFiles: envFiles.length,
                envReferences: envVarUsage.length
            });

            expect(envVarUsage.length).toBeGreaterThan(0); // Should use env vars
        });

        it('should check for weak default passwords', async () => {
            const weakPasswords = [
                'password',
                '123456',
                'admin',
                'root',
                'guest',
                'test',
                'default',
                'changeme',
                'password123',
                'admin123'
            ];

            const weakPasswordFindings = [];
            
            // Get all configuration and script files
            const configFiles = await glob('**/*.{js,json,yaml,yml,sh,conf}', {
                cwd: projectRoot,
                ignore: ['node_modules/**', '.git/**', 'tests/**']
            });

            for (const configFile of configFiles) {
                try {
                    const content = await fs.readFile(path.join(projectRoot, configFile), 'utf8');
                    
                    for (const weakPassword of weakPasswords) {
                        const pattern = new RegExp(`["']${weakPassword}["']`, 'gi');
                        if (pattern.test(content)) {
                            const lines = content.split('\n');
                            const lineNumber = lines.findIndex(line => pattern.test(line)) + 1;
                            
                            weakPasswordFindings.push({
                                file: configFile,
                                line: lineNumber,
                                weakPassword,
                                context: lines[lineNumber - 1]?.trim()
                            });
                        }
                    }
                } catch (error) {
                    continue;
                }
            }

            if (weakPasswordFindings.length === 0) {
                testResults.push({
                    test: 'Weak Default Password Check',
                    status: 'PASS',
                    details: 'No weak default passwords found in configuration files'
                });
            } else {
                testResults.push({
                    test: 'Weak Default Password Check',
                    status: 'FAIL',
                    details: `Found ${weakPasswordFindings.length} weak default passwords`,
                    findings: weakPasswordFindings
                });
            }

            expect(weakPasswordFindings.length).toBe(0);
        });

        it('should validate certificate and key file permissions', async () => {
            const certFiles = await glob('**/*.{pem,crt,key,p12,pfx}', {
                cwd: projectRoot,
                ignore: ['node_modules/**', '.git/**']
            });

            const permissionIssues = [];

            for (const certFile of certFiles) {
                try {
                    const filePath = path.join(projectRoot, certFile);
                    const stats = await fs.stat(filePath);
                    const mode = stats.mode & parseInt('777', 8);
                    
                    // Private keys should be 600 or 400
                    if (certFile.includes('.key') || certFile.includes('private')) {
                        if (mode !== parseInt('600', 8) && mode !== parseInt('400', 8)) {
                            permissionIssues.push({
                                file: certFile,
                                currentMode: mode.toString(8),
                                expectedMode: '600 or 400',
                                risk: 'HIGH'
                            });
                        }
                    }
                    
                    // Certificates can be more permissive but not world-writable
                    if (mode & parseInt('002', 8)) {
                        permissionIssues.push({
                            file: certFile,
                            currentMode: mode.toString(8),
                            issue: 'World-writable',
                            risk: 'MEDIUM'
                        });
                    }
                } catch (error) {
                    // File might not exist or be accessible
                    continue;
                }
            }

            if (permissionIssues.length === 0) {
                testResults.push({
                    test: 'Certificate File Permissions',
                    status: 'PASS',
                    details: `Checked ${certFiles.length} certificate files, permissions are secure`
                });
            } else {
                testResults.push({
                    test: 'Certificate File Permissions',
                    status: 'FAIL',
                    details: `Found ${permissionIssues.length} permission issues`,
                    findings: permissionIssues
                });
            }

            expect(permissionIssues.filter(issue => issue.risk === 'HIGH').length).toBe(0);
        });
    });

    describe('Sensitive Data Patterns', () => {
        it('should detect potential PII in configuration', async () => {
            const piiPatterns = [
                { pattern: /\b\d{3}-\d{2}-\d{4}\b/g, type: 'SSN', risk: 'HIGH' },
                { pattern: /\b\d{4}[\s-]?\d{4}[\s-]?\d{4}[\s-]?\d{4}\b/g, type: 'Credit Card', risk: 'CRITICAL' },
                { pattern: /\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}\b/g, type: 'Email', risk: 'LOW' },
                { pattern: /\b\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\b/g, type: 'IP Address', risk: 'MEDIUM' }
            ];

            const configFiles = await glob('**/*.{json,yaml,yml,env}', {
                cwd: projectRoot,
                ignore: ['node_modules/**', '.git/**', 'tests/**']
            });

            const piiFindings = [];

            for (const configFile of configFiles) {
                try {
                    const content = await fs.readFile(path.join(projectRoot, configFile), 'utf8');
                    
                    for (const { pattern, type, risk } of piiPatterns) {
                        const matches = content.matchAll(pattern);
                        for (const match of matches) {
                            // Skip common false positives
                            if (type === 'IP Address' && (
                                match[0].startsWith('127.') || 
                                match[0].startsWith('192.168.') ||
                                match[0] === '0.0.0.0'
                            )) {
                                continue;
                            }

                            piiFindings.push({
                                file: configFile,
                                type,
                                risk,
                                value: match[0]
                            });
                        }
                    }
                } catch (error) {
                    continue;
                }
            }

            const criticalPII = piiFindings.filter(f => f.risk === 'CRITICAL');
            
            testResults.push({
                test: 'PII Detection in Configuration',
                status: criticalPII.length > 0 ? 'FAIL' : 'PASS',
                details: `Found ${piiFindings.length} potential PII instances`,
                findings: piiFindings.filter(f => f.risk === 'CRITICAL' || f.risk === 'HIGH')
            });

            expect(criticalPII.length).toBe(0);
        });

        it('should validate secret rotation indicators', async () => {
            const configFiles = await glob('**/*.{js,json,yaml,yml}', {
                cwd: projectRoot,
                ignore: ['node_modules/**', '.git/**', 'tests/**']
            });

            let hasRotationConfig = false;
            const rotationPatterns = [
                /rotation[_-]?interval/gi,
                /secret[_-]?ttl/gi,
                /key[_-]?rotation/gi,
                /expire[_-]?after/gi,
                /max[_-]?age/gi
            ];

            for (const configFile of configFiles) {
                try {
                    const content = await fs.readFile(path.join(projectRoot, configFile), 'utf8');
                    
                    if (rotationPatterns.some(pattern => pattern.test(content))) {
                        hasRotationConfig = true;
                        break;
                    }
                } catch (error) {
                    continue;
                }
            }

            testResults.push({
                test: 'Secret Rotation Configuration',
                status: hasRotationConfig ? 'PASS' : 'WARN',
                details: hasRotationConfig 
                    ? 'Found secret rotation configuration'
                    : 'No secret rotation configuration detected'
            });

            // This is a recommendation, not a hard requirement
            if (!hasRotationConfig) {
                console.warn('Consider implementing secret rotation for enhanced security');
            }
        });
    });
});