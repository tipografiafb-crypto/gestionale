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
echo -e "${YELLOW}⚠ ATTENZIONE: Se stai aggiornando da una versione precedente,${NC}"
echo -e "${YELLOW}   resetta SEMPRE il database con db:drop + db:create${NC}"
bundle exec rake db:drop 2>/dev/null || true
bundle exec rake db:create
echo -e "${GREEN}✓ Database created${NC}"

echo ""
echo -e "${YELLOW}Step 5: Running migrations...${NC}"
DATABASE_URL="$DATABASE_URL" bundle exec rake db:migrate
if [ $? -ne 0 ]; then
  echo -e "${RED}❌ Migrations failed${NC}"
  exit 1
fi
echo -e "${GREEN}✓ All migrations executed${NC}"

echo ""
echo -e "${YELLOW}Step 5.5: Verifying tables were created...${NC}"
TABLE_COUNT=$(PGPASSWORD="$PGPASSWORD" psql -h "$PGHOST" -U "$PGUSER" -d "$PGDATABASE" -t -c "SELECT count(*) FROM information_schema.tables WHERE table_schema='public' AND table_type='BASE TABLE';")
if [ "$TABLE_COUNT" -lt 15 ]; then
  echo -e "${RED}❌ Tables not created! Only found $TABLE_COUNT tables (expected at least 15)${NC}"
  echo "Listing available tables:"
  PGPASSWORD="$PGPASSWORD" psql -h "$PGHOST" -U "$PGUSER" -d "$PGDATABASE" -c "\dt"
  exit 1
fi
echo -e "${GREEN}✓ All tables created successfully ($TABLE_COUNT tables)${NC}"

echo ""
echo -e "${YELLOW}Step 6: Adding missing columns...${NC}"
PGPASSWORD="$PGPASSWORD" psql -h "$PGHOST" -U "$PGUSER" -d "$PGDATABASE" << EOF
ALTER TABLE product_categories ADD COLUMN IF NOT EXISTS description TEXT;
ALTER TABLE print_machines ADD COLUMN IF NOT EXISTS description VARCHAR;
ALTER TABLE products ADD COLUMN IF NOT EXISTS description TEXT;

-- CRM TABLES
PGPASSWORD="$PGPASSWORD" psql -h "$PGHOST" -U "$PGUSER" -d "$PGDATABASE" << EOF
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
EOF
echo -e "${GREEN}✓ Missing columns added${NC}"

echo ""
echo -e "${YELLOW}Step 7: Loading seed data...${NC}"
bundle exec rake db:seed 2>/dev/null || echo -e "${YELLOW}(No seed data file)${NC}"
echo -e "${GREEN}✓ Seed data loaded${NC}"

echo ""
echo -e "${YELLOW}Step 8: Configuring FTP (optional)...${NC}"

read -p "  Do you have FTP for importing orders? (y/n) [n]: " USE_FTP
USE_FTP=${USE_FTP:-n}

FTP_HOST=""
FTP_USER=""
FTP_PASS=""
FTP_PORT="21"
FTP_PATH="/orders"
FTP_POLL_INTERVAL="60"

if [[ "$USE_FTP" == "y" || "$USE_FTP" == "Y" ]]; then
  read -p "  FTP Host: " FTP_HOST
  read -p "  FTP User: " FTP_USER
  read -sp "  FTP Password: " FTP_PASS
  echo ""
  read -p "  FTP Port [21]: " FTP_PORT
  FTP_PORT=${FTP_PORT:-21}
  read -p "  FTP Path [/orders]: " FTP_PATH
  FTP_PATH=${FTP_PATH:-/orders}
  read -p "  Poll Interval in seconds [60]: " FTP_POLL_INTERVAL
  FTP_POLL_INTERVAL=${FTP_POLL_INTERVAL:-60}
fi

echo ""
echo -e "${YELLOW}Step 9: Creating .env file...${NC}"
if [ ! -f .env ]; then
  # Get local IP for default server URL
  LOCAL_IP=$(hostname -I | awk '{print $1}' || echo "localhost")
  
  cat > .env << EOF
# Database (Auto-configured for print-orchestrator)
DATABASE_URL=$DATABASE_URL

# Server
PORT=5000
RACK_ENV=production
SERVER_BASE_URL=http://$LOCAL_IP:5000

# Switch Integration
SWITCH_WEBHOOK_URL=http://192.168.1.162/webhook/
SWITCH_API_KEY=
SWITCH_SIMULATION=false

# FTP Configuration (for order imports)
EOF

  if [ ! -z "$FTP_HOST" ]; then
    cat >> .env << EOF
FTP_HOST=$FTP_HOST
FTP_USER=$FTP_USER
FTP_PASS=$FTP_PASS
FTP_PORT=$FTP_PORT
FTP_PATH=$FTP_PATH
FTP_POLL_INTERVAL=$FTP_POLL_INTERVAL
FTP_DELETE_AFTER_IMPORT=false
EOF
    echo -e "${GREEN}✓ .env file created with FTP configuration${NC}"
  else
    cat >> .env << EOF
# FTP_HOST=your-ftp-host
# FTP_USER=username
# FTP_PASS=password
# FTP_PORT=21
# FTP_PATH=/orders
# FTP_POLL_INTERVAL=60
# FTP_DELETE_AFTER_IMPORT=false
EOF
    echo -e "${GREEN}✓ .env file created (FTP disabled)${NC}"
  fi
else
  echo -e "${YELLOW}(Existing .env file kept)${NC}"
fi

echo ""
echo -e "${YELLOW}Step 10: Testing application...${NC}"
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
