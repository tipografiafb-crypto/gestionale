# PROMPTS - AI Request Templates

> Standardized templates for surgical AI modifications
> **Enhanced with mandatory sections and scope validation**

## 🔧 Template 1: Bugfix Request (MANDATORY SECTIONS)

```
Feature: [bulk-price|frame-bulk|canvas|ai|stage|cart|admin|ui|validation|export] ⚠️ REQUIRED
Goal: [specific issue description] ⚠️ REQUIRED

🎯 MANDATORY: Entrypoint Modules
- [module-name]: [specific purpose] ⚠️ REQUIRED
- [module-name]: [specific purpose]

🔗 MANDATORY: Hooks/Events to touch
- [specific hooks or events] ⚠️ REQUIRED

✅ MANDATORY: Files allowed (from scope/{feature}.allow)
- [exact file paths only] ⚠️ REQUIRED

❌ MANDATORY: Files forbidden (from scope/{feature}.deny)
- [areas to avoid] ⚠️ REQUIRED

🧪 MANDATORY: Test criteria
- [specific behavior to verify] ⚠️ REQUIRED
- [edge cases to check] ⚠️ REQUIRED

📋 Risk Assessment: [LOW|MEDIUM|HIGH] ⚠️ REQUIRED
Blast Radius: [estimated files affected] ⚠️ REQUIRED

Expected output: Complete rewritten files + regression notes
```

## 🏗️ Template 2: Refactor Request (MANDATORY SECTIONS)

```
Feature: [feature-name] ⚠️ REQUIRED
Goal: [refactoring objective] ⚠️ REQUIRED

🔍 MANDATORY: Scope validation
Scope: [LOCAL|MODULE|FEATURE] ⚠️ REQUIRED
Target modules: [specific modules only] ⚠️ REQUIRED
Scope file reference: scope/{feature}.allow ⚠️ REQUIRED

🏗️ MANDATORY: Architecture constraints
- Maintain existing APIs ⚠️ REQUIRED
- Preserve @contracts behavior ⚠️ REQUIRED
- Keep risk level or lower ⚠️ REQUIRED

⚙️ MANDATORY: Capabilities required
- [specific capabilities needed] ⚠️ REQUIRED

🔗 MANDATORY: Dependencies to preserve
- Internal: [module dependencies] ⚠️ REQUIRED
- External: [external dependencies] ⚠️ REQUIRED

📊 MANDATORY: Success criteria
- [measurable outcomes] ⚠️ REQUIRED

🧪 MANDATORY: Testing approach
- [validation method] ⚠️ REQUIRED
```

## 🚀 Template 3: Extension Request (MANDATORY SECTIONS)

```
Feature: [target-feature] ⚠️ REQUIRED
Goal: [new functionality description] ⚠️ REQUIRED

🔌 MANDATORY: Integration validation
Integration approach: [MINIMAL|ADDITIVE|HOOK-BASED] ⚠️ REQUIRED
Scope boundary check: scope/{feature}.allow verified ⚠️ REQUIRED

⚙️ MANDATORY: New capabilities to add
- [specific new capabilities] ⚠️ REQUIRED

🎯 MANDATORY: Entry points for integration
- [existing hooks or extension points] ⚠️ REQUIRED

📋 MANDATORY: New contracts to implement
- [expected input/output behavior] ⚠️ REQUIRED

🔄 MANDATORY: Compatibility & Risk
Backward compatibility: [REQUIRED|OPTIONAL] ⚠️ REQUIRED
Risk tolerance: [LOW|MEDIUM] ⚠️ REQUIRED
Dependency impact: [assessment] ⚠️ REQUIRED

🧪 MANDATORY: Testing approach
- [validation method] ⚠️ REQUIRED
- [integration tests] ⚠️ REQUIRED
```

## 📋 Standard Request Checklist

Every AI request must include:
- [ ] Feature designation from standard set
- [ ] Specific entry point modules  
- [ ] Exact file paths allowed/forbidden
- [ ] Hook/event targeting
- [ ] Clear test criteria
- [ ] Risk/impact assessment

## 🎯 Feature Set (Canonical)

Use only these standardized feature names:
- **bulk-price**: Bulk quantity pricing logic
- **frame-bulk**: Frames-specific bulk pricing  
- **canvas**: Canvas engine and manipulation
- **ai**: AI image generation and processing
- **stage**: Multi-stage workflow management
- **cart**: Shopping cart and checkout
- **admin**: Admin interface and configuration
- **ui**: User interface components
- **validation**: Data validation and integrity
- **export**: File export and generation

## 💡 Usage Examples

### Example: Cart Bug Fix
```
Feature: cart
Goal: Fix price recalculation after item removal

Entrypoint Modules:
- BulkPricingBackend: Recalculate group pricing tiers
- CartIntegration: Update cart totals

Hooks/Events to touch:
- woocommerce_cart_item_removed
- woocommerce_before_calculate_totals

Files allowed:
- includes/class-wc-ai-bulk-pricing.php
- public/class-wc-ai-product-customizer-public.php

Test criteria:
- Remove item → remaining items update unit_price
- Undo removal → prices remain consistent
- Mini-cart and cart page show same totals
```
