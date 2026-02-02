🌐 Workflow di Traduzione per WC AI Product Customizer
## Panoramica
Questo documento descrive il processo completo per tradurre stringhe nei sistemi **Magenta** e **Frames** che hanno architetture di traduzione diverse ma complementari.

## 🎯 SISTEMI DI TRADUZIONE

### 📊 MAGENTA SYSTEM (Template Inline) ✅
- **Template**: `templates/magenta-customizer.php`
- **Config JS**: `window.magentaGlobalConfig.i18n`
- **Metodo**: Traduzioni hardcoded nel template PHP
- **Componenti**: Tutti i componenti Magenta (incluso Design Library)

### 📊 FRAMES SYSTEM (wp_localize_script)
- **Handler PHP**: `includes/interfaces/class-wc-ai-frames-handler.php`
- **Config JS**: `window.wcAiFramesConfig.translations` + `window.wcAiFramesConfig.i18n`
- **Metodo**: Traduzioni passate via wp_localize_script

---

## 🔧 WORKFLOW MAGENTA (Template Inline)

### 1. Modifica File JavaScript
**File**: Es. `LayoutManager.js`
**Formato**: `${this.parent.config.i18n.CHIAVE || 'Fallback'}`
```javascript
// DA:
<span class="mg-btn-text">Close</span>
// A:
<span class="mg-btn-text">${this.parent.config.i18n.close || 'Close'}</span>
```

### 2. Aggiunta al File PO
**File**: `languages/wc-ai-product-customizer-it_IT.po`
```
#: templates/magenta-customizer.php
msgid "Close"
msgstr "Chiudi"
```

### 3. Ricompilazione
```bash
cd wc-ai-product-customizer/languages && php compile-po.php
```

### 4. ⚠️ CRITICO: Template PHP
**File**: `templates/magenta-customizer.php` (riga ~164)
```php
i18n: {
    close: '<?php echo esc_js( __( 'Close', 'wc-ai-product-customizer' ) ); ?>',
}
```

---

## 🔧 WORKFLOW FRAMES (wp_localize_script)

### 1. Identificare Chiave JavaScript
**Esempio**: AIDelegate.js usa `translations.generateImage`
```javascript
$generateText.text(translations.generateImage || 'Generate Image');
```

### 2. Aggiunta al File PO
**File**: `languages/wc-ai-product-customizer-it_IT.po`
```
#: includes/interfaces/class-wc-ai-frames-handler.php
msgid "Generate Image"
msgstr "Genera Immagine"
```

### 3. Ricompilazione
```bash
cd wc-ai-product-customizer/languages && php compile-po.php
```

### 4. ⚠️ CRITICO: PHP Handler
**File**: `includes/interfaces/class-wc-ai-frames-handler.php`
**Sezione**: Array `'i18n'` (riga ~240+)
```php
'i18n' => array(
    'generateImage' => __( 'Generate Image', 'wc-ai-product-customizer' ),
    // ... altre chiavi
)
```

### 5. ⚠️ DUPLICAZIONE NECESSARIA
**Frames richiede ENTRAMBI gli array** per retrocompatibilità:
```php
// Dopo la chiusura dell'array i18n:
$frames_config['translations'] = $frames_config['i18n'];
```

---

## 🚨 PROBLEMI COMUNI E SOLUZIONI

### ❌ "Vedo ancora la stringa inglese"
**Magenta**: Manca chiave in `magenta-customizer.php` oggetto `i18n`
**Frames**: Manca chiave in `class-wc-ai-frames-handler.php` array `i18n`

### ❌ "Solo alcune stringhe non si traducono"
**Causa**: JavaScript cerca chiavi che non esistono nel config passato da PHP
**Soluzione**: Verifica il mapping esatto tra nome chiave JS ↔ nome chiave PHP

### ❌ "Funziona in Magenta ma non in Frames"
**Causa**: Sistemi diversi - Magenta usa `i18n`, Frames usa `translations`
**Soluzione**: Frames necessita della duplicazione: `$frames_config['translations'] = $frames_config['i18n']`

---

## 📝 CHECKLIST COMPLETA

### Per MAGENTA:
- [ ] 1. Modificato file JavaScript con `this.parent.config.i18n.CHIAVE` oppure `config.i18n.CHIAVE`
- [ ] 2. Aggiunto stringa al file .po
- [ ] 3. Eseguito `php compile-po.php`
- [ ] 4. Aggiunto chiave a `magenta-customizer.php` oggetto `i18n`
- [ ] 5. Testato `window.magentaGlobalConfig.i18n.CHIAVE`

**⚠️ REGOLA CRITICA**: Tutti i componenti Magenta (incluso Design Library) usano **SOLO** il sistema template inline (`this.parent.config.i18n`). **MAI** usare `wp_localize_script` per componenti Magenta.

### Per FRAMES:
- [ ] 1. Identificato chiave usata in JavaScript (`translations.CHIAVE`)
- [ ] 2. Aggiunto stringa al file .po
- [ ] 3. Eseguito `php compile-po.php`  
- [ ] 4. Aggiunto chiave a `class-wc-ai-frames-handler.php` array `i18n`
- [ ] 5. Verificato duplicazione: `$frames_config['translations'] = $frames_config['i18n']`
- [ ] 6. Testato `window.wcAiFramesConfig.translations.CHIAVE`

---

## 🎯 COMANDI RAPIDI

**Per tradurre in Magenta**: "Traduci la stringa X in Magenta seguendo TRANSLATION_WORKFLOW.md"
**Per tradurre in Frames**: "Traduci la stringa X in Frames seguendo TRANSLATION_WORKFLOW.md"

---

## ✅ SISTEMA UNIFICATO MAGENTA

**Data unificazione**: Gennaio 2025

Tutti i componenti del sistema Magenta (LayoutManager, AIPanel, TextPanel, UploadPanel, **Design Library**, ecc.) ora usano **esclusivamente** il sistema template inline:

### Struttura Unificata:
```javascript
// Accesso alle traduzioni nei componenti Magenta
const t = this.parent.config.i18n.designLibrary?.saveModal || {};

// Esempio utilizzo
modalHTML = `<h3>${t.title || 'Save Design'}</h3>`;
```

### Template PHP (Single Source of Truth):
```php
// templates/magenta-customizer.php
i18n: {
    designLibrary: {
        saveModal: {
            title: '<?php echo esc_js( __( 'Save Design', 'wc-ai-product-customizer' ) ); ?>',
            // ...
        }
    }
}
```

**Vantaggi**:
- ✅ Un solo punto di manutenzione
- ✅ Coerenza architettonica totale
- ✅ Facilità di debug
- ✅ Workflow unificato e semplificato

**Questo workflow risolve il 99% dei problemi di traduzione in entrambi i sistemi!** 🎊