# Agent Workflow & Operational Guidelines

> **Location**: This file contains the complete operational workflow for AI agents working on the Gestionale (Ruby/Sinatra) project.
> 
> **Purpose**: Detailed instructions for surgical AI targeting, pre-commit guards, and enterprise-grade module routing.

## 🚀 ENTERPRISE-GRADE MODULE ROUTING SYSTEM (Jan 28, 2026)

### 📊 Universal Mapping System - Core Features

**Auto-Generation Tool**: `System_program/tools/build-universal-mapping.mjs`

This tool automatically scans the codebase (Ruby & JS) and generates 5 key documentation files:

1. **`System_program/mod-index.json`** - Programmatic index
   - Risk/stability distribution
   - Feature-based organization
   - Searchable module metadata

2. **`System_program/SYSTEM_STATUS.md`** - Real-time health dashboard
   - System metrics and quality indicators
   - High-risk module alerts
   - Module stability distribution

3. **`System_program/ORPHANS.md`** - Cross-reference analysis
   - Detects orphaned files (no @feature tag)
   - Identifies potential duplicates
   - Lists missing metadata (risk, stability, domain)
   - Single-file features requiring expansion

4. **`System_program/MODULES.md`** - Complete documentation with AI-ready metadata
   - All modules organized by feature
   - JSDoc/RubyDoc (`# @ai-module`) extraction
   - AI-ready format for surgical targeting

5. **`System_program/HOOKS.md`** - Hooks/Callbacks registry
   - Auto-extracted from `# @ai-hook` comments
   - Interception points for customization

---

### 🎯 Surgical AI Targeting Workflow

1.  **Feature Targeting**: Always specify which feature you're working on:
    ```
    Feature Target: [orders|products|ui|auth|switch|print-flow|api]
    ```

2.  **Pre-Work Checklist** (Universal Mapping System):
    **Core Analysis Files** (located in `System_program/`):
    *   Consult `System_program/SYSTEM_STATUS.md` for current health status
    *   Review `System_program/MODULES.md` for complete module metadata and AI-ready descriptions
    *   Check `System_program/ORPHANS.md` for architectural issues (orphan files, duplicates, missing metadata)
    *   Review `System_program/mod-index.json` for programmatic module index access

    **Integration & Data Flow**:
    *   Consult `System_program/HOOKS.md` for event/callback registry
    *   **CRITICAL**: Check `System_program/DATAFLOW.md` for dependencies and blast radius analysis before touching HIGH/CRITICAL modules.

    **Navigation & Templates**:
    *   Use `System_program/SEARCH_SHORTCUTS.md` for quick module navigation
    *   Reference `System_program/PROMPTS.md` for standardized AI request templates

    **Auto-Generated Files** (updated every commit):
    *   `System_program/mod-index.json` - Searchable module index
    *   `System_program/SYSTEM_STATUS.md` - Health dashboard
    *   `System_program/MODULES.md` - AI-ready documentation
    *   `System_program/ORPHANS.md` - Code quality alerts

3.  **Request Template for New Chats**:
    ```
    🎯 RICHIESTA CHIRURGICA PER GESTIONALE (Jan 2026)

    **Feature Target**: [scegli una feature specifica]
    **Obiettivo**: [descrivi la modifica]
    **Vincoli**: Usa solo moduli della feature selezionata

    **Istruzioni per l'AI**:
    1. Leggi System_program/MODULES.md per i moduli giusti
    2. Consulta System_program/ORPHANS.md per issues architetturali
    3. Verifica System_program/HOOKS.md per interception points
    4. Usa template in System_program/PROMPTS.md
    5. Esegui System_program/tools/build-universal-mapping.mjs alla fine
       (auto-regenera: mod-index.json, SYSTEM_STATUS.md, ORPHANS.md, MODULES.md, HOOKS.md)
    ```

4.  **Safety Protections (Automatic)**:
    *   ✅ Blast radius control (max 15 files changed)
    *   ✅ Critical function protection (Ruby/JS)
    *   ✅ Contract validation (@contracts enforcement)
    *   ✅ Feature name validation with suggestions
    *   ✅ Scope-lock enforcement
    *   ✅ Pre-commit hook auto-regenerates module documentation

5.  **Post-Modification Commands** (Auto-Executed):
    
    **On every commit (automatic via pre-commit hook)**:
    *   `build-universal-mapping.mjs` regenerates:
        - `mod-index.json`
        - `SYSTEM_STATUS.md`
        - `ORPHANS.md`
        - `MODULES.md` (AI-ready documentation)
        - `HOOKS.md`
    
    **Manual verification (if needed)**:
    *   `node System_program/tools/ci-guards.mjs` → Check safety violations
    *   Check `System_program/SYSTEM_STATUS.md` → View automated health dashboard
    *   Consult `System_program/ORPHANS.md` → Review code quality issues

