/* CONTRACT TEST
@module: CanvasEngineContractTest
@path: tests/contracts/CanvasEngineContract.test.js
@domain: testing, contracts
@feature: canvas-contracts
@purpose: Contract tests per Canvas Engine hub: interfacce pubbliche, lifecycle, state management
@exports: test suites for Canvas contracts
@consumes: Engine.js, InstanceManager.js, test framework
@events: test:started, test:passed, test:failed
@touches: Canvas initialization, Instance management, State consistency, Interface compliance
@owner: canvas-testing
@risk: LOW
@tests: Public API contracts, State management, Lifecycle methods, Error handling
*/

/**
 * Canvas Engine Contract Tests
 * Testa contratti pubblici del Canvas Engine hub
 * 
 * @package WC_AI_Product_Customizer
 */

// Import mock di Fabric.js per testing
const mockFabric = {
    Canvas: jest.fn().mockImplementation(() => ({
        setWidth: jest.fn(),
        setHeight: jest.fn(),
        renderAll: jest.fn(),
        dispose: jest.fn(),
        getObjects: jest.fn(() => []),
        add: jest.fn(),
        remove: jest.fn(),
        clear: jest.fn(),
        on: jest.fn(),
        off: jest.fn()
    })),
    Object: {
        prototype: {
            set: jest.fn(),
            get: jest.fn()
        }
    }
};

// Mock globals
global.fabric = mockFabric;
global.document = {
    getElementById: jest.fn(() => ({
        getContext: jest.fn(() => ({})),
        style: {}
    })),
    createElement: jest.fn(() => ({
        getContext: jest.fn(() => ({}))
    }))
};
global.window = {
    wcAiCustomizer: {
        printAreaConfig: {
            width: 100,
            height: 100,
            dpi: 300
        }
    }
};

