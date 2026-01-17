#!/bin/bash
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}Inizio installazione Orchestratore...${NC}"

# Check for PostgreSQL
if ! command -v psql &> /dev/null; then
    echo -e "${RED}Errore: PostgreSQL non è installato.${NC}"
    exit 1
fi

echo -e "${YELLOW}Configurazione Database...${NC}"
# Use sudo only if necessary, but try to handle common Ubuntu setups
sudo -u postgres psql -c "DROP DATABASE IF EXISTS print_orchestrator_dev;" 2>/dev/null
sudo -u postgres psql -c "DROP USER IF EXISTS orchestrator_user;" 2>/dev/null
sudo -u postgres psql -c "CREATE USER orchestrator_user WITH ENCRYPTED PASSWORD 'Paolo_Strong_123' CREATEDB;"
sudo -u postgres psql -c "CREATE DATABASE print_orchestrator_dev OWNER orchestrator_user;"

echo -e "${YELLOW}Configurazione Ambiente...${NC}"
cat > .env << 'ENVEOF'
DATABASE_URL=postgresql://orchestrator_user:Paolo_Strong_123@localhost:5432/print_orchestrator_dev
RACK_ENV=production
PORT=5000
SERVER_BASE_URL=http://localhost:5000
ENVEOF

echo -e "${YELLOW}Installazione dipendenze Ruby...${NC}"
bundle install

echo -e "${YELLOW}Esecuzione Migrazioni...${NC}"
# Use a fresh schema load approach
rm -f db/schema.rb
export DATABASE_URL=postgresql://orchestrator_user:Paolo_Strong_123@localhost:5432/print_orchestrator_dev
bundle exec rake db:migrate

echo -e "${GREEN}Installazione completata con successo!${NC}"
echo -e "Puoi avviare il server con: ${YELLOW}bundle exec puma -p 5000 config.ru${NC}"
