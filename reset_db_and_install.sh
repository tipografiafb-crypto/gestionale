#!/bin/bash
# Script to reset database and run fresh installation

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}Aggiornamento script di installazione...${NC}"
# Assicuriamoci che la password sia corretta nel quick_start_linux.sh
sed -i "s/Paolo_Strong_123!/Paolo_Strong_123/g" quick_start_linux.sh
sed -i "s/password 'paolo'/password 'Paolo_Strong_123'/g" quick_start_linux.sh

echo -e "${YELLOW}Reset del database in corso...${NC}"
sudo -u postgres psql -c "DROP DATABASE IF EXISTS print_orchestrator_dev;"
sudo -u postgres psql -c "DROP USER IF EXISTS orchestrator_user;"

echo -e "${YELLOW}Creazione nuovo utente e database...${NC}"
sudo -u postgres psql -c "CREATE USER orchestrator_user WITH ENCRYPTED PASSWORD 'Paolo_Strong_123';"
sudo -u postgres psql -c "ALTER USER orchestrator_user CREATEDB;"
sudo -u postgres psql -c "CREATE DATABASE print_orchestrator_dev OWNER orchestrator_user;"

echo -e "${YELLOW}Avvio installazione pulita...${NC}"
bash quick_start_linux.sh
