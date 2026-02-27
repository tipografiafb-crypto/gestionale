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

echo "Step 2: Installazione dipendenze Ruby..."
# Installazione locale per l'utente magenta
bundle install --path vendor/bundle

echo "Step 3: Esecuzione migrazioni sicure (ActiveRecord)..."
# Questo aggiungerà tabelle e colonne mancanti basandosi sul file ConsolidatedSchema
bundle exec rake db:migrate

echo "Step 3: Verifica integrità schema..."
# Aggiunte manuali via SQL per sicurezza estrema (IF NOT EXISTS)
psql "$DB_URL" << 'SQLEOF'
-- ========================================
-- ORDERS TABLE
-- ========================================
ALTER TABLE orders ADD COLUMN IF NOT EXISTS external_order_code VARCHAR;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS customer_name VARCHAR;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS customer_note TEXT;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS source VARCHAR DEFAULT 'api';

-- ========================================
-- STORES TABLE
-- ========================================
ALTER TABLE stores ADD COLUMN IF NOT EXISTS code VARCHAR;

-- ========================================
-- PRODUCTS TABLE (Cut file management)
-- ========================================
ALTER TABLE products ADD COLUMN IF NOT EXISTS has_cut_file BOOLEAN DEFAULT FALSE;
ALTER TABLE products ADD COLUMN IF NOT EXISTS cut_file_path VARCHAR;
ALTER TABLE products ADD COLUMN IF NOT EXISTS is_dependent BOOLEAN DEFAULT FALSE;
ALTER TABLE products ADD COLUMN IF NOT EXISTS master_product_id INTEGER;
CREATE INDEX IF NOT EXISTS index_products_on_master_product_id ON products(master_product_id);

-- ========================================
-- PRINT_FLOWS TABLE (Azione Photoshop)
-- ========================================
ALTER TABLE print_flows ADD COLUMN IF NOT EXISTS azione_photoshop_enabled BOOLEAN DEFAULT false;
ALTER TABLE print_flows ADD COLUMN IF NOT EXISTS azione_photoshop_options TEXT;
ALTER TABLE print_flows ADD COLUMN IF NOT EXISTS default_azione_photoshop VARCHAR;

-- ========================================
-- BACKUP_CONFIGS TABLE
-- ========================================
CREATE TABLE IF NOT EXISTS backup_configs (
  id SERIAL PRIMARY KEY,
  remote_ip VARCHAR(255),
  remote_path VARCHAR(1024),
  ssh_username VARCHAR(255),
  ssh_password VARCHAR(1024),
  ssh_port INTEGER DEFAULT 22,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ========================================
-- AGGREGATED_JOBS TABLES
-- ========================================
CREATE TABLE IF NOT EXISTS aggregated_jobs (
  id SERIAL PRIMARY KEY,
  name VARCHAR(255) NOT NULL,
  status VARCHAR(50) DEFAULT 'pending',
  nr_files INTEGER DEFAULT 0,
  print_flow_id INTEGER REFERENCES print_flows(id) ON DELETE SET NULL,
  aggregated_file_url TEXT,
  aggregated_filename VARCHAR(255),
  sent_at TIMESTAMP,
  aggregated_at TIMESTAMP,
  completed_at TIMESTAMP,
  preprint_sent_at TIMESTAMP,
  notes TEXT,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS aggregated_job_items (
  id SERIAL PRIMARY KEY,
  aggregated_job_id INTEGER NOT NULL REFERENCES aggregated_jobs(id) ON DELETE CASCADE,
  order_item_id INTEGER NOT NULL REFERENCES order_items(id) ON DELETE CASCADE,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  UNIQUE(aggregated_job_id, order_item_id)
);

-- ========================================
-- INDEXES
-- ========================================
CREATE INDEX IF NOT EXISTS idx_aggregated_jobs_status ON aggregated_jobs(status);
CREATE INDEX IF NOT EXISTS idx_aggregated_job_items_job_id ON aggregated_job_items(aggregated_job_id);
CREATE INDEX IF NOT EXISTS idx_aggregated_job_items_item_id ON aggregated_job_items(order_item_id);
-- ========================================
-- CRM TABLES
-- ========================================
CREATE TABLE IF NOT EXISTS customers (
    id BIGSERIAL PRIMARY KEY,
    email VARCHAR(255) NOT NULL UNIQUE,
    first_name VARCHAR(255),
    last_name VARCHAR(255),
    phone VARCHAR(50),
    billing_address TEXT,
    shipping_address TEXT,
    total_spent DECIMAL(10,2) DEFAULT 0,
    order_count INTEGER DEFAULT 0,
    first_order_at TIMESTAMP,
    last_order_at TIMESTAMP,
    store_id BIGINT REFERENCES stores(id),
    notes TEXT,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS index_customers_on_email ON customers(email);
CREATE INDEX IF NOT EXISTS index_customers_on_store_id ON customers(store_id);
CREATE INDEX IF NOT EXISTS index_customers_on_last_order_at ON customers(last_order_at);

CREATE TABLE IF NOT EXISTS sales (
    id BIGSERIAL PRIMARY KEY,
    customer_id BIGINT NOT NULL REFERENCES customers(id),
    store_id BIGINT REFERENCES stores(id),
    external_order_code VARCHAR(255) NOT NULL,
    order_date TIMESTAMP,
    total DECIMAL(10,2) DEFAULT 0,
    tax DECIMAL(10,2) DEFAULT 0,
    shipping DECIMAL(10,2) DEFAULT 0,
    discount DECIMAL(10,2) DEFAULT 0,
    payment_method VARCHAR(100),
    currency VARCHAR(10) DEFAULT 'EUR',
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE UNIQUE INDEX IF NOT EXISTS index_sales_on_store_and_order ON sales(store_id, external_order_code);
CREATE INDEX IF NOT EXISTS index_sales_on_customer_id ON sales(customer_id);
CREATE INDEX IF NOT EXISTS index_sales_on_order_date ON sales(order_date);

CREATE TABLE IF NOT EXISTS sale_items (
    id BIGSERIAL PRIMARY KEY,
    sale_id BIGINT NOT NULL REFERENCES sales(id) ON DELETE CASCADE,
    sku VARCHAR(255),
    product_name VARCHAR(255),
    quantity INTEGER DEFAULT 1,
    line_total DECIMAL(10,2) DEFAULT 0,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS index_sale_items_on_sale_id ON sale_items(sale_id);
CREATE INDEX IF NOT EXISTS index_sale_items_on_sku ON sale_items(sku);
SQLEOF

echo ""
echo "Step 4: Conteggio tabelle..."
TABLE_COUNT=$(psql "$DB_URL" -t -c "SELECT count(*) FROM information_schema.tables WHERE table_schema='public' AND table_type='BASE TABLE';" 2>&1 | tr -d ' ')
echo "✅ Totale tabelle: $TABLE_COUNT"

echo ""
echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║  ✅ AGGIORNAMENTO COMPLETATO CON SUCCESSO!                    ║"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo ""
echo "Ora puoi avviare/riavviare l'applicazione con:"
echo "  sudo systemctl restart print-orchestrator"
echo ""
echo "Oppure manualmente:"
echo "  bundle exec puma -b tcp://0.0.0.0:5000 -p 5000 config.ru"
