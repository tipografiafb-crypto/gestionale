# FEATURE: MEDIA-HANDLER

> Generated automatically by `tools/build-universal-mapping.mjs`  
> **Focus Slice** - Targeted view for surgical AI modifications

## 📊 Quick Stats
- **Modules**: 1
- **Hooks**: 0  
- **Events**: 3
- **Dependencies**: 1
- **Risk Distribution**: MEDIUM: 1

## 🎯 Modules Registry

| Module | Path | Purpose | Risk |
|---|---|---|---|
| AdminMediaHandler | `admin/js/core/media-handler.js` | Media management: WordPress Media Library integration, mask upload/removal, stage detection, file handling | MEDIUM |

## 🔗 Hooks
- None

## ⚡ Events
- **click** (listen): `admin/js/core/media-handler.js`
- **click** (listen): `admin/js/core/media-handler.js`
- **select** (listen): `admin/js/core/media-handler.js`

## 📦 Dependencies
- **Media**: `admin/js/core/media-handler.js`

## 🚀 AI Usage Guidelines

### Surgical Targeting Protocol
1. **Scope**: Work only within this feature boundary
2. **Entry Points**: Use modules above as primary targets
3. **Risk Assessment**: Respect risk levels - avoid HIGH risk modules unless critical
4. **Hook Safety**: Preserve existing hook behavior when modifying

### Allowed Files
- `admin/js/core/media-handler.js`

### Testing Checklist
- [ ] Media library integration
- [ ] File upload/removal
- [ ] Stage detection
- [ ] Mask handling
