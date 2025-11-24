#!/bin/bash
set -e

echo "Setting up systemd service for Print Order Orchestrator..."

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
  echo "This script must be run as root: sudo ./setup_service.sh"
  exit 1
fi

# Get current user (the one who ran sudo)
REAL_USER=$(who am i | awk '{print $1}')
WORK_DIR=$(pwd)

# Get Ruby path
RUBY_PATH=$(which ruby)
BUNDLE_PATH=$(which bundle)

echo "User: $REAL_USER"
echo "Directory: $WORK_DIR"
echo "Ruby: $RUBY_PATH"
echo ""

# Create systemd service file
cat > /etc/systemd/system/print-orchestrator.service << EOF
[Unit]
Description=Print Order Orchestrator
After=network.target postgresql.service
Wants=postgresql.service

[Service]
Type=simple
User=$REAL_USER
WorkingDirectory=$WORK_DIR
Environment="PATH=/home/$REAL_USER/.gem/ruby/3.2.0/bin:/home/$REAL_USER/.local/bin:\$PATH"
Environment="RACK_ENV=production"

# Load .env file if it exists
EnvironmentFile=$WORK_DIR/.env

# Start command
ExecStart=$BUNDLE_PATH exec puma -b tcp://0.0.0.0:5000 config.ru

# Restart policy
Restart=on-failure
RestartSec=5

# Logging
StandardOutput=journal
StandardError=journal
SyslogIdentifier=print-orchestrator

[Install]
WantedBy=multi-user.target
EOF

# Reload systemd daemon
systemctl daemon-reload

echo "✓ Systemd service file created at /etc/systemd/system/print-orchestrator.service"
echo ""
echo "Next steps:"
echo "  1. Enable the service: sudo systemctl enable print-orchestrator.service"
echo "  2. Start the service: sudo systemctl start print-orchestrator.service"
echo "  3. Check status: sudo systemctl status print-orchestrator.service"
echo "  4. View logs: sudo journalctl -u print-orchestrator.service -f"
echo ""
