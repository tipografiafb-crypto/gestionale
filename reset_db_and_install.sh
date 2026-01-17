#!/bin/bash
# Portable Installer for Print Orchestrator (Ubuntu)

echo "Resetting database..."
sudo -u postgres psql -c "DROP DATABASE IF EXISTS print_orchestrator_dev;" 2>/dev/null
sudo -u postgres psql -c "DROP USER IF EXISTS orchestrator_user;" 2>/dev/null
sudo -u postgres psql -c "CREATE USER orchestrator_user WITH ENCRYPTED PASSWORD 'Paolo_Strong_123' CREATEDB;"
sudo -u postgres psql -c "CREATE DATABASE print_orchestrator_dev OWNER orchestrator_user;"

echo "Configuring environment..."
cat > .env << 'ENVEOF'
DATABASE_URL=postgresql://orchestrator_user:Paolo_Strong_123@localhost:5432/print_orchestrator_dev
RACK_ENV=production
PORT=5000
SERVER_BASE_URL=http://localhost:5000
ENVEOF

echo "Installing dependencies..."
bundle install

echo "Running migrations..."
rm -f db/schema.rb
export DATABASE_URL=postgresql://orchestrator_user:Paolo_Strong_123@localhost:5432/print_orchestrator_dev
bundle exec rake db:migrate

echo "Installation complete!"
