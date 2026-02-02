# SEARCH SHORTCUTS

> Comandi di ricerca rapida per trovare moduli specifici

## By Feature

### Trovare moduli per Bulk Price
```bash
# Trova tutti i moduli bulk pricing (classic)
grep -r "@feature.*bulk-price" --include="*.js" --include="*.php" .

# Trova tutti i moduli frames bulk pricing  
grep -r "@feature.*frame-bulk-pricing" --include="*.js" --include="*.php" .

# Trova tutti i moduli pricing in generale
grep -r "@domain.*pricing" --include="*.js" --include="*.php" .
```

### Trovare moduli per Canvas
```bash
# Trova moduli canvas core
grep -r "@feature.*fabric-engine" --include="*.js" .

# Trova bridge canvas (delegates)
grep -r "@feature.*canvas-bridge" --include="*.js" .

# Trova tutti i moduli canvas
grep -r "@domain.*canvas" --include="*.js" .
```

### Trovare moduli per UI/Interface
```bash  
# Trova moduli Magenta UI
grep -r "@feature.*magenta-" --include="*.js" .

# Trova moduli UI in generale
grep -r "@domain.*ui" --include="*.js" .

# Trova moduli panels
grep -r "@feature.*panels" --include="*.js" .
```

## By Domain

### Backend Modules
```bash
# Trova tutti i moduli backend
grep -r "@domain.*backend" --include="*.php" .

# Trova moduli integration  
grep -r "@domain.*integration" --include="*.php" .

# Trova moduli routing
grep -r "@domain.*routing" --include="*.php" .
```

### Frontend Modules
```bash
# Trova moduli UI frontend
grep -r "@domain.*ui" --include="*.js" .

# Trova moduli customizer
grep -r "@domain.*customizer" --include="*.js" .
```

## By Risk Level

### High Risk Modules (pricing, core)
```bash
grep -r "@risk.*HIGH" --include="*.js" --include="*.php" .
```

### Medium Risk Modules (UI, integration)
```bash
grep -r "@risk.*MEDIUM" --include="*.js" --include="*.php" .
```

### Low Risk Modules (utilities, display)
```bash
grep -r "@risk.*LOW" --include="*.js" --include="*.php" .
```

## By Specific Events/Hooks

### Trovare chi tocca i totali carrello
```bash
# Trova moduli che gestiscono totali cart
grep -r "woocommerce_before_calculate_totals\|@events.*before_calculate_totals" --include="*.php" .

# Trova moduli che gestiscono add-to-cart
grep -r "woocommerce_add_to_cart\|@events.*add_to_cart" --include="*.php" .

# Trova moduli che gestiscono cart item removal
grep -r "woocommerce_cart_item_removed\|@events.*cart_item_removed" --include="*.php" .
```

### Trovare eventi Canvas
```bash
# Trova moduli che gestiscono eventi canvas
grep -r "@events.*canvas" --include="*.js" .

# Trova moduli che gestiscono stage switching
grep -r "@events.*stage" --include="*.js" .
```

## By Entry Points

### Trovare tutti gli entry points UI pricing
```bash
grep -r "@domain.*pricing" public/js/ --include="*.js"
```

### Trovare entry points AJAX
```bash
grep -r "@exports.*ajax_" --include="*.php" .
```

### Trovare export functions principali
```bash
# Trova funzioni init
grep -r "@exports.*init" --include="*.js" --include="*.php" .

# Trova funzioni calculate
grep -r "@exports.*calculate" --include="*.js" --include="*.php" .
```

## Module Dependencies

### Trovare chi consuma un modulo specifico
```bash
# Esempio: chi usa PricingManager?
grep -r "@consumes.*pricing-manager\|@consumes.*class-wc-ai-pricing-manager" --include="*.js" --include="*.php" .

# Esempio: chi usa CanvasEngine?
grep -r "@consumes.*CanvasEngine\|@consumes.*Engine.js" --include="*.js" .
```

### Trovare dipendenze di un modulo
```bash
# Vedere cosa consuma un modulo guardando il suo header MODULE
grep -A 15 "MODULE" [path-to-file] | grep "@consumes"
```

## Quick Filters

### Solo file HIGH RISK
```bash
grep -l "@risk.*HIGH" $(find . -name "*.js" -o -name "*.php") | head -10
```

### Solo moduli PRICING
```bash
grep -l "@domain.*pricing" $(find . -name "*.js" -o -name "*.php")
```

### Solo moduli che toccano CART
```bash
grep -l "@touches.*[Cc]art" $(find . -name "*.js" -o -name "*.php")
```

## Usage

1. **Copy/paste** il comando appropriato nel terminale
2. **Personalizza** il pattern di ricerca se necessario
3. **Combina** più comandi per ricerche specifiche
4. Usa questi shortcuts nel README per riferimento rapido