describe('Canvas Engine Hub - Contract Tests', () => {
    let Engine, InstanceManager;
    
    beforeAll(async () => {
        // Import modules dopo mock setup
        Engine = await import('../../public/js/core/canvas/core/Engine.js');
        InstanceManager = await import('../../public/js/core/canvas/core/InstanceManager.js');
    });
    
    beforeEach(() => {
        // Reset mocks
        jest.clearAllMocks();
        
        // Reset instance storage
        if (InstanceManager.resetInstances) {
            InstanceManager.resetInstances();
        }
    });
    
    describe('🎯 Canvas Engine Core Interface Contract', () => {
        test('ENGINE_CONTRACT_01: initCanvas deve restituire istanza valida', () => {
            const canvasId = 'test-canvas-1';
            const config = { width: 800, height: 600 };
            const printArea = { x: 0, y: 0, width: 200, height: 200 };
            
            const instance = Engine.initCanvas(canvasId, config, printArea);
            
            // Verifica contratto interfaccia pubblica
            expect(instance).toBeDefined();
            expect(instance.id).toBe(canvasId);
            expect(instance.canvas).toBeDefined();
            expect(typeof instance.canvas.setWidth).toBe('function');
            expect(typeof instance.canvas.setHeight).toBe('function');
        });
        
        test('ENGINE_CONTRACT_02: getCanvasInstance deve restituire istanza esistente', () => {
            const canvasId = 'test-canvas-2';
            const config = { width: 800, height: 600 };
            const printArea = { x: 0, y: 0, width: 200, height: 200 };
            
            // Crea istanza
            const created = Engine.initCanvas(canvasId, config, printArea);
            
            // Recupera istanza
            const retrieved = Engine.getCanvasInstance(canvasId);
            
            // Verifica contratto identità
            expect(retrieved).toBeDefined();
            expect(retrieved.id).toBe(canvasId);
            expect(retrieved).toBe(created);
        });
        
        test('ENGINE_CONTRACT_03: destroyCanvas deve rimuovere istanza', () => {
            const canvasId = 'test-canvas-3';
            const config = { width: 800, height: 600 };
            const printArea = { x: 0, y: 0, width: 200, height: 200 };
            
            // Crea e distruggi istanza
            Engine.initCanvas(canvasId, config, printArea);
            Engine.destroyCanvas(canvasId);
            
            // Verifica contratto cleanup
            const retrieved = Engine.getCanvasInstance(canvasId);
            expect(retrieved).toBeNull();
        });
        
        test('ENGINE_CONTRACT_04: hasChanges e markAsChanged devono gestire stato', () => {
            const canvasId = 'test-canvas-4';
            const config = { width: 800, height: 600 };
            const printArea = { x: 0, y: 0, width: 200, height: 200 };
            
            Engine.initCanvas(canvasId, config, printArea);
            
            // Verifica contratto state management
            expect(Engine.hasChanges(canvasId)).toBe(false);
            
            Engine.markAsChanged(canvasId);
            expect(Engine.hasChanges(canvasId)).toBe(true);
            
            Engine.clearChanges(canvasId);
            expect(Engine.hasChanges(canvasId)).toBe(false);
        });
    });
    
    describe('🎯 Instance Manager Interface Contract', () => {
        test('INSTANCE_CONTRACT_01: createCanvasInstance deve creare istanza con fabric canvas', () => {
            const canvasId = 'test-instance-1';
            const config = { width: 800, height: 600 };
            
            const instance = InstanceManager.createCanvasInstance(canvasId, config);
            
            // Verifica contratto creazione istanza
            expect(instance).toBeDefined();
            expect(instance.id).toBe(canvasId);
            expect(instance.canvas).toBeDefined();
            expect(instance.config).toEqual(config);
            expect(mockFabric.Canvas).toHaveBeenCalled();
        });
        
        test('INSTANCE_CONTRACT_02: getCanvasInstance deve restituire null per ID inesistente', () => {
            const nonExistentId = 'non-existent-canvas';
            
            const instance = InstanceManager.getCanvasInstance(nonExistentId);
            
            // Verifica contratto null safety
            expect(instance).toBeNull();
        });
        
        test('INSTANCE_CONTRACT_03: destroyCanvasInstance deve fare cleanup completo', () => {
            const canvasId = 'test-instance-3';
            const config = { width: 800, height: 600 };
            
            // Crea istanza
            const instance = InstanceManager.createCanvasInstance(canvasId, config);
            expect(instance.canvas.dispose).not.toHaveBeenCalled();
            
            // Distruggi istanza
            InstanceManager.destroyCanvasInstance(canvasId);
            
            // Verifica contratto cleanup
            expect(instance.canvas.dispose).toHaveBeenCalled();
            expect(InstanceManager.getCanvasInstance(canvasId)).toBeNull();
        });
    });
    
    describe('🎯 Error Handling Contracts', () => {
        test('ERROR_CONTRACT_01: initCanvas deve gestire parametri invalidi', () => {
            // Test contratto error handling
            expect(() => {
                Engine.initCanvas(null, {}, {});
            }).toThrow();
            
            expect(() => {
                Engine.initCanvas('', {}, {});
            }).toThrow();
        });
        
        test('ERROR_CONTRACT_02: getCanvasInstance deve essere safe con parametri invalidi', () => {
            // Verifica contratto null safety
            expect(Engine.getCanvasInstance(null)).toBeNull();
            expect(Engine.getCanvasInstance(undefined)).toBeNull();
            expect(Engine.getCanvasInstance('')).toBeNull();
        });
    });
    
    describe('🎯 State Consistency Contracts', () => {
        test('STATE_CONTRACT_01: multiple canvas instances devono essere isolate', () => {
            const canvas1Id = 'test-state-1';
            const canvas2Id = 'test-state-2';
            const config = { width: 800, height: 600 };
            const printArea = { x: 0, y: 0, width: 200, height: 200 };
            
            // Crea due istanze separate
            const instance1 = Engine.initCanvas(canvas1Id, config, printArea);
            const instance2 = Engine.initCanvas(canvas2Id, config, printArea);
            
            // Verifica contratto isolamento
            expect(instance1).not.toBe(instance2);
            expect(instance1.id).toBe(canvas1Id);
            expect(instance2.id).toBe(canvas2Id);
            
            // Modifica stato di una istanza
            Engine.markAsChanged(canvas1Id);
            
            // Verifica isolamento stato
            expect(Engine.hasChanges(canvas1Id)).toBe(true);
            expect(Engine.hasChanges(canvas2Id)).toBe(false);
        });
        
        test('STATE_CONTRACT_02: canvas state deve persistere tra operazioni', () => {
            const canvasId = 'test-state-persistence';
            const config = { width: 800, height: 600 };
            const printArea = { x: 0, y: 0, width: 200, height: 200 };
            
            // Crea istanza e modifica stato
            Engine.initCanvas(canvasId, config, printArea);
            Engine.markAsChanged(canvasId);
            
            // Verifica persistenza attraverso operazioni
            expect(Engine.hasChanges(canvasId)).toBe(true);
            
            const instance = Engine.getCanvasInstance(canvasId);
            expect(instance).toBeDefined();
            expect(Engine.hasChanges(canvasId)).toBe(true);
        });
    });
});

// Export test utilities per altri contract tests
export const CanvasContractUtils = {
    createMockCanvas: (canvasId = 'mock-canvas') => ({
        id: canvasId,
        canvas: mockFabric.Canvas(),
        config: { width: 800, height: 600 }
    }),
    
    verifyInstanceContract: (instance, expectedId) => {
        expect(instance).toBeDefined();
        expect(instance.id).toBe(expectedId);
        expect(instance.canvas).toBeDefined();
        expect(typeof instance.canvas.setWidth).toBe('function');
        expect(typeof instance.canvas.setHeight).toBe('function');
    }
};