/* CONTRACT TEST
@module: ValidationServiceContractTest
@path: tests/contracts/ValidationServiceContract.test.js
@domain: testing, contracts
@feature: validation-contracts
@purpose: Contract tests per Validation Service hub: configuration validation, sanitization, error handling
@exports: test suites for Validation contracts
@consumes: ValidationService.js, test framework
@events: test:started, test:passed, test:failed
@touches: Config validation, DPI checks, Dimension validation, Error contracts
@owner: validation-testing
@risk: LOW
@tests: Validation logic contracts, Error boundaries, Configuration compliance, Data sanitization
*/

/**
 * Validation Service Contract Tests
 * Testa contratti pubblici del Validation Service hub
 * 
 * @package WC_AI_Product_Customizer
 */

// Mock canvas instance per validation testing
const mockCanvasInstance = {
    id: 'test-canvas',
    canvas: {
        getObjects: jest.fn(() => [
            { type: 'image', imageId: 'test-img', name: 'user-image' },
            { type: 'text', text: 'Hello', name: 'user-text' }
        ]),
        renderAll: jest.fn()
    },
    printAreaRect: {
        left: 10,
        top: 10,
        width: 200,
        height: 200
    },
    config: {
        width: 800,
        height: 600
    }
};

// Mock engine per getCanvasInstance
jest.mock('../../public/js/core/canvas/core/Engine.js', () => ({
    getCanvasInstance: jest.fn((canvasId) => {
        if (canvasId === 'valid-canvas') return mockCanvasInstance;
        if (canvasId === 'no-print-area') return { ...mockCanvasInstance, printAreaRect: null };
        return null;
    })
}));

// Mock globals
global.window = {
    wcAiCustomizer: {
        printAreaConfig: {
            width: 100,
            height: 100,
            dpi: 300
        }
    }
};

