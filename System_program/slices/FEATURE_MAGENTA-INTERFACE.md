# FEATURE: MAGENTA-INTERFACE

> Generated automatically by `tools/build-universal-mapping.mjs`  
> **Focus Slice** - Targeted view for surgical AI modifications

## 📊 Quick Stats
- **Modules**: 3
- **Hooks**: 3  
- **Events**: 16
- **Dependencies**: 27
- **Risk Distribution**: MEDIUM: 2, LOW: 1

## 🎯 Modules Registry

| Module | Path | Purpose | Risk |
|---|---|---|---|
| AdminMagentaTab | `admin/js/features/magenta-tab.js` | Magenta product configuration admin interface and multi-stage management | MEDIUM |
| MagentaHandler | `includes/interfaces/class-wc-ai-magenta-handler.php` | Handler per interfaccia Magenta full-screen: routing, asset loading, multicanvas order integration | LOW |
| MagentaCustomizer | `public/js/interfaces-v2/magenta-customizer/MagentaCustomizer.js` | Controller principale Magenta: stage switch, canvas management, orchestrazione UI | MEDIUM |

## 🔗 Hooks
- **wp_enqueue_scripts**: `includes/interfaces/class-wc-ai-magenta-handler.php` :: anonymous()
- **wc_ai_order_print_files**: `includes/interfaces/class-wc-ai-magenta-handler.php` :: anonymous()
- **wc_ai_order_screenshots**: `includes/interfaces/class-wc-ai-magenta-handler.php` :: anonymous()

## ⚡ Events
- **change** (listen): `admin/js/features/magenta-tab.js`
- **change** (listen): `admin/js/features/magenta-tab.js`
- **input** (listen): `admin/js/features/magenta-tab.js`
- **input** (listen): `admin/js/features/magenta-tab.js`
- **click** (listen): `admin/js/features/magenta-tab.js`
- **click** (listen): `admin/js/features/magenta-tab.js`
- **click** (listen): `admin/js/features/magenta-tab.js`
- **click** (listen): `admin/js/features/magenta-tab.js`
- **click** (listen): `admin/js/features/magenta-tab.js`
- **click** (listen): `admin/js/features/magenta-tab.js`
- **click** (listen): `admin/js/features/magenta-tab.js`
- **change** (listen): `admin/js/features/magenta-tab.js`
- **DOMContentLoaded** (listen): `public/js/interfaces-v2/magenta-customizer/MagentaCustomizer.js`
- **keydown** (listen): `public/js/interfaces-v2/magenta-customizer/MagentaCustomizer.js`
- **resize** (listen): `public/js/interfaces-v2/magenta-customizer/MagentaCustomizer.js`
- **beforeunload** (listen): `public/js/interfaces-v2/magenta-customizer/MagentaCustomizer.js`

## 📦 Dependencies
- **Font**: `includes/interfaces/class-wc-ai-magenta-handler.php`
- **DesignLibrary**: `includes/interfaces/class-wc-ai-magenta-handler.php`
- **CanvasTransfer**: `includes/interfaces/class-wc-ai-magenta-handler.php`
- **CategoryUI**: `includes/interfaces/class-wc-ai-magenta-handler.php`
- **Layout**: `includes/interfaces/class-wc-ai-magenta-handler.php`
- **Instance**: `public/js/interfaces-v2/magenta-customizer/MagentaCustomizer.js`
- **Instance**: `public/js/interfaces-v2/magenta-customizer/MagentaCustomizer.js`
- **Font**: `public/js/interfaces-v2/magenta-customizer/MagentaCustomizer.js`
- **AI**: `public/js/interfaces-v2/magenta-customizer/MagentaCustomizer.js`
- **AI**: `public/js/interfaces-v2/magenta-customizer/MagentaCustomizer.js`
- **AI**: `public/js/interfaces-v2/magenta-customizer/MagentaCustomizer.js`
- **Layout**: `public/js/interfaces-v2/magenta-customizer/MagentaCustomizer.js`
- **Layout**: `public/js/interfaces-v2/magenta-customizer/MagentaCustomizer.js`
- **Sidebar**: `public/js/interfaces-v2/magenta-customizer/MagentaCustomizer.js`
- **Panel**: `public/js/interfaces-v2/magenta-customizer/MagentaCustomizer.js`
- **Workspace**: `public/js/interfaces-v2/magenta-customizer/MagentaCustomizer.js`
- **Product**: `public/js/interfaces-v2/magenta-customizer/MagentaCustomizer.js`
- **Help**: `public/js/interfaces-v2/magenta-customizer/MagentaCustomizer.js`
- **AI**: `public/js/interfaces-v2/magenta-customizer/MagentaCustomizer.js`
- **Font**: `public/js/interfaces-v2/magenta-customizer/MagentaCustomizer.js`
- **Layout**: `public/js/interfaces-v2/magenta-customizer/MagentaCustomizer.js`
- **To**: `public/js/interfaces-v2/magenta-customizer/MagentaCustomizer.js`
- **Font**: `public/js/interfaces-v2/magenta-customizer/MagentaCustomizer.js`
- **Font**: `public/js/interfaces-v2/magenta-customizer/MagentaCustomizer.js`
- **Font**: `public/js/interfaces-v2/magenta-customizer/MagentaCustomizer.js`
- **CanvasTransfer**: `public/js/interfaces-v2/magenta-customizer/MagentaCustomizer.js`
- **CanvasTransfer**: `public/js/interfaces-v2/magenta-customizer/MagentaCustomizer.js`

## 🚀 AI Usage Guidelines

### Surgical Targeting Protocol
1. **Scope**: Work only within this feature boundary
2. **Entry Points**: Use modules above as primary targets
3. **Risk Assessment**: Respect risk levels - avoid HIGH risk modules unless critical
4. **Hook Safety**: Preserve existing hook behavior when modifying

### Allowed Files
- `admin/js/features/magenta-tab.js`
- `includes/interfaces/class-wc-ai-magenta-handler.php`
- `public/js/interfaces-v2/magenta-customizer/MagentaCustomizer.js`

### Testing Checklist
- [ ] Interface switching
- [ ] Stage management
- [ ] Mask toggle
- [ ] State synchronization
- [ ] Asset enqueuing
- [ ] Page detection
- [ ] Template loading
- [ ] Multicanvas file integration
- [ ] Stage switch preserva objects
- [ ] Canvas reset corretto
- [ ] Multi-stage navigation
