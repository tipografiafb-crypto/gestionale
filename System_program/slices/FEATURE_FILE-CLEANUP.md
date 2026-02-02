# FEATURE: FILE-CLEANUP

> Generated automatically by `tools/build-universal-mapping.mjs`  
> **Focus Slice** - Targeted view for surgical AI modifications

## 📊 Quick Stats
- **Modules**: 5
- **Hooks**: 4  
- **Events**: 9
- **Dependencies**: 6
- **Risk Distribution**: HIGH: 3, MEDIUM: 2

## 🎯 Modules Registry

| Module | Path | Purpose | Risk |
|---|---|---|---|
| FileManagementTab | `admin/dashboard/tabs/class-wc-ai-file-management-tab.php` | Admin file management tab for cleanup operations and file statistics | HIGH |
| AdminFileManagement | `admin/js/features/file-management.js` | Complete file management system - statistics, cleanup, temp file management | HIGH |
| AdminFileUploadSettings | `admin/js/features/file-upload-settings.js` | Admin file upload settings management and form handling | MEDIUM |
| FileArchiver | `includes/class-wc-ai-file-archiver.php` | Archiviazione file ordini per riordino (locale e S3) | MEDIUM |
| FileManager | `includes/class-wc-ai-file-manager.php` | Gestione manutenzione file: cleanup, AI images, screenshots, print files | HIGH |

## 🔗 Hooks
- **wp_ajax_wc_ai_save_file_upload_settings**: `admin/dashboard/tabs/class-wc-ai-file-management-tab.php` :: anonymous()
- **wp_ajax_wc_ai_cleanup_files**: `admin/dashboard/tabs/class-wc-ai-file-management-tab.php` :: anonymous()
- **wp_ajax_wc_ai_get_file_stats**: `admin/dashboard/tabs/class-wc-ai-file-management-tab.php` :: anonymous()
- **wp_ajax_wc_ai_cleanup_temp_files**: `admin/dashboard/tabs/class-wc-ai-file-management-tab.php` :: anonymous()

## ⚡ Events
- **submit** (listen): `admin/js/features/file-management.js`
- **click** (listen): `admin/js/features/file-management.js`
- **change** (listen): `admin/js/features/file-management.js`
- **click** (listen): `admin/js/features/file-management.js`
- **click** (listen): `admin/js/features/file-management.js`
- **click** (listen): `admin/js/features/file-management.js`
- **click** (listen): `admin/js/features/file-management.js`
- **click** (listen): `admin/js/features/file-management.js`
- **submit** (listen): `admin/js/features/file-upload-settings.js`

## 📦 Dependencies
- **WC_AI_File_**: `admin/dashboard/tabs/class-wc-ai-file-management-tab.php`
- **WC_AI_File_**: `admin/dashboard/tabs/class-wc-ai-file-management-tab.php`
- **WC_AI_File_**: `admin/dashboard/tabs/class-wc-ai-file-management-tab.php`
- **WC_AI_File_**: `admin/dashboard/tabs/class-wc-ai-file-management-tab.php`
- **WC_AI_File_**: `admin/dashboard/tabs/class-wc-ai-file-management-tab.php`
- **WC_AI_AWS_S3_**: `includes/class-wc-ai-file-archiver.php`

## 🚀 AI Usage Guidelines

### Surgical Targeting Protocol
1. **Scope**: Work only within this feature boundary
2. **Entry Points**: Use modules above as primary targets
3. **Risk Assessment**: Respect risk levels - avoid HIGH risk modules unless critical
4. **Hook Safety**: Preserve existing hook behavior when modifying

### Allowed Files
- `admin/dashboard/tabs/class-wc-ai-file-management-tab.php`
- `admin/js/features/file-management.js`
- `admin/js/features/file-upload-settings.js`
- `includes/class-wc-ai-file-archiver.php`
- `includes/class-wc-ai-file-manager.php`

### Testing Checklist
- [ ] File cleanup
- [ ] Statistics accuracy
- [ ] Temp file removal
- [ ] Storage calculations
- [ ] File cleanup
- [ ] Statistics accuracy
- [ ] Temp file removal
- [ ] Storage calculations
- [ ] Settings save
- [ ] Form validation
- [ ] AJAX response
- [ ] Configuration persistence
- [ ] Archive creation
- [ ] File copy
- [ ] Directory structure
- [ ] S3/Local compatibility
- [ ] File cleanup
- [ ] Statistics calculation
- [ ] Period detection
- [ ] Cleanup safety
