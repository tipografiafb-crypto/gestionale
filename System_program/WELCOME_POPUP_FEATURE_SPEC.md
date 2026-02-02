# Welcome Popup Feature Specification
> **Date**: Nov 20, 2025  
> **Feature Scope**: `magenta-interface` + `admin`  
> **Status**: DESIGN PHASE

---

## 🎯 Feature Target
```
Feature: magenta-interface (UI) + admin (configuration)
Goal: Add customizable welcome popup on customizer load
Entrypoints: 
  - Admin: WooCommerce Settings > Magenta Customizer > Welcome Popup Tab
  - Frontend: Customizer Bootstrap → PopupManager
```

---

## 📐 ARCHITECTURE DESIGN

### 1️⃣ FRONTEND MODULE STRUCTURE (`magenta-interface` / `ui`)

#### New Components:
```
magenta-product-customizer/
└── public/js/
    └── components/
        ├── WelcomePopupManager.js          // @feature: magenta-interface
        │   ├── popup creation logic
        │   ├── event handling
        │   └── styling (error-message style)
        ├── WelcomePopupContent.js          // @feature: ui
        │   ├── title, message, instructions
        │   └── close button
        └── popups/
            └── welcome-popup.css            // error-style theme
```

#### Key Responsibilities:
```javascript
// WelcomePopupManager
- Check localStorage for "welcome_popup_seen_[product_id]"
- Fetch global + product-level config from `/wp-json/magenta/v1/welcome-popup`
- Render popup on customizer init
- Handle close action (mark as seen, trigger callback)
- Apply error-message styling

// WelcomePopupContent
- Render title, message, instructions
- Handle HTML content (sanitized)
- Trigger custom event `magenta_welcome_closed`
```

---

### 2️⃣ ADMIN MODULE STRUCTURE (`admin`)

#### Settings Location:
```
WordPress Admin
├── WooCommerce → Settings
├── Tab: Magenta Settings (existing)
└── Sub-section: Welcome Popup (NEW)
    ├── Global Settings
    │   ├── Enable/Disable toggle
    │   ├── Title (global)
    │   ├── Message (global, WYSIWYG editor)
    │   ├── Instructions (global, WYSIWYG editor)
    │   └── Styling options (color, dismissible)
    ├── Per-Product Override Tab (NEW)
    │   └── In Product Edit Screen
    │       ├── Enable/Disable per product
    │       ├── Title (override)
    │       ├── Message (override)
    │       └── Instructions (override)
```

#### New Files:
```
magenta-product-customizer/includes/
├── admin/
│   ├── class-welcome-popup-settings.php    // @feature: admin
│   │   ├── register_settings() → option keys
│   │   ├── render_global_section()
│   │   ├── sanitize_callbacks()
│   │   └── enqueue admin JS/CSS
│   └── class-welcome-popup-product-meta.php // @feature: admin
│       ├── register_meta_box() on product edit
│       ├── save_product_meta()
│       └── get_product_config()
├── class-welcome-popup-config.php         // @feature: magenta-interface
│   ├── get_config_for_product($product_id)
│   ├── merge_global_and_product_settings()
│   └── REST endpoint handler
└── class-welcome-popup-manager.php        // @feature: magenta-interface
    ├── enqueue JS/CSS
    ├── localize_script() with config
    └── register_rest_endpoints()
```

---

### 3️⃣ REST API ENDPOINTS

```php
// Endpoint: /wp-json/magenta/v1/welcome-popup
GET /wp-json/magenta/v1/welcome-popup?product_id={id}

Response:
{
  "enabled": true,
  "title": "Welcome!",
  "message": "<p>Customize your product</p>",
  "instructions": "Click Save when done",
  "styling": {
    "background_color": "#fee",
    "text_color": "#333",
    "show_close_button": true
  },
  "product_override": true  // true if product has custom settings
}
```

---

### 4️⃣ DATA STORAGE

#### Option Keys (Global):
```php
option_name: 'magenta_welcome_popup_enabled'        // bool
option_name: 'magenta_welcome_popup_title'          // string
option_name: 'magenta_welcome_popup_message'        // string (HTML)
option_name: 'magenta_welcome_popup_instructions'   // string (HTML)
option_name: 'magenta_welcome_popup_styling'        // JSON (colors, etc)
```

