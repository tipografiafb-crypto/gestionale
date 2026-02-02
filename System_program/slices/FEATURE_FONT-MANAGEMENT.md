# FEATURE: FONT-MANAGEMENT

> Generated automatically by `tools/build-universal-mapping.mjs`  
> **Focus Slice** - Targeted view for surgical AI modifications

## 📊 Quick Stats
- **Modules**: 4
- **Hooks**: 5  
- **Events**: 0
- **Dependencies**: 2
- **Risk Distribution**: MEDIUM: 1, LOW: 3

## 🎯 Modules Registry

| Module | Path | Purpose | Risk |
|---|---|---|---|
| FontManagementTab | `admin/dashboard/tabs/class-wc-ai-font-management-tab.php` | Admin font management tab for font upload, preview, and database management | MEDIUM |
| FontCSSHandler | `includes/class-wc-ai-font-css-handler.php` | CSS generation and frontend enqueuing for font system integration | LOW |
| FontInstaller | `includes/class-wc-ai-font-installer.php` | Font installation and setup system for default fonts and font manager initialization | LOW |
| FontManager | `includes/class-wc-ai-font-manager.php` | Gestione locale fonts: storage, processamento, CSS generation, font loading | LOW |

## 🔗 Hooks
- **wp_ajax_wc_ai_upload_font**: `admin/dashboard/tabs/class-wc-ai-font-management-tab.php` :: anonymous()
- **wp_ajax_wc_ai_toggle_font**: `admin/dashboard/tabs/class-wc-ai-font-management-tab.php` :: anonymous()
- **wp_ajax_wc_ai_delete_font**: `admin/dashboard/tabs/class-wc-ai-font-management-tab.php` :: anonymous()
- **wp_ajax_wc_ai_get_active_fonts**: `admin/dashboard/tabs/class-wc-ai-font-management-tab.php` :: anonymous()
- **wp_ajax_nopriv_wc_ai_get_active_fonts**: `admin/dashboard/tabs/class-wc-ai-font-management-tab.php` :: anonymous()

## ⚡ Events
- None

## 📦 Dependencies
- **WC_AI_Font_**: `includes/class-wc-ai-font-css-handler.php`
- **WC_AI_Font_**: `includes/class-wc-ai-font-installer.php`

## 🚀 AI Usage Guidelines

### Surgical Targeting Protocol
1. **Scope**: Work only within this feature boundary
2. **Entry Points**: Use modules above as primary targets
3. **Risk Assessment**: Respect risk levels - avoid HIGH risk modules unless critical
4. **Hook Safety**: Preserve existing hook behavior when modifying

### Allowed Files
- `admin/dashboard/tabs/class-wc-ai-font-management-tab.php`
- `includes/class-wc-ai-font-css-handler.php`
- `includes/class-wc-ai-font-installer.php`
- `includes/class-wc-ai-font-manager.php`

### Testing Checklist
- [ ] Font upload
- [ ] File validation
- [ ] Database operations
- [ ] Preview generation
- [ ] CSS generation
- [ ] Font loading
- [ ] Performance impact
- [ ] Cache efficiency
- [ ] Installation success
- [ ] Font availability
- [ ] System setup validation
- [ ] Font installation
- [ ] CSS generation
- [ ] Font loading
- [ ] Storage management
