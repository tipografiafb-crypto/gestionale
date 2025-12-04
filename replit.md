# Print Order Orchestrator - Replit Project

## Overview

Local print order management system built with Ruby, Sinatra, and PostgreSQL. Integrates with Magenta Product Designer and Enfocus Switch for automated print workflow.

## Project Status

✅ **MVP Complete** (November 2025)
- Database schema and migrations
- Order import API
- Asset download service
- Switch integration
- Web interface
- Agent workflow system

## Recent Work

### December 4, 2025 (Bulk Print & Rippato Status)
- Added new 'ripped' print status for bulk print operations
- Implemented bulk print functionality in /line_items page:
  - Checkbox selection for multiple items ready for print
  - "Invia Selezionati a Stampa" button with selected count
  - Modal for print machine selection
  - Sequential API calls with progress bar and results feedback
- Created POST /api/v1/bulk_print_item API endpoint for bulk operations
- Added 'rippato' filter option in line items status dropdown
- Updated confirm_print to accept both 'processing' and 'ripped' statuses
- Updated print_result_section UI to show "Rippato - In coda stampa" status
- Workflow: pending → ripped (bulk) or processing (single) → completed
- Fixed aggregation print payload to use absolute URLs and include nr_files/file_index

### December 2, 2025 (Aggregated Jobs System)
- Implemented complete Aggregated Jobs system for batch processing
- New workflow: pending → aggregating → aggregated → printing → completed
- Created AggregatedJob and AggregatedJobItem models with full database schema
- Added routes for creating, viewing, and managing aggregated jobs
- Integrated with SwitchClient for sending aggregation requests to Switch
- Added API callbacks: `/api/v1/aggregation_callback` and `/api/v1/aggregation_print_callback`
- Added "Aggregazioni" link in main navigation menu
- Updated quick_start_linux.sh with aggregated_jobs tables (Step 5.7)
- Views: aggregated_jobs_list.erb, aggregated_job_detail.erb, aggregated_jobs_new.erb

### December 1, 2025 (Switch Port Configuration Verified)
- Confirmed Switch webhook URL port is 51088 (v7 on Ubuntu Switch installation)
- Verified via Switch system port checking
- Configuration: SWITCH_WEBHOOK_BASE_URL=http://192.168.1.162:51088
- Added mandatory `/scripting/` prefix required by Switch Webhook v7 app
- Made webhook prefix configurable via SWITCH_WEBHOOK_PREFIX environment variable
- Corrected webhook path construction: base_url + `/scripting` + webhook_path
- System sends to correct URL format: http://192.168.1.162:51088/scripting/prestampa_adesivi
- Added debug logging to show complete URL and response from Switch

### November 25, 2025 (Switch Webhook Payload Standardization)
- Fixed Switch webhook payload format for all three operations (preprint, stampa, etichetta)
- Implemented proper payload structure per SWITCH_WORKFLOW.md with: id_riga, codice_ordine, product, operation_id, url, widegest_url, filename, quantita, materiale, campi_custom, opzioni_stampa, campi_webhook
- Updated SwitchClient to auto-generate job_id from payload (format: PREPRINT/PRINT/LABEL-CODICE-RIGA-TIMESTAMP)
- Fixed webhook URL building to use ENV['SWITCH_WEBHOOK_URL'] dynamically
- Updated installer to configure SERVER_BASE_URL and SWITCH_WEBHOOK_URL automatically
- All three operations now send correct payload to Switch at http://192.168.1.162/webhook/

### November 25, 2025 (FTP Integration & Schema Consolidation)
- Fixed critical `attr_accessor` bugs in Product, PrintFlow, ProductCategory models
- Added missing columns: preprint_completed_at, print_started_at, print_completed_at, preprint_print_flow_id
- Consolidated all 30 fragmented migrations into single unified migration file
- Updated installer to include FTP configuration during setup
- Fixed webhook/print flow assignments now persist to database correctly
- Created MIGRATION_GUIDE.md for future deployments

### November 24, 2025 (Ubuntu Deployment)
- Consolidated fragmented 30+ migrations into single clean migration
- Fixed schema mismatch issues (missing `hook_path`, `active` columns)
- Created automated installation scripts for Linux (Ubuntu 24.04+)
- Fixed mass assignment security for Store model
- Set up complete database with all 15 tables correctly
- Deployed successfully on Ubuntu 24.04.3 LTS at 192.168.1.100:5000

### November 20, 2025
- Initial project setup with Ruby 3.2 and Sinatra 4.2
- Created all database models and migrations
- Implemented API endpoints for order management
- Built services for asset downloads and Switch integration
- Created web UI with Bootstrap
- Established System_program structure for AI agent workflows
- Configured Puma workflow on port 5000

## Structure

The project follows an Enterprise-Grade Module Routing System with feature-based organization:

- **orders**: Order management and data models
- **storage**: Asset downloads and file management
- **switch**: Enfocus Switch integration
- **ui**: Web interface for operators
- **integration**: Core application and external APIs
- **quality**: Code quality and documentation

See `AGENT_WORKFLOW.md` for detailed workflow guidelines.

## User Preferences

### Development Style
- Feature-targeted surgical changes
- Minimal blast radius approach
- Use scope files for permission control
- Follow Ruby and Sinatra conventions
- Keep models, services, and routes separated

