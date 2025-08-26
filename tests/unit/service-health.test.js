const config = require('../config/test-config');

describe('Service Health Configuration Tests', () => {
  test('should have valid endpoint configurations', () => {
    expect(config.ENDPOINTS).toBeDefined();
    expect(Object.keys(config.ENDPOINTS)).toHaveLength(4);
    
    // Check all required services are configured
    expect(config.ENDPOINTS.vault).toBeDefined();
    expect(config.ENDPOINTS.consul).toBeDefined();
    expect(config.ENDPOINTS.nomad).toBeDefined();
    expect(config.ENDPOINTS.traefik).toBeDefined();
    
    // Check URLs are properly formatted
    Object.values(config.ENDPOINTS).forEach(endpoint => {
      expect(endpoint).toMatch(/^https:\/\/.+\.cloudya\.net$/);
    });
  });

  test('should have health check paths configured', () => {
    expect(config.HEALTH_PATHS).toBeDefined();
    expect(Object.keys(config.HEALTH_PATHS)).toHaveLength(4);
    
    // Check health paths start with /
    Object.values(config.HEALTH_PATHS).forEach(path => {
      expect(path).toMatch(/^\//);
    });
  });

  test('should have reasonable timeout configurations', () => {
    expect(config.TEST_TIMEOUT).toBeGreaterThan(5000); // At least 5 seconds
    expect(config.SSL_TIMEOUT).toBeGreaterThan(1000); // At least 1 second
    expect(config.HEALTH_CHECK_TIMEOUT).toBeGreaterThan(10000); // At least 10 seconds
  });

  test('should have performance thresholds configured', () => {
    expect(config.PERFORMANCE_THRESHOLDS).toBeDefined();
    expect(config.PERFORMANCE_THRESHOLDS.responseTime).toBeGreaterThan(0);
    expect(config.PERFORMANCE_THRESHOLDS.availability).toBeGreaterThan(90);
    expect(config.PERFORMANCE_THRESHOLDS.ssl_handshake).toBeGreaterThan(0);
  });

  test('should have SSL validation settings', () => {
    expect(config.SSL_VALIDATION).toBeDefined();
    expect(config.SSL_VALIDATION.minValidDays).toBeGreaterThan(0);
    expect(config.SSL_VALIDATION.rejectDefaultTraefikCerts).toBe(true);
  });
});

describe('Environment Configuration Tests', () => {
  test('should handle missing environment variables gracefully', () => {
    const originalEnv = process.env.NODE_ENV;
    delete process.env.NODE_ENV;
    
    // Re-require to test default behavior
    delete require.cache[require.resolve('../config/test-config')];
    const testConfig = require('../config/test-config');
    
    expect(testConfig.TEST_ENV).toBe('test');
    
    // Restore
    process.env.NODE_ENV = originalEnv;
  });

  test('should have retry configuration', () => {
    expect(config.RETRY).toBeDefined();
    expect(config.RETRY.attempts).toBeGreaterThan(0);
    expect(config.RETRY.delay).toBeGreaterThan(0);
  });
});

describe('Service Endpoint Validation', () => {
  test('should validate URL format for all endpoints', () => {
    const urlRegex = /^https:\/\/[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$/;
    
    Object.entries(config.ENDPOINTS).forEach(([service, endpoint]) => {
      expect(endpoint).toMatch(urlRegex);
      expect(endpoint).toContain('cloudya.net');
      expect(endpoint).toContain(service);
    });
  });

  test('should have consistent service naming', () => {
    const services = Object.keys(config.ENDPOINTS);
    const healthServices = Object.keys(config.HEALTH_PATHS);
    
    expect(services.sort()).toEqual(healthServices.sort());
  });
});