#!/bin/bash
set -e

echo "================================================"
echo "Print Order Orchestrator - Installation Script"
echo "================================================"
echo ""

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if running on Linux
if [[ ! "$OSTYPE" == "linux-gnu"* ]]; then
  echo -e "${RED}❌ This script is designed for Linux (Ubuntu 24.04+)${NC}"
  exit 1
fi

echo -e "${YELLOW}Step 1: Checking prerequisites...${NC}"

# Check Ruby
if ! command -v ruby &> /dev/null; then
  echo -e "${RED}❌ Ruby not found. Install with: sudo apt install ruby-full${NC}"
  exit 1
fi
echo -e "${GREEN}✓ Ruby $(ruby -v)${NC}"

# Check Bundler
if ! command -v bundle &> /dev/null; then
  echo -e "${RED}❌ Bundler not found. Install with: gem install bundler${NC}"
  exit 1
fi
echo -e "${GREEN}✓ Bundler installed${NC}"

# Check PostgreSQL client
if ! command -v psql &> /dev/null; then
  echo -e "${RED}❌ PostgreSQL client not found. Install with: sudo apt install postgresql-client${NC}"
  exit 1
fi
echo -e "${GREEN}✓ PostgreSQL client installed${NC}"

echo ""
echo -e "${YELLOW}Step 2: Installing Ruby dependencies...${NC}"
bundle install --quiet
echo -e "${GREEN}✓ Dependencies installed${NC}"

echo ""
echo -e "${YELLOW}Step 3: Database setup...${NC}"

# Read database credentials from environment or prompt user
if [ -z "$DATABASE_URL" ]; then
  echo "PostgreSQL Connection Details:"
  read -p "  Host [localhost]: " PGHOST
  PGHOST=${PGHOST:-localhost}
  read -p "  Port [5432]: " PGPORT
  PGPORT=${PGPORT:-5432}
  read -p "  User [orchestrator_user]: " PGUSER
  PGUSER=${PGUSER:-orchestrator_user}
  read -sp "  Password: " PGPASSWORD
  echo ""
  read -p "  Database [print_orchestrator_dev]: " PGDATABASE
  PGDATABASE=${PGDATABASE:-print_orchestrator_dev}
  
  export PGHOST PGPORT PGUSER PGPASSWORD PGDATABASE
  export DATABASE_URL="postgresql://$PGUSER:$PGPASSWORD@$PGHOST:$PGPORT/$PGDATABASE"
fi

# Test connection
echo "Testing database connection..."
if PGPASSWORD="$PGPASSWORD" psql -h "$PGHOST" -U "$PGUSER" -d "$PGDATABASE" -c "SELECT 1" > /dev/null 2>&1; then
  echo -e "${GREEN}✓ Database connection successful${NC}"
else
  echo -e "${RED}❌ Could not connect to database${NC}"
  exit 1
fi

echo ""
echo -e "${YELLOW}Step 4: Dropping old database and recreating...${NC}"
bundle exec rake db:drop 2>/dev/null || true
bundle exec rake db:create
echo -e "${GREEN}✓ Database created${NC}"

echo ""
echo -e "${YELLOW}Step 5: Running migrations...${NC}"
bundle exec rake db:migrate
echo -e "${GREEN}✓ Migrations completed${NC}"

echo ""
echo -e "${YELLOW}Step 6: Loading seed data...${NC}"
bundle exec rake db:seed 2>/dev/null || echo -e "${YELLOW}(No seed data file)${NC}"
echo -e "${GREEN}✓ Seed data loaded${NC}"

echo ""
echo -e "${YELLOW}Step 7: Creating .env file...${NC}"
if [ ! -f .env ]; then
  cat > .env << EOF
# Database
DATABASE_URL=$DATABASE_URL

# Server
PORT=5000
RACK_ENV=development

# Enfocus Switch
SWITCH_WEBHOOK_BASE_URL=http://localhost:9000
SWITCH_API_KEY=your_api_key_here

# FTP Settings
FTP_HOST=your_ftp_host
FTP_PORT=21
FTP_USER=your_ftp_user
FTP_PASSWORD=your_ftp_password
FTP_DIRECTORY=/orders
EOF
  echo -e "${GREEN}✓ .env file created${NC}"
  echo -e "${YELLOW}  ⚠ Update .env with your Enfocus Switch and FTP credentials${NC}"
else
  echo -e "${GREEN}✓ .env file already exists${NC}"
fi

echo ""
echo "================================================"
echo -e "${GREEN}✅ Installation complete!${NC}"
echo "================================================"
echo ""
echo "Next steps:"
echo "  1. Update .env with your Enfocus Switch and FTP credentials"
echo "  2. Start the server: bundle exec puma -b tcp://0.0.0.0:5000 config.ru"
echo "  3. Open http://localhost:5000 in your browser"
echo ""
echo "For systemd service setup, run: sudo ./setup_service.sh"
echo ""