describe('Validation Service Hub - Contract Tests', () => {
    let ValidationService;
    
    beforeAll(async () => {
        ValidationService = await import('../../public/js/core/canvas/export/ValidationService.js');
    });
    
    beforeEach(() => {
        jest.clearAllMocks();
        
        // Reset global config to valid state
        global.window.wcAiCustomizer = {
            printAreaConfig: {
                width: 100,
                height: 100,
                dpi: 300
            }
        };
    });
    
    describe('🎯 HD Export Configuration Contract', () => {
        test('VALIDATION_CONTRACT_01: validateHDExportConfig deve restituire configurazione valida', () => {
            const canvasId = 'valid-canvas';
            
            const result = ValidationService.validateHDExportConfig(canvasId);
            
            // Verifica contratto configurazione valida
            expect(result).toBeDefined();
            expect(result.instance).toBeDefined();
            expect(result.config).toBeDefined();
            expect(result.canvas).toBeDefined();
            expect(result.instance.id).toBe(canvasId);
            expect(result.config.width).toBeDefined();
            expect(result.config.height).toBeDefined();
            expect(result.config.dpi).toBeDefined();
        });
        
        test('VALIDATION_CONTRACT_02: deve rigettare canvas inesistente', () => {
            const invalidCanvasId = 'non-existent-canvas';
            
            // Verifica contratto error handling
            expect(() => {
                ValidationService.validateHDExportConfig(invalidCanvasId);
            }).toThrow('Canvas instance not found');
        });
        
        test('VALIDATION_CONTRACT_03: deve rigettare canvas senza print area', () => {
            const canvasId = 'no-print-area';
            
            // Verifica contratto print area validation
            expect(() => {
                ValidationService.validateHDExportConfig(canvasId);
            }).toThrow('Print area not configured');
        });
        
        test('VALIDATION_CONTRACT_04: deve rigettare configurazione backend mancante', () => {
            const canvasId = 'valid-canvas';
            
            // Rimuovi configurazione backend
            delete global.window.wcAiCustomizer;
            
            // Verifica contratto backend validation
            expect(() => {
                ValidationService.validateHDExportConfig(canvasId);
            }).toThrow('Backend print area configuration not available');
        });
    });
    
    describe('🎯 DPI Validation Contract', () => {
        test('DPI_CONTRACT_01: deve accettare DPI nel range valido', () => {
            const validDPIs = [150, 200, 300, 400, 500, 600];
            
            validDPIs.forEach(dpi => {
                global.window.wcAiCustomizer.printAreaConfig.dpi = dpi;
                
                // Deve non lanciare errore
                expect(() => {
                    ValidationService.validateHDExportConfig('valid-canvas');
                }).not.toThrow();
            });
        });
        
        test('DPI_CONTRACT_02: deve rigettare DPI troppo basso', () => {
            global.window.wcAiCustomizer.printAreaConfig.dpi = 100; // Sotto soglia minima
            
            expect(() => {
                ValidationService.validateHDExportConfig('valid-canvas');
            }).toThrow('Invalid DPI value: 100');
        });
        
        test('DPI_CONTRACT_03: deve rigettare DPI troppo alto', () => {
            global.window.wcAiCustomizer.printAreaConfig.dpi = 800; // Sopra soglia massima
            
            expect(() => {
                ValidationService.validateHDExportConfig('valid-canvas');
            }).toThrow('Invalid DPI value: 800');
        });
    });
    
    describe('🎯 Dimension Validation Contract', () => {
        test('DIMENSION_CONTRACT_01: deve accettare dimensioni ragionevoli', () => {
            const validSizes = [
                { width: 50, height: 50 },
                { width: 100, height: 150 },
                { width: 297, height: 420 }, // A3
                { width: 500, height: 500 }  // Massimo
            ];
            
            validSizes.forEach(size => {
                global.window.wcAiCustomizer.printAreaConfig.width = size.width;
                global.window.wcAiCustomizer.printAreaConfig.height = size.height;
                
                expect(() => {
                    ValidationService.validateHDExportConfig('valid-canvas');
                }).not.toThrow();
            });
        });
        
        test('DIMENSION_CONTRACT_02: deve rigettare dimensioni troppo grandi', () => {
            global.window.wcAiCustomizer.printAreaConfig.width = 600; // Sopra limite
            global.window.wcAiCustomizer.printAreaConfig.height = 400;
            
            expect(() => {
                ValidationService.validateHDExportConfig('valid-canvas');
            }).toThrow('Print dimensions too large');
        });
        
        test('DIMENSION_CONTRACT_03: deve rigettare configurazione incompleta', () => {
            // Test width mancante
            delete global.window.wcAiCustomizer.printAreaConfig.width;
            
            expect(() => {
                ValidationService.validateHDExportConfig('valid-canvas');
            }).toThrow('Invalid print area configuration');
            
            // Reset e test height mancante
            global.window.wcAiCustomizer.printAreaConfig.width = 100;
            delete global.window.wcAiCustomizer.printAreaConfig.height;
            
            expect(() => {
                ValidationService.validateHDExportConfig('valid-canvas');
            }).toThrow('Invalid print area configuration');
        });
    });
    
    describe('🎯 Content Validation Contract', () => {
        test('CONTENT_CONTRACT_01: validateUserContent deve identificare oggetti utente', () => {
            const canvasId = 'valid-canvas';
            const mockInstance = {
                canvas: {
                    getObjects: jest.fn(() => [
                        { type: 'image', imageId: 'user-img-1', name: 'user-upload' },
                        { type: 'text', text: 'User Text', name: 'user-text' },
                        { type: 'rect', name: 'background' } // Non-user object
                    ])
                }
            };
            
            // Mock temporaneo per questo test
            const originalMock = require('../../public/js/core/canvas/core/Engine.js').getCanvasInstance;
            require('../../public/js/core/canvas/core/Engine.js').getCanvasInstance.mockReturnValue(mockInstance);
            
            const hasContent = ValidationService.validateUserContent(canvasId);
            
            // Verifica contratto content detection
            expect(hasContent).toBe(true);
            expect(mockInstance.canvas.getObjects).toHaveBeenCalled();
            
            // Restore original mock
            require('../../public/js/core/canvas/core/Engine.js').getCanvasInstance.mockImplementation(originalMock);
        });
        
        test('CONTENT_CONTRACT_02: deve restituire false per canvas senza contenuto utente', () => {
            const canvasId = 'valid-canvas';
            const mockEmptyInstance = {
                canvas: {
                    getObjects: jest.fn(() => [
                        { type: 'rect', name: 'background' },
                        { type: 'line', name: 'grid' }
                    ])
                }
            };
            
            const originalMock = require('../../public/js/core/canvas/core/Engine.js').getCanvasInstance;
            require('../../public/js/core/canvas/core/Engine.js').getCanvasInstance.mockReturnValue(mockEmptyInstance);
            
            const hasContent = ValidationService.validateUserContent(canvasId);
            
            // Verifica contratto empty content
            expect(hasContent).toBe(false);
            
            require('../../public/js/core/canvas/core/Engine.js').getCanvasInstance.mockImplementation(originalMock);
        });
    });
    
    describe('🎯 Error Boundary Contracts', () => {
        test('ERROR_BOUNDARY_01: validation deve gestire gracefully canvas null', () => {
            const originalMock = require('../../public/js/core/canvas/core/Engine.js').getCanvasInstance;
            require('../../public/js/core/canvas/core/Engine.js').getCanvasInstance.mockReturnValue(null);
            
            expect(() => {
                ValidationService.validateUserContent('invalid-canvas');
            }).not.toThrow(); // Deve gestire gracefully e restituire false
            
            const result = ValidationService.validateUserContent('invalid-canvas');
            expect(result).toBe(false);
            
            require('../../public/js/core/canvas/core/Engine.js').getCanvasInstance.mockImplementation(originalMock);
        });
        
        test('ERROR_BOUNDARY_02: validation deve gestire oggetti canvas malformati', () => {
            const mockBrokenInstance = {
                canvas: {
                    getObjects: jest.fn(() => {
                        throw new Error('Canvas corrupted');
                    })
                }
            };
            
            const originalMock = require('../../public/js/core/canvas/core/Engine.js').getCanvasInstance;
            require('../../public/js/core/canvas/core/Engine.js').getCanvasInstance.mockReturnValue(mockBrokenInstance);
            
            // Deve gestire l'errore gracefully
            const result = ValidationService.validateUserContent('broken-canvas');
            expect(result).toBe(false);
            
            require('../../public/js/core/canvas/core/Engine.js').getCanvasInstance.mockImplementation(originalMock);
        });
    });
    
    describe('🎯 Data Sanitization Contracts', () => {
        test('SANITIZATION_CONTRACT_01: configurazione deve essere sanitizzata', () => {
            // Test con valori stringa che dovrebbero essere numerici
            global.window.wcAiCustomizer.printAreaConfig.width = '100';
            global.window.wcAiCustomizer.printAreaConfig.height = '200';
            global.window.wcAiCustomizer.printAreaConfig.dpi = '300';
            
            const result = ValidationService.validateHDExportConfig('valid-canvas');
            
            // Verifica che la validazione gestisca correttamente i tipi
            expect(result).toBeDefined();
            expect(result.config).toBeDefined();
        });
        
        test('SANITIZATION_CONTRACT_02: deve gestire valori NaN e Infinity', () => {
            global.window.wcAiCustomizer.printAreaConfig.width = NaN;
            global.window.wcAiCustomizer.printAreaConfig.height = Infinity;
            
            expect(() => {
                ValidationService.validateHDExportConfig('valid-canvas');
            }).toThrow('Invalid print area configuration');
        });
    });
});

