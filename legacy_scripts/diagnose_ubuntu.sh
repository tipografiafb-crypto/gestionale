#!/bin/bash
# Diagnostic script to identify database issues on Ubuntu

echo "🔍 Print Order Orchestrator - Ubuntu Diagnostic"
echo "==============================================="

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Load .env
if [ ! -f ".env" ]; then
  echo -e "${RED}❌ .env not found${NC}"
  exit 1
fi
source .env

echo -e "\n${YELLOW}[1] Checking PostgreSQL connection...${NC}"
psql "$DATABASE_URL" -c "SELECT version();" > /dev/null 2>&1
if [ $? -eq 0 ]; then
  echo -e "${GREEN}✓ PostgreSQL connection OK${NC}"
else
  echo -e "${RED}✗ Cannot connect to PostgreSQL${NC}"
  echo -e "${YELLOW}Check DATABASE_URL in .env: $DATABASE_URL${NC}"
  exit 1
fi

echo -e "\n${YELLOW}[2] Counting tables in database...${NC}"
TABLE_COUNT=$(psql "$DATABASE_URL" -t -c "SELECT count(*) FROM information_schema.tables WHERE table_schema='public';" 2>&1 | tr -d ' ')
echo -e "Found: ${GREEN}$TABLE_COUNT tables${NC}"

if [ "$TABLE_COUNT" -lt 5 ]; then
  echo -e "${RED}⚠ Very few tables! Database might not be initialized.${NC}"
  echo -e "${YELLOW}Run: bash quick_start_ubuntu_complete.sh${NC}"
fi

echo -e "\n${YELLOW}[3] Checking orders table...${NC}"
psql "$DATABASE_URL" -c "SELECT COUNT(*) FROM orders LIMIT 1;" > /dev/null 2>&1
if [ $? -eq 0 ]; then
  ORDERS=$(psql "$DATABASE_URL" -t -c "SELECT count(*) FROM orders;" 2>&1 | tr -d ' ')
  echo -e "${GREEN}✓ orders table exists ($ORDERS rows)${NC}"
  
  # Check columns
  psql "$DATABASE_URL" -c "\d orders" | grep customer_note > /dev/null 2>&1
  if [ $? -eq 0 ]; then
    echo -e "${GREEN}  ✓ customer_note column exists${NC}"
  else
    echo -e "${RED}  ✗ customer_note column MISSING${NC}"
  fi
  
  psql "$DATABASE_URL" -c "\d orders" | grep customer_name > /dev/null 2>&1
  if [ $? -eq 0 ]; then
    echo -e "${GREEN}  ✓ customer_name column exists${NC}"
  else
    echo -e "${RED}  ✗ customer_name column MISSING${NC}"
  fi
else
  echo -e "${RED}✗ orders table NOT FOUND${NC}"
  echo -e "${YELLOW}Run: bash quick_start_ubuntu_complete.sh${NC}"
fi

echo -e "\n${YELLOW}[4] Listing all tables...${NC}"
psql "$DATABASE_URL" -t -c "SELECT tablename FROM pg_tables WHERE schemaname='public' ORDER BY tablename;" 2>&1 | while read table; do
  if [ ! -z "$table" ]; then
    COUNT=$(psql "$DATABASE_URL" -t -c "SELECT COUNT(*) FROM $table;" 2>&1 | tr -d ' ')
    printf "  %-30s %s rows\n" "$table:" "$COUNT"
  fi
done

echo -e "\n${YELLOW}[5] Checking .env configuration...${NC}"
echo -e "DATABASE_URL is set: ${GREEN}$([ -z "$DATABASE_URL" ] && echo "NO" || echo "YES")${NC}"
echo -e "SWITCH_WEBHOOK_BASE_URL: ${GREEN}${SWITCH_WEBHOOK_BASE_URL:-not set}${NC}"

echo -e "\n${GREEN}===============================================${NC}"
echo -e "${YELLOW}If tables are missing, run:${NC}"
echo -e "  ${GREEN}bash quick_start_ubuntu_complete.sh${NC}"
