# 🐧 Print Order Orchestrator - Installazione su Linux Server

Guida completa per installare il Print Order Orchestrator su **un server Linux dedicato** in locale. Questa è la soluzione **più semplice e stabile** per produzione.

## ⚡ SCELTA RAPIDA: Installazione Automatica (Consigliato!)

Se vuoi **saltare tutta la configurazione manuale**, usa gli script automatici:

```bash
# 1. Clona il repository
mkdir -p /home/paolo/apps
cd /home/paolo/apps
git clone https://github.com/tipografiafb-crypto/gestionale.git print-orchestrator
cd print-orchestrator

# 2. Esegui l'installazione automatica
bash quick_start_linux.sh

# 3. Configura il servizio systemd
sudo bash setup_service.sh

# 4. Abilita e avvia
sudo systemctl enable print-orchestrator.service
sudo systemctl start print-orchestrator.service

# 5. Verifica
curl http://localhost:5000/orders
```

**Fatto!** L'app è pronta e avviata automaticamente. 🚀

---

### Cosa fanno gli script automatici?

- ✅ `quick_start_linux.sh` - Controlla prerequisiti, installa dipendenze, configura database, copia `.env`
  - **Database setup garantito**: Esegue migrazioni + carica schema consolidato (15 tabelle garantite)
  - Verifica che tutte le tabelle siano state create prima di proseguire
  - Carica i dati di seed (negozi, prodotti, etc.)

- ✅ `setup_service.sh` - Crea il servizio systemd per avviare automaticamente l'app al boot

### ⚠️ IMPORTANTE - Prima di Installare su Ubuntu

Se hai modificato il codice su Replit, **DEVI sincronizzare i file su GitHub** altrimenti Ubuntu avrà versione vecchia:

```bash
# Su Replit (oppure dalla cartella print-orchestrator):
cd /home/paolo/apps/print-orchestrator
git add -A
git commit -m "Update installer and database setup"
git push
```

Poi su Ubuntu:
```bash
git pull  # Scarica gli ultimi aggiornamenti da GitHub
bash quick_start_linux.sh
```

---

## 📖 INSTALLAZIONE MANUALE (Alternativa)

Se preferisci configurare tutto manualmente, continua sotto:

---

# PARTE 1: Preparazione del Server Linux

## 1.1 Scarica Ubuntu Server

Scarica **Ubuntu Server 22.04 LTS** (versione testuale, senza GUI):
https://ubuntu.com/download/server

### Opzioni:
- **Opzione A**: Installa su una vecchia macchina dedicata (PC, Mini PC, Raspberry Pi)
- **Opzione B**: Usa una VM (VirtualBox, Proxmox, ESXi)
- **Opzione C**: Noleggia un server cloud (DigitalOcean, Hetzner, AWS - più economico)

## 1.2 Installa Ubuntu Server

Durante l'installazione:
1. Scegli **"Installation type: Ubuntu Server (minimal)"**
2. Configura rete (DHCP o IP statico - vedi sotto)
3. Crea un utente (es: `orchestrator`)
4. Completa l'installazione e riavvia

---

# PARTE 2: Configurazione di Rete

## 2.1 Connetti il Server in Rete Locale

### Se Usi Ethernet (Consigliato)

Collega il cavo Ethernet direttamente al router.

### Se Usi WiFi

```bash
# Accedi al server e vedi le reti disponibili
sudo nmtui

# Oppure da linea di comando
nmcli device wifi list
nmcli device wifi connect "NOME_RETE" password "PASSWORD"
```

## 2.2 Scopri l'IP del Server

```bash
# Visualizza l'indirizzo IP del server
hostname -I

# Output: 192.168.1.100
```

**Annota questo IP!** Lo userai per accedere da altri computer.

## 2.3 Configura IP Statico (Opzionale ma Consigliato)

Per evitare che l'IP cambi ogni volta che riavvii:

```bash
# Edita il file di configurazione di rete
sudo nano /etc/netplan/00-installer-config.yaml
```

Sostituisci il contenuto con:

```yaml
network:
  version: 2
  ethernets:
    eth0:
      dhcp4: false
      addresses:
        - 192.168.1.100/24
      routes:
        - to: default
          via: 192.168.1.1
      nameservers:
        addresses: [8.8.8.8, 8.8.4.4]
```

Salva (Ctrl+O, Invio, Ctrl+X) e applica:

```bash
sudo netplan apply
```

**Ora l'IP sarà sempre 192.168.1.100!** 🎯

---

# PARTE 3: Accesso da Remoto da Un Altro Computer

## 3.1 Abilita SSH (Accesso Remoto)

SSH dovrebbe essere già installato. Se no:

```bash
sudo apt-get update
sudo apt-get install -y openssh-server
sudo systemctl start ssh
sudo systemctl enable ssh
```

## 3.2 Accedi da Un Altro Computer

### Da Mac/Linux:

```bash
ssh orchestrator@192.168.1.100

# Inserisci la password che hai creato durante l'installazione
```

### Da Windows:

Usa **PuTTY** o **Windows Terminal**:
- Scarica PuTTY: https://www.putty.org/
- Hostname: `192.168.1.100`
- Username: `orchestrator`
- Password: (quella che hai creato)

### Oppure da Terminal di Windows 11+:

```powershell
ssh orchestrator@192.168.1.100
```

---

# PARTE 4: Installazione dell'Applicazione

Una volta connesso al server via SSH, esegui questi comandi:

## 4.1 Aggiorna il Sistema

```bash
sudo apt-get update
sudo apt-get upgrade -y
```

## 4.2 Installa i Prerequisiti

```bash
# Ruby, PostgreSQL, Git, e altre dipendenze
sudo apt-get install -y \
  ruby-3.2 \
  postgresql \
  postgresql-contrib \
  git \
  build-essential \
  libpq-dev \
  curl \
  wget

# Verifica le versioni
ruby --version
psql --version
```

## 4.3 Installa Bundler

```bash
sudo gem install bundler

# Verifica
bundle --version
```

## 4.4 Clona il Repository

```bash
# Crea una cartella per l'app
mkdir -p /home/orchestrator/apps
cd /home/orchestrator/apps

# Clona il repository
git clone https://github.com/tipografiafb-crypto/gestionale.git print-orchestrator
cd print-orchestrator
```

## 4.5 Crea l'Utente PostgreSQL

```bash
# Accedi a PostgreSQL
sudo -u postgres psql

# Dentro psql, esegui:
CREATE USER orchestrator_user WITH PASSWORD 'your_secure_password';
ALTER ROLE orchestrator_user CREATEDB;
\q
```

## 4.6 Configura il Database

Edita il file `config/database.yml`:

```bash
nano config/database.yml
```

Incolla questo contenuto:

```yaml
development:
  adapter: postgresql
  encoding: utf8
  database: print_orchestrator_dev
  username: orchestrator_user
  password: your_secure_password
  host: localhost
  port: 5432

production:
  adapter: postgresql
  encoding: utf8
  database: print_orchestrator_prod
  username: orchestrator_user
  password: your_secure_password
  host: localhost
  port: 5432
```

Sostituisci `your_secure_password` con una password sicura!

## 4.7 Crea il File `.env`

### Opzione A: Copia da template (Automatico)
```bash
cp .env.example .env
nano .env
# Modifica solo la password PostgreSQL se necessario
```

### Opzione B: Crea manualmente
```bash
nano .env
```

Incolla:

```env
DATABASE_URL=postgresql://orchestrator_user:your_secure_password@localhost:5432/print_orchestrator_dev
RACK_ENV=production
PORT=5000
SERVER_BASE_URL=http://192.168.1.100:5000
SWITCH_WEBHOOK_URL=http://192.168.1.162:5000/switch/
SWITCH_API_KEY=your_switch_api_key
SWITCH_SIMULATION=false

# Storage Cleanup (giorni di retention)
DAYS_TO_KEEP=45

# FTP (opzionale)
FTP_HOST=c72965.sgvps.net
FTP_USER=widegest@thepickshouse.com
FTP_PASS=WidegestImport24
FTP_PATH=/test/
FTP_POLL_INTERVAL=60
FTP_DELETE_AFTER_IMPORT=false
```

