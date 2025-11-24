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
  echo -e "${YELLOW}⚠ .env not found. Creating template...${NC}"
  cat > .env << 'ENVEOF'
DATABASE_URL=postgresql://orchestrator:password@localhost:5432/print_orchestrator_development
SWITCH_WEBHOOK_URL=http://192.168.1.162/webhook/
SERVER_BASE_URL=http://localhost:5000
PORT=5000
RACK_ENV=development
ENVEOF
  echo -e "${YELLOW}⚠ Edit .env with your values!${NC}"
fi
echo -e "${GREEN}✓ Environment configuration ready${NC}"

# Step 4: Create storage directory
echo -e "\n${YELLOW}[4/7]${NC} Creating storage directory..."
mkdir -p storage
chmod 755 storage
echo -e "${GREEN}✓ Storage directory ready${NC}"

# Step 5: Database setup
echo -e "\n${YELLOW}[5/7]${NC} Setting up database..."
bundle exec rake db:migrate
bundle exec rake db:seed
echo -e "${GREEN}✓ Database ready${NC}"

# Step 6: Health check
echo -e "\n${YELLOW}[6/7]${NC} Testing database connection..."
bundle exec rake db:migrate:status > /dev/null 2>&1
if [ $? -eq 0 ]; then
  echo -e "${GREEN}✓ Database connected${NC}"
else
  echo -e "${RED}✗ Database connection failed${NC}"
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
