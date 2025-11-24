# Print Order Orchestrator - Linux Installation Guide

## System Requirements

- **OS**: Ubuntu 24.04.3 LTS (o equivalente Debian-based)
- **Ruby**: 3.2 or higher
- **PostgreSQL**: 14 or higher
- **Disk Space**: 2GB minimum
- **RAM**: 2GB minimum
- **Network**: Access to Switch server (192.168.1.162)

## Installation Steps

### 1. Prerequisites Installation

```bash
# Update system packages
sudo apt update
sudo apt upgrade -y

# Install system dependencies
sudo apt install -y \
  curl \
  git \
  build-essential \
  postgresql-client \
  libpq-dev \
  ruby-full \
  bundler

# Verify Ruby version (should be 3.2+)
ruby --version
```

### 2. Clone Repository

```bash
# Choose your installation directory
cd /opt  # or ~/projects or wherever you prefer

# Clone the project
git clone <your-repo-url> print-orchestrator
cd print-orchestrator
```

### 3. PostgreSQL Setup

#### Option A: Install PostgreSQL Locally

```bash
# Install PostgreSQL
sudo apt install -y postgresql postgresql-contrib

# Start PostgreSQL service
sudo systemctl start postgresql
sudo systemctl enable postgresql

# Create database user
sudo -u postgres psql << EOF
CREATE USER orchestrator WITH PASSWORD 'secure_password_here';
CREATE DATABASE print_orchestrator_development OWNER orchestrator;
ALTER USER orchestrator CREATEDB;
\q
EOF
```

#### Option B: Use Existing PostgreSQL Server

If PostgreSQL is already running elsewhere, just ensure connectivity:

```bash
# Test connection
psql -h <db-host> -U <db-user> -d print_orchestrator_development
```

### 4. Application Setup

```bash
# Install Ruby dependencies
bundle install --path vendor/bundle

# Create .env file with your configuration
cp .env.example .env

# Edit .env with your values
nano .env
```

### 5. Configure Environment Variables

Edit `.env` file:

```bash
# Database
DATABASE_URL=postgresql://orchestrator:secure_password_here@localhost:5432/print_orchestrator_development

# Switch Integration
SWITCH_WEBHOOK_URL=http://192.168.1.162/webhook/
SERVER_BASE_URL=http://<your-linux-ip>:5000
SWITCH_API_KEY=

# FTP Polling (optional if using local testing)
FTP_HOST=c72965.sgvps.net
FTP_USER=widegest@thepickshouse.com
FTP_PASS=WidegestImport24
FTP_PORT=21
FTP_PATH=/test/
FTP_POLL_INTERVAL=60
FTP_DELETE_AFTER_IMPORT=false

# Server
PORT=5000
RACK_ENV=development
```

**Important:** Replace `<your-linux-ip>` with the actual IP of your Linux machine (e.g., `192.168.1.100`)

### 6. Database Setup

```bash
# Create tables
bundle exec rake db:migrate

# Load seed data
bundle exec rake db:seed
```

### 7. Create Storage Directory

```bash
# Create storage folder for local files
mkdir -p storage

# Set permissions
chmod 755 storage
```

### 8. Start the Application

```bash
# Option A: Development mode
bundle exec puma -b tcp://0.0.0.0:5000 -p 5000 config.ru

# Option B: Background with systemd (production-like)
# See section below: "Running as Systemd Service"

# Application will be available at:
# http://<your-linux-ip>:5000
# or
# http://localhost:5000 (if running locally)
```

---

## Running as Systemd Service (Recommended)

### Create Systemd Service File

```bash
sudo nano /etc/systemd/system/print-orchestrator.service
```

Paste this content:

```ini
[Unit]
Description=Print Order Orchestrator
After=network.target postgresql.service
Wants=postgresql.service

[Service]
Type=simple
User=ubuntu
WorkingDirectory=/opt/print-orchestrator
Environment="RACK_ENV=production"
Environment="PORT=5000"
Environment="DATABASE_URL=postgresql://orchestrator:password@localhost:5432/print_orchestrator_development"
Environment="SWITCH_WEBHOOK_URL=http://192.168.1.162/webhook/"
Environment="SERVER_BASE_URL=http://192.168.1.100:5000"
ExecStart=/usr/bin/bundle exec puma -b tcp://0.0.0.0:5000 -p 5000 config.ru
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
```

### Enable and Start Service

```bash
# Reload systemd daemon
sudo systemctl daemon-reload

# Enable service to start on boot
sudo systemctl enable print-orchestrator.service

# Start the service
sudo systemctl start print-orchestrator.service

# Check status
sudo systemctl status print-orchestrator.service

# View logs
sudo journalctl -u print-orchestrator.service -f
```

---

## Verification

### Check Application Health

```bash
# Test health endpoint
curl http://localhost:5000/health

# Expected response:
# {"status":"ok","timestamp":"2025-01-15T10:30:00Z","database":"connected"}
```