## 🔹 PRE-COMMIT GUARDS

**Feature Target**: `pre-commit | routing | contracts | lint`

**Descrizione**: Sistema di guard-rail automatico che si attiva prima di ogni commit Git. Garantisce che i moduli rispettino le regole dell'Enterprise-Grade Module Routing System.

**Scope**:
    *   **Include**: `.git/hooks/pre-commit`, `System_program/tools/enforce-file-tags.mjs`, `.rubocop.yml` (se presente)
    *   **Deny**: `vendor/`, `node_modules/`, `tmp/`

**Checks Eseguiti**:

1.  **Mapping & Linter**:
    *   `System_program/tools/build-universal-mapping.mjs`
    *   `System_program/tools/metadata-linter.mjs`
    *   `System_program/tools/contracts-checker.mjs`
    *   `System_program/tools/ci-guards.mjs --fail-on-cross-scope`

2.  **Static Analysis**:
    *   **ESLint** (per JS)
    *   **Rubocop** (per Ruby - se configurato)

3.  **File Annotations**:
    *   `System_program/tools/enforce-file-tags.mjs` → fallisce se i file Ruby/JS modificati non hanno tag `@feature` o `@domain` nelle prime 50 righe

**Definition of Done (DoD)**:
*   ✅ Ogni commit passa tutti i guard senza errori
*   ✅ Nessun file Ruby/JS privo di tag `@feature`/`@domain`
*   ✅ Import cross-scope bloccati

**Prompt Routing Example**:
```
Ruolo: revisore pre-commit  
File target: .git/hooks/pre-commit, System_program/tools/enforce-file-tags.mjs  
Obiettivo: aggiornare i guard aggiungendo un nuovo tool di check  
Vincoli: non modificare la logica dei guard esistenti, solo appendere  
DoD: commit fallisce se il nuovo tool ritorna codice di errore != 0
```

**Note**:
*   Per bypass urgente: `SKIP_GUARDS=1 git commit -m "hotfix"`
*   Aggiornare `.eslintrc.cjs` con le zones estratte dai file `scope/*.allow`
*   Aggiornare `README-Precommit.md` quando si introducono nuove regole

## 🎪 Example Surgical Requests

*   "Feature target: ai. Add WebP support to AI image generator"
*   "Feature target: canvas. Fix mobile rotation tool in customizer"
*   "Feature target: cart. Improve validation for custom products"
*   "Feature target: quality. Analyze and improve code quality in BulkPricingBackend.php"

## 🔍 QUALITY WORKFLOW

**Feature Target**: `quality`

**Descrizione**: Sistema per analizzare e migliorare la qualità del codice in modo chirurgico, basandosi su metriche oggettive anziché valutazioni soggettive.

### Quando Usare

Usa il Quality Workflow quando:
- Vuoi ridurre la complessità ciclomatica di un file
- Devi eliminare code smell (variabili inutilizzate, codice irraggiungibile, etc.)
- Vuoi migliorare best practices in un modulo specifico
- Il codice funziona ma è difficile da mantenere

### Workflow in 3 Fasi (Aggiornato)

#### FASE 0: Pre-Screening Intelligente (NUOVO - File Size Guard)

**Perché questa fase è critica**: File molto lunghi (>500 righe) richiedono un approccio focalizzato per evitare di superare il limite di contesto dell'AI. Il Pre-Screening identifica automaticamente questi file e permette un refactoring chirurgico profondo invece che superficiale.

1. **Esegui il File Size Guard**:
   ```bash
   # Per una feature specifica
   node System_program/tools/check-file-length.mjs --feature=canvas
   
   # Per tutto il plugin
   node System_program/tools/check-file-length.mjs --all
   
   # Con soglia personalizzata
   node System_program/tools/check-file-length.mjs --feature=ai --threshold=800
   ```

2. **L'AI analizza l'output JSON** che contiene:
   - **long_files**: Lista di file che superano la soglia (ordinati per numero di righe)
   - **recommendation**: Suggerimenti su quali file affrontare per primi
   - **workflow_suggestion**: Comando diretto per analyze-quality.mjs sul file più critico

3. **Decisione di Routing Chirurgico**:
   - Se **0 file lunghi**: Procedi con analisi multi-file standard
   - Se **1-3 file lunghi**: L'AI propone il file più critico e chiede conferma
   - Se **>3 file lunghi**: L'AI lavora sui top 3, uno alla volta, usando tutta la finestra di contesto

**Output Esempio**:
```json
{
  "status": "warning",
  "feature": "canvas",
  "long_files": [
    {
      "file": "magenta-product-customizer/public/css/magenta.css",
      "lines": 1980,
      "category": "stylesheet"
    },
    {
      "file": "magenta-product-customizer/includes/admin/class-magenta-admin-settings.php",
      "lines": 720,
      "category": "php"
    }
  ],
  "recommendation": "Focus on top 2 files for surgical refactoring",
  "workflow_suggestion": "node System_program/tools/analyze-quality.mjs magenta-product-customizer/public/css/magenta.css"
}
```

