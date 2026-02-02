# FEATURE: UI

> Generated automatically by `tools/build-universal-mapping.mjs`  
> **Focus Slice** - Targeted view for surgical AI modifications

## 📊 Quick Stats
- **Modules**: 10
- **Hooks**: 3  
- **Events**: 27
- **Dependencies**: 4
- **Risk Distribution**: MEDIUM: 1, LOW: 9

## 🎯 Modules Registry

| Module | Path | Purpose | Risk |
|---|---|---|---|
| CanvaHandler | `includes/interfaces/class-wc-ai-canva-handler.php` | Full-page Canva-style interface handler for product customization routing | MEDIUM |
| ModalHandler | `includes/interfaces/class-wc-ai-modal-handler.php` | Traditional modal popup interface handler for product customization | LOW |
| MagentaFloatingCanvasPanelCSS | `public/css/magenta/stage-select-modal.css` | CSS styling for floating canvas selection panel component | LOW |
| VariantSelector | `public/js/variant-selector.js` | Master/Servant variant selector modal with canvas transfer support + Universal Customizer Launcher | LOW |
| PreCheckoutSelector | `public/js/components/PreCheckoutSelector.js` | Pre-checkout pricing selector: displays variant/quantity dropdowns above customize button | LOW |
| ClientErrorModal | `public/js/core/client-error-modal.js` | Clean client-facing error modal system with PO/MO translation support | LOW |
| ConfirmModal | `public/js/interfaces-v2/magenta-customizer/ui/components/ConfirmModal.js` | Confirmation modal for destructive actions in Magenta Customizer | LOW |
| MagentaStageSelectModal | `public/js/interfaces-v2/magenta-customizer/ui/components/StageSelectModal.js` | Floating panel component for canvas/stage selection in multi-stage customizer | LOW |
| ClipArtPanel | `public/js/interfaces-v2/magenta-customizer/ui/panels/ClipArtPanel.js` | Pannello clip art con selezione da libreria SVG gestita dall'admin | LOW |
| PriceFormatter | `public/js/utils/price-formatter.js` | Centralized price formatting with currency configuration | LOW |

## 🔗 Hooks
- **template_redirect**: `includes/interfaces/class-wc-ai-canva-handler.php` :: anonymous()
- **wp_enqueue_scripts**: `includes/interfaces/class-wc-ai-canva-handler.php` :: anonymous()
- **wp_footer**: `includes/interfaces/class-wc-ai-modal-handler.php` :: anonymous()

## ⚡ Events
- **click** (listen): `public/js/variant-selector.js`
- **click** (listen): `public/js/variant-selector.js`
- **click** (listen): `public/js/variant-selector.js`
- **click** (listen): `public/js/variant-selector.js`
- **click** (listen): `public/js/variant-selector.js`
- **click** (listen): `public/js/variant-selector.js`
- **keydown** (listen): `public/js/variant-selector.js`
- **click** (listen): `public/js/variant-selector.js`
- **change** (listen): `public/js/components/PreCheckoutSelector.js`
- **click** (listen): `public/js/components/PreCheckoutSelector.js`
- **change** (listen): `public/js/components/PreCheckoutSelector.js`
- **change** (listen): `public/js/components/PreCheckoutSelector.js`
- **change** (listen): `public/js/components/PreCheckoutSelector.js`
- **change** (listen): `public/js/components/PreCheckoutSelector.js`
- **change** (listen): `public/js/components/PreCheckoutSelector.js`
- **click** (listen): `public/js/core/client-error-modal.js`
- **click** (listen): `public/js/core/client-error-modal.js`
- **keydown** (listen): `public/js/core/client-error-modal.js`
- **click** (listen): `public/js/interfaces-v2/magenta-customizer/ui/components/ConfirmModal.js`
- **click** (listen): `public/js/interfaces-v2/magenta-customizer/ui/components/ConfirmModal.js`
- **click** (listen): `public/js/interfaces-v2/magenta-customizer/ui/components/ConfirmModal.js`
- **keydown** (listen): `public/js/interfaces-v2/magenta-customizer/ui/components/ConfirmModal.js`
- **click** (listen): `public/js/interfaces-v2/magenta-customizer/ui/components/StageSelectModal.js`
- **keydown** (listen): `public/js/interfaces-v2/magenta-customizer/ui/components/StageSelectModal.js`
- **click** (listen): `public/js/interfaces-v2/magenta-customizer/ui/components/StageSelectModal.js`
- **keydown** (listen): `public/js/interfaces-v2/magenta-customizer/ui/components/StageSelectModal.js`
- **click** (listen): `public/js/interfaces-v2/magenta-customizer/ui/panels/ClipArtPanel.js`

## 📦 Dependencies
- **CanvasTransfer**: `public/js/variant-selector.js`
- **Workspace**: `public/js/variant-selector.js`
- **CategoryUI**: `public/js/interfaces-v2/magenta-customizer/ui/panels/ClipArtPanel.js`
- **Positioning**: `public/js/interfaces-v2/magenta-customizer/ui/panels/ClipArtPanel.js`

## 🚀 AI Usage Guidelines

### Surgical Targeting Protocol
1. **Scope**: Work only within this feature boundary
2. **Entry Points**: Use modules above as primary targets
3. **Risk Assessment**: Respect risk levels - avoid HIGH risk modules unless critical
4. **Hook Safety**: Preserve existing hook behavior when modifying

### Allowed Files
- `includes/interfaces/class-wc-ai-canva-handler.php`
- `includes/interfaces/class-wc-ai-modal-handler.php`
- `public/css/magenta/stage-select-modal.css`
- `public/js/variant-selector.js`
- `public/js/components/PreCheckoutSelector.js`
- `public/js/core/client-error-modal.js`
- `public/js/interfaces-v2/magenta-customizer/ui/components/ConfirmModal.js`
- `public/js/interfaces-v2/magenta-customizer/ui/components/StageSelectModal.js`
- `public/js/interfaces-v2/magenta-customizer/ui/panels/ClipArtPanel.js`
- `public/js/utils/price-formatter.js`

### Testing Checklist
- [ ] Interface routing
- [ ] Asset loading
- [ ] Product validation
- [ ] Template rendering
- [ ] Modal rendering
- [ ] Interface functionality
- [ ] Product integration
- [ ] Visual rendering
- [ ] Responsive behavior
- [ ] Panel animations
- [ ] Canvas selection
- [ ] Variant selection
- [ ] Canvas transfer before redirect
- [ ] Modal interaction
- [ ] Direct customizer launch
- [ ] Data loading
- [ ] Price calculation
- [ ] Selection persistence
- [ ] Mode rendering
- [ ] Modal display
- [ ] Translation integration
- [ ] Error code validation
- [ ] Modal display
- [ ] Confirm/Cancel actions
- [ ] Keyboard navigation
- [ ] Panel show/hide
- [ ] Stage selection
- [ ] Multi-stage navigation
- [ ] ClipArt loading
- [ ] Category filter
- [ ] Gallery display
- [ ] Canvas integration
- [ ] Format with different currencies
- [ ] positions
- [ ] separators
- [ ] decimal places
