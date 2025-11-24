# Switch Webhook Setup Guide

## Panoramica
La connessione con Enfocus Switch utilizza un sistema **pull/push**:
1. **Pull**: Switch scarica i file dal nostro server quando è pronto
2. **Push**: Noi inviamo i job a Switch (POST)
3. **Callback**: Switch ci invia i risultati via POST quando finisce

## Endpoints Disponibili

### 1. Invio Job a Switch (noi → Switch)
Quello che noi facciamo quando clicchi "Invia a Switch" nel nostro UI

```
POST /api/orders/:id/send
```

Payload che inviamo a Switch:
```json
{
  "external_order_code": "ORD-12345",
  "store_code": "MAGENTA",
  "store_name": "Magenta",
  "items": [
    {
      "sku": "TPH500",
      "quantity": 1,
      "assets": [
        {
          "type": "print",
          "url": "http://...",
          "local_path": "/home/runner/.../storage/MAGENTA/ORD-12345/TPH500/design.png"
        }
      ]
    }
  ],
  "metadata": {
    "order_id": 123,
    "created_at": "2025-01-15T10:30:00Z"
  }
}
```

### 2. Download Asset (Switch → noi)
Switch richiama questo endpoint per scaricare i file da processare

```
GET /api/assets/:id/download
```

Risposta: Binary file (PNG, PDF, JPG)

Esempio: `GET /api/assets/45/download` → scarica il file dell'asset con ID 45

### 3. Callback Webhook (Switch → noi)
**QUESTO È QUELLO CHE SWITCH DEVE SAPERE** - è dove Switch ti invia i risultati

```
POST /api/switch/callback
```

**Payload che Switch deve inviare:**
```json
{
  "job_id": "PREPRINT-ORD123-IT456-1705314600000",
  "status": "completed",
  "result_preview_url": "https://switch.enfocus.com/preview/xyz123",
  "job_operation_id": "switch_op_5678",
  "result_files": ["file1.pdf", "file2.pdf"],
  "error_message": null
}
```

**Oppure in caso di errore:**
```json
{
  "job_id": "PRINT-ORD123-IT456-1705314600000",
  "status": "failed",
  "error_message": "Errore nel processamento del file"
}
```

## Come Configurare in Switch

### Fase 1: Identificare il Webhook Listener in Switch
In Switch, cerca nella sezione **"Settings"** o **"Webhooks"** oppure **"Actions"** il punto dove puoi configurare un **callback URL** o **webhook endpoint**.

### Fase 2: Registrare il Nostro Endpoint

**Per ambiente LOCALE (mentre sviluppi):**
```
POST http://localhost:5000/api/switch/callback
```

**Per ambiente UBUNTU 24.04 (produzione):**
```
POST https://tuoserverubuntu.com/api/switch/callback
```
oppure se hai un dominio:
```
POST https://print-orchestrator.tuodominio.it/api/switch/callback
```

### Fase 3: Configurare il Payload
In Switch, assicurati di inviare **almeno questi dati**:
- `job_id` (string) - ID univoco del job (es: PREPRINT-ORD123-IT456-timestamp)
- `status` (string) - "completed", "failed", "processing"
- `result_preview_url` (string, optional) - URL preview del risultato
- `job_operation_id` (string, optional) - ID operazione Switch
- `result_files` (array, optional) - Lista file risultato
- `error_message` (string, optional) - Messaggio errore se fallito

## Formato Job ID (Importante!)
Switch deve inviare il `job_id` in questo formato:

```
{PHASE}-ORD{ORDER_ID}-IT{ITEM_ID}-{TIMESTAMP}
```

Esempi:
- `PREPRINT-ORD123-IT456-1705314600000` → Fase pre-press, ordine 123, item 456
- `PRINT-ORD123-IT456-1705314600000` → Fase print, ordine 123, item 456
- `LABEL-ORD123-IT456-1705314600000` → Fase label, ordine 123, item 456

Questo formato permette al nostro sistema di sapere automaticamente:
- Quale ordine update
- Quale item update
- Quale fase (preprint/print/label)

## Flow Completo

```
┌─────────────────────────────────────┐
│ 1. Tu clicchi "Invia a Switch" nel UI
└────────────┬────────────────────────┘
             │
             ▼
┌─────────────────────────────────────┐
│ 2. Noi facciamo POST a Switch       │
│    (con payload job_data)           │
└────────────┬────────────────────────┘
             │
             ▼
┌─────────────────────────────────────┐
│ 3. Switch scarica i file            │
│    GET /api/assets/:id/download     │
└────────────┬────────────────────────┘
             │
             ▼
┌─────────────────────────────────────┐
│ 4. Switch processa i file           │
│    (pre-press, print, label...)     │
└────────────┬────────────────────────┘
             │
             ▼
┌─────────────────────────────────────┐
│ 5. Switch invia risultati via POST  │
│    /api/switch/callback             │
│    (con job_id, status, files...)   │
└────────────┬────────────────────────┘
             │
             ▼
┌─────────────────────────────────────┐
│ 6. Noi aggiorniamo lo stato nel DB  │
│    (completed/failed/processing)    │
│    Il UI mostra il risultato        │
└─────────────────────────────────────┘
```

## Variabili d'Ambiente Necessarie

Nel tuo `.env`:

```bash
# Se collegato a Switch reale
SWITCH_WEBHOOK_URL=http://localhost:9999/webhook
SWITCH_API_KEY=your_api_key_if_needed

# Per simulazione (durante sviluppo/test)
SWITCH_SIMULATION=false
```

## Test Locale con cURL

Per testare il callback webhook localmente, puoi fare:

```bash
curl -X POST http://localhost:5000/api/switch/callback \
  -H "Content-Type: application/json" \
  -d '{
    "job_id": "PREPRINT-ORD1-IT1-1705314600000",
    "status": "completed",
    "result_preview_url": "https://example.com/preview.png",
    "job_operation_id": "switch_op_123",
    "result_files": ["output1.pdf", "output2.pdf"]
  }'
```

Dovresti ricevere una risposta JSON:
```json
{
  "success": true,
  "order_id": 1,
  "item_id": 1,
  "phase": "preprint",
  "new_status": "completed",
  "timestamp": "2025-01-15T10:35:00Z"
}
```

## Checklist Configurazione

- [ ] Accesso al pannello Switch configurato
- [ ] Sezione Webhooks/Callbacks localizzata in Switch
- [ ] URL callback registrato: `http://localhost:5000/api/switch/callback` (locale) o `/api/switch/callback` (produzione)
- [ ] Payload Switch configurato con almeno: job_id, status, result_files
- [ ] Variabili d'ambiente `.env` settate
- [ ] Test callback con cURL completato con successo
- [ ] Primo job reale inviato e callback ricevuto

## Note

1. **Sicurezza**: Per produzione, aggiungi autenticazione al callback (es: header API key)
2. **Ritentative**: Configura Switch per rifare il callback in caso di errore (max 3 volte con backoff)
3. **Timeout**: Switch dovrebbe aspettare max 30 secondi per la risposta del callback
4. **Logging**: Verifica i log della nostra app per troubleshooting dei callback

---

**Quando hai localizzato la sezione webhook in Switch, fammi sapere e prepariamo il resto!**
