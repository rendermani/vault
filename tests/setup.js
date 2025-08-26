/**
 * Jest Test Setup
 * Global test configuration and setup for all test suites
 */

// Increase timeout for integration tests
jest.setTimeout(60000);

// Global test configuration
global.TEST_CONFIG = {
    timeouts: {
        integration: 60000,
        security: 45000,
        performance: 120000,
        ssl: 30000
    },
    endpoints: {
        vault: process.env.VAULT_ADDR || 'http://localhost:8200',
        consul: process.env.CONSUL_ADDR || 'http://localhost:8500',
        nomad: process.env.NOMAD_ADDR || 'http://localhost:4646',
        traefik: process.env.TRAEFIK_ADDR || 'http://localhost:8080'
    },
    skipIntegrationTests: process.env.SKIP_INTEGRATION === 'true',
    skipPerformanceTests: process.env.SKIP_PERFORMANCE === 'true'
};

// Mock console methods in test environment to reduce noise
const originalConsole = console;
global.console = {
    ...originalConsole,
    log: process.env.NODE_ENV === 'test' ? jest.fn() : originalConsole.log,
    warn: process.env.NODE_ENV === 'test' ? jest.fn() : originalConsole.warn,
    error: originalConsole.error, // Always show errors
    info: process.env.NODE_ENV === 'test' ? jest.fn() : originalConsole.info
};

// Global test utilities
global.testUtils = {
    // Wait for a specified amount of time
    sleep: (ms) => new Promise(resolve => setTimeout(resolve, ms)),
    
    // Generate random test data
    generateRandomString: (length = 10) => {
        return Math.random().toString(36).substring(2, length + 2);
    },
    
    // Create mock response with timing
    createMockResponse: (data, delay = 0) => {
        return new Promise(resolve => {
            setTimeout(() => resolve(data), delay);
        });
    },
    
    // Retry function with exponential backoff
    retryWithBackoff: async (fn, maxRetries = 3, baseDelay = 1000) => {
        for (let i = 0; i < maxRetries; i++) {
            try {
                return await fn();
            } catch (error) {
                if (i === maxRetries - 1) throw error;
                await global.testUtils.sleep(baseDelay * Math.pow(2, i));
            }
        }
    }
};

// Global error handler for unhandled rejections
process.on('unhandledRejection', (reason, promise) => {
    console.error('Unhandled Rejection at:', promise, 'reason:', reason);
});

// Cleanup after all tests
afterAll(async () => {
    // Cleanup any global resources if needed
    if (global.gc) {
        global.gc();
    }
});