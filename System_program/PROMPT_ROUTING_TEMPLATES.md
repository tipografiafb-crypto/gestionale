# PROMPT ROUTING TEMPLATES

> Template di prompt per "instradare" l'AI verso i moduli giusti

## Template Base

```
Context (routing)
Feature: [feature-name]
Domain: [domain-name]
Entry modules:
- [module-path] (@exports: [key-exports])
- [module-path] (@exports: [key-exports])

Goal: "[descrizione specifica del problema/obiettivo]"

Instructions
1. Modifica SOLO i moduli sopra elencati
2. Mantieni API esistenti
3. Aggiungi test manuali elencati in @tests
4. Output: file completi riscritti
```

## Template per Bulk Pricing

```
Context (routing)
Feature: bulk-price
Domain: pricing
Entry modules:
- includes/class-wc-ai-pricing-manager.php (@exports: resolveMode, calculateForItem, getInstance)
- public/class-wc-ai-product-customizer-public.php (@exports: apply_frames_custom_pricing, ajax_add_to_cart)

Goal: "Fix bulk pricing calculation and cart synchronization"

Instructions
1. Modifica SOLO i moduli sopra elencati
2. Mantieni API esistenti  
3. Aggiungi test: Pricing consistency, Meta persistenza
4. Output: file completi riscritti
```

## Template per Frame Bulk Pricing

```
Context (routing)
Feature: frame-bulk-pricing  
Domain: pricing, frames
Entry modules:
- includes/class-wc-ai-frames-bulk-pricing.php (@exports: ajax_get_cart_quantity, before_calculate_totals)
- public/class-wc-ai-product-customizer-public.php (@exports: apply_frames_custom_pricing)

Goal: "Fix frames tier calculation dopo rimozione item in cart"

Instructions
1. Modifica SOLO i moduli sopra elencati
2. Mantieni API esistenti
3. Aggiungi test: Tier update dopo rimozione, Scan cart per frames
4. Output: file completi riscritti
```

## Template per Magenta UI

```
Context (routing)
Feature: magenta-interface
Domain: ui, customizer
Entry modules:  
- public/js/interfaces-v2/magenta-customizer/MagentaCustomizer.js (@exports: init, switchStage, getCurrentStage)
- public/js/interfaces-v2/magenta-customizer/managers/PanelManager.js (@exports: showPanel, hidePanel, togglePanel)

Goal: "[problema UI specifico]"

Instructions
1. Modifica SOLO i moduli sopra elencati
2. Mantieni API esistenti
3. Aggiungi test: Stage switch preserva objects, Panel switching
4. Output: file completi riscritti
```

## Template per Canvas Operations

```
Context (routing)
Feature: fabric-engine
Domain: canvas
Entry modules:
- public/js/core/canvas/core/Engine.js (@exports: initCanvas, getFabricCanvas, exportCanvas)
- public/js/interfaces-v2/magenta-customizer/delegates/CanvasDelegate.js (@exports: initialize, isEmpty, addImage)

Goal: "[operazione canvas specifica]"

Instructions  
1. Modifica SOLO i moduli sopra elencati
2. Mantieni API esistenti
3. Aggiungi test: Stage switch non rompe mask, Export consistency
4. Output: file completi riscritti
```

## Template per Interface Routing

```
Context (routing)
Feature: interface-routing
Domain: routing, backend
Entry modules:
- includes/class-wc-ai-interface-router.php (@exports: handle_canva_route, handle_magenta_route, handle_frames_route)

Goal: "[problema routing specifico]"

Instructions
1. Modifica SOLO i moduli sopra elencati  
2. Mantieni API esistenti
3. Aggiungi test: Routing corretto per product type
4. Output: file completi riscritti
```

## Usage Instructions

1. **Copy/paste** il template appropriato quando chiedi una modifica
2. **Personalizza** il Goal con la descrizione specifica del problema
3. **Aggiungi Entry modules** se necessari altri file correlati
4. L'AI andrà direttamente ai moduli giusti senza esplorazioni