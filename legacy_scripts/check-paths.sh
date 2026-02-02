#!/bin/bash

echo "========================================="
echo "Print Order Orchestrator - Percorsi"
echo "========================================="
echo ""

# Percorso app
APP_DIR="/home/paolo/apps/print-orchestrator"
echo "📁 APP DIRECTORY:"
echo "   $APP_DIR"
if [ -d "$APP_DIR" ]; then
    echo "   ✓ Esiste"
else
    echo "   ✗ Non trovata"
fi
echo ""

# File principali
echo "📄 FILE PRINCIPALI:"
echo "   .env:                    $APP_DIR/.env"
echo "   Gemfile:                 $APP_DIR/Gemfile"
echo "   config.ru:               $APP_DIR/config.ru"
echo "   print-orchestrator.service: /etc/systemd/system/print-orchestrator.service"
echo ""

# Database
echo "🗄️  DATABASE:"
echo "   Host: localhost:5432"
echo "   Database: print_orchestrator"
echo "   User: orchestrator_user"
echo ""

# Comandi utili
echo "⚙️  COMANDI UTILI:"
echo ""
echo "   Controllare status servizio:"
echo "   sudo systemctl status print-orchestrator.service"
echo ""
echo "   Visualizzare log servizio:"
echo "   sudo journalctl -u print-orchestrator.service -n 50 -f"
echo ""
echo "   Riavviare servizio:"
echo "   sudo systemctl restart print-orchestrator.service"
echo ""
echo "   Entrare nella directory app:"
echo "   cd $APP_DIR"
echo ""
echo "========================================="
