# 🖨️ Print Order Orchestrator - Installazione Locale su Mac

Guida step-by-step per installare e eseguire il Print Order Orchestrator in locale sul tuo Mac.

## 📋 Prerequisiti

Assicurati di avere:
- **macOS** (Monterey o versioni successive)
- **Homebrew** ([installa qui](https://brew.sh/))
- **Git**
- **Ruby 3.2+**
- **PostgreSQL 14+**
- **Node.js 18+** (opzionale, per asset management)

---

## 🚀 Step-by-Step Installation

### Step 1: Installa i Prerequisiti Principali

#### 1.1 Installa Ruby 3.2 con Homebrew

```bash
# Installa Ruby tramite Homebrew
brew install ruby@3.2

# Aggiungi Ruby al PATH
echo 'export PATH="/usr/local/opt/ruby@3.2/bin:$PATH"' >> ~/.zshrc
source ~/.zshrc

# Verifica l'installazione
ruby --version
# Dovrebbe mostrare: ruby 3.2.x (2023-XX-XX) [x86_64-darwin23]
```

#### 1.2 Installa PostgreSQL

```bash
# Installa PostgreSQL
brew install postgresql@15

# Avvia il servizio PostgreSQL
brew services start postgresql@15

# Verifica che PostgreSQL funziona
psql --version
```

#### 1.3 Installa Bundler (gestore dipendenze Ruby)

```bash
gem install bundler
bundle --version
```

---

### Step 2: Clona il Repository

```bash
# Clona il repository (sostituisci con il tuo URL)
git clone <tuo-repository-url> print-orchestrator
cd print-orchestrator

# Verifica di essere nel branch corretto
git branch
```

---

### Step 3: Installa le Dipendenze Ruby

```bash
# Installa tutte le gemme specificate in Gemfile
bundle install

# Se hai problemi, forza l'installazione
bundle install --force
```

Se ricevi un errore riguardante `pg` (PostgreSQL gem):

```bash
# Installa il file di header PostgreSQL
brew install postgresql@15 --with-dev

# Retry bundle install
bundle install
```

---

### Step 4: Configura il Database

#### 4.1 Crea l'utente PostgreSQL per l'app

```bash
# Accedi a PostgreSQL
psql postgres

# Dentro la console PostgreSQL, esegui:
CREATE USER orchestrator_user WITH PASSWORD 'your_secure_password';
ALTER ROLE orchestrator_user CREATEDB;
\q
```

#### 4.2 Aggiorna la configurazione database

Modifica il file `config/database.yml`:

```yaml
development:
  adapter: postgresql
  encoding: utf8
  database: print_orchestrator_dev
  username: orchestrator_user
  password: your_secure_password
  host: localhost
  port: 5432

test:
  adapter: postgresql
  encoding: utf8
  database: print_orchestrator_test
  username: orchestrator_user
  password: your_secure_password
  host: localhost
  port: 5432

production:
  adapter: postgresql
  encoding: utf8
  database: print_orchestrator_production
  username: orchestrator_user
  password: your_secure_password
  host: localhost
  port: 5432
```

#### 4.3 Crea il database e esegui le migrazioni

```bash
# Crea i database
bundle exec rake db:create

# Esegui le migrazioni
bundle exec rake db:migrate

# Verifica lo stato
bundle exec rake db:migrate:status
```

---

### Step 5: Configura le Variabili d'Ambiente

#### 5.1 Crea il file `.env`

Copia il file di esempio e modifica i valori:

```bash
# Copia il template (se esiste)
cp .env.example .env

# Se non esiste, crea manualmente
touch .env
```

#### 5.2 Aggiungi le variabili necessarie

Modifica `.env` e aggiungi:

```env
# Database
DATABASE_URL=postgresql://orchestrator_user:your_secure_password@localhost:5432/print_orchestrator_dev

# Rails/Sinatra
RACK_ENV=development
PORT=5000

# Switch Integration
SWITCH_WEBHOOK_URL=http://localhost:9999/webhook
SWITCH_API_KEY=your_switch_api_key_here
SWITCH_SIMULATION=false

# FTP Poller (opzionale)
FTP_HOST=c72965.sgvps.net
FTP_USER=your_ftp_user
FTP_PASSWORD=your_ftp_password
FTP_PATH=/test/

# Asset Base URL
ASSET_BASE_URL=http://localhost:5000
```

---

### Step 6: Avvia il Server

#### 6.1 Avvia Puma (web server)

```bash
# Da dentro la cartella del progetto
bundle exec puma -b tcp://0.0.0.0:5000 -t 5 config.ru

# Output atteso:
# Puma starting in single mode...
# * Listening on http://0.0.0.0:5000
```

#### 6.2 Accedi all'app

Apri il browser e vai a:

```
http://localhost:5000
```

Vedrai la dashboard dei Print Order Orchestrator! 🎉

---

### Step 7: Crea i Dati di Test Iniziali

Dopo il primo accesso, vai in **⚙️ Impostazioni** e crea:

#### 7.1 Webhook Switch

1. Vai a `/webhooks`
2. Clicca "➕ Nuovo Webhook"
3. Crea almeno 2 webhook:
   - Nome: "Preprint Flow"
   - Hook Path: `/preprint`
   - Nome: "Print Flow"
   - Hook Path: `/print`

#### 7.2 Negozi

1. Vai a **⚙️ Impostazioni → 🏪 Negozi**
2. Clicca "➕ Nuovo Negozio"
3. Aggiungi i tuoi negozi (es: `TPH_EU`, `TPH_ES`)

#### 7.3 Flussi di Stampa

1. Vai a **⚙️ Impostazioni → 🔄 Flussi di Stampa**
2. Clicca "➕ Nuovo Flusso"
3. Configura:
   - Nome: "Standard Workflow"
   - Webhook Pre-Stampa: seleziona quello creato
   - Webhook Stampa: seleziona quello creato
   - Salva
4. Dopo il salvataggio, vedrai una sezione "🔧 Macchine da Stampa" - collegiale

#### 7.4 Macchine da Stampa

1. Vai a **⚙️ Impostazioni → 🔧 Macchine da Stampa**
2. Clicca "➕ Nuova Macchina"
3. Crea le tue macchine (es: "Stampante UV 01", "Canon Print System")

#### 7.5 Categorie e Prodotti

1. **Categorie**: Vai a **📂 Categorie** e crea categorie prodotto
2. **Prodotti**: Vai a **📦 Prodotti** e crea i tuoi prodotti con SKU

---

## 🔌 Configurazione Switch (Locale)

Se stai testando con Switch in locale:

### Setup di Switch

1. **Assicurati che Switch sia in ascolto** sulla porta 9999 (o modifica `SWITCH_WEBHOOK_URL` in `.env`)

2. **Configura il callback in Switch** per postare a:
   ```
   http://localhost:5000/api/switch/callback
   ```
   Metodo: **POST**
   Content-Type: **application/json**

3. **Test rapido** - Fai una richiesta di test:

```bash
curl -X POST http://localhost:5000/api/switch/callback \
  -H "Content-Type: application/json" \
  -d '{
    "job_id": "PREPRINT-ORD1-IT1-1234567890",
    "status": "completed",
    "result_preview_url": "http://example.com/preview.jpg"
  }'
```

Se la risposta è `{"success":true,...}` tutto funziona! ✅

---

## 📥 Importare Ordini

### Metodo 1: Tramite API

```bash
curl -X POST http://localhost:5000/api/orders/import \
  -H "Content-Type: application/json" \
  -d '@order_example.json'
```

### Metodo 2: Tramite FTP (se configurato)

L'app ascolterà automaticamente gli ordini dal server FTP configurato in `.env`

### Metodo 3: Interfaccia Web

1. Vai a **📋 Ordini**
2. Clicca "➕ Nuovo Ordine" (se disponibile)
3. Compila il form

---

## 🛠️ Troubleshooting

### Errore: "Could not connect to database"

```bash
# Verifica che PostgreSQL sia in esecuzione
brew services list | grep postgresql

# Se non è in esecuzione, avvialo
brew services start postgresql@15

# Ricrea i database
bundle exec rake db:drop db:create db:migrate
```

### Errore: "Bundler version conflicts"

```bash
# Aggiorna bundler
gem install bundler

# Ricrea il lock file
rm Gemfile.lock
bundle install
```

### Errore: "Port 5000 already in use"

```bash
# Uccidi il processo che usa la porta
lsof -i :5000 | grep LISTEN | awk '{print $2}' | xargs kill -9

# O usa una porta diversa
PORT=3000 bundle exec puma config.ru
```

### La pagina non carica / errore 500

```bash
# Controlla i log di Puma nella console
# Verifica il database
bundle exec rake db:migrate:status

# Ricrea il database se necessario
bundle exec rake db:drop db:create db:migrate
```

---

## 📊 Comandi Utili

```bash
# Avvia il server in background
bundle exec puma -b tcp://0.0.0.0:5000 -d

# Visualizza i log
tail -f log/puma.log

# Accedi alla console Ruby con accesso al database
bundle exec irb

# Resetta il database completamente
bundle exec rake db:drop db:create db:migrate

# Verifica lo stato del database
bundle exec rake db:migrate:status

# Creare una nuova migrazione
bundle exec rake db:create_migration NAME=add_field_to_orders

# Esegui la migrazione
bundle exec rake db:migrate

# Annulla l'ultima migrazione
bundle exec rake db:rollback
```

---

## 🧪 Test della Connessione

Una volta che tutto è avviato, verifica:

```bash
# Verifica salute API
curl http://localhost:5000/health

# Output atteso:
# {"status":"ok","timestamp":"2025-11-23T...","database":"connected"}
```

---

## 🎯 Prossimi Step

1. **Configura i tuoi ordini** nei negozi
2. **Collega Switch** al tuo ambiente locale
3. **Testa il flusso** completo: ordine → download assets → send to Switch → callback
4. **Monitora i log** durante il testing

---

## 📞 Supporto e Note

- Se trovi problemi, controlla i log di Puma nella console
- Verifica che tutte le variabili d'ambiente siano impostate in `.env`
- Assicurati che PostgreSQL sia sempre in esecuzione
- Per Switch, assicurati che l'URL del callback sia raggiungibile dalla tua rete

---

## 🎉 Sei Pronto!

Se hai completato tutti gli step, il tuo Print Order Orchestrator è ora in esecuzione localmente su `http://localhost:5000` 🚀

Buon lavoro con lo sviluppo locale!
