# FEATURE: CANVAS

> Generated automatically by `tools/build-universal-mapping.mjs`  
> **Focus Slice** - Targeted view for surgical AI modifications

## 📊 Quick Stats
- **Modules**: 4
- **Hooks**: 0  
- **Events**: 2
- **Dependencies**: 23
- **Risk Distribution**: MEDIUM: 3, LOW: 1

## 🎯 Modules Registry

| Module | Path | Purpose | Risk |
|---|---|---|---|
| GuidelinesManager | `public/js/core/canvas/positioning/GuidelinesManager.js` | Sistema snap to center con guide lines: linee guida tratteggiate, magnetismo oggetti al centro canvas, feedback visivo | MEDIUM |
| PositioningManager | `public/js/core/canvas/positioning/PositioningManager.js` | Calcoli posizionamento immagini: trasformazioni iniziali, fit scale, print area positioning | MEDIUM |
| ImageFiltersManager | `public/js/interfaces-v2/frames-customizer/managers/ImageFiltersManager.js` | Image filters using Fabric.js native filters: cross-browser, no position/layering bugs | MEDIUM |
| CanvasTransferManager | `public/js/interfaces-v2/magenta-customizer/utils/CanvasTransferManager.js` | Trasferimento stato canvas tra prodotti servant usando coordinate normalizzate | LOW |

## 🔗 Hooks
- None

## ⚡ Events
- **canvasDimensionsChanged** (listen): `public/js/core/canvas/positioning/PositioningManager.js`
- **click** (listen): `public/js/interfaces-v2/frames-customizer/managers/ImageFiltersManager.js`

## 📦 Dependencies
- **Guidelines**: `public/js/core/canvas/positioning/GuidelinesManager.js`
- **Guidelines**: `public/js/core/canvas/positioning/GuidelinesManager.js`
- **Guidelines**: `public/js/core/canvas/positioning/GuidelinesManager.js`
- **Guidelines**: `public/js/core/canvas/positioning/GuidelinesManager.js`
- **Guidelines**: `public/js/core/canvas/positioning/GuidelinesManager.js`
- **Guidelines**: `public/js/core/canvas/positioning/GuidelinesManager.js`
- **Guidelines**: `public/js/core/canvas/positioning/GuidelinesManager.js`
- **Instance**: `public/js/core/canvas/positioning/PositioningManager.js`
- **Positioning**: `public/js/core/canvas/positioning/PositioningManager.js`
- **Positioning**: `public/js/core/canvas/positioning/PositioningManager.js`
- **ImageFilters**: `public/js/interfaces-v2/frames-customizer/managers/ImageFiltersManager.js`
- **Event**: `public/js/interfaces-v2/frames-customizer/managers/ImageFiltersManager.js`
- **State**: `public/js/interfaces-v2/frames-customizer/managers/ImageFiltersManager.js`
- **CanvasTransfer**: `public/js/interfaces-v2/magenta-customizer/utils/CanvasTransferManager.js`
- **CanvasTransfer**: `public/js/interfaces-v2/magenta-customizer/utils/CanvasTransferManager.js`
- **CanvasTransfer**: `public/js/interfaces-v2/magenta-customizer/utils/CanvasTransferManager.js`
- **CanvasTransfer**: `public/js/interfaces-v2/magenta-customizer/utils/CanvasTransferManager.js`
- **CanvasTransfer**: `public/js/interfaces-v2/magenta-customizer/utils/CanvasTransferManager.js`
- **CanvasTransfer**: `public/js/interfaces-v2/magenta-customizer/utils/CanvasTransferManager.js`
- **CanvasTransfer**: `public/js/interfaces-v2/magenta-customizer/utils/CanvasTransferManager.js`
- **CanvasTransfer**: `public/js/interfaces-v2/magenta-customizer/utils/CanvasTransferManager.js`
- **CanvasTransfer**: `public/js/interfaces-v2/magenta-customizer/utils/CanvasTransferManager.js`
- **CanvasTransfer**: `public/js/interfaces-v2/magenta-customizer/utils/CanvasTransferManager.js`

## 🚀 AI Usage Guidelines

### Surgical Targeting Protocol
1. **Scope**: Work only within this feature boundary
2. **Entry Points**: Use modules above as primary targets
3. **Risk Assessment**: Respect risk levels - avoid HIGH risk modules unless critical
4. **Hook Safety**: Preserve existing hook behavior when modifying

### Allowed Files
- `public/js/core/canvas/positioning/GuidelinesManager.js`
- `public/js/core/canvas/positioning/PositioningManager.js`
- `public/js/interfaces-v2/frames-customizer/managers/ImageFiltersManager.js`
- `public/js/interfaces-v2/magenta-customizer/utils/CanvasTransferManager.js`

### Testing Checklist
- [ ] Guidelines visibility
- [ ] Snap functionality
- [ ] Center calculation
- [ ] Multi-object support
- [ ] Position calculation
- [ ] Scale determination
- [ ] Print area fitting
- [ ] Transform accuracy
- [ ] Filter application
- [ ] Position preservation
- [ ] Layering integrity
- [ ] Safari compatibility
- [ ] Canvas transfer
- [ ] Coordinate normalization
- [ ] Storage cleanup
