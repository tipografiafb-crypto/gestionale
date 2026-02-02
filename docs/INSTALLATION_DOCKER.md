# 🐳 Print Order Orchestrator - Installazione con Docker

Guida rapida per installare e eseguire il Print Order Orchestrator su **Mac, Windows o Linux** usando Docker.

**Docker rende tutto molto più semplice** - non devi installare Ruby, PostgreSQL, etc. Docker fa tutto per te! 🚀

---

## 📋 Prerequisiti

- **Docker Desktop** installato
  - Mac: https://www.docker.com/products/docker-desktop
  - Windows: https://www.docker.com/products/docker-desktop
  - Linux: https://docs.docker.com/engine/install/

Verifica che funziona:

```bash
docker --version
docker run hello-world
```

---

## 🚀 Installazione Veloce (3 Step)

### Step 1: Clona il Repository

```bash
git clone https://github.com/tipografiafb-crypto/gestionale.git print-orchestrator
cd print-orchestrator
```

### Step 2: Crea il File `.env`

```bash
touch .env
```

Aggiungi questo contenuto (modifica le password):

```env
DATABASE_URL=postgresql://orchestrator_user:your_secure_password@db:5432/print_orchestrator_dev
RACK_ENV=development
PORT=5000
SWITCH_WEBHOOK_URL=http://localhost:9999/webhook
SWITCH_API_KEY=your_switch_api_key_here
SWITCH_SIMULATION=false
```

### Step 3: Avvia Docker

```bash
# Avvia i container (Ruby app + PostgreSQL)
docker-compose up

# Output atteso:
# db_1  | database system is ready to accept connections
# web_1 | * Listening on http://0.0.0.0:5000
```

✅ **FATTO!** Vai a http://localhost:5000 nel browser! 🎉

---

## 📁 Come Funziona Docker

Il progetto contiene due file speciali:

- **`Dockerfile`** - Istruzioni per creare l'immagine dell'app Ruby
- **`docker-compose.yml`** - Configura 2 servizi:
  - `web` - L'app Ruby Puma sulla porta 5000
  - `db` - PostgreSQL sulla porta 5432

Questi file **fanno tutto automaticamente**. Non devi configurare nulla! 🎯

---

## 🔄 Comandi Utili

### Avviare i Container

```bash
# Avvia in foreground (vedi i log)
docker-compose up

# Oppure in background
docker-compose up -d
```

### Fermare i Container

```bash
# Ferma tutto
docker-compose down

# Oppure nel terminale dove è in esecuzione
Ctrl + C
```

### Visualizzare i Log

```bash
# Log di tutti i servizi
docker-compose logs -f

# Log solo dell'app web
docker-compose logs -f web

# Log solo del database
docker-compose logs -f db
```

### Eseguire Comandi nel Container

```bash
# Accedi alla console Ruby dell'app
docker-compose exec web bundle exec irb

# Esegui migrazioni
docker-compose exec web bundle exec rake db:migrate

# Ricrea il database
docker-compose exec web bundle exec rake db:drop db:create db:migrate
```

### Riavviare il Database

Se il database ha problemi:

```bash
# Cancella il volume (ATTENZIONE: perde tutti i dati!)
docker-compose down -v

# Ricrea da zero
docker-compose up
```

---

## 📊 Primo Accesso

1. Apri http://localhost:5000
2. Vai in **⚙️ Impostazioni**
3. Crea i dati di test (Negozi, Flussi, Macchine) - come nella guida Mac

---

## 🔌 Configurare Switch con Docker

Se Switch è in esecuzione **localmente** sul tuo Mac/Linux:

1. **Nel file `docker-compose.yml`**, modifica:

```yaml
services:
  web:
    environment:
      SWITCH_WEBHOOK_URL: http://host.docker.internal:9999/webhook
```

(Usa `host.docker.internal` invece di `localhost`)

2. **In Switch**, configura il callback a:
```
http://localhost:5000/api/switch/callback
```

---

## 🐛 Troubleshooting

### Errore: "Port 5000 already in use"

Un'altra app sta usando la porta 5000. Cambia la porta in `docker-compose.yml`:

```yaml
ports:
  - "3000:5000"  # Accedi a http://localhost:3000
```

### Errore: "Database connection refused"

Il database non è ancora pronto. Aspetta 5-10 secondi e aggiorna il browser.

```bash
# Se continua, ricrea il database
docker-compose down -v
docker-compose up
```

### Errore: "Cannot connect to Docker daemon"

Docker Desktop non è in esecuzione:
- **Mac/Windows**: Apri l'app "Docker" dal menu
- **Linux**: Avvia il servizio `sudo systemctl start docker`

### Errore: "Container exited with code 1"

Vedi i log per il dettaglio:

```bash
docker-compose logs web
```

Poi riavvia:

```bash
docker-compose down
docker-compose up
```

---

## 🗑️ Pulire Tutto

Se vuoi ricominciar da zero:

```bash
# Ferma e cancella tutti i container e volumi
docker-compose down -v

# Cancella l'immagine (ricreata automaticamente al prossimo avvio)
docker image rm print-orchestrator-web

# Ricomincia
docker-compose up
```

---

## 📝 File di Configurazione (docker-compose.yml)

Se vuoi modificare qualcosa, il file è tipo questo:

```yaml
version: '3.8'

services:
  db:
    image: postgres:15
    environment:
      POSTGRES_USER: orchestrator_user
      POSTGRES_PASSWORD: your_secure_password
      POSTGRES_DB: print_orchestrator_dev
    ports:
      - "5432:5432"
    volumes:
      - postgres_data:/var/lib/postgresql/data

  web:
    build: .
    command: bundle exec puma -b tcp://0.0.0.0:5000 config.ru
    ports:
      - "5000:5000"
    environment:
      DATABASE_URL: postgresql://orchestrator_user:your_secure_password@db:5432/print_orchestrator_dev
      RACK_ENV: development
    depends_on:
      - db
    volumes:
      - .:/app

volumes:
  postgres_data:
```

---

## ✅ Vantaggi di Docker

| | Mac/Linux Manuale | Docker |
|---|---|---|
| Tempo installazione | 30+ minuti | 5 minuti |
| Configurare Ruby | ⚠️ Complicato | ✅ Automatico |
| Configurare PostgreSQL | ⚠️ Complicato | ✅ Automatico |
| Switch locale | ⭕ Problemi di path | ✅ Facile |
| Riavviare | Complesso | `docker-compose restart` |
| Backup database | Manuale | `docker volume backup` |
| Sharable con altri | ❌ No | ✅ Sì (basta Docker) |

---

## 🚀 Deploy da Docker

Quando sei pronto per production:

```bash
# Build l'immagine per production
docker build -t print-orchestrator:latest .

# Push su un registry (Docker Hub, GitHub Container Registry, etc.)
docker push your-registry/print-orchestrator:latest

# Deploy su qualsiasi server con Docker
docker run -p 5000:5000 your-registry/print-orchestrator:latest
```

---

## 💡 Prossimi Step

1. ✅ Installa Docker Desktop
2. ✅ Clona il repository
3. ✅ Crea il file `.env`
4. ✅ Esegui `docker-compose up`
5. ✅ Vai a http://localhost:5000
6. ✅ Crea dati di test
7. ✅ Testa il flusso completo

---

## 📞 Aiuto Veloce

Se hai problemi:

```bash
# Vedi tutti i container in esecuzione
docker ps

# Vedi tutti i container (anche fermi)
docker ps -a

# Vedi i log dettagliati
docker-compose logs -f

# Ricrea tutto da zero
docker-compose down -v && docker-compose up
```

---

**Docker rende tutto più semplice.** Non devi più preoccuparti di configurare Ruby, PostgreSQL, path, etc. È tutto dentro i container! 🎉

Buona installazione! 🚀
