# Print Order Orchestrator - Switch Integration Workflow

## System Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│ FTP POLLING (Gestionale)                                    │
│ Recupera file JSON da FTP in polling                        │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────┐
│ ORDER IMPORT (Nostro Sistema)                               │
│ • Popola righe di ordine dal JSON                           │
│ • Scarica i file (immagini, assets)                         │
│ • Salva tutto localmente                                    │
└────────────────────┬────────────────────────────────────────┘
                     │
          ┌──────────┼──────────┐
          │          │          │
          ▼          ▼          ▼
      PRE-PRESS  STAMPA     ETICHETTA
```

---

## Flusso Dettagliato per Fase

### FASE 1: PRE-PRESS (Prepress Adhesive Labels)
**Caratteristica: Riceve file PDF in risposta ✅**

#### Endpoint di Invio
```
POST http://192.168.1.162/webhook/prestampa_adesivi
```

#### Payload Inviato a Switch
```json
{
  "id_riga": 1,
  "codice_ordine": "UK7267",
  "product": "TPH500 - Plettro TPH",
  "operation_id": 1,
  "job_operation_id": null,
  "url": "http://localhost:5000/api/assets/45/download",
  "widegest_url": "http://localhost:5000/api/v1/reports_create",
  "filename": "UK7267_1.png",
  "quantita": 9,
  "materiale": "Celluloide bianca",
  "campi_custom": {},
  "opzioni_stampa": {},
  "campi_webhook": {}
}
```

#### Flusso di Elaborazione in Switch
1. Switch riceve il payload
2. Switch legge il file da: `GET /api/assets/ID/download`
3. Switch processa il file (pre-press operations)
4. **Switch invia il PDF indietro** a `widegest_url`

#### Callback da Switch
```
POST http://localhost:5000/api/v1/reports_create
Content-Type: multipart/form-data

codice_ordine: "UK7267"
id_riga: 1
job_operation_id: 38097
file: <binary PDF data>
```

#### Risposta del Nostro Sistema
1. Riceve il callback in `/api/v1/reports_create`
2. Estrae codice ordine e id riga
3. Salva il PDF localmente: `storage/MAGENTA/UK7267/TPH500/print_output_*.pdf`
4. Crea un Asset con type "print_output"
5. Aggiorna item.print_status = "completed"
6. Ritorna success a Switch

#### Visualizzazione nel UI
- L'operatore vede il PDF in anteprima nella pagina dettaglio ordine
- Asset type "print_output" è disponibile per il download

---

### FASE 2: STAMPA (Print)
**Caratteristica: Nessun callback ❌**

#### Endpoint di Invio
```
POST http://192.168.1.162/webhook/  (stesso server di Switch)
```

#### Payload Inviato a Switch
```json
{
  "id_riga": 1,
  "codice_ordine": "UK7267",
  "product": "TPH500 - Plettro TPH",
  "operation_id": 2,
  "job_operation_id": null,
  "url": "http://localhost:5000/api/assets/45/download",
  "widegest_url": "http://localhost:5000/api/v1/reports_create",
  "filename": "UK7267_1.png",
  "quantita": 9,
  "materiale": "Celluloide bianca",
  "campi_custom": {},
  "opzioni_stampa": {},
  "campi_webhook": {}
}
```

#### Flusso di Elaborazione in Switch
1. Switch riceve il payload
2. Switch legge il file da: `GET /api/assets/ID/download`
3. Switch processa il file (print operations)
4. **Switch NON invia nulla indietro**
5. Switch completa il flusso internamente

#### Risposta del Nostro Sistema
- **Nessun callback ricevuto**
- Lo stato rimane come è (il nostro sistema non sa quando è finito)
- Opzione futura: implementare polling di status o webhook separato

#### Note
- Il file `widegest_url` è comunque incluso nel payload
- Switch può usarlo se configurato, ma nel flusso stampa non lo fa
- Questa è una limitazione del workflow di Switch, non del nostro sistema

---

### FASE 3: ETICHETTA (Label)
**Caratteristica: Nessun callback ❌**

#### Endpoint di Invio
```
POST http://192.168.1.162/webhook/  (stesso server di Switch)
```

#### Payload Inviato a Switch
```json
{
  "id_riga": 1,
  "codice_ordine": "UK7267",
  "product": "TPH500 - Plettro TPH",
  "operation_id": 3,
  "job_operation_id": null,
  "url": "http://localhost:5000/api/assets/45/download",
  "widegest_url": "http://localhost:5000/api/v1/reports_create",
  "filename": "UK7267_1.png",
  "quantita": 9,
  "materiale": "Celluloide bianca",
  "campi_custom": {},
  "opzioni_stampa": {},
  "campi_webhook": {}
}
```

#### Flusso di Elaborazione in Switch
1. Switch riceve il payload
2. Switch legge il file da: `GET /api/assets/ID/download`
3. Switch processa il file (label operations)
4. **Switch NON invia nulla indietro**
5. Switch completa il flusso internamente

#### Risposta del Nostro Sistema
- **Nessun callback ricevuto**
- Lo stato rimane come è
- Opzione futura: implementare polling di status o webhook separato

---

## Endpoints del Nostro Sistema

### Download Asset (usato da Switch)
```
GET /api/assets/:id/download
```
- Switch richiama questo per scaricare i file
- Usato in tutti e tre i flussi (prepress, stampa, etichetta)
- Ritorna il file binary

### Callback Report (usato da Switch per prepress)
```
POST /api/v1/reports_create
```
- Riceve risultati da Switch (solo in prepress)
- Accetta sia form-data che JSON
- Salva il PDF ricevuto
- Crea Asset record con type "print_output"
- Ritorna JSON response

### Variabili d'Ambiente Necessarie
```bash
SWITCH_WEBHOOK_URL=http://192.168.1.162/webhook/
SERVER_BASE_URL=http://localhost:5000  (o dominio/IP quando in produzione)
```

---

## Tabella Comparativa dei Flussi

| Aspetto | Pre-Press | Stampa | Etichetta |
|---------|-----------|--------|-----------|
| **Endpoint** | `/webhook/prestampa_adesivi` | `/webhook/` | `/webhook/` |
| **Metodo** | POST | POST | POST |
| **File Inviato** | JSON payload | JSON payload | JSON payload |
| **Switch Scarica File** | ✅ GET `/api/assets/:id/download` | ✅ GET `/api/assets/:id/download` | ✅ GET `/api/assets/:id/download` |
| **Switch Processa** | ✅ Pre-press operations | ✅ Print operations | ✅ Label operations |
| **Switch Ritorna Callback** | ✅ POST `/api/v1/reports_create` con PDF | ❌ No callback | ❌ No callback |
| **Noi Riceviamo** | ✅ PDF file | ❌ Nothing | ❌ Nothing |
| **Asset Salvato** | ✅ `print_output` type | ❌ No | ❌ No |
| **Visibile nel UI** | ✅ Sì (anteprima PDF) | ❌ No | ❌ No |
| **Status Aggiornato** | ✅ `print_status: completed` | ✅ (ma dipende da polling esterno) | ✅ (ma dipende da polling esterno) |

---

## Flusso Completo - Scenario Reale

### Scenario: Ordine UK7267 con 3 Item

```
1. POLLING FTP
   └─ Legge file JSON da FTP
   └─ Crea ordine UK7267
   └─ Crea 3 order_items
   └─ Scarica 3 asset files

