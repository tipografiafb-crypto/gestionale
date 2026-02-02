# FEATURE: FRAME-BULK

> Generated automatically by `tools/build-universal-mapping.mjs`  
> **Focus Slice** - Targeted view for surgical AI modifications

## 📊 Quick Stats
- **Modules**: 1
- **Hooks**: 12  
- **Events**: 0
- **Dependencies**: 5
- **Risk Distribution**: HIGH: 1

## 🎯 Modules Registry

| Module | Path | Purpose | Risk |
|---|---|---|---|
| FramesRangeMode | `includes/product-modes/class-wc-ai-frames-range-mode.php` | Dynamic range pricing with cart aggregation (vs static tier bulk pricing) | HIGH |

## 🔗 Hooks
- **wp_ajax_frames_range_get_cart_quantity**: `includes/product-modes/class-wc-ai-frames-range-mode.php` :: anonymous()
- **wp_ajax_nopriv_frames_range_get_cart_quantity**: `includes/product-modes/class-wc-ai-frames-range-mode.php` :: anonymous()
- **wp_ajax_frames_range_get_pricing**: `includes/product-modes/class-wc-ai-frames-range-mode.php` :: anonymous()
- **wp_ajax_nopriv_frames_range_get_pricing**: `includes/product-modes/class-wc-ai-frames-range-mode.php` :: anonymous()
- **wp_ajax_frames_range_save_pricing**: `includes/product-modes/class-wc-ai-frames-range-mode.php` :: anonymous()
- **woocommerce_add_cart_item_data**: `includes/product-modes/class-wc-ai-frames-range-mode.php` :: anonymous()
- **woocommerce_before_calculate_totals**: `includes/product-modes/class-wc-ai-frames-range-mode.php` :: anonymous()
- **woocommerce_cart_item_removed**: `includes/product-modes/class-wc-ai-frames-range-mode.php` :: anonymous()
- **woocommerce_cart_item_restored**: `includes/product-modes/class-wc-ai-frames-range-mode.php` :: anonymous()
- **woocommerce_after_cart_item_quantity_update**: `includes/product-modes/class-wc-ai-frames-range-mode.php` :: anonymous()
- **init**: `includes/product-modes/class-wc-ai-frames-range-mode.php` :: anonymous()
- **init**: `includes/product-modes/class-wc-ai-frames-range-mode.php` :: anonymous()

## ⚡ Events
- None

## 📦 Dependencies
- **WC_AI_Pricing_**: `includes/product-modes/class-wc-ai-frames-range-mode.php`
- **WC_AI_Pricing_**: `includes/product-modes/class-wc-ai-frames-range-mode.php`
- **WC_AI_Pricing_**: `includes/product-modes/class-wc-ai-frames-range-mode.php`
- **WC_AI_Pricing_**: `includes/product-modes/class-wc-ai-frames-range-mode.php`
- **WC_AI_Pricing_**: `includes/product-modes/class-wc-ai-frames-range-mode.php`

## 🚀 AI Usage Guidelines

### Surgical Targeting Protocol
1. **Scope**: Work only within this feature boundary
2. **Entry Points**: Use modules above as primary targets
3. **Risk Assessment**: Respect risk levels - avoid HIGH risk modules unless critical
4. **Hook Safety**: Preserve existing hook behavior when modifying

### Allowed Files
- `includes/product-modes/class-wc-ai-frames-range-mode.php`

### Testing Checklist
- [ ] Cart aggregation
- [ ] Range calculation
- [ ] Item removal → price update
- [ ] Range tier transitions
