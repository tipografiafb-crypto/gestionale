#!/bin/bash
#
# ========================================================================
# Print Order Orchestrator - Complete Fresh Installation Script
# ========================================================================
# Questo script installa l'applicazione su una macchina Linux nuova.
# Supporta Ubuntu 22.04/24.04 e sistemi compatibili.
#
# Uso: bash install_fresh.sh [--reset]
#   --reset: Cancella il database esistente e ricrea da zero
#
# Autore: Tipografia FB
# ========================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Configuration
APP_NAME="Print Order Orchestrator"
DB_USER="orchestrator_user"
DB_NAME="print_orchestrator_dev"
DEFAULT_PORT=5000

# Parse arguments
RESET_MODE=false
if [ "$1" == "--reset" ]; then
  RESET_MODE=true
fi

# Header
echo ""
echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║                                                               ║${NC}"
echo -e "${CYAN}║     ${BOLD}🖨️  PRINT ORDER ORCHESTRATOR - INSTALLAZIONE${NC}${CYAN}              ║${NC}"
echo -e "${CYAN}║                                                               ║${NC}"
echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════╝${NC}"
echo ""

if [ "$RESET_MODE" == "true" ]; then
  echo -e "${RED}⚠️  MODALITÀ RESET: Il database verrà cancellato e ricreato!${NC}"
  echo ""
  read -p "Sei sicuro? (y/N): " CONFIRM
  if [ "$CONFIRM" != "y" ] && [ "$CONFIRM" != "Y" ]; then
    echo "Operazione annullata."
    exit 0
  fi
fi

# ========================================================================
# STEP 1: Check if running on Linux
# ========================================================================
echo -e "${YELLOW}[STEP 1/10]${NC} Verifica sistema operativo..."

if [[ ! "$OSTYPE" =~ ^linux ]]; then
  echo -e "${RED}❌ Questo script è progettato per Linux (Ubuntu 22.04+)${NC}"
  echo "   Per macOS, usa: bundle install && bundle exec rake db:migrate"
  exit 1
fi
echo -e "${GREEN}✓ Sistema Linux rilevato${NC}"

# ========================================================================
# STEP 2: Check prerequisites
# ========================================================================
echo -e "\n${YELLOW}[STEP 2/10]${NC} Verifica prerequisiti..."

MISSING=""

# Check Ruby
if command -v ruby &> /dev/null; then
  RUBY_VERSION=$(ruby -v | cut -d' ' -f2)
  echo -e "${GREEN}✓ Ruby $RUBY_VERSION installato${NC}"
else
  MISSING="$MISSING ruby-full"
  echo -e "${RED}✗ Ruby non trovato${NC}"
fi

# Check Bundler
if command -v bundle &> /dev/null; then
  echo -e "${GREEN}✓ Bundler installato${NC}"
else
  MISSING="$MISSING ruby-bundler"
  echo -e "${RED}✗ Bundler non trovato${NC}"
fi

# Check PostgreSQL client
if command -v psql &> /dev/null; then
  echo -e "${GREEN}✓ PostgreSQL client installato${NC}"
else
  MISSING="$MISSING postgresql-client"
  echo -e "${RED}✗ PostgreSQL client non trovato${NC}"
fi

# Check build essentials (needed for native gems)
if dpkg -l | grep -q build-essential; then
  echo -e "${GREEN}✓ build-essential installato${NC}"
else
  MISSING="$MISSING build-essential"
  echo -e "${RED}✗ build-essential non trovato${NC}"
fi

# Check libpq-dev (needed for pg gem)
if dpkg -l | grep -q libpq-dev; then
  echo -e "${GREEN}✓ libpq-dev installato${NC}"
else
  MISSING="$MISSING libpq-dev"
  echo -e "${RED}✗ libpq-dev non trovato${NC}"
fi

if [ ! -z "$MISSING" ]; then
  echo ""
  echo -e "${YELLOW}Pacchetti mancanti. Installare con:${NC}"
  echo -e "${CYAN}  sudo apt update && sudo apt install -y $MISSING${NC}"
  exit 1
fi

# ========================================================================
# STEP 3: Install Ruby dependencies
# ========================================================================
echo -e "\n${YELLOW}[STEP 3/10]${NC} Installazione dipendenze Ruby..."

bundle config set --local path 'vendor/bundle'
bundle install --quiet
echo -e "${GREEN}✓ Dipendenze Ruby installate in vendor/bundle${NC}"

