# FEATURE: AI

> Generated automatically by `tools/build-universal-mapping.mjs`  
> **Focus Slice** - Targeted view for surgical AI modifications

## 📊 Quick Stats
- **Modules**: 6
- **Hooks**: 8  
- **Events**: 0
- **Dependencies**: 9
- **Risk Distribution**: HIGH: 3, MEDIUM: 1, LOW: 2

## 🎯 Modules Registry

| Module | Path | Purpose | Risk |
|---|---|---|---|
| AIConfigurationTab | `admin/dashboard/tabs/class-wc-ai-ai-configuration-tab.php` | AI configuration tab handler for OpenAI settings and style management | HIGH |
| AIProviderFactory | `includes/class-wc-ai-provider-factory.php` | Factory pattern per gestire la selezione dinamica dei provider AI (OpenAI, Google Gemini) | MEDIUM |
| StylesManager | `includes/class-wc-ai-styles-manager.php` | AI prompt templates and styles management for image generation | LOW |
| AIProviderInterface | `includes/interfaces/interface-wc-ai-provider.php` | Interface comune per tutti i provider AI (OpenAI, Google Gemini, etc.) | LOW |
| GoogleGeminiProvider | `includes/providers/class-wc-ai-google-gemini-provider.php` | Google Gemini API provider for AI image generation and editing | HIGH |
| OpenAIProvider | `includes/providers/class-wc-ai-openai-provider.php` | OpenAI API provider for AI image generation and editing (refactored from existing implementation) | HIGH |

## 🔗 Hooks
- **wp_ajax_wc_ai_get_style**: `admin/dashboard/tabs/class-wc-ai-ai-configuration-tab.php` :: anonymous()
- **wp_ajax_wc_ai_add_style**: `admin/dashboard/tabs/class-wc-ai-ai-configuration-tab.php` :: anonymous()
- **wp_ajax_wc_ai_update_style**: `admin/dashboard/tabs/class-wc-ai-ai-configuration-tab.php` :: anonymous()
- **wp_ajax_wc_ai_set_default_style**: `admin/dashboard/tabs/class-wc-ai-ai-configuration-tab.php` :: anonymous()
- **wp_ajax_wc_ai_toggle_style_status**: `admin/dashboard/tabs/class-wc-ai-ai-configuration-tab.php` :: anonymous()
- **wp_ajax_wc_ai_delete_style**: `admin/dashboard/tabs/class-wc-ai-ai-configuration-tab.php` :: anonymous()
- **wp_ajax_wc_ai_test_api_connection**: `admin/dashboard/tabs/class-wc-ai-ai-configuration-tab.php` :: anonymous()
- **wp_ajax_wc_ai_save_ai_settings**: `admin/dashboard/tabs/class-wc-ai-ai-configuration-tab.php` :: anonymous()

## ⚡ Events
- None

## 📦 Dependencies
- **WC_AI_Styles_**: `admin/dashboard/tabs/class-wc-ai-ai-configuration-tab.php`
- **WC_AI_Styles_**: `admin/dashboard/tabs/class-wc-ai-ai-configuration-tab.php`
- **WC_AI_Styles_**: `admin/dashboard/tabs/class-wc-ai-ai-configuration-tab.php`
- **WC_AI_Styles_**: `admin/dashboard/tabs/class-wc-ai-ai-configuration-tab.php`
- **WC_AI_Styles_**: `admin/dashboard/tabs/class-wc-ai-ai-configuration-tab.php`
- **WC_AI_Styles_**: `admin/dashboard/tabs/class-wc-ai-ai-configuration-tab.php`
- **WC_AI_Styles_**: `admin/dashboard/tabs/class-wc-ai-ai-configuration-tab.php`
- **WC_AI_Styles_**: `includes/providers/class-wc-ai-google-gemini-provider.php`
- **WC_AI_Styles_**: `includes/providers/class-wc-ai-openai-provider.php`

## 🚀 AI Usage Guidelines

### Surgical Targeting Protocol
1. **Scope**: Work only within this feature boundary
2. **Entry Points**: Use modules above as primary targets
3. **Risk Assessment**: Respect risk levels - avoid HIGH risk modules unless critical
4. **Hook Safety**: Preserve existing hook behavior when modifying

### Allowed Files
- `admin/dashboard/tabs/class-wc-ai-ai-configuration-tab.php`
- `includes/class-wc-ai-provider-factory.php`
- `includes/class-wc-ai-styles-manager.php`
- `includes/interfaces/interface-wc-ai-provider.php`
- `includes/providers/class-wc-ai-google-gemini-provider.php`
- `includes/providers/class-wc-ai-openai-provider.php`

### Testing Checklist
- [ ] API key validation
- [ ] OpenAI connection
- [ ] Style management
- [ ] Settings save
- [ ] Provider creation
- [ ] Configuration validation
- [ ] Factory pattern consistency
- [ ] Style creation
- [ ] Template validation
- [ ] Database operations
- [ ] Prompt formatting
- [ ] Interface compliance
- [ ] Provider implementations
- [ ] API integration
- [ ] Image generation
- [ ] Response formatting
- [ ] Error handling
- [ ] API integration
- [ ] Image generation
- [ ] Response formatting
- [ ] Error handling
