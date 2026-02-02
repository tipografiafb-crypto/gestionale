# Guida Migrazioni Database

## Stato Attuale (25 Novembre 2025)

La migrazione consolidata `db/migrate/001_create_all_tables.rb` contiene TUTTE le colonne necessarie per:

- **order_items**: campi per pre-stampa, stampa, tracking, webhook metadata
- **print_flows**: webhook references (preprint, print, label)
- **products**: routing e categorie
- **print_machines**: macchine e associazioni ai flussi
- **inventories**: gestione stock
- E tutte le altre tabelle core

## Per Installazioni NUOVE

```bash
bash install.sh
```

Creerà il database con TUTTE le tabelle e colonne in una singola migrazione.

## Per AGGIORNAMENTI da versioni precedenti

Se hai un'installazione Ubuntu precedente con database già creato:

```bash
cd /home/paolo/apps/print-orchestrator

# Opzione 1: Reset completo (CANCELLA TUTTI I DATI)
bundle exec rake db:drop
bundle exec rake db:create
bundle exec rake db:migrate

# Opzione 2: Aggiorna solo schema (mantiene dati)
# Non disponibile - usare Opzione 1 per prima installazione
```

## Colonne in order_items (consolidate)

```ruby
# Switch payload
scala (default: "1:1")
materiale
campi_custom (JSON)
campi_webhook (JSON)

# Preprint tracking
preprint_status (default: 'pending')
preprint_job_id
preprint_preview_url
preprint_started_at
preprint_completed_at
preprint_print_flow_id (FK -> print_flows)

# Print tracking
print_status (default: 'pending')
print_job_id
print_started_at
print_completed_at
print_machine_id (FK -> print_machines)
```

## Checklist per installazioni future

- ✅ Migrazione consolidata = UNA sola migrazione
- ✅ Tutte le colonne definite UP-FRONT
- ✅ Foreign keys incluse
- ✅ Default values impostati
- ✅ Indici per performance

NON aggiungere più colonne via SQL manuale - aggiornare SEMPRE `001_create_all_tables.rb`
