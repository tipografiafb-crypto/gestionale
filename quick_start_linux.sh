#!/bin/bash
# Quick Start Script for Print Order Orchestrator on Linux

echo "🚀 Print Order Orchestrator - Quick Start Setup"
echo "================================================"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if running on Linux
if [[ ! "$OSTYPE" =~ ^linux ]]; then
  echo -e "${RED}✗ This script is for Linux only${NC}"
  exit 1
fi

# Step 1: Check prerequisites
echo -e "\n${YELLOW}[1/7]${NC} Checking prerequisites..."
command -v ruby &> /dev/null || { echo -e "${RED}✗ Ruby not found${NC}"; exit 1; }
command -v bundle &> /dev/null || { echo -e "${RED}✗ Bundler not found${NC}"; exit 1; }
command -v psql &> /dev/null || { echo -e "${RED}✗ PostgreSQL client not found${NC}"; exit 1; }
echo -e "${GREEN}✓ All prerequisites found${NC}"

# Step 2: Install Ruby gems
echo -e "\n${YELLOW}[2/7]${NC} Installing Ruby dependencies..."
bundle install --path vendor/bundle
echo -e "${GREEN}✓ Dependencies installed${NC}"

# Step 3: Create .env if not exists
echo -e "\n${YELLOW}[3/7]${NC} Checking environment configuration..."
if [ ! -f ".env" ]; then
  if [ -f ".env.example" ]; then
    echo -e "${GREEN}✓ Copying .env from .env.example${NC}"
    cp .env.example .env
    echo -e "${YELLOW}⚠ IMPORTANTE: Modifica il file .env e aggiorna la password PostgreSQL!${NC}"
  else
    echo -e "${YELLOW}⚠ .env not found. Creating template...${NC}"
    cat > .env << 'ENVEOF'
DATABASE_URL=postgresql://orchestrator_user:paolo@localhost:5432/print_orchestrator_dev
RACK_ENV=production
PORT=5000
SERVER_BASE_URL=http://192.168.1.100:5000
SWITCH_WEBHOOK_BASE_URL=http://192.168.1.162:51088
SWITCH_WEBHOOK_PREFIX=/scripting
SWITCH_API_KEY=
SWITCH_SIMULATION=false
FTP_HOST=c72965.sgvps.net
FTP_USER=widegest@thepickshouse.com
FTP_PASS=WidegestImport24
FTP_PATH=/test/
FTP_POLL_INTERVAL=60
ENVEOF
    echo -e "${YELLOW}⚠ Edit .env with your values!${NC}"
  fi
fi
echo -e "${GREEN}✓ Environment configuration ready${NC}"

# Step 3.5: Create PostgreSQL user if not exists
echo -e "\n${YELLOW}[3.5/7]${NC} Setting up PostgreSQL user..."
sudo -u postgres psql -c "CREATE USER orchestrator_user WITH ENCRYPTED PASSWORD 'paolo';" 2>/dev/null || true
sudo -u postgres psql -c "ALTER USER orchestrator_user CREATEDB;" 2>/dev/null || true
echo -e "${GREEN}✓ PostgreSQL user ready${NC}"

# Step 4: Create storage directory
echo -e "\n${YELLOW}[4/7]${NC} Creating storage directories..."
mkdir -p storage
mkdir -p storage/aggregated
chmod 755 storage
chmod 755 storage/aggregated
echo -e "${GREEN}✓ Storage directories ready${NC}"

# Step 5: Database setup
echo -e "\n${YELLOW}[5/7]${NC} Setting up database..."
source .env  # Carica variabili dal .env

# Create database if not exists
echo -e "${YELLOW}  → Creating database...${NC}"
bundle exec rake db:create 2>/dev/null || true

# Run all migrations
echo -e "${YELLOW}  → Running migrations...${NC}"
bundle exec rake db:migrate
if [ $? -ne 0 ]; then
  echo -e "${RED}❌ Migration failed${NC}"
  exit 1
fi

# Also run setup_complete for additional setup
bundle exec rake db:setup_complete 2>/dev/null || true

echo -e "${GREEN}✓ Database ready${NC}"

# Step 5.5: Verify and add all missing columns to orders
echo -e "\n${YELLOW}[5.5/7]${NC} Ensuring all orders columns exist..."
psql "$DATABASE_URL" << 'SQLEOF'
ALTER TABLE orders 
  ADD COLUMN IF NOT EXISTS customer_name VARCHAR,
  ADD COLUMN IF NOT EXISTS customer_note text,
  ADD COLUMN IF NOT EXISTS source VARCHAR DEFAULT 'api';
SQLEOF
if [ $? -eq 0 ]; then
  echo -e "${GREEN}✓ All orders columns verified${NC}"
else
  echo -e "${YELLOW}⚠ Could not add orders columns (they may already exist)${NC}"
fi

# Step 5.5b: Add Azione Photoshop columns to print_flows
echo -e "\n${YELLOW}[5.5b/7]${NC} Adding Azione Photoshop columns to print_flows..."
psql "$DATABASE_URL" << 'SQLEOF'
ALTER TABLE print_flows 
  ADD COLUMN IF NOT EXISTS azione_photoshop_enabled boolean DEFAULT false,
  ADD COLUMN IF NOT EXISTS azione_photoshop_options text,
  ADD COLUMN IF NOT EXISTS default_azione_photoshop varchar;