# ========================================================================
# STEP 4: Setup .env file
# ========================================================================
echo -e "\n${YELLOW}[STEP 4/10]${NC} Configurazione ambiente (.env)..."

if [ -f ".env" ]; then
  echo -e "${GREEN}✓ File .env esistente trovato${NC}"
  source .env
else
  if [ -f ".env.example" ]; then
    cp .env.example .env
    echo -e "${GREEN}✓ File .env creato da .env.example${NC}"
  else
    echo -e "${YELLOW}Creazione .env da template...${NC}"
    LOCAL_IP=$(hostname -I | awk '{print $1}' || echo "localhost")
    cat > .env << ENVEOF
# Database (IMPORTANTE: sostituisci la password!)
DATABASE_URL=postgresql://${DB_USER}:YOUR_PASSWORD_HERE@localhost:5432/${DB_NAME}

# Server
PORT=${DEFAULT_PORT}
RACK_ENV=production
SERVER_BASE_URL=http://${LOCAL_IP}:${DEFAULT_PORT}

# Switch Integration
SWITCH_WEBHOOK_BASE_URL=http://192.168.1.162:51088
SWITCH_WEBHOOK_PREFIX=/scripting
SWITCH_API_KEY=
SWITCH_SIMULATION=false

# Storage Cleanup (giorni di retention)
DAYS_TO_KEEP=45

# FTP Polling (opzionale)
# FTP_HOST=
# FTP_USER=
# FTP_PASS=
# FTP_PORT=21
# FTP_PATH=/orders/
# FTP_POLL_INTERVAL=60
ENVEOF
    echo -e "${GREEN}✓ File .env creato${NC}"
  fi
  
  echo ""
  echo -e "${RED}⚠️  IMPORTANTE: Modifica il file .env con le tue credenziali!${NC}"
  echo -e "   ${CYAN}nano .env${NC}"
  echo ""
  read -p "Premi INVIO quando hai configurato .env..." 
  source .env
fi

# Verify DATABASE_URL is set
if [ -z "$DATABASE_URL" ]; then
  echo -e "${RED}❌ DATABASE_URL non configurata in .env${NC}"
  exit 1
fi

# ========================================================================
# STEP 5: Setup PostgreSQL user
# ========================================================================
echo -e "\n${YELLOW}[STEP 5/10]${NC} Configurazione utente PostgreSQL..."

# Try to create user (will fail silently if exists)
sudo -u postgres psql -c "CREATE USER ${DB_USER} WITH ENCRYPTED PASSWORD 'Change_Me_123';" 2>/dev/null || true
sudo -u postgres psql -c "ALTER USER ${DB_USER} CREATEDB;" 2>/dev/null || true
echo -e "${GREEN}✓ Utente PostgreSQL configurato${NC}"
echo -e "${YELLOW}   (Ricorda di cambiare la password in .env)${NC}"

# ========================================================================
# STEP 6: Create storage directories
# ========================================================================
echo -e "\n${YELLOW}[STEP 6/10]${NC} Creazione directory storage..."

mkdir -p storage
mkdir -p storage/aggregated
mkdir -p storage/backups
chmod 755 storage
chmod 755 storage/aggregated
chmod 755 storage/backups
echo -e "${GREEN}✓ Directory storage create${NC}"

# ========================================================================
# STEP 7: Database setup
# ========================================================================
echo -e "\n${YELLOW}[STEP 7/10]${NC} Setup database..."

if [ "$RESET_MODE" == "true" ]; then
  echo -e "${RED}Cancellazione database esistente...${NC}"
  bundle exec rake db:drop 2>/dev/null || true
fi

# Create database
echo -e "${YELLOW}  → Creazione database...${NC}"
bundle exec rake db:create 2>/dev/null || true

# Run migrations
echo -e "${YELLOW}  → Esecuzione migrazioni...${NC}"
bundle exec rake db:migrate
if [ $? -ne 0 ]; then
  echo -e "${RED}❌ Migrazione fallita${NC}"
  exit 1
fi

echo -e "${GREEN}✓ Database configurato con successo${NC}"

# ========================================================================
# STEP 8: Add missing columns (safety net)
# ========================================================================
echo -e "\n${YELLOW}[STEP 8/10]${NC} Verifica colonne aggiuntive..."

psql "$DATABASE_URL" << 'SQLEOF'
-- Orders table enhancements
ALTER TABLE orders ADD COLUMN IF NOT EXISTS customer_name VARCHAR;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS customer_note TEXT;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS source VARCHAR DEFAULT 'api';

