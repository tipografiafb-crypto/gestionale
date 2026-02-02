# FEATURE: ADMIN

> Generated automatically by `tools/build-universal-mapping.mjs`  
> **Focus Slice** - Targeted view for surgical AI modifications

## 📊 Quick Stats
- **Modules**: 4
- **Hooks**: 17  
- **Events**: 24
- **Dependencies**: 9
- **Risk Distribution**: LOW: 1, MEDIUM: 3

## 🎯 Modules Registry

| Module | Path | Purpose | Risk |
|---|---|---|---|
| DashboardCoordinator | `admin/dashboard/js/dashboard.js` | Lightweight dashboard coordination and tab management for unified admin interface | LOW |
| ClipArtManagementTab | `admin/dashboard/tabs/class-wc-ai-clipart-management-tab.php` | Admin clipart management tab for SVG upload, categorization, and library management | MEDIUM |
| GeneralSettingsTab | `admin/dashboard/tabs/class-wc-ai-general-settings-tab.php` | General settings tab handler for unified dashboard configuration | MEDIUM |
| AdminClipArtManager | `admin/js/features/clipart-manager.js` | Admin clipart management: CRUD operations, category management, upload handling | MEDIUM |

## 🔗 Hooks
- **wp_ajax_wc_ai_upload_clipart**: `admin/dashboard/tabs/class-wc-ai-clipart-management-tab.php` :: anonymous()
- **wp_ajax_wc_ai_toggle_clipart**: `admin/dashboard/tabs/class-wc-ai-clipart-management-tab.php` :: anonymous()
- **wp_ajax_wc_ai_delete_clipart**: `admin/dashboard/tabs/class-wc-ai-clipart-management-tab.php` :: anonymous()
- **wp_ajax_wc_ai_update_clipart_category**: `admin/dashboard/tabs/class-wc-ai-clipart-management-tab.php` :: anonymous()
- **wp_ajax_wc_ai_create_clipart_category**: `admin/dashboard/tabs/class-wc-ai-clipart-management-tab.php` :: anonymous()
- **wp_ajax_wc_ai_update_clipart_category_name**: `admin/dashboard/tabs/class-wc-ai-clipart-management-tab.php` :: anonymous()
- **wp_ajax_wc_ai_delete_clipart_category**: `admin/dashboard/tabs/class-wc-ai-clipart-management-tab.php` :: anonymous()
- **wp_ajax_wc_ai_toggle_clipart_category**: `admin/dashboard/tabs/class-wc-ai-clipart-management-tab.php` :: anonymous()
- **wp_ajax_wc_ai_get_active_cliparts**: `admin/dashboard/tabs/class-wc-ai-clipart-management-tab.php` :: anonymous()
- **wp_ajax_nopriv_wc_ai_get_active_cliparts**: `admin/dashboard/tabs/class-wc-ai-clipart-management-tab.php` :: anonymous()
- **wp_ajax_wc_ai_get_clipart_categories**: `admin/dashboard/tabs/class-wc-ai-clipart-management-tab.php` :: anonymous()
- **wp_ajax_nopriv_wc_ai_get_clipart_categories**: `admin/dashboard/tabs/class-wc-ai-clipart-management-tab.php` :: anonymous()
- **wp_ajax_wc_ai_import_clipart_zip**: `admin/dashboard/tabs/class-wc-ai-clipart-management-tab.php` :: anonymous()
- **wp_ajax_wc_ai_change_clipart_category**: `admin/dashboard/tabs/class-wc-ai-clipart-management-tab.php` :: anonymous()
- **wp_ajax_wc_ai_bulk_clipart_action**: `admin/dashboard/tabs/class-wc-ai-clipart-management-tab.php` :: anonymous()
- **wp_ajax_wc_ai_grant_existing_credits**: `admin/dashboard/tabs/class-wc-ai-general-settings-tab.php` :: anonymous()
- **wp_ajax_wc_ai_test_aws_connection**: `admin/dashboard/tabs/class-wc-ai-general-settings-tab.php` :: anonymous()

## ⚡ Events
- **click** (listen): `admin/dashboard/js/dashboard.js`
- **click** (listen): `admin/dashboard/js/dashboard.js`
- **select** (listen): `admin/dashboard/js/dashboard.js`
- **click** (listen): `admin/dashboard/js/dashboard.js`
- **click** (listen): `admin/dashboard/js/dashboard.js`
- **click** (listen): `admin/dashboard/js/dashboard.js`
- **change** (listen): `admin/dashboard/js/dashboard.js`
- **click** (listen): `admin/dashboard/js/dashboard.js`
- **submit** (listen): `admin/js/features/clipart-manager.js`
- **click** (listen): `admin/js/features/clipart-manager.js`
- **click** (listen): `admin/js/features/clipart-manager.js`
- **change** (listen): `admin/js/features/clipart-manager.js`
- **change** (listen): `admin/js/features/clipart-manager.js`
- **change** (listen): `admin/js/features/clipart-manager.js`
- **change** (listen): `admin/js/features/clipart-manager.js`
- **click** (listen): `admin/js/features/clipart-manager.js`
- **change** (listen): `admin/js/features/clipart-manager.js`
- **change** (listen): `admin/js/features/clipart-manager.js`
- **click** (listen): `admin/js/features/clipart-manager.js`
- **dragover** (listen): `admin/js/features/clipart-manager.js`
- **dragleave** (listen): `admin/js/features/clipart-manager.js`
- **drop** (listen): `admin/js/features/clipart-manager.js`
- **change** (listen): `admin/js/features/clipart-manager.js`
- **progress** (listen): `admin/js/features/clipart-manager.js`

## 📦 Dependencies
- **WC_AI_Credits_**: `admin/dashboard/tabs/class-wc-ai-general-settings-tab.php`
- **WC_AI_AWS_S3_**: `admin/dashboard/tabs/class-wc-ai-general-settings-tab.php`
- **ClipArt**: `admin/js/features/clipart-manager.js`
- **ClipArt**: `admin/js/features/clipart-manager.js`
- **ClipArt**: `admin/js/features/clipart-manager.js`
- **ClipArt**: `admin/js/features/clipart-manager.js`
- **ClipArt**: `admin/js/features/clipart-manager.js`
- **ClipArt**: `admin/js/features/clipart-manager.js`
- **ClipArt**: `admin/js/features/clipart-manager.js`

## 🚀 AI Usage Guidelines

### Surgical Targeting Protocol
1. **Scope**: Work only within this feature boundary
2. **Entry Points**: Use modules above as primary targets
3. **Risk Assessment**: Respect risk levels - avoid HIGH risk modules unless critical
4. **Hook Safety**: Preserve existing hook behavior when modifying

### Allowed Files
- `admin/dashboard/js/dashboard.js`
- `admin/dashboard/tabs/class-wc-ai-clipart-management-tab.php`
- `admin/dashboard/tabs/class-wc-ai-general-settings-tab.php`
- `admin/js/features/clipart-manager.js`

### Testing Checklist
- [ ] Tab switching
- [ ] Module coordination
- [ ] Notification display
- [ ] UI responsiveness
- [ ] SVG upload
- [ ] Sanitization
- [ ] Database operations
- [ ] Category management
- [ ] Settings save
- [ ] Validation
- [ ] AJAX response
- [ ] Options storage
- [ ] Upload/delete
- [ ] Category management
- [ ] Toggle functionality
- [ ] File validation