**Vantaggi del Pre-Screening**:
- ✅ **Laser Focus**: Concentra l'AI su 1 file alla volta invece di 10
- ✅ **Scope-Aware**: Usa i file `.allow` esistenti per filtering per feature
- ✅ **Zero Costi Sprecati**: Identificazione meccanica veloce invece di caricamenti multipli
- ✅ **Routing Intelligente**: Prioritizzazione automatica basata su line count

#### FASE 1: Analisi (Il "Cosa" migliorare)

1. **Esegui l'analisi di qualità**:
   ```bash
   node System_program/tools/analyze-quality.mjs <percorso/del/file>
   ```

2. **L'AI analizza l'output JSON** che contiene:
   - **Issues**: Lista di problemi trovati (complexity, code-smell, security, best-practice)
   - **Summary**: Statistiche aggregate (totale errori/warning, categorie, top issues)
   - **Details**: Riga, colonna, severità, messaggio per ogni problema

3. **L'AI prioritizza** gli interventi basandosi su:
   - Severità (error > warning)
   - Categoria (security > complexity > code-smell > best-practice)
   - Frequenza (problemi che si ripetono più volte)

#### FASE 2: Correzione Chirurgica (Il "Come" migliorare)

Per ogni problema identificato:

1. **Applicare fix chirurgico**:
   - Semplificare funzioni con alta complessità
   - Rimuovere parametri non utilizzati
   - Estrarre funzioni helper per ridurre annidamento
   - Applicare best practice (const vs var, eqeqeq, etc.)

2. **Validare le modifiche**:
   ```bash
   # Riesegui l'analisi per verificare miglioramenti
   node System_program/tools/analyze-quality.mjs <percorso/del/file>
   
   # Esegui i guard per assicurarti di non introdurre regressioni
   node System_program/tools/ci-guards.mjs
   
   # Se ci sono test per il modulo, eseguili
   npm test -- <test-specifico>
   ```

3. **Verifica finale**:
   - ✅ Issues risolti senza introdurre nuovi problemi
   - ✅ Guard passati
   - ✅ Test passati (se presenti)

### Request Template (Aggiornato con Pre-Screening)

```
🎯 RICHIESTA DI QUALITÀ PER MAGENTA PLUGIN

**Feature Target**: quality
**Target**: [feature-name] oppure [percorso/del/file.php o file.js se già noto]
**Obiettivo**: Analizzare e correggere i problemi di qualità e code smell

**Istruzioni per l'AI**:
0. [NUOVO] Se stai analizzando una feature (non un file specifico):
    a. Esegui `node System_program/tools/check-file-length.mjs --feature=[feature-name]`
    b. Identifica file lunghi (>500 righe) che richiedono refactoring focalizzato
    c. Proponi il file più critico all'utente per conferma prima di procedere
    d. Se l'utente conferma, procedi con quel singolo file usando TUTTA la finestra di contesto

1. Esegui `node System_program/tools/analyze-quality.mjs [File Target]`
2. Analizza l'output JSON dei problemi
3. Per ogni problema (partendo da quelli più severi):
    a. Applica una correzione chirurgica
    b. Usa la tua intelligenza per problemi di "alta complessità"
4. Dopo le modifiche:
    a. Riesegui analyze-quality.mjs per verificare miglioramenti
    b. Esegui ci-guards.mjs per assicurarti di non aver introdotto regressioni
    c. Se ci sono test, eseguili
5. Report finale: mostra before/after dei problemi risolti
```

### Metriche Supportate

### Metriche Supportate

**JavaScript** (via ESLint):
- `complexity` - Complessità ciclomatica
- `max-depth` - Livelli di annidamento
- `max-lines-per-function` - Lunghezza funzioni
- `max-params` - Numero parametri
- `no-unused-vars` - Variabili inutilizzate
- `no-unreachable` - Codice irraggiungibile
- Security rules (no-eval, etc.)

**Ruby** (via Rubocop/Manual Review):
- Class Length
- Method Length
- Perceived Complexity
- Cyclomatic Complexity
- Security checks

### Example Output

```json
{
  "file": "includes/class-wc-ai-bulk-pricing.php",
  "summary": {
    "total": 12,
    "errors": 3,
    "warnings": 9,
    "byCategory": {
      "complexity": 5,
      "code-smell": 4,
      "best-practice": 3
    },
    "topIssues": [
      {
        "issue": "complexity: Function has complexity of 15 (max 10)",
        "count": 2
      }
    ]
  },
  "issues": [...]
}
```

### Regole Operative