### Access Web Interface

```
Open browser: http://<your-linux-ip>:5000
```

You should see:
- Orders page
- Inventory page
- Products page
- All navigation menus

### Test FTP Polling (if configured)

```bash
# View logs
tail -f ~/.log/print-orchestrator.log

# You should see FTP polling messages every 60 seconds
```

---

## Troubleshooting

### PostgreSQL Connection Error

```bash
# Check if PostgreSQL is running
sudo systemctl status postgresql

# Check connection parameters
psql -h localhost -U orchestrator -d print_orchestrator_development

# View PostgreSQL logs
sudo tail -f /var/log/postgresql/postgresql-14-main.log
```

### Port 5000 Already in Use

```bash
# Check what's using port 5000
sudo lsof -i :5000

# Kill the process if needed
sudo kill -9 <PID>

# Or use different port (edit PORT in .env)
```

### Bundle Install Issues

```bash
# Update Bundler
sudo gem update bundler

# Install specific Ruby version (if needed)
rbenv install 3.2.2  # if using rbenv

# Reinstall dependencies
bundle install
```

### Storage Directory Permission Error

```bash
# Fix permissions
sudo chown $USER:$USER -R storage
chmod 755 storage
chmod 777 storage/*/*
```

---

## FTP Polling Configuration

### Test FTP Connection

```bash
# Install FTP client
sudo apt install -y ftp

# Test connection
ftp -n << EOF
open c72965.sgvps.net 21
user widegest@thepickshouse.com
WidegestImport24
cd test/
ls
quit
EOF
```

### Disable FTP Polling for Testing

In `.env`, set:
```bash
FTP_POLL_INTERVAL=999999
```

Or comment out FTP config in `config.rb` if needed.

---

## Network Configuration

### Make Application Accessible from Network

Ensure firewall allows port 5000:

```bash
# UFW (Uncomplicated Firewall)
sudo ufw allow 5000/tcp

# iptables
sudo iptables -A INPUT -p tcp --dport 5000 -j ACCEPT

# Verify
sudo ufw status
```

### Configure for Switch Communication

Switch needs to reach your Linux machine:

```bash
# Get your Linux IP
hostname -I

# Update Switch configuration to use:
# http://<your-linux-ip>:5000
```

---

## Common Commands

```bash
# Start application
bundle exec puma -b tcp://0.0.0.0:5000 -p 5000 config.ru

# Run console (for debugging)
bundle exec rails console

# Check database status
bundle exec rake db:migrate:status

# Reset database (CAUTION: Destroys all data)
bundle exec rake db:drop db:create db:migrate db:seed

# View application logs
tail -f ~/.log/print-orchestrator.log

# Stop application
Ctrl+C (in console)
# or
sudo systemctl stop print-orchestrator.service
```

---

## Testing the System

### 1. Test Import Order

```bash
curl -X POST http://localhost:5000/api/orders/import \
  -H "Content-Type: application/json" \
  -d '{
    "store_id": "MAGENTA",
    "external_order_code": "TEST001",
    "items": [
      {
        "sku": "TPH500",
        "quantity": 2,
        "image_urls": [],
        "product_name": "Plettro TPH"
      }
    ]
  }'
```

### 2. Test Health Endpoint

```bash
curl http://localhost:5000/health
```

### 3. Test Switch Callback

```bash
curl -X POST http://localhost:5000/api/v1/reports_create \
  -H "Content-Type: application/json" \
  -d '{
    "codice_ordine": "TEST001",
    "id_riga": 1,
    "job_operation_id": 12345
  }'
```

---

## Next Steps

1. **Verify Installation**: Access web interface at `http://<your-linux-ip>:5000`
2. **Test Import**: Create test orders via API or UI
3. **Configure Switch**: Update Switch webhook URL to point to your Linux machine
4. **Run First Test**: Send a job through the prepress workflow
5. **Monitor Logs**: Use `systemctl logs` to verify operation

---

## Backup and Maintenance

### Backup Database

```bash
# Create backup
pg_dump -U orchestrator print_orchestrator_development > backup.sql

# Restore from backup
psql -U orchestrator print_orchestrator_development < backup.sql
```

### Backup Local Files

```bash
# Backup storage folder
tar -czf storage-backup.tar.gz storage/

# Restore
tar -xzf storage-backup.tar.gz
```

---

## Performance Tips

1. **Production Database**: Use dedicated PostgreSQL server
2. **Background Jobs**: Consider Sidekiq for async processing
3. **Caching**: Redis can help with caching
4. **Load Balancing**: Use Nginx/Apache reverse proxy
5. **Monitoring**: Set up Prometheus metrics

---

**Installation Date**: November 24, 2025
**Ruby**: 3.2+
**PostgreSQL**: 14+
**Status**: Ready for Local Testing
