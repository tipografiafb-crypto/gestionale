#!/bin/bash
# Reset Database and Install (Development/Replit Environment)
# WARNING: This script is for development and will reset the local database.

set -e

echo "⚠️  RESET DATABASE & RE-INSTALL (Development Mode)"
echo "================================================="

if [ -f .env ]; then
  # Estraiamo DATABASE_URL se presente
  DB_URL=$(grep '^DATABASE_URL=' .env | cut -d '=' -f2-)
fi

# In Replit, DATABASE_URL is managed by the system
if [ -z "$DB_URL" ]; then
    echo "❌ DATABASE_URL not set. Are you in a Replit environment with a database?"
    exit 1
fi

echo "Step 1: Dropping and recreating schema (Clean start)..."
# We don't drop the whole database in Replit, we just clear the public schema
psql "$DB_URL" -c "DROP SCHEMA public CASCADE; CREATE SCHEMA public;"

echo "Step 2: Running consolidated migrations..."
bundle exec rake db:migrate

echo "✅ Reset completed successfully."