-- Print flows Photoshop actions
ALTER TABLE print_flows ADD COLUMN IF NOT EXISTS azione_photoshop_enabled BOOLEAN DEFAULT false;
ALTER TABLE print_flows ADD COLUMN IF NOT EXISTS azione_photoshop_options TEXT;
ALTER TABLE print_flows ADD COLUMN IF NOT EXISTS default_azione_photoshop VARCHAR;

-- Products cut file management
ALTER TABLE products ADD COLUMN IF NOT EXISTS has_cut_file BOOLEAN DEFAULT FALSE;
ALTER TABLE products ADD COLUMN IF NOT EXISTS cut_file_path VARCHAR;
ALTER TABLE products ADD COLUMN IF NOT EXISTS is_dependent BOOLEAN DEFAULT FALSE;
ALTER TABLE products ADD COLUMN IF NOT EXISTS master_product_id INTEGER;

-- Backup configs
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

-- Aggregated jobs
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

-- Indexes
CREATE INDEX IF NOT EXISTS idx_aggregated_jobs_status ON aggregated_jobs(status);
CREATE INDEX IF NOT EXISTS idx_aggregated_job_items_job_id ON aggregated_job_items(aggregated_job_id);
CREATE INDEX IF NOT EXISTS idx_aggregated_job_items_item_id ON aggregated_job_items(order_item_id);
CREATE INDEX IF NOT EXISTS idx_products_master ON products(master_product_id);

-- CRM TABLES
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

echo -e "${GREEN}✓ Colonne aggiuntive verificate${NC}"

# ========================================================================
# STEP 9: Verify installation
# ========================================================================
echo -e "\n${YELLOW}[STEP 9/10]${NC} Verifica installazione..."

# Count tables
TABLE_COUNT=$(psql "$DATABASE_URL" -t -c "SELECT count(*) FROM information_schema.tables WHERE table_schema='public' AND table_type='BASE TABLE';" 2>&1 | tr -d ' ')

if [ "$TABLE_COUNT" -lt 10 ]; then
  echo -e "${RED}❌ Installazione incompleta: solo $TABLE_COUNT tabelle (minimo 10)${NC}"
  exit 1
fi

echo -e "${GREEN}✓ Database verificato: $TABLE_COUNT tabelle create${NC}"

# Test rake tasks
if bundle exec rake -T > /dev/null 2>&1; then
  echo -e "${GREEN}✓ Rake tasks funzionanti${NC}"
else
  echo -e "${RED}✗ Problema con rake tasks${NC}"
fi

# ========================================================================
# STEP 10: Final summary
# ========================================================================
echo -e "\n${YELLOW}[STEP 10/10]${NC} Riepilogo installazione..."

LOCAL_IP=$(hostname -I | awk '{print $1}' || echo "localhost")

echo ""
echo -e "${GREEN}╔═══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║                                                               ║${NC}"
echo -e "${GREEN}║     ✅ INSTALLAZIONE COMPLETATA CON SUCCESSO!                 ║${NC}"
echo -e "${GREEN}║                                                               ║${NC}"
echo -e "${GREEN}╚═══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${CYAN}${BOLD}PROSSIMI PASSI:${NC}"
echo ""
echo -e "  ${YELLOW}1.${NC} Avvia il server manualmente:"
echo -e "     ${CYAN}bundle exec puma -b tcp://0.0.0.0:${DEFAULT_PORT} -p ${DEFAULT_PORT} config.ru${NC}"
echo ""
echo -e "  ${YELLOW}2.${NC} OPPURE installa come servizio systemd:"
echo -e "     ${CYAN}sudo bash setup_service.sh${NC}"
echo -e "     ${CYAN}sudo systemctl enable print-orchestrator${NC}"
echo -e "     ${CYAN}sudo systemctl start print-orchestrator${NC}"
echo ""
echo -e "  ${YELLOW}3.${NC} Accedi all'applicazione:"
echo -e "     ${CYAN}http://${LOCAL_IP}:${DEFAULT_PORT}${NC}"
echo ""
echo -e "${CYAN}${BOLD}DOCUMENTAZIONE:${NC}"
echo -e "  - Installazione: INSTALL_LINUX.md"
echo -e "  - Switch Workflow: SWITCH_WORKFLOW.md"
echo -e "  - API: README.md"
echo ""
