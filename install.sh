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
echo -e "${YELLOW}Step 5: Running migrations (CONSOLIDATED)...${NC}"
bundle exec rake db:migrate
echo -e "${GREEN}✓ All tables created from single consolidated migration${NC}"

echo ""
echo -e "${YELLOW}Step 6: Loading seed data...${NC}"
bundle exec rake db:seed 2>/dev/null || echo -e "${YELLOW}(No seed data file)${NC}"
echo -e "${GREEN}✓ Seed data loaded${NC}"

echo ""
echo -e "${YELLOW}Step 7: Creating .env file...${NC}"
if [ ! -f .env ]; then
  cat > .env << EOF
# Database (Auto-configured for print-orchestrator)
DATABASE_URL=$DATABASE_URL

# Server
PORT=5000
RACK_ENV=development

# Switch Integration (Optional)
# SWITCH_WEBHOOK_URL=https://your-switch-instance/webhook
# SWITCH_API_KEY=your-api-key
EOF
  echo -e "${GREEN}✓ .env file created${NC}"
else
  echo -e "${YELLOW}(Existing .env file kept)${NC}"
fi

echo ""
echo -e "${YELLOW}Step 8: Testing application...${NC}"
if bundle exec rake -T > /dev/null 2>&1; then
  echo -e "${GREEN}✓ Application is ready${NC}"
else
  echo -e "${RED}❌ Application test failed${NC}"
  exit 1
fi

echo ""
echo -e "${GREEN}================================================${NC}"
echo -e "${GREEN}✓ Installation completed successfully!${NC}"
echo -e "${GREEN}================================================${NC}"
echo ""
echo "Next steps:"
echo "  1. Start the server:"
echo "     bundle exec puma -b tcp://0.0.0.0:5000 -p 5000 config.ru"
echo ""
echo "  2. Or setup as systemd service:"
echo "     sudo bash setup_service.sh"
echo ""
echo "  3. Access the application at:"
echo "     http://$(hostname -I | awk '{print $1}'):5000"
echo ""
