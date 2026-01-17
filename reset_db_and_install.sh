#!/bin/bash
# Portable Installer for Print Orchestrator (Ubuntu)

echo "Resetting database..."
# If we are in a Replit environment, we use PG env vars directly
if [ -n "$PGHOST" ]; then
  psql -c "DROP TABLE IF EXISTS schema_migrations CASCADE;"
  # We don't drop the whole DB in Replit as it's managed, just clean it
  psql -c "DROP TABLE IF EXISTS stores, orders, order_items, products, inventories, assets, switch_webhooks, print_flows, product_categories, switch_jobs, print_machines, print_flow_machines, logs, import_errors CASCADE;"
else
  # Ubuntu portable path
  sudo -u postgres psql -c "DROP DATABASE IF EXISTS print_orchestrator_dev;" 2>/dev/null
  sudo -u postgres psql -c "DROP USER IF EXISTS orchestrator_user;" 2>/dev/null
  sudo -u postgres psql -c "CREATE USER orchestrator_user WITH ENCRYPTED PASSWORD 'Paolo_Strong_123' CREATEDB;"
  sudo -u postgres psql -c "CREATE DATABASE print_orchestrator_dev OWNER orchestrator_user;"
fi

echo "Configuring environment..."
if [ -z "$PGHOST" ]; then
  cat > .env << 'ENVEOF'
DATABASE_URL=postgresql://orchestrator_user:Paolo_Strong_123@localhost:5432/print_orchestrator_dev
RACK_ENV=production
PORT=5000
SERVER_BASE_URL=http://localhost:5000
ENVEOF
fi

echo "Installing dependencies..."
bundle install

echo "Running migrations..."
rm -f db/schema.rb
if [ -n "$DATABASE_URL" ]; then
  bundle exec rake db:migrate
else
  export DATABASE_URL=postgresql://orchestrator_user:Paolo_Strong_123@localhost:5432/print_orchestrator_dev
  bundle exec rake db:migrate
fi

echo "Installation complete!"
