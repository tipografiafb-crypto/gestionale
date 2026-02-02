# FEATURE: EXPORT

> Generated automatically by `tools/build-universal-mapping.mjs`  
> **Focus Slice** - Targeted view for surgical AI modifications

## 📊 Quick Stats
- **Modules**: 2
- **Hooks**: 0  
- **Events**: 1
- **Dependencies**: 3
- **Risk Distribution**: MEDIUM: 2

## 🎯 Modules Registry

| Module | Path | Purpose | Risk |
|---|---|---|---|
| OrderZipGenerator | `includes/class-wc-ai-order-zip-generator.php` | Generazione ZIP con tutti i file di customizzazione di un ordine | MEDIUM |
| ExportIdempotencyManager | `public/js/core/canvas/export/IdempotencyManager.js` | Idempotency manager per export: previene duplicazioni, cache risultati, mutex per race conditions | MEDIUM |

## 🔗 Hooks
- None

## ⚡ Events
- **mutex** (emit): `public/js/core/canvas/export/IdempotencyManager.js`

## 📦 Dependencies
- **ExportIdempotency**: `public/js/core/canvas/export/IdempotencyManager.js`
- **ExportIdempotency**: `public/js/core/canvas/export/IdempotencyManager.js`
- **ExportIdempotency**: `public/js/core/canvas/export/IdempotencyManager.js`

## 🚀 AI Usage Guidelines

### Surgical Targeting Protocol
1. **Scope**: Work only within this feature boundary
2. **Entry Points**: Use modules above as primary targets
3. **Risk Assessment**: Respect risk levels - avoid HIGH risk modules unless critical
4. **Hook Safety**: Preserve existing hook behavior when modifying

### Allowed Files
- `includes/class-wc-ai-order-zip-generator.php`
- `public/js/core/canvas/export/IdempotencyManager.js`

### Testing Checklist
- [ ] ZIP creation
- [ ] File collection
- [ ] Download serving
- [ ] Cleanup
- [ ] Job ID generation
- [ ] Cache functionality
- [ ] Mutex behavior
- [ ] Duplicate detection