#### Post Meta Keys (Per-Product):
```php
meta_key: '_magenta_welcome_popup_override'         // bool
meta_key: '_magenta_welcome_popup_title'            // string
meta_key: '_magenta_welcome_popup_message'          // string (HTML)
meta_key: '_magenta_welcome_popup_instructions'     // string (HTML)
```

---

### 5️⃣ FLOW DIAGRAM

```
FRONTEND FLOW:
┌─────────────────────────────────────────────────────┐
│ Customizer Page Load                                │
└─────────────────┬───────────────────────────────────┘
                  │
                  ▼
         WelcomePopupManager.init()
                  │
    ┌─────────────┴──────────────┐
    │                            │
    ▼                            ▼
Check localStorage         Check global config
[popup_seen]             [enabled = true?]
    │                            │
    └─────────────┬──────────────┘
                  │
                  ▼ (both pass)
        Fetch product config
        /wp-json/magenta/v1/welcome-popup
                  │
                  ▼
        Render PopupContent
        (error-message style)
                  │
    ┌─────────────┴──────────────┐
    │                            │
    ▼                            ▼
 Close Button          Auto-Dismiss?
    │                            │
    └─────────────┬──────────────┘
                  │
                  ▼
        Set localStorage[popup_seen]
        Trigger custom event
        Remove from DOM
```

---

## 🎨 STYLING (Error-Message Theme)

```css
/* Inherit from existing error message styles */
.magenta-welcome-popup {
  border-left: 4px solid #dc3545;      /* Error color */
  background-color: #fff5f5;
  color: #721c24;
  padding: 20px;
  border-radius: 4px;
  box-shadow: 0 2px 8px rgba(0,0,0,0.1);
  max-width: 600px;
  margin: auto;
}

.magenta-welcome-popup__title {
  font-weight: 600;
  font-size: 18px;
  margin-bottom: 12px;
}

.magenta-welcome-popup__message {
  line-height: 1.6;
  margin-bottom: 12px;
}

.magenta-welcome-popup__instructions {
  font-size: 14px;
  opacity: 0.9;
}

.magenta-welcome-popup__close {
  position: absolute;
  top: 10px;
  right: 10px;
  background: transparent;
  border: none;
  cursor: pointer;
  font-size: 20px;
  color: inherit;
}
```

---

## 📝 IMPLEMENTATION PHASE CHECKLIST

### PHASE 1: Configuration Layer (Admin)
- [ ] Create `WelcomePopupSettings` class → register global options
- [ ] Create `WelcomePopupProductMeta` class → register product meta
- [ ] Add admin settings UI in WooCommerce → Magenta Settings
- [ ] Add product meta box in product edit screen
- [ ] Create REST endpoint for config retrieval

### PHASE 2: Frontend Display Layer
- [ ] Create `WelcomePopupManager` class
- [ ] Create `WelcomePopupContent` component
- [ ] Add popup CSS (error-message theme)
- [ ] Implement localStorage checking logic
- [ ] Hook into customizer initialization

### PHASE 3: Integration & Testing
- [ ] Test global settings enable/disable
- [ ] Test product-level overrides
- [ ] Test localStorage persistence
- [ ] Test across all customizer types (magenta, frames, diecut)
- [ ] Verify event triggering

---

## ✅ MODULE CONTRACTS (Pre-commit Guards)

Each file must include proper headers:

```php
<?php
/**
 * Welcome Popup Configuration Manager
 * 
 * @feature: magenta-interface
 * @domain: customizer
 * @since: 2.0.0
 */
```

```javascript
/**
 * Welcome Popup Manager
 * @feature magenta-interface
 * @domain ui-components
 */
```

---

## 🔗 DEPENDENCIES

### Existing Systems to Integrate With:
1. **Admin Settings**: WooCommerce Settings framework
2. **Product Data**: WooCommerce Post Meta
3. **Frontend**: Customizer bootstrapping system
4. **Styling**: Existing `magenta.css` (error-message theme)
5. **REST API**: Magenta REST controller base class

### Scope Constraints:
- ✅ Allowed: Modifying `includes/admin/`, `public/js/components/`
- ❌ Forbidden: Modifying legacy folders, external APIs
- ✅ Integration with existing customizer init hooks

---

## 📊 FEATURE METRICS

| Metric | Value |
|--------|-------|
| New Files | 5 |
| Modified Files | 3-4 (admin config, customizer init) |
| New Components | 2 |
| Blast Radius | 🟢 LOW (isolated feature) |
| Testing Surface | Medium (UI + Config) |
| Breaking Changes | ⚠️ NONE |

