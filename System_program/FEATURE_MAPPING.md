# Feature Mapping - Canonical Feature Set

> Standardized feature tags for universal AI targeting

## 🎯 Canonical Feature Set

Use ONLY these standardized feature names in MODULE headers:

### Core Features
- **bulk-price**: Bulk quantity pricing logic and cart calculations
- **frame-bulk**: Frames-specific bulk pricing with aggregation  
- **canvas**: Canvas engine, Fabric.js integration, and manipulation
- **ai**: AI image generation, OpenAI integration, and processing
- **stage**: Multi-stage workflow management and coordination
- **cart**: Shopping cart operations and checkout integration
- **admin**: Admin interface, dashboard, and configuration
- **ui**: User interface components and interactions
- **validation**: Data validation, integrity checks, and verification
- **export**: File export, HD generation, and download operations

### Specialized Features  
- **font-management**: Font loading, storage, and CSS generation
- **file-cleanup**: File maintenance, cleanup, and storage management
- **pricing-orchestrator**: Core pricing delegation and mode resolution
- **interface-routing**: Interface selection and routing logic
- **s3-integration**: AWS S3 storage and cloud operations
- **magenta-interface**: Magenta full-screen customizer interface
- **frames-interface**: Frames multi-step customizer interface  
- **page-interface**: Page-based customizer interface
- **diecut-interface**: Standalone die-cut sticker customization (Canvas HTML5 native + OpenCV, NO Fabric.js)

## 🔄 Feature Normalization Status

### ✅ Normalized (Using Canonical Tags)
- All admin modules → `admin`
- Pricing core modules → `bulk-price` 
- Canvas engine → `canvas`
- AI generation → `ai`

### 🔄 To Normalize (Legacy Tags)
- `pricing-orchestrator` → `bulk-price`
- `ai-image-generation` → `ai`
- `fabric-engine` → `canvas`
- `magenta-*` → `ui` (for components) or `magenta-interface` (for core)

## 📊 Feature Module Count

| Feature | Module Count | Primary Domains |
|---------|-------------|-----------------|
| bulk-price | 12 | pricing, backend |
| canvas | 25 | canvas, export |
| ai | 18 | ai, generation |
| admin | 14 | admin, configuration |
| ui | 35 | ui, components |
| magenta-interface | 28 | interface, customizer |
| frames-interface | 20 | interface, workflow |
| diecut-interface | 5 | interface, opencv |

## 🎯 Quick Feature Targeting

### Bulk Pricing Issues
```
Feature: bulk-price
Entrypoints: [PricingManager, BulkMode, FramesBulkPricingManager]
```

### Canvas Problems  
```
Feature: canvas
Entrypoints: [CanvasEngine, CanvasExportService, CanvasInstanceManager]
```

### AI Generation Issues
```
Feature: ai
Entrypoints: [AIOrchestrator, AIImageGenerator, OpenAIIntegration]
```

### UI Component Issues
```
Feature: ui
Entrypoints: [MagentaButtonComponent, MagentaLayoutManager, PanelManager]
```

## 🔧 Migration Script

To normalize all feature tags to canonical set:

```bash
# Update legacy feature tags
cd wc-ai-product-customizer
find . -name "*.php" -o -name "*.js" | xargs sed -i 's/@feature: pricing-orchestrator/@feature: bulk-price/g'
find . -name "*.php" -o -name "*.js" | xargs sed -i 's/@feature: ai-image-generation/@feature: ai/g'
find . -name "*.php" -o -name "*.js" | xargs sed -i 's/@feature: fabric-engine/@feature: canvas/g'

# Regenerate mapping
node tools/build-universal-mapping.mjs .
```

## 📋 Feature Validation Rules

1. **Single Feature Per Module**: Each module should have exactly one @feature tag
2. **Canonical Names Only**: Use only features from the canonical set above
3. **Consistent Naming**: No variations (e.g., `bulk_price` vs `bulk-price`)
4. **Hierarchical Logic**: Sub-features use parent feature (e.g., all pricing → `bulk-price`)

## 🚀 AI Request Examples

### Standardized Feature Request
```
Feature: bulk-price
Goal: Fix cart recalculation after item removal
Entrypoint: PricingManager → resolve_mode capability
Files: includes/class-wc-ai-pricing-manager.php
```

### Multi-Feature Coordination
```
Feature: canvas + ai
Goal: AI image integration with canvas positioning
Entrypoints: AIOrchestrator + CanvasEngine
Coordination: AI generates → Canvas positions → Export handles
```