### Project Goals
1. Manage print orders from e-commerce platforms
2. Download and organize product images locally
3. Send jobs to Enfocus Switch for processing
4. Track job status and results
5. Provide simple web interface for operators

## Architecture

### Tech Stack
- **Ruby**: 3.2.2
- **Web Framework**: Sinatra 4.2
- **Database**: PostgreSQL (via ActiveRecord 7.2)
- **Server**: Puma 6.6 on port 5000
- **Frontend**: Bootstrap 5 with ERB templates

### Key Dependencies
- sinatra-activerecord - Database integration
- http - HTTP client for downloads and webhooks
- pg - PostgreSQL adapter
- dotenv - Environment configuration

## Database

PostgreSQL database configured via Replit's built-in database service.

Tables:
- `stores` - E-commerce stores
- `orders` - Print orders
- `order_items` - Items within orders
- `assets` - Images and files
- `switch_jobs` - Switch job tracking
- `aggregated_jobs` - Aggregated batch jobs for multiple items
- `aggregated_job_items` - Join table linking aggregated jobs to order items

Run migrations:
```bash
bundle exec rake db:migrate
```

## Workflows

**Print Orchestrator** (Port 5000)
- Command: `bundle exec puma -p 5000 -b tcp://0.0.0.0 config.ru`
- Output: webview
- Status: Running

## Environment Variables

**Database:**
- `DATABASE_URL` - PostgreSQL connection (auto-configured)

**Server:**
- `PORT` - Server port (default: 5000)
- `RACK_ENV` - Environment mode (production/development)

**Switch Integration (v7 Webhook):**
- `SWITCH_WEBHOOK_BASE_URL` - Switch server base URL (e.g., http://192.168.1.162:51088)
- `SWITCH_WEBHOOK_PREFIX` - Webhook prefix for v7 (use `/scripting` for v7, empty for v6)
- `SWITCH_API_KEY` - Switch API authentication (optional)
- `SWITCH_SIMULATION` - Test mode without real Switch (true/false)

**FTP Order Import (Optional):**
- `FTP_HOST` - FTP server hostname (e.g., c72965.sgvps.net)
- `FTP_USER` - FTP username
- `FTP_PASS` - FTP password
- `FTP_PORT` - FTP port (default: 21)
- `FTP_PATH` - Directory path on FTP server (default: /orders)
- `FTP_POLL_INTERVAL` - Check interval in seconds (default: 60)
- `FTP_DELETE_AFTER_IMPORT` - Delete files after import (true/false)

## Extension Guidelines

When adding features:

1. **Choose Feature Target**: Select from orders, storage, switch, ui, integration, or quality
2. **Check Scope**: Review `System_program/scope/<feature>.allow` and `.deny`
3. **Make Changes**: Modify only permitted files
4. **Test**: Verify functionality through web UI or API
5. **Document**: Update relevant documentation

See `README.md` for detailed API documentation and examples.

## Testing

To test the system:

1. **Import Order**: POST to `/api/orders/import` with order JSON
2. **View Orders**: Visit `/orders` in web browser
3. **Download Assets**: Click "Download" button or POST to `/api/orders/:id/download_assets`
4. **Send to Switch**: Click "Send to Switch" or POST to `/api/orders/:id/send_to_switch`
5. **Check Results**: View order detail page for status and previews

## Common Tasks

### Create New Migration
```bash
bundle exec rake db:create_migration NAME=add_field_to_orders
```

### Reset Database
```bash
bundle exec rake db:drop db:create db:migrate
```

### Check Database Status
Visit `/health` endpoint for system status.

### View Logs
Check Replit workflow logs or console output.

## Next Steps

Planned improvements:
- Add authentication/authorization
- Implement background job processing
- Add comprehensive test suite
- Enhance error handling and logging
- Create admin panel for configuration
- Add monitoring and alerting

## Critical: Print Workflow File Paths

### File per la Stampa (IMPORTANTE)
Quando Switch restituisce un file processato, viene salvato e reso disponibile per la stampa:

| Dato | Valore | Uso |
|------|--------|-----|
| **URL Frontend** | `/file/{asset.id}` | Preview nel browser e invio alla stampante |
| **Percorso Locale** | `storage/{store_code}/{order_code}/{sku}/{filename}` | File fisico su disco |
| **Campo DB** | `assets.local_path` | Recupera il percorso del file |
| **Esempio** | `storage/TPH_EU/EU12351/TPH001-71/eu12351-2.pdf` | File PDF pronto per stampa |

### Come Recuperare il File per la Stampa
```ruby
# Dato un OrderItem, ottieni il file da stampare:
asset = item.assets.find_by(asset_type: 'print_output')
file_path = asset.local_path_full  # Percorso completo su disco
# Oppure serve via HTTP:
url = "/file/#{asset.id}"
```

### Flusso File Switch → Stampa
1. Switch processa il file e chiama callback `/api/switch/report`
2. Il file viene salvato in `storage/{store}/{order}/{sku}/`
3. Viene creato un Asset con `local_path` = percorso del file
4. Frontend mostra preview via `/file/{asset.id}`
5. **Per stampare**: usa `asset.local_path_full` per inviare alla stampante

## Notes

- The workflow system (`System_program/`) enables AI agents to work surgically on specific features
- All models use ActiveRecord associations for clean data access
- Services encapsulate business logic separate from routes
- Views use ERB templates with Bootstrap for responsive design
- API returns consistent JSON format with `success` and `error` fields