// Export validation contract utilities
export const ValidationContractUtils = {
    createValidConfig: (overrides = {}) => ({
        width: 100,
        height: 100,
        dpi: 300,
        ...overrides
    }),
    
    createMockInstance: (hasContent = true, hasPrintArea = true) => ({
        id: 'mock-canvas',
        canvas: {
            getObjects: jest.fn(() => hasContent ? [
                { type: 'image', imageId: 'test', name: 'user-image' }
            ] : []),
            renderAll: jest.fn()
        },
        printAreaRect: hasPrintArea ? { left: 0, top: 0, width: 200, height: 200 } : null,
        config: { width: 800, height: 600 }
    }),
    
    verifyValidationResult: (result) => {
        expect(result).toBeDefined();
        expect(result.instance).toBeDefined();
        expect(result.config).toBeDefined();
        expect(result.canvas).toBeDefined();
    },
    
    testDPIRange: (ValidationService, validCanvasId, minDPI = 150, maxDPI = 600) => {
        // Test boundary values
        [minDPI, maxDPI].forEach(dpi => {
            global.window.wcAiCustomizer.printAreaConfig.dpi = dpi;
            expect(() => {
                ValidationService.validateHDExportConfig(validCanvasId);
            }).not.toThrow();
        });
        
        // Test out of range values
        [minDPI - 1, maxDPI + 1].forEach(dpi => {
            global.window.wcAiCustomizer.printAreaConfig.dpi = dpi;
            expect(() => {
                ValidationService.validateHDExportConfig(validCanvasId);
            }).toThrow();
        });
    }
};