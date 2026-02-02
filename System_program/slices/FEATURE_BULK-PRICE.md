# FEATURE: BULK-PRICE

> Generated automatically by `tools/build-universal-mapping.mjs`  
> **Focus Slice** - Targeted view for surgical AI modifications

## 📊 Quick Stats
- **Modules**: 6
- **Hooks**: 16  
- **Events**: 0
- **Dependencies**: 15
- **Risk Distribution**: HIGH: 3, LOW: 2, MEDIUM: 1

## 🎯 Modules Registry

| Module | Path | Purpose | Risk |
|---|---|---|---|
| PricingManagementTab | `admin/dashboard/tabs/class-wc-ai-pricing-management-tab.php` | Admin pricing management tab for creating and managing reusable pricing models | HIGH |
| PricingManager | `includes/class-wc-ai-pricing-manager.php` | Orchestrator pricing: instrada Product Modes (bulk, size, variant, matrix) | HIGH |
| PreCheckoutAjax | `includes/ajax/class-wc-ai-pre-checkout-ajax.php` | AJAX handler for pre-checkout pricing selector: retrieve pricing data and configuration | LOW |
| SizeMatrixMode | `includes/product-modes/class-wc-ai-size-matrix-mode.php` | Matrix pricing con row personalizzabili, SKU suffix support, unified footer | MEDIUM |
| StandardMode | `includes/product-modes/class-wc-ai-standard-mode.php` | Standard product mode - basic customization without bulk pricing | LOW |
| VariantBulkMode | `includes/product-modes/class-wc-ai-variant-bulk-mode.php` | Combined variant + bulk pricing mode for complex product configurations | HIGH |

## 🔗 Hooks
- **wp_ajax_wc_ai_get_pricing_type**: `admin/dashboard/tabs/class-wc-ai-pricing-management-tab.php` :: anonymous()
- **wp_ajax_wc_ai_create_pricing_type**: `admin/dashboard/tabs/class-wc-ai-pricing-management-tab.php` :: anonymous()
- **wp_ajax_wc_ai_update_pricing_type**: `admin/dashboard/tabs/class-wc-ai-pricing-management-tab.php` :: anonymous()
- **wp_ajax_wc_ai_delete_pricing_type**: `admin/dashboard/tabs/class-wc-ai-pricing-management-tab.php` :: anonymous()
- **wp_ajax_wc_ai_export_pricing_type**: `admin/dashboard/tabs/class-wc-ai-pricing-management-tab.php` :: anonymous()
- **wp_ajax_wc_ai_export_all_pricing_types**: `admin/dashboard/tabs/class-wc-ai-pricing-management-tab.php` :: anonymous()
- **wp_ajax_wc_ai_import_pricing_types**: `admin/dashboard/tabs/class-wc-ai-pricing-management-tab.php` :: anonymous()
- **wp_ajax_wc_ai_push_pricing_type_to_sites**: `admin/dashboard/tabs/class-wc-ai-pricing-management-tab.php` :: anonymous()
- **wp_ajax_wc_ai_get_pre_checkout_data**: `includes/ajax/class-wc-ai-pre-checkout-ajax.php` :: anonymous()
- **wp_ajax_nopriv_wc_ai_get_pre_checkout_data**: `includes/ajax/class-wc-ai-pre-checkout-ajax.php` :: anonymous()
- **wc_ai_product_data_for_frontend**: `includes/product-modes/class-wc-ai-size-matrix-mode.php` :: anonymous()
- **wc_ai_validate_cart_item**: `includes/product-modes/class-wc-ai-size-matrix-mode.php` :: anonymous()
- **wc_ai_format_cart_item_data**: `includes/product-modes/class-wc-ai-size-matrix-mode.php` :: anonymous()
- **wc_ai_product_data_for_frontend**: `includes/product-modes/class-wc-ai-variant-bulk-mode.php` :: anonymous()
- **wc_ai_validate_cart_item**: `includes/product-modes/class-wc-ai-variant-bulk-mode.php` :: anonymous()
- **wc_ai_format_cart_item_data**: `includes/product-modes/class-wc-ai-variant-bulk-mode.php` :: anonymous()

## ⚡ Events
- None

## 📦 Dependencies
- **WC_AI_Pricing_**: `admin/dashboard/tabs/class-wc-ai-pricing-management-tab.php`
- **WC_AI_Sync_**: `admin/dashboard/tabs/class-wc-ai-pricing-management-tab.php`
- **WC_AI_Pricing_**: `includes/ajax/class-wc-ai-pre-checkout-ajax.php`
- **WC_AI_Pricing_**: `includes/ajax/class-wc-ai-pre-checkout-ajax.php`
- **WC_AI_Pricing_**: `includes/ajax/class-wc-ai-pre-checkout-ajax.php`
- **WC_AI_Pricing_**: `includes/ajax/class-wc-ai-pre-checkout-ajax.php`
- **Pricing**: `includes/ajax/class-wc-ai-pre-checkout-ajax.php`
- **WC_AI_Pricing_**: `includes/ajax/class-wc-ai-pre-checkout-ajax.php`
- **WC_AI_Pricing_**: `includes/product-modes/class-wc-ai-size-matrix-mode.php`
- **WC_AI_Pricing_**: `includes/product-modes/class-wc-ai-size-matrix-mode.php`
- **WC_AI_Pricing_**: `includes/product-modes/class-wc-ai-size-matrix-mode.php`
- **WC_AI_Pricing_**: `includes/product-modes/class-wc-ai-standard-mode.php`
- **WC_AI_Pricing_**: `includes/product-modes/class-wc-ai-variant-bulk-mode.php`
- **WC_AI_Pricing_**: `includes/product-modes/class-wc-ai-variant-bulk-mode.php`
- **WC_AI_Pricing_**: `includes/product-modes/class-wc-ai-variant-bulk-mode.php`

## 🚀 AI Usage Guidelines

### Surgical Targeting Protocol
1. **Scope**: Work only within this feature boundary
2. **Entry Points**: Use modules above as primary targets
3. **Risk Assessment**: Respect risk levels - avoid HIGH risk modules unless critical
4. **Hook Safety**: Preserve existing hook behavior when modifying

### Allowed Files
- `admin/dashboard/tabs/class-wc-ai-pricing-management-tab.php`
- `includes/class-wc-ai-pricing-manager.php`
- `includes/ajax/class-wc-ai-pre-checkout-ajax.php`
- `includes/product-modes/class-wc-ai-size-matrix-mode.php`
- `includes/product-modes/class-wc-ai-standard-mode.php`
- `includes/product-modes/class-wc-ai-variant-bulk-mode.php`

### Testing Checklist
- [ ] Pricing creation
- [ ] Model validation
- [ ] AJAX responses
- [ ] Database operations
- [ ] remove item -> unit price updates for group; undo -> tiers consistent
- [ ] AJAX response validation
- [ ] Data structure
- [ ] Mode detection
- [ ] Price calculation
- [ ] Matrix selection
- [ ] Price calculation
- [ ] Cart validation
- [ ] SKU suffix handling
- [ ] Custom row names
- [ ] Mode detection
- [ ] Config generation
- [ ] Pricing consistency
- [ ] Variant + bulk combination
- [ ] Cart validation
- [ ] Pricing accuracy
