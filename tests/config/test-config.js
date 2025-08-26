// Load environment variables if dotenv is available
try {
  require('dotenv').config();
} catch (e) {
  // dotenv not available, continue without it
}

module.exports = {
  // Test configuration
  TEST_TIMEOUT: 30000,
  SSL_TIMEOUT: 10000,
  HEALTH_CHECK_TIMEOUT: 60000,
  
  // Service endpoints
  ENDPOINTS: {
    vault: 'https://vault.cloudya.net',
    consul: 'https://consul.cloudya.net',
    nomad: 'https://nomad.cloudya.net',
    traefik: 'https://traefik.cloudya.net'
  },
  
  // Health check paths
  HEALTH_PATHS: {
    vault: '/v1/sys/health',
    consul: '/v1/status/leader',
    nomad: '/v1/status/leader',
    traefik: '/api/overview'
  },
  
  // SSL validation settings
  SSL_VALIDATION: {
    checkExpiry: true,
    checkIssuer: true,
    checkSubjectAltName: true,
    minValidDays: 30,
    expectedIssuer: 'Let\'s Encrypt',
    rejectDefaultTraefikCerts: true
  },
  
  // Performance thresholds
  PERFORMANCE_THRESHOLDS: {
    responseTime: 2000, // 2 seconds max
    availability: 99.9,  // 99.9% uptime
    ssl_handshake: 1000  // 1 second max for SSL
  },
  
  // Test environments
  TEST_ENV: process.env.NODE_ENV || 'test',
  
  // Retry configuration
  RETRY: {
    attempts: 3,
    delay: 2000 // 2 seconds between attempts
  }
};