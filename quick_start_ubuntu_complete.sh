#!/bin/bash
# Complete database setup script for Ubuntu - Creates everything from scratch
# Use this if quick_start_linux.sh has issues

set -e  # Exit on any error

echo "🚀 Print Order Orchestrator - Complete Ubuntu Setup"
echo "===================================================="

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Load environment
if [ ! -f ".env" ]; then
  echo -e "${RED}❌ .env file not found. Please copy .env.example to .env first.${NC}"
  exit 1
fi

source .env

echo -e "\n${YELLOW}[Step 1]${NC} Dropping and recreating database from scratch..."

# Drop existing database if exists
psql -U postgres -h localhost -c "DROP DATABASE IF EXISTS print_orchestrator_dev;" 2>/dev/null || true
echo -e "${GREEN}✓ Dropped existing database${NC}"

# Create fresh database
psql -U postgres -h localhost -c "CREATE DATABASE print_orchestrator_dev OWNER orchestrator_user;" 2>/dev/null
echo -e "${GREEN}✓ Created fresh database${NC}"

echo -e "\n${YELLOW}[Step 2]${NC} Running migrations to create all tables..."

bundle exec rake db:create 2>/dev/null || true
bundle exec rake db:migrate

echo -e "${GREEN}✓ All migrations completed${NC}"

echo -e "\n${YELLOW}[Step 3]${NC} Verifying all tables were created..."

TABLES=$(psql "$DATABASE_URL" -t -c "SELECT count(*) FROM information_schema.tables WHERE table_schema='public' AND table_type='BASE TABLE';" 2>&1 | tr -d ' ')

if [ "$TABLES" -lt 10 ]; then
  echo -e "${RED}❌ Only $TABLES tables created, expected 15+${NC}"
  exit 1
fi

echo -e "${GREEN}✓ $TABLES tables created successfully${NC}"

echo -e "\n${YELLOW}[Step 4]${NC} Adding missing columns to existing tables..."

# Ensure orders table has all columns
psql "$DATABASE_URL" << 'SQLEOF'
ALTER TABLE orders 
  ADD COLUMN IF NOT EXISTS customer_name VARCHAR,
  ADD COLUMN IF NOT EXISTS customer_note text,
  ADD COLUMN IF NOT EXISTS source VARCHAR DEFAULT 'api';
SQLEOF
echo -e "${GREEN}✓ Orders columns verified${NC}"

# Ensure print_flows has Azione Photoshop columns
psql "$DATABASE_URL" << 'SQLEOF'
ALTER TABLE print_flows 
  ADD COLUMN IF NOT EXISTS azione_photoshop_enabled boolean DEFAULT false,
  ADD COLUMN IF NOT EXISTS azione_photoshop_options text,
  ADD COLUMN IF NOT EXISTS default_azione_photoshop varchar;
SQLEOF
echo -e "${GREEN}✓ Print flows columns verified${NC}"

# Create backup_configs if missing
psql "$DATABASE_URL" << 'SQLEOF'
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
SQLEOF
echo -e "${GREEN}✓ Backup configs table verified${NC}"

# Create aggregated_jobs tables
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

CREATE INDEX IF NOT EXISTS idx_aggregated_jobs_status ON aggregated_jobs(status);
CREATE INDEX IF NOT EXISTS idx_aggregated_job_items_job_id ON aggregated_job_items(aggregated_job_id);
CREATE INDEX IF NOT EXISTS idx_aggregated_job_items_item_id ON aggregated_job_items(order_item_id);
SQLEOF
echo -e "${GREEN}✓ Aggregated jobs tables verified${NC}"

echo -e "\n${YELLOW}[Step 5]${NC} Final verification..."

# Count all tables
ALL_TABLES=$(psql "$DATABASE_URL" -t -c "SELECT string_agg(tablename, ', ') FROM pg_tables WHERE schemaname='public';" 2>&1 | tr -d ' ')
TABLE_COUNT=$(psql "$DATABASE_URL" -t -c "SELECT count(*) FROM information_schema.tables WHERE table_schema='public' AND table_type='BASE TABLE';" 2>&1 | tr -d ' ')

echo -e "${GREEN}✓ Total tables: $TABLE_COUNT${NC}"
echo -e "${GREEN}Tables: ${ALL_TABLES}${NC}"

echo -e "\n${GREEN}===================================================${NC}"
echo -e "${GREEN}✅ Database setup complete!${NC}"
echo -e "${GREEN}===================================================${NC}"
echo -e "\n${YELLOW}Next steps:${NC}"
echo -e "1. Start the server: bundle exec puma -b tcp://0.0.0.0:5000 -p 5000 config.ru"
echo -e "2. Open browser: http://localhost:5000"
echo -e "\n${YELLOW}If you still have issues, check:${NC}"
echo -e "- DATABASE_URL is correct in .env"
echo -e "- PostgreSQL user 'orchestrator_user' exists with password 'paolo'"
echo -e "- PostgreSQL service is running"