## 4.8 Installa le Dipendenze Ruby

```bash
# Dalla cartella print-orchestrator
bundle install
```

## 4.9 Crea il Database

### ⭐ NUOVO: Setup Automatico Completo

```bash
DATABASE_URL=postgresql://orchestrator_user:your_secure_password@localhost:5432/print_orchestrator_dev bundle exec rake db:setup_complete
```

Questo comando:
- ✅ Crea il database
- ✅ Esegue tutte le migrazioni
- ✅ Carica automaticamente lo schema SQL consolidato come fallback
- ✅ Verifica che tutte le 15 tabelle siano create
- ✅ Carica i dati di seed

Se tutto va bene, vedrai:
```
✓ Database connected (15 tables created)
✅ Database setup complete!
```

### ✋ Alternativa Manuale (se il task non funziona)

```bash
bundle exec rake db:create
bundle exec rake db:migrate
psql -U orchestrator_user -d print_orchestrator_dev -f db/init/consolidated_schema.sql
```

---

# PARTE 5: Avvio dell'Applicazione

## 5.1 Avvio Manuale (per Test)

```bash
# Dalla cartella print-orchestrator
bundle exec puma -b tcp://0.0.0.0:5000 -e production

# Dovresti vedere:
# * Puma starting in cluster mode...
# * Listening on http://0.0.0.0:5000
```

Ora da qualsiasi computer nella rete, vai a:
```
http://192.168.1.100:5000
```

✅ **L'app è accessibile!**

## 5.2 Avvio Automatico (con Systemd)

### Opzione A: Automatico (Consigliato)
```bash
sudo bash setup_service.sh
sudo systemctl enable print-orchestrator.service
sudo systemctl start print-orchestrator.service
sudo systemctl status print-orchestrator.service
```

### Opzione B: Manuale

Crea un file di servizio:

```bash
sudo nano /etc/systemd/system/print-orchestrator.service
```

Incolla (sostituisci `paolo` con il tuo username):

```ini
[Unit]
Description=Print Order Orchestrator
After=network.target postgresql.service
Wants=postgresql.service

[Service]
Type=simple
User=paolo
WorkingDirectory=/home/paolo/apps/print-orchestrator
Environment="PATH=/home/paolo/.gem/ruby/3.2.0/bin:/home/paolo/.local/bin:$PATH"
Environment="RACK_ENV=production"
EnvironmentFile=/home/paolo/apps/print-orchestrator/.env
ExecStart=/usr/local/bin/bundle exec puma -b tcp://0.0.0.0:5000 config.ru
Restart=on-failure
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
```

Salva e abilita:

```bash
sudo systemctl daemon-reload
sudo systemctl enable print-orchestrator.service
sudo systemctl start print-orchestrator.service
sudo systemctl status print-orchestrator.service
```

Perfetto! L'app parte **automaticamente all'avvio del server**! 🚀

---

# PARTE 6: Accesso da Più Computer

Una volta che il server è pronto, **qualsiasi computer nella rete locale** può accedere così:

### Da Tablet/Smartphone:

Apri il browser e vai a:
```
http://192.168.1.100:5000
```

### Da Qualsiasi PC:

```
http://192.168.1.100:5000
```

**Tutti vedono la stessa app!** 🎯

---

# PARTE 7: Configurazione FTP (Se Necessario)

Se usi l'importazione automatica da FTP:

## 7.1 Verifica che FTP sia Configurato nel `.env`

```bash
# Controlla il .env
cat .env | grep FTP
```

Dovrebbe mostrare:
```
FTP_HOST=c72965.sgvps.net
FTP_USER=tuo_utente
FTP_PASS=tua_password
FTP_PATH=/test/
```

## 7.2 Riavvia l'App

```bash
sudo systemctl restart print-orchestrator
```

Vedrai nei log:
```
[FTPPoller] Starting FTP polling...
```

