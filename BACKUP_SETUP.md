# Print Order Orchestrator - Backup Setup Guide

## Overview

This guide explains how to set up automated daily backups of your Print Order Orchestrator database and storage files, sending them to your Enfocus Switch server.

## Prerequisites

- SSH access to your Switch PC (e.g., 192.168.1.162)
- User account on Switch PC that can receive backups
- PostgreSQL client tools (`pg_dump`) installed on your orchestrator server

## Setup Instructions

### 1. Create SSH Key for Backups (Ubuntu/Linux)

On your orchestrator server, create a dedicated SSH key:

```bash
ssh-keygen -t rsa -b 4096 -f ~/.ssh/backup_key -N ""
chmod 600 ~/.ssh/backup_key
```

### 2. Configure Remote Server

On your Switch PC, add the public key to allow passwordless backups:

```bash
# On Switch PC
mkdir -p ~/.ssh
cat backup_key.pub >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
chmod 700 ~/.ssh

# Create backup directory
mkdir -p /backup/print-orchestrator
chmod 755 /backup/print-orchestrator
```

### 3. Update .env Configuration

On your orchestrator server, add these backup configuration variables:

```bash
nano /home/paolo/apps/print-orchestrator/.env
```

Add the following lines:

```
# Backup Configuration
REMOTE_BACKUP_USER=orchestrator_user
REMOTE_BACKUP_HOST=192.168.1.162
REMOTE_BACKUP_PATH=/backup/print-orchestrator
REMOTE_BACKUP_SSH_KEY=/home/paolo/.ssh/backup_key
```

Replace values as needed:
- `REMOTE_BACKUP_USER`: Username on Switch PC (default: orchestrator)
- `REMOTE_BACKUP_HOST`: IP address of Switch PC (default: 192.168.1.162)
- `REMOTE_BACKUP_PATH`: Directory on Switch PC to store backups (default: /backup/print-orchestrator)
- `REMOTE_BACKUP_SSH_KEY`: Path to SSH private key

### 4. Test the Backup Script

Test local backup (no remote send):

```bash
cd /home/paolo/apps/print-orchestrator
bash scripts/backup.sh
```

Test sending to remote server:

```bash
bash scripts/backup.sh send
```

You should see output like:
```
✓ Backup directory ready
✓ Database backed up: 125MB
✓ Storage backed up: 2.3GB
✓ Final backup created: 2.4GB
✓ Backup sent successfully
✓ Cleanup complete
```

### 5. Schedule Daily Backups (Crontab)

Set up automatic daily backups:

```bash
crontab -e
```

Add one of these lines:

**Option A: Backup only (store locally)**
```
# Daily backup at 3 AM, keep 30 days locally
0 3 * * * cd /home/paolo/apps/print-orchestrator && bash scripts/backup.sh >> /var/log/print-orchestrator-backup.log 2>&1
```

**Option B: Backup and send to remote (recommended)**
```
# Daily backup and send to Switch PC at 3 AM
0 3 * * * cd /home/paolo/apps/print-orchestrator && bash scripts/backup.sh send >> /var/log/print-orchestrator-backup.log 2>&1
```

### 6. Monitor Backup Logs

Check backup status:

```bash
# View recent backup logs
tail -50 /var/log/print-orchestrator-backup.log

# Check last backup file size
ls -lh /tmp/print-orchestrator-backups/ | tail -5
```

## Backup Contents

Each backup contains:

```
print-orchestrator-backup_YYYYMMDD_HHMMSS.tar.gz
├── print-orchestrator-backup_..._db.sql.gz       # PostgreSQL database dump
└── print-orchestrator-backup_..._storage.tar.gz  # All images in storage/
```

## Restore from Backup

### Restore Database

```bash
# Extract database dump
tar -xzf print-orchestrator-backup_YYYYMMDD_HHMMSS.tar.gz
gunzip print-orchestrator-backup_YYYYMMDD_HHMMSS_db.sql.gz

# Restore to PostgreSQL
psql "$DATABASE_URL" < print-orchestrator-backup_YYYYMMDD_HHMMSS_db.sql
```

### Restore Storage Files

```bash
# Extract storage files
tar -xzf print-orchestrator-backup_YYYYMMDD_HHMMSS_storage.tar.gz

# This creates a "storage/" directory with your files
```

## Retention Policy

- **Local backups**: Automatically deleted after 7 days
- **Remote backups**: Manually managed on Switch PC
- **Recommended**: Keep backups on Switch PC for 30+ days for recovery

## Troubleshooting

### "REMOTE_BACKUP_SSH_KEY not set"
Add the SSH key path to your `.env` file (see step 3)

### "Failed to send backup"
- Verify SSH connectivity: `ssh -i ~/.ssh/backup_key orchestrator@192.168.1.162`
- Check that remote directory exists and is writable
- Ensure public key is in `~/.ssh/authorized_keys` on Switch PC

### "pg_dump command not found"
Install PostgreSQL client tools:
```bash
sudo apt-get install postgresql-client
```

### Backup files are too large
- Check storage/ directory: `du -sh /home/paolo/apps/print-orchestrator/storage/`
- Consider cleaning up old files using the Storage Cleanup feature
- Increase remote storage space

## Using Rake Tasks (Alternative)

You can also trigger backups using Rake:

```bash
# Local backup only
bundle exec rake backup:local

# Backup and send
bundle exec rake backup:send
```

## Additional Notes

- Backups run at **3 AM daily** (adjust crontab time as needed)
- Each backup is **timestamped** with date and time
- **Automatic cleanup** keeps only recent local backups to save disk space
- Backups are **compressed** (gzip) to save bandwidth and storage
