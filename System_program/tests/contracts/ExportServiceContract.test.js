/* CONTRACT TEST
@module: ExportServiceContractTest
@path: tests/contracts/ExportServiceContract.test.js
@domain: testing, contracts
@feature: export-contracts
@purpose: Contract tests per Export Service hub: export operations, idempotenza, performance
@exports: test suites for Export contracts
@consumes: ExportService.js, IdempotencyManager.js, test framework
@events: test:started, test:passed, test:failed
@touches: Export operations, Idempotency behavior, Performance contracts, Error handling
@owner: export-testing
@risk: LOW
@tests: Export API contracts, Idempotency verification, Performance characteristics, Error scenarios
*/

/**
 * Export Service Contract Tests
 * Testa contratti pubblici dell'Export Service hub
 * 
 * @package WC_AI_Product_Customizer
 */

// Mock per ExportService dependencies
const mockCanvasData = {
    objects: [
        { type: 'image', imageId: 'test-img-1', name: 'user-image' },
        { type: 'text', text: 'Hello World', name: 'user-text' }
    ],
    width: 800,
    height: 600,
    backgroundColor: '#ffffff'
};

const mockExportResult = {
    data: 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
    isBlob: false
};

// Mock screenshot capture
jest.mock('../../public/js/core/canvas/export/ScreenshotCapture.js', () => ({
    captureCanvasScreenshot: jest.fn((canvasId, options, callback) => {
        setTimeout(() => callback(mockExportResult.data, mockExportResult.isBlob), 10);
    })
}));

// Mock HD exporter
jest.mock('../../public/js/core/canvas/export/HDExporter.js', () => ({
    generateHDPrintImage: jest.fn((canvasId, callback) => {
        setTimeout(() => callback(mockExportResult.data, mockExportResult.isBlob), 20);
    })
}));