SQLEOF
if [ $? -eq 0 ]; then
  echo -e "${GREEN}✓ Azione Photoshop columns added${NC}"
else
  echo -e "${YELLOW}⚠ Could not add columns (they may already exist)${NC}"
fi

# Step 5.6: Create backup_configs table with SSH columns
echo -e "\n${YELLOW}[5.6/7]${NC} Creating backup_configs table..."
psql "$DATABASE_URL" << 'SQLEOF'
CREATE TABLE IF NOT EXISTS backup_configs (
  id SERIAL PRIMARY KEY,
  remote_ip VARCHAR(255),
  remote_path VARCHAR(1024),
  ssh_username VARCHAR(255),
  ssh_password VARCHAR(1024),
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Add SSH columns if they don't exist (for existing databases)
ALTER TABLE backup_configs ADD COLUMN IF NOT EXISTS ssh_username VARCHAR(255);
ALTER TABLE backup_configs ADD COLUMN IF NOT EXISTS ssh_password VARCHAR(1024);
SQLEOF
if [ $? -eq 0 ]; then
  echo -e "${GREEN}✓ backup_configs table created with SSH support${NC}"
else
  echo -e "${YELLOW}⚠ Could not create backup_configs table (it may already exist)${NC}"
fi

# Step 5.7: Create aggregated_jobs tables
echo -e "\n${YELLOW}[5.7/7]${NC} Creating aggregated_jobs tables..."
psql "$DATABASE_URL" << 'SQLEOF'
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
  notes TEXT,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

ALTER TABLE aggregated_jobs ADD COLUMN IF NOT EXISTS aggregated_file_url TEXT;
ALTER TABLE aggregated_jobs ADD COLUMN IF NOT EXISTS aggregated_filename VARCHAR(255);
ALTER TABLE aggregated_jobs ADD COLUMN IF NOT EXISTS aggregated_at TIMESTAMP;
ALTER TABLE aggregated_jobs ADD COLUMN IF NOT EXISTS completed_at TIMESTAMP;
ALTER TABLE aggregated_jobs ADD COLUMN IF NOT EXISTS preprint_sent_at TIMESTAMP;
ALTER TABLE aggregated_jobs ADD COLUMN IF NOT EXISTS notes TEXT;

CREATE TABLE IF NOT EXISTS aggregated_job_items (
  id SERIAL PRIMARY KEY,
  aggregated_job_id INTEGER NOT NULL REFERENCES aggregated_jobs(id) ON DELETE CASCADE,
  order_item_id INTEGER NOT NULL REFERENCES order_items(id) ON DELETE CASCADE,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  UNIQUE(aggregated_job_id, order_item_id)
);

CREATE INDEX IF NOT EXISTS idx_aggregated_jobs_status ON aggregated_jobs(status);
CREATE INDEX IF NOT EXISTS idx_aggregated_job_items_job_id ON aggregated_job_items(aggregated_job_id);
CREATE INDEX IF NOT EXISTS idx_aggregated_job_items_item_id ON aggregated_job_items(order_item_id);
SQLEOF
if [ $? -eq 0 ]; then
  echo -e "${GREEN}✓ Aggregated jobs tables created${NC}"
else
  echo -e "${YELLOW}⚠ Could not create aggregated_jobs tables (they may already exist)${NC}"
fi

# Step 5.8: Add SSH port column to backup_configs
echo -e "\n${YELLOW}[5.8/7]${NC} Adding SSH port column to backup_configs..."
psql "$DATABASE_URL" << 'SQLEOF'
ALTER TABLE backup_configs ADD COLUMN IF NOT EXISTS ssh_port INTEGER DEFAULT 22;
SQLEOF
if [ $? -eq 0 ]; then
  echo -e "${GREEN}✓ SSH port column added${NC}"
else
  echo -e "${YELLOW}⚠ Could not add SSH port column (it may already exist)${NC}"
fi

# Step 6: Health check
echo -e "\n${YELLOW}[6/7]${NC} Testing database connection..."
TABLE_COUNT=$(psql "$DATABASE_URL" -t -c "SELECT count(*) FROM information_schema.tables WHERE table_schema='public' AND table_type='BASE TABLE';" 2>/dev/null || echo "0")

if [ "$TABLE_COUNT" -gt 13 ]; then
  echo -e "${GREEN}✓ Database connected ($TABLE_COUNT tables created)${NC}"
else
  echo -e "${RED}✗ Database setup incomplete (only $TABLE_COUNT tables, expected 16+)${NC}"
  exit 1
fi

echo -e "\n${GREEN}================================================${NC}"
echo -e "${GREEN}✓ Setup Complete!${NC}"
echo -e "${GREEN}================================================${NC}"
echo -e "\n${YELLOW}Next steps:${NC}"
echo -e "1. Edit .env with your configuration"
echo -e "2. Start the server: bundle exec puma -b tcp://0.0.0.0:5000 -p 5000 config.ru"
echo -e "3. Open browser: http://localhost:5000"
echo -e "\n${YELLOW}Documentation:${NC}"
echo -e "- Installation: INSTALL_LINUX.md"
echo -e "- Switch Workflow: SWITCH_WORKFLOW.md"
echo -e "- API Docs: README.md"
