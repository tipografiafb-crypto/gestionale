#!/usr/bin/env bash
set -euo pipefail

APP_DIR=/home/magenta/apps/print-orchestrator
DB_NAME=print_orchestrator_dev
DB_USER=orchestrator_user
DB_PASSWORD="$(openssl rand -hex 24)"

cd "$APP_DIR"

sudo -u postgres psql --set=ON_ERROR_STOP=1 --command \
  "DO \$\$ BEGIN
     IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = '${DB_USER}') THEN
       CREATE ROLE ${DB_USER} LOGIN PASSWORD '${DB_PASSWORD}';
     ELSE
       ALTER ROLE ${DB_USER} PASSWORD '${DB_PASSWORD}';
     END IF;
   END \$\$;"

if ! sudo -u postgres psql --tuples-only --no-align --command \
  "SELECT 1 FROM pg_database WHERE datname = '${DB_NAME}'" | grep -qx 1; then
  sudo -u postgres createdb --owner="$DB_USER" "$DB_NAME"
fi

install -m 600 /dev/null "$APP_DIR/.env"
printf '%s\n' \
  "DATABASE_URL=postgresql://${DB_USER}:${DB_PASSWORD}@localhost:5432/${DB_NAME}" \
  "PORT=5000" \
  "RACK_ENV=production" \
  "SERVER_BASE_URL=http://192.168.1.44:5000" \
  "SWITCH_WEBHOOK_BASE_URL=http://192.168.1.162:51088" \
  "SWITCH_WEBHOOK_PREFIX=/scripting" \
  "SWITCH_SIMULATION=true" \
  "AUTOMATION_ACTION_SIMULATION=false" \
  "AUTOMATION_DESTINATIONS_ROOT=/mnt/gestionale" \
  "DAYS_TO_KEEP=30" \
  > "$APP_DIR/.env"
chown magenta:magenta "$APP_DIR/.env"

set -a
# shellcheck disable=SC1091
. "$APP_DIR/.env"
set +a

bundle exec rake db:migrate

psql "$DATABASE_URL" --set=ON_ERROR_STOP=1 <<'SQL'
UPDATE automation_destinations
SET config = jsonb_build_object(
      'container_path', '/mnt/gestionale/print',
      'host_mount_path', '/mnt/gestionale/print',
      'network_uri', ''
    ),
    updated_at = CURRENT_TIMESTAMP
WHERE code = 'LOCAL_PRINT';

UPDATE automation_destinations
SET config = jsonb_build_object(
      'container_path', '/mnt/gestionale/labels',
      'host_mount_path', '/mnt/gestionale/labels',
      'network_uri', ''
    ),
    updated_at = CURRENT_TIMESTAMP
WHERE code = 'LOCAL_LABELS';
SQL

sudo install -m 644 \
  "$APP_DIR/deploy/systemd/print-orchestrator.service" \
  /etc/systemd/system/print-orchestrator.service
sudo install -m 644 \
  "$APP_DIR/deploy/systemd/print-orchestrator-worker.service" \
  /etc/systemd/system/print-orchestrator-worker.service

sudo systemctl daemon-reload
sudo systemctl enable --now postgresql cups
sudo systemctl enable --now print-orchestrator print-orchestrator-worker

if sudo ufw status | grep -q '^Status: active'; then
  sudo ufw allow 5000/tcp
fi
