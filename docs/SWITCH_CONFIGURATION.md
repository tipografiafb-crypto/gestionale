# Configurazione Switch - Connessione Webhook

## URL Webhook di Switch

**URL Base Switch:**
```
http://192.168.1.162/webhook/
```

**Il nome del webhook** (es: `prestampa_adesivi`) **viene aggiunto da Switch automaticamente**.

## Configurazione Attuale

Abbiamo settato:
```
SWITCH_WEBHOOK_URL=http://192.168.1.162/webhook/
```

## Come Funziona

### 1. Registrare il Webhook in Switch
Nel tuo gestionale/Switch, nella sezione webhook (come visto nella tua screenshot):
- **Nome**: `prestampa_adesivi` (o il nome che preferisci)
- **Descrizione**: Prepress Adhesive Labels
- **Tipo di protocollo**: HTTP
- **Metodo di richiesta**: POST
- **Percorso**: `prestampa_adesivi`
- **Nome dataset payload**: Payload
- **Modello dataset payload**: JSON

### 2. Quando Inviamo un Ordine
Nel nostro sistema, quando clicchi **"Invia a Switch"**, mandiamo il payload a:
```
POST http://192.168.1.162/webhook/prestampa_adesivi
```

Con il payload:
```json
{
  "id_riga": 1,
  "codice_ordine": "UK7267",
  "product": "TPH500 - Plettro TPH",
  "operation_id": 1,
  "url": "http://localhost:5000/api/assets/45/download",
  "filename": "UK7267_1.png",
  "quantita": 9,
  "materiale": "Celluloide bianca",
  "campi_custom": {},
  "opzioni_stampa": {},
  "campi_webhook": {}
}
```

### 3. Switch Legge i Dati
Switch riceve il payload e legge il campo **"url"** per scaricare il file:
```
GET http://localhost:5000/api/assets/45/download
```

Il nostro endpoint restituisce il file da processare.

### 4. Switch Processa il File
- Pre-press
- Print
- Eventualmente Label
- Archiviazione

## Per Ambiente di Produzione (Ubuntu)

Quando sarai su Ubuntu 24.04, aggiorna:
```
SERVER_BASE_URL=http://IP_UBUNTU_O_DOMINIO:5000
SWITCH_WEBHOOK_URL=http://192.168.1.162/webhook/  (rimane uguale, è il tuo Switch locale)
```

## Test Locale

Puoi testare il payload con cURL:

```bash
curl -X POST http://192.168.1.162/webhook/prestampa_adesivi \
  -H "Content-Type: application/json" \
  -d '{
    "id_riga": 1,
    "codice_ordine": "TEST001",
    "product": "TPH500 - Plettro",
    "operation_id": 1,
    "url": "http://localhost:5000/api/assets/1/download",
    "filename": "test.png",
    "quantita": 1,
    "materiale": "Test"
  }'
```

## Prossimo Passo: Il Callback da Switch

Dopo che Switch processa il file, dovrà inviarti i risultati. Questo lo configureremo nella prossima fase una volta che capiremo come Switch restituisce i risultati.

---

**Status:** ✅ Pronto a inviare ordini a Switch
