# Storage Cleanup - Setup & Usage

## Test Pulizia Manuale (DRY RUN)

### Via Web Interface (NO DELETE)
1. Vai a `/admin/cleanup`
2. Sezione **"Pulizia Manuale per Mese"**
3. Seleziona anno e mese
4. Clicca **"🔍 Anteprima"** (mostra cosa verrebbe cancellato SENZA cancellare)
5. Poi opzionalmente clicca il pulsante di eliminazione se sei sicuro

### Via Script (DRY RUN - NO DELETE)
```bash
cd /home/runner/workspace
bundle exec ruby scripts/cleanup.rb --dry-run
```
Output: Mostra ESATTAMENTE cosa verrebbe cancellato senza cancellare nulla

### Via Script (LIVE DELETE)
```bash
cd /home/runner/workspace
bundle exec ruby scripts/cleanup.rb
```
Output: Cancella e mostra i risultati

### Parametri Script
```bash
# Dry run con retention di 14 giorni
bundle exec ruby scripts/cleanup.rb --dry-run --days=14

# Live delete con retention di 60 giorni  
bundle exec ruby scripts/cleanup.rb --days=60
```

---

## Setup Pulizia Automatica su Ubuntu

### Opzione 1: Cron Job (CONSIGLIATO)

#### 1. Apri il crontab dell'utente
```bash
crontab -e
```

#### 2. Aggiungi una linea per la pulizia notturna (es: 02:00 ogni giorno)
```cron
# Cleanup storage - Run daily at 2:00 AM
0 2 * * * cd /path/to/project && bundle exec ruby scripts/cleanup.rb >> /var/log/print-orchestrator-cleanup.log 2>&1
```

#### 3. Salva (Ctrl+X, Y, Enter in nano)

#### 4. Verifica il cron sia stato aggiunto
```bash
crontab -l | grep cleanup
```

---

### Opzione 2: Systemd Timer (MODERNO)

#### 1. Crea il servizio
```bash
sudo nano /etc/systemd/system/print-orchestrator-cleanup.service
```

Incolla:
```ini
[Unit]
Description=Print Orchestrator Storage Cleanup
After=network.target

[Service]
Type=oneshot
User=ubuntu
WorkingDirectory=/path/to/project
ExecStart=/usr/bin/bundle exec ruby scripts/cleanup.rb
StandardOutput=journal
StandardError=journal
```

#### 2. Crea il timer
```bash
sudo nano /etc/systemd/system/print-orchestrator-cleanup.timer
```

Incolla:
```ini
[Unit]
Description=Print Orchestrator Storage Cleanup Timer
Requires=print-orchestrator-cleanup.service

[Timer]
# Run daily at 2:00 AM
OnCalendar=daily
OnCalendar=*-*-* 02:00:00
Persistent=true

[Install]
WantedBy=timers.target
```

#### 3. Abilita e avvia
```bash
sudo systemctl daemon-reload
sudo systemctl enable print-orchestrator-cleanup.timer
sudo systemctl start print-orchestrator-cleanup.timer
```

#### 4. Verifica lo stato
```bash
sudo systemctl status print-orchestrator-cleanup.timer
sudo systemctl list-timers print-orchestrator-cleanup.timer
```

---

## Monitoraggio

### Vedere i log del cleanup (Cron)
```bash
tail -f /var/log/print-orchestrator-cleanup.log
```

### Vedere i log del cleanup (Systemd)
```bash
sudo journalctl -u print-orchestrator-cleanup.service -f
```

### Verificare gli asset eliminati nel database
```sql
SELECT COUNT(*) FROM assets WHERE deleted_at IS NOT NULL;
```

---

## Variabili di Ambiente

Personalizza la retention nel file `.env`:
```env
DAYS_TO_KEEP=30    # Default: 30 giorni
```

---

## Troubleshooting

### Il cron non viene eseguito?
1. Verifica il permesso di crontab: `sudo -l`
2. Controlla se cron è attivo: `systemctl status cron`
3. Vedi i log: `grep CRON /var/log/syslog` (Ubuntu)

### Errore "bundle: command not found"?
Usa il path completo di Ruby:
```bash
/home/ubuntu/.rbenv/shims/bundle exec ruby scripts/cleanup.rb
```

O installa bundle globalmente:
```bash
gem install bundler
```

---

## Sicurezza

⚠️ **IMPORTANTE:**
- Il cleanup NON cancella ordini recenti (retention_days)
- Il cleanup NON cancella asset con deleted_at = NULL (sicurezza)
- Il cleanup usa `--dry-run` per testare PRIMA di eseguire
- Sempre fare un backup prima di attivare la pulizia automatica

---

## Verificare Adesso (TEST)

```bash
# Test dry run locale
cd /home/runner/workspace
bundle exec ruby scripts/cleanup.rb --dry-run --days=30

# Poi visita: http://localhost:5000/admin/cleanup
# Per preview via web
```