1. **Non modificare la logica funzionale** - solo refactoring per qualità
2. **Un problema alla volta** - fix chirurgici, non riscritture massive
3. **Sempre testare** dopo ogni modifica
4. **Documentare i miglioramenti** in commit message

## Recent Changes

*   **✅ BULK PRICING UI UNIFIED** (Oct 2025): Refactored bulk pricing mode UI to use unified footer-price-summary instead of internal bulk-summary component. Enhanced code maintainability by centralizing price display logic.
*   **✅ PROJECT CLEANUP** (Oct 22, 2025): Consolidated all system documentation files into `System_program/` as single source of truth. Removed duplicate files from root and plugin directories. Updated build scripts to scan plugin and write to `System_program/`. Created `AGENT_WORKFLOW.md` for complete operational guidelines.
*   **✅ AGENT WORKFLOW ENHANCED** (Jan 26, 2026): Added Project Structure, Quick Commands, Environment Setup, Common Pitfalls, and Debug Workflow sections for improved AI targeting.
*   **✅ ORPHANS & DUPLICATES RESOLVED** (Jan 26, 2026): Tagged 41+ orphaned files with `@feature` tags. Consolidated duplicate providers (Gemini/OpenAI) via `@deprecated` tags and renamed the `CanvasEngine` facade to prevent module indexing name collisions.

---

## 📁 Project Structure

```
Gestionale/
├── app.rb                       # ⚡ Main Application Entry Point
├── config.ru                    # Rack Configuration
├── Gemfile                      # Ruby Dependencies
├── models/                      # 🗄️ ActiveRecord Models (DB Layer)
├── routes/                      # 🛣️ Sinatra Routes (Controllers)
├── services/                    # ⚙️ Business Logic Services
├── lib/                         # 🛠️ Utility Classes/Modules
├── public/                      # 🌐 Static Assets (JS, CSS)
│   ├── js/                      # Frontend Logic
│   └── css/                     # Styles
├── views/                       # 🎨 ERB Templates
│   ├── layout.erb
│   └── ...
├── db/                          # Database Migrations & Config
├── System_program/              # 📊 Documentation & Tools
│   ├── tools/                   # CLI tools (mjs)
│   └── *.md                     # Auto-generated docs
└── README.md
```

---

## 🔧 Quick Commands Reference

| Obiettivo | Comando |
|-----------|---------|
| **Rigenera TUTTA la documentazione** | `node System_program/tools/build-universal-mapping.mjs` |
| Analizza qualità file | `node System_program/tools/analyze-quality.mjs <file>` |
| Check guard CI | `node System_program/tools/ci-guards.mjs` |
| Verifica contratti | `node System_program/tools/contracts-checker.mjs` |
| Genera status sistema | `node System_program/tools/system-status-generator.mjs` |

---

## ⚙️ Environment Setup

**Prerequisiti Minimi**:
| Requisito | Versione | Note |
|-----------|----------|------|
| Node.js | v18+ | Per eseguire i tool .mjs |
| Ruby | 3.2+ | Core Language |
| PostgreSQL | 14+ | Database |

**Setup Iniziale**:
```bash
# 1. Install dependencies
bundle install

# 2. Verify System Tools
node System_program/tools/build-universal-mapping.mjs

# 3. Check System Status
cat System_program/SYSTEM_STATUS.md
```

---
 
 ## 📦 Portable System Usage (Enterprise Ready)
 
 The `System_program` directory is designed to be **portable**. You can drop it into any project to immediately gain AI-ready documentation and quality guards.
 
 **How to Install**:
 
 1.  **Copy**: Copy the `System_program/` folder to the root.
 2.  **Run Build**: `node System_program/tools/build-universal-mapping.mjs`
 3.  **Setup Pre-Commit**: Copy template to `.git/hooks/pre-commit`.

---
 
 ## ⚠️ Common Pitfalls

### 🔴 File MAI Modificare Direttamente
- `vendor/` - Managed by Bundler
- `public/js/lib/` - External libraries

### 🟡 Problemi Architetturali Noti
- **Untagged Ruby Files**: Many legacy files might miss `# @feature` tags.
- **Fat Models**: Check `models/` for excessive logic that belongs in `services/`.

---

## 🔍 Debug Workflow

### Flow di Investigazione

```
ERRORE → Identifica Layer → Trova Feature → Localizza File → Fix
```

| Tipo Errore | Layer | Directory Principale |
|-------------|-------|---------------------|
| Ruby Syntax/Runtime | Backend | `models/`, `routes/`, `services/` |
| Route Not Found (404) | Routing | `routes/` |
| DB Constraint | Database | `models/`, `db/migrations/` |
| JS Console | Frontend | `public/js/` |

### Debug Steps

1.  **Backend Errors**: Check terminal output (Rack logs) or logs file.
2.  **Frontend Errors**: Browser Console.

