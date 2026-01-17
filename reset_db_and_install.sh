#!/bin/bash
# Consolidated Installer for Print Orchestrator

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}Aggiornamento configurazione...${NC}"
if [ -f "quick_start_linux.sh" ]; then
    sed -i "s/Paolo_Strong_123!/Paolo_Strong_123/g" quick_start_linux.sh
fi

echo -e "${YELLOW}Reset del database...${NC}"
sudo -u postgres psql -c "DROP DATABASE IF EXISTS print_orchestrator_dev;"
sudo -u postgres psql -c "DROP USER IF EXISTS orchestrator_user;"
sudo -u postgres psql -c "CREATE USER orchestrator_user WITH ENCRYPTED PASSWORD 'Paolo_Strong_123';"
sudo -u postgres psql -c "ALTER USER orchestrator_user CREATEDB;"
sudo -u postgres psql -c "CREATE DATABASE print_orchestrator_dev OWNER orchestrator_user;"

echo -e "${YELLOW}Generazione file .env...${NC}"
cat > .env << 'ENVEOF'
DATABASE_URL=postgresql://orchestrator_user:Paolo_Strong_123@localhost:5432/print_orchestrator_dev
RACK_ENV=production
PORT=5000
SERVER_BASE_URL=http://localhost:5000
ENVEOF

echo -e "${YELLOW}Installazione dipendenze e migrazione...${NC}"
bundle install
bundle exec rake db:migrate

echo -e "${GREEN}Installazione completata con successo!${NC}"
