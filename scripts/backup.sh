#!/bin/bash
#
# Print Order Orchestrator - Daily Backup Script
# Backs up PostgreSQL database and storage files
# Compresses into a single archive and optionally sends to remote server
#
# Usage: bash scripts/backup.sh [send]
# If "send" is provided, will also push backup to remote server via SCP

set -e

# Configuration
APP_DIR="/home/paolo/apps/print-orchestrator"
BACKUP_DIR="/tmp/print-orchestrator-backups"
STORAGE_DIR="$APP_DIR/storage"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_NAME="print-orchestrator-backup_${TIMESTAMP}"
BACKUP_FILE="$BACKUP_DIR/${BACKUP_NAME}.tar.gz"

# Remote server configuration (from .env)
REMOTE_USER="${REMOTE_BACKUP_USER:-orchestrator}"
REMOTE_HOST="${REMOTE_BACKUP_HOST:-192.168.1.162}"
REMOTE_PATH="${REMOTE_BACKUP_PATH:-/backup/print-orchestrator}"

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}=== Print Order Orchestrator Backup ===${NC}"
echo "Timestamp: $(date)"
echo ""

# Create backup directory
mkdir -p "$BACKUP_DIR"
echo -e "${GREEN}✓${NC} Backup directory ready: $BACKUP_DIR"

# Backup database
echo -e "${YELLOW}Backing up PostgreSQL database...${NC}"
DB_DUMP="$BACKUP_DIR/${BACKUP_NAME}_db.sql.gz"
cd "$APP_DIR"
# Source .env to get DATABASE_URL
if [ -f .env ]; then
  export $(grep -v '^#' .env | xargs)
fi

pg_dump "$DATABASE_URL" | gzip > "$DB_DUMP"
DB_SIZE=$(du -h "$DB_DUMP" | cut -f1)
echo -e "${GREEN}✓${NC} Database backed up: $DB_SIZE"

# Backup storage files
echo -e "${YELLOW}Backing up storage files...${NC}"
if [ -d "$STORAGE_DIR" ]; then
  STORAGE_BACKUP="$BACKUP_DIR/${BACKUP_NAME}_storage.tar.gz"
  tar -czf "$STORAGE_BACKUP" -C "$APP_DIR" storage/
  STORAGE_SIZE=$(du -h "$STORAGE_BACKUP" | cut -f1)
  echo -e "${GREEN}✓${NC} Storage backed up: $STORAGE_SIZE"
else
  echo -e "${YELLOW}!${NC} Storage directory not found, skipping"
fi

# Create combined archive
echo -e "${YELLOW}Creating final backup archive...${NC}"
cd "$BACKUP_DIR"
tar -czf "$BACKUP_FILE" ${BACKUP_NAME}_db.sql.gz ${BACKUP_NAME}_storage.tar.gz 2>/dev/null || true
TOTAL_SIZE=$(du -h "$BACKUP_FILE" | cut -f1)
echo -e "${GREEN}✓${NC} Final backup created: $TOTAL_SIZE"
echo "Location: $BACKUP_FILE"

# Clean up intermediate files
rm -f "$BACKUP_DIR/${BACKUP_NAME}_db.sql.gz" "$BACKUP_DIR/${BACKUP_NAME}_storage.tar.gz"

# Send to remote if requested
if [ "$1" == "send" ]; then
  echo ""
  echo -e "${YELLOW}Sending backup to remote server...${NC}"
  echo "Target: $REMOTE_USER@$REMOTE_HOST:$REMOTE_PATH"
  
  # Check if SSH key is configured
  if [ -z "$REMOTE_BACKUP_SSH_KEY" ]; then
    echo -e "${RED}✗${NC} REMOTE_BACKUP_SSH_KEY not set in .env"
    echo "Please add to .env:"
    echo "  REMOTE_BACKUP_SSH_KEY=/home/paolo/.ssh/backup_key"
    exit 1
  fi
  
  # Send via SCP
  scp -i "$REMOTE_BACKUP_SSH_KEY" -q "$BACKUP_FILE" "$REMOTE_USER@$REMOTE_HOST:$REMOTE_PATH/" 2>/dev/null
  
  if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓${NC} Backup sent successfully"
    
    # Keep only last 7 days of backups locally
    echo -e "${YELLOW}Cleaning up old backups (keeping last 7 days)...${NC}"
    find "$BACKUP_DIR" -name "print-orchestrator-backup_*.tar.gz" -mtime +7 -delete
    echo -e "${GREEN}✓${NC} Cleanup complete"
  else
    echo -e "${RED}✗${NC} Failed to send backup"
    exit 1
  fi
else
  echo ""
  echo -e "${YELLOW}Tip:${NC} To send backup to remote, run: bash scripts/backup.sh send"
fi

echo ""
echo -e "${GREEN}=== Backup Complete ===${NC}"
echo "Date: $(date)"
