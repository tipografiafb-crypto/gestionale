#!/bin/bash
# Installatore Sicuro per Ubuntu (Ambiente di Produzione)
# Questo script aggiunge solo tabelle/colonne mancanti senza cancellare dati esistenti.

set -e

# Carica variabili d'ambiente
if [ -f .env ]; then
  # Estraiamo DATABASE_URL se presente
  DB_URL=$(grep '^DATABASE_URL=' .env | cut -d '=' -f2-)
fi

echo "🚀 Print Order Orchestrator - Safe Ubuntu Setup"
echo "==============================================="

if [ -z "$DB_URL" ]; then
    echo "❌ DATABASE_URL non trovata nel file .env"
    exit 1
fi

echo "Step 1: Verifica connessione al database..."
psql "$DB_URL" -c "SELECT 1" > /dev/null 2>&1 || {
    echo "❌ Impossibile connettersi al database. Verifica le credenziali nel file .env"
    exit 1
}
echo "✅ Connessione riuscita."

echo "Step 2: Esecuzione migrazioni sicure (ActiveRecord)..."
# Questo aggiungerà tabelle e colonne mancanti basandosi sul file ConsolidatedSchema
bundle exec rake db:migrate

echo "Step 3: Verifica integrità schema..."
# Opzionale: aggiunte manuali via SQL per sicurezza estrema (IF NOT EXISTS)
psql "$DB_URL" << 'SQLEOF'
-- Esempio di colonna critica che deve esserci
ALTER TABLE orders ADD COLUMN IF NOT EXISTS external_order_code VARCHAR;
ALTER TABLE stores ADD COLUMN IF NOT EXISTS code VARCHAR;

-- Cut file management for products
ALTER TABLE products ADD COLUMN IF NOT EXISTS has_cut_file BOOLEAN DEFAULT FALSE;
ALTER TABLE products ADD COLUMN IF NOT EXISTS cut_file_path VARCHAR;
SQLEOF

echo "✅ Aggiornamento completato con successo."
echo "==============================================="
echo "Ora puoi avviare l'applicazione con:"
echo "bundle exec puma -C config/puma.rb"