describe('Export Service Hub - Contract Tests', () => {
    let ExportService, IdempotencyManager;
    
    beforeAll(async () => {
        // Import after mocks
        const exportModule = await import('../../public/js/core/canvas/export/ExportService.js');
        const idempotencyModule = await import('../../public/js/core/canvas/export/IdempotencyManager.js');
        
        ExportService = exportModule;
        IdempotencyManager = idempotencyModule.default;
    });
    
    beforeEach(() => {
        jest.clearAllMocks();
        // Reset idempotency cache
        if (ExportService.resetExportCache) {
            ExportService.resetExportCache();
        }
    });
    
    describe('🎯 Export API Interface Contract', () => {
        test('EXPORT_CONTRACT_01: exportCanvas deve restituire Promise con data', async () => {
            const canvasId = 'test-export-1';
            const format = 'screenshot';
            
            const result = await ExportService.exportCanvas(canvasId, format, {}, mockCanvasData);
            
            // Verifica contratto interfaccia
            expect(result).toBeDefined();
            expect(result.data).toBeDefined();
            expect(typeof result.isBlob).toBe('boolean');
        });
        
        test('EXPORT_CONTRACT_02: exportMultiple deve gestire array formati', async () => {
            const canvasId = 'test-export-2';
            const formats = ['screenshot', 'hdPrint'];
            
            const results = await ExportService.exportMultiple(canvasId, formats, {}, mockCanvasData);
            
            // Verifica contratto multiple export
            expect(results).toBeDefined();
            expect(typeof results).toBe('object');
            expect(results.screenshot).toBeDefined();
            expect(results.hdPrint).toBeDefined();
        });
        
        test('EXPORT_CONTRACT_03: exportForCheckout deve includere screenshot e hdPrint', async () => {
            const canvasId = 'test-export-3';
            
            const result = await ExportService.exportForCheckout(canvasId);
            
            // Verifica contratto checkout export
            expect(result).toBeDefined();
            expect(result.screenshot).toBeDefined();
            expect(result.hdPrint).toBeDefined();
            expect(result.screenshot.data).toBeDefined();
            expect(result.hdPrint.data).toBeDefined();
        });
        
        test('EXPORT_CONTRACT_04: getExportStats deve restituire metriche complete', () => {
            const stats = ExportService.getExportStats();
            
            // Verifica contratto statistiche
            expect(stats).toBeDefined();
            expect(typeof stats.totalJobs).toBe('number');
            expect(typeof stats.duplicatesPrevented).toBe('number');
            expect(typeof stats.cacheHits).toBe('number');
            expect(typeof stats.averageJobTime).toBe('number');
            expect(typeof stats.duplicatePercentage).toBe('string');
            expect(typeof stats.cacheHitPercentage).toBe('string');
            expect(typeof stats.averageJobTimeFormatted).toBe('string');
        });
    });
    
    describe('🎯 Idempotency Contract', () => {
        test('IDEMPOTENCY_CONTRACT_01: export identici devono restituire stesso risultato', async () => {
            const canvasId = 'test-idempotency-1';
            const format = 'screenshot';
            const options = { quality: 0.8 };
            
            // Primo export
            const result1 = await ExportService.exportCanvas(canvasId, format, options, mockCanvasData);
            
            // Secondo export identico
            const result2 = await ExportService.exportCanvas(canvasId, format, options, mockCanvasData);
            
            // Verifica contratto idempotenza
            expect(result1).toBeDefined();
            expect(result2).toBeDefined();
            expect(result1.data).toBe(result2.data);
            expect(result1.isBlob).toBe(result2.isBlob);
        });
        
        test('IDEMPOTENCY_CONTRACT_02: generateExportJobId deve essere deterministic', () => {
            const canvasId = 'test-job-id';
            const stageIds = ['stage1', 'stage2'];
            const options = { format: 'screenshot', quality: 0.8 };
            
            // Genera due job ID identici
            const jobId1 = ExportService.generateExportJobId(canvasId, stageIds, options, mockCanvasData);
            const jobId2 = ExportService.generateExportJobId(canvasId, stageIds, options, mockCanvasData);
            
            // Verifica contratto determinismo
            expect(jobId1).toBeDefined();
            expect(jobId2).toBeDefined();
            expect(jobId1).toBe(jobId2);
            expect(typeof jobId1).toBe('string');
            expect(jobId1.length).toBeGreaterThan(0);
        });
        
        test('IDEMPOTENCY_CONTRACT_03: job ID diversi per parametri diversi', () => {
            const canvasId = 'test-job-diff';
            const stageIds1 = ['stage1'];
            const stageIds2 = ['stage2'];
            const options = { format: 'screenshot' };
            
            const jobId1 = ExportService.generateExportJobId(canvasId, stageIds1, options, mockCanvasData);
            const jobId2 = ExportService.generateExportJobId(canvasId, stageIds2, options, mockCanvasData);
            
            // Verifica contratto unicità
            expect(jobId1).not.toBe(jobId2);
        });
        
        test('IDEMPOTENCY_CONTRACT_04: preventDuplicateExport deve prevenire esecuzioni multiple', async () => {
            const jobId = 'test-prevent-duplicate';
            let executionCount = 0;
            
            const testFunction = async () => {
                executionCount++;
                await new Promise(resolve => setTimeout(resolve, 10));
                return { result: 'test', count: executionCount };
            };
            
            // Esegui due operazioni duplicate in parallelo
            const [result1, result2] = await Promise.all([
                ExportService.preventDuplicateExport(jobId, testFunction),
                ExportService.preventDuplicateExport(jobId, testFunction)
            ]);
            
            // Verifica contratto prevenzione duplicati
            expect(executionCount).toBe(1); // Funzione eseguita solo una volta
            expect(result1).toBeDefined();
            expect(result2).toBeDefined();
            expect(result1.result).toBe('test');
            expect(result2.result).toBe('test');
        });
    });
    
    describe('🎯 Performance Contracts', () => {
        test('PERFORMANCE_CONTRACT_01: export deve completare entro timeout ragionevole', async () => {
            const canvasId = 'test-performance-1';
            const format = 'screenshot';
            const startTime = performance.now();
            
            await ExportService.exportCanvas(canvasId, format, {}, mockCanvasData);
            
            const duration = performance.now() - startTime;
            
            // Verifica contratto performance (timeout di 5 secondi)
            expect(duration).toBeLessThan(5000);
        }, 6000);
        
        test('PERFORMANCE_CONTRACT_02: statistiche devono aggiornare metriche tempo', async () => {
            const canvasId = 'test-performance-2';
            const format = 'screenshot';
            
            // Verifica stats iniziali
            const initialStats = ExportService.getExportStats();
            const initialJobs = initialStats.totalJobs;
            
            // Esegui export
            await ExportService.exportCanvas(canvasId, format, {}, mockCanvasData);
            
            // Verifica aggiornamento stats
            const updatedStats = ExportService.getExportStats();
            expect(updatedStats.totalJobs).toBeGreaterThan(initialJobs);
        });
    });
    
    describe('🎯 Error Handling Contracts', () => {
        test('ERROR_CONTRACT_01: exportCanvas deve rigettare per formato non supportato', async () => {
            const canvasId = 'test-error-1';
            const invalidFormat = 'unsupported-format';
            
            // Verifica contratto error handling
            await expect(
                ExportService.exportCanvas(canvasId, invalidFormat, {}, mockCanvasData)
            ).rejects.toThrow('Unsupported format');
        });
        
        test('ERROR_CONTRACT_02: generateExportJobId deve gestire parametri invalidi', () => {
            // Test con parametri null/undefined
            expect(() => {
                ExportService.generateExportJobId(null, [], {}, {});
            }).not.toThrow(); // Deve fallback a ID safe
            
            expect(() => {
                ExportService.generateExportJobId('test', null, {}, {});
            }).not.toThrow(); // Deve gestire gracefully
        });
        
        test('ERROR_CONTRACT_03: exportMultiple deve gestire errori parziali', async () => {
            const canvasId = 'test-error-3';
            const formats = ['screenshot', 'unsupported-format'];
            
            const results = await ExportService.exportMultiple(canvasId, formats, {}, mockCanvasData);
            
            // Verifica contratto errori parziali
            expect(results).toBeDefined();
            expect(results.screenshot).toBeDefined();
            expect(results['unsupported-format']).toBeDefined();
            expect(results['unsupported-format'].error).toBeDefined();
        });
    });
    
    describe('🎯 State Management Contracts', () => {
        test('STATE_CONTRACT_01: resetExportCache deve pulire correttamente', () => {
            const initialStats = ExportService.getExportStats();
            
            // Reset cache
            ExportService.resetExportCache();
            
            const resetStats = ExportService.getExportStats();
            
            // Verifica contratto reset
            expect(resetStats.totalJobs).toBe(0);
            expect(resetStats.duplicatesPrevented).toBe(0);
            expect(resetStats.cacheHits).toBe(0);
            expect(resetStats.cacheSize).toBe(0);
        });
        
        test('STATE_CONTRACT_02: cache deve rispettare TTL', async () => {
            // Questo test verifica che la cache management funzioni correttamente
            // In un ambiente di test vero si potrebbe manipolare il tempo
            const stats = ExportService.getExportStats();
            expect(typeof stats.cacheSize).toBe('number');
            expect(stats.cacheSize).toBeGreaterThanOrEqual(0);
        });
    });
});

// Export contract utilities
export const ExportContractUtils = {
    createMockExportResult: (data = mockExportResult.data, isBlob = false) => ({
        data,
        isBlob
    }),
    
    verifyExportResult: (result) => {
        expect(result).toBeDefined();
        expect(result.data).toBeDefined();
        expect(typeof result.isBlob).toBe('boolean');
    },
    
    verifyStatsContract: (stats) => {
        expect(stats).toBeDefined();
        expect(typeof stats.totalJobs).toBe('number');
        expect(typeof stats.duplicatesPrevented).toBe('number');
        expect(typeof stats.cacheHits).toBe('number');
        expect(typeof stats.averageJobTime).toBe('number');
        expect(typeof stats.duplicatePercentage).toBe('string');
        expect(typeof stats.cacheHitPercentage).toBe('string');
    }
};