✅ **FTP è attivo!**

---

# PARTE 8: Monitoraggio e Manutenzione

## 8.1 Visualizzare i Log

```bash
# Log in real-time
sudo journalctl -u print-orchestrator -f

# Log degli ultimi 50 linee
sudo journalctl -u print-orchestrator -n 50
```

## 8.2 Riavviare l'App

```bash
sudo systemctl restart print-orchestrator
```

## 8.3 Aggiornare il Codice

Quando fai `git push` su GitHub:

```bash
# Vai nella cartella
cd /home/orchestrator/apps/print-orchestrator

# Scarica gli ultimi cambiamenti
git pull

# Ricaricare le dipendenze (se necessario)
bundle install

# Riavvia l'app
sudo systemctl restart print-orchestrator
```

## 8.4 Backup del Database

```bash
# Esegui un backup
pg_dump -U orchestrator_user -d print_orchestrator_dev > backup_$(date +%Y%m%d).sql

# Salva in cloud o USB
```

---

# PARTE 9: Troubleshooting

### Errore: "Cannot connect to database"

```bash
# Verifica che PostgreSQL è in esecuzione
sudo systemctl status postgresql

# Se no, avvia
sudo systemctl start postgresql
```

### Errore: "Port 5000 already in use"

```bash
# Uccidi il processo che usa la porta
sudo lsof -i :5000 | grep LISTEN | awk '{print $2}' | xargs kill -9
```

### L'app non parte

```bash
# Visualizza gli errori
sudo journalctl -u print-orchestrator -n 100
```

### Errore di permessi su file

```bash
# Dai i permessi corretti
sudo chown -R orchestrator:orchestrator /home/orchestrator/apps/print-orchestrator
```

---

# PARTE 10: Configurazione Firewall (Opzionale)

Se hai un firewall abilitato:

```bash
# Abilita la porta 5000
sudo ufw allow 5000

# Abilita SSH (importante per l'accesso remoto!)
sudo ufw allow 22

# Abilita il firewall
sudo ufw enable
```

---

# CHECKLIST Finale

### Se hai usato l'Installazione Automatica:
- ✅ Ubuntu Server installato
- ✅ Repository clonato
- ✅ `quick_start_linux.sh` eseguito
- ✅ `setup_service.sh` eseguito
- ✅ Servizio abilitato con `sudo systemctl enable print-orchestrator.service`
- ✅ Servizio avviato con `sudo systemctl start print-orchestrator.service`
- ✅ Accessibile da `http://192.168.1.100:5000`

### Se hai usato l'Installazione Manuale:
- ✅ Ubuntu Server installato
- ✅ IP statico configurato (192.168.1.100)
- ✅ SSH abilitato
- ✅ Ruby, PostgreSQL, Git installati
- ✅ Repository clonato
- ✅ Database creato
- ✅ `.env` configurato
- ✅ App avviata con systemd
- ✅ Accessibile da `http://192.168.1.100:5000`
- ✅ FTP configurato (se necessario)

---

# 🎉 Tutto Pronto!

L'app è ora in esecuzione su **un server Linux locale**, accessibile da qualsiasi computer della rete.

**Vantaggi di questa configurazione:**

| Aspetto | Valore |
|---|---|
| **Stabilità** | ⭐⭐⭐⭐⭐ Ottima |
| **Performance** | ⭐⭐⭐⭐⭐ Nativa |
| **Facilità Manutenzione** | ⭐⭐⭐⭐⭐ Molto semplice |
| **Costi** | ⭐⭐⭐⭐⭐ Bassissimi |
| **Scalabilità** | ⭐⭐⭐⭐ Buona |

---

## Prossimi Step

1. ✅ Installazione completata
2. ✅ Crea i dati di test (Negozi, Flussi, Macchine)
3. ✅ Importa ordini da FTP
4. ✅ Configura Switch
5. ✅ Testa il flusso completo

---

**Buona fortuna con il tuo server Linux! 🐧🚀**

Se hai domande, guarda i log con `sudo journalctl -u print-orchestrator -f`