2. OPERATORE CLICCA "INVIA A SWITCH"
   └─ Pre-Press Item 1
      └─ POST /webhook/prestampa_adesivi (item 1)
      └─ Switch scarica asset file
      └─ Switch processa
      └─ Switch POST /api/v1/reports_create (PDF)
      └─ Noi salviamo PDF, item.print_status = completed
      
   └─ Stampa Item 1
      └─ POST /webhook/ (item 1)
      └─ Switch scarica asset file
      └─ Switch processa
      └─ ❌ Nessun callback
      └─ Item rimane in stato precedente
      
   └─ Etichetta Item 1
      └─ POST /webhook/ (item 1)
      └─ Switch scarica asset file
      └─ Switch processa
      └─ ❌ Nessun callback
      └─ Item rimane in stato precedente

3. VISUALIZZAZIONE
   └─ Nel UI ordine UK7267, vediamo:
      └─ Item 1: PDF preview (da prepress)
      └─ Item 2: Asset upload originale
      └─ Item 3: Asset upload originale
```

---

## Considerazioni Importanti

### Pre-Press è "Stateful"
- Riceve feedback da Switch
- Sappiamo quando è completato
- Abbiamo il risultato (PDF)
- Possiamo mostrarlo nell'UI

### Stampa e Etichetta sono "Fire-and-Forget"
- Inviamo i dati a Switch
- Non sappiamo quando finiscono
- Non riceviamo feedback
- **Soluzione futura**: 
  - Implementare polling per controllare lo stato
  - Implementare webhook separato da Switch per fine lavoro
  - Coordinare con Switch admin per capire come ricevere status

---

## Testing

### Test Pre-Press (con PDF)
```bash
curl -X POST http://localhost:5000/api/v1/reports_create \
  -F "codice_ordine=UK7267" \
  -F "id_riga=1" \
  -F "job_operation_id=38097" \
  -F "file=@output.pdf"
```

### Test Callback Senza File
```bash
curl -X POST http://localhost:5000/api/v1/reports_create \
  -H "Content-Type: application/json" \
  -d '{
    "codice_ordine": "UK7267",
    "id_riga": 1,
    "job_operation_id": 38097
  }'
```

---

## Status Attuale

✅ **Implementato:**
- Polling FTP e import ordini
- Download assets
- Invio payload a Switch per tutti i flussi (prepress, stampa, etichetta)
- Ricezione callback PDF da prepress
- Salvataggio e visualizzazione PDF

⏳ **Da Implementare (Futuro):**
- Status polling per stampa ed etichetta
- Webhook separato da Switch per notifiche completamento
- Archivio storico dei PDF generati
- Report e analytics

---

**Ultimo aggiornamento:** November 24, 2025
**Status:** Production Ready
