# Print Order Orchestrator

## Overview
The Print Order Orchestrator is a local print order management system designed to streamline the print production workflow. Built with Ruby, Sinatra, and PostgreSQL, its primary purpose is to manage print orders originating from e-commerce platforms. The system automates the process of downloading and organizing product images, sending jobs to Enfocus Switch for processing, and tracking job statuses. It provides a simple web interface for operators to monitor and manage orders, aiming to enhance efficiency and reduce manual intervention in print production.

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

## Recent Work

### December 9, 2025 - Autopilot Payload Fixed (Switch Endpoint Issue)
- ✅ **FIXED AUTOPILOT PAYLOAD**: Autopilot was using WRONG endpoint and INCOMPLETE payload
  - **Previous**: Used `/jobs/preprint` endpoint with minimal payload (operation_id, codice_ordine, id_riga, sku, quantity, product_name, category, print_files, timestamp)
  - **Now**: Uses `/plettro_automatico` endpoint (SAME as manual send) with COMPLETE payload
  - **Complete payload includes**: job_operation_id, url (gestionale asset download), widegest_url (callback), filename, quantita, materiale, campi_custom, opzioni_stampa, campi_webhook
- ✅ **Updated switch_integration.rb**: Now uses `build_preprint_payload()` that mirrors `SwitchClient.build_payload()` format exactly
- ✅ **Uses correct URLs**: Gestionale base URL for asset downloads + server base URL for Switch callbacks
- 🎯 **AUTOPILOT NOW FULLY COMPATIBLE WITH REAL SWITCH**: Same endpoint and payload format as manual send = guaranteed compatibility

### December 8, 2025 - Autopilot System Complete & Fixed
- ✅ **FIXED CRITICAL BUG**: Created missing `services/switch_integration.rb` class
  - AutopilotService was calling `SwitchIntegration.send_to_preprint()` but class didn't exist
  - Error: "uninitialized constant AutopilotService::SwitchIntegration"
  - Solution: Created wrapper class with `send_to_preprint(order_item)` method
  - Added `require_relative 'switch_integration'` to autopilot_service.rb
  
- ✅ **ENHANCED AUTOPILOT LOGGING**: Added detailed debug messages to understand flow:
  - `[AutopilotService] → Checking preprint readiness...` - marks asset validation
  - Shows `preprint_status`, asset count, and file existence for each asset
  - New logs help diagnose why items don't send to preprint
  
- ✅ **FIXED PRODUCT CATEGORY ASSIGNMENT**: 
  - Product SKU "TPH001-88" (ID 7) was missing `product_category_id`
  - Manually assigned to category "Plettri" (ID 1) which has autopilot enabled
  - Now autopilot can find category and check if autopilot is enabled
  
- ✅ **UPDATED quick_start_ubuntu_safe.sh**:
  - Fixed table name from `categories` to `product_categories`
  - Script now correctly adds `autopilot_preprint_enabled` column for new installations
  
- 🎯 **AUTOPILOT NOW FULLY FUNCTIONAL**:
  - New orders via FTP with enabled category → automatically sent to Switch (or simulated)
  - Preprint status updates from 'pending' to 'processing'
  - Complete logging trail for debugging

### December 8, 2025 - Earlier Autopilot Debugging & Fixes
- ✅ **Fixed Missing Database Column**: Added `autopilot_preprint_enabled` to product_categories for existing installations via SQL
- ✅ **Fixed FTPPoller require**: Added `require_relative 'autopilot_service'` to services/ftp_poller.rb
- ✅ **Fixed Orders API require**: Added `require_relative '../services/autopilot_service'` to routes/orders_api.rb (PRIMARY BUG)
- ✅ **Enhanced AutopilotService logging**: Added detailed debug messages for troubleshooting:
  - "[AutopilotService] ⏱ STARTING" - marks entry point
  - "[AutopilotService] → Checking item" - item validation
  - "[AutopilotService] Category: {name}, Autopilot: {status}" - category autopilot status
  - "[AutopilotService] ✓ SUCCESS" or "[AutopilotService] ✗ FAILED" - outcome
- ✅ **Enhanced API error logging**: Added [API] prefix messages to orders_api.rb:
  - "[API] 🔷 About to find order" - before order lookup
  - "[API] 🔶 Order found, calling AutopilotService" - before autopilot call
  - "[API] 🔵 AutopilotService completed" - after successful completion
  - "[API] ❌ StandardError/JSON/Record errors" - error tracking with backtrace

### December 6, 2025 - Autopilot Preprint System + Bug Fixes
- ✅ **IMPLEMENTED AUTOPILOT PREPRINT FEATURE**:
  - Created `services/autopilot_service.rb` - automatically sends items to Switch preprint when category autopilot is enabled
  - Added `autopilot_preprint_enabled` boolean column to categories table
  - Updated `quick_start_ubuntu_safe.sh` to auto-migrate autopilot columns for Ubuntu installations
  
- ✅ **Autopilot Integration**:
  - FTPPoller calls `AutopilotService.process_order()` after asset download
  - API import (POST /api/orders/import) calls autopilot service after import
  - Logic: Category has preprint autopilot? → YES: auto-send to Switch | NO: wait for operator
  
- ✅ **Category Management UI**:
  - Added "Autopilot Preprint" column in `/product_categories` list with toggle button (⚡ ABILITATO / Disabilitato)
  - Added checkbox in category form (create/edit) to enable/disable autopilot preprint
  - Created POST `/product_categories/:id/toggle_autopilot` route for quick enable/disable
  
- ✅ **Fixed FTP Import**: FTPPoller now saves `customer_name` and `customer_note` to database
  
- ✅ **Fixed Delete Button**: Orders list `/orders` delete button now properly deletes orders (was opening order page)

## System Architecture

The project follows an Enterprise-Grade Module Routing System with a feature-based organization.

### Tech Stack
- **Ruby**: 3.2.2
- **Web Framework**: Sinatra 4.2
- **Database**: PostgreSQL (via ActiveRecord 7.2)
- **Server**: Puma 6.6 on port 5000
- **Frontend**: Bootstrap 5 with ERB templates

### Key Features
- **Autopilot Preprint System**: Categories can be configured to automatically send items to Switch preprint when orders arrive
- **Order Management**: Handles order import via API and FTP, supporting WooCommerce JSON format mapping
- **Asset Management**: Downloads and organizes product images locally, tracking them via `assets` table
- **Switch Integration**: Communicates with Enfocus Switch for automated print workflow (preprint, print, label)
- **Aggregated Jobs System**: Implements batch processing for multiple items
- **Print Workflow**: Manages print statuses and facilitates bulk print operations
- **Analytics Dashboard**: Interactive charts for daily sales, top products, sales by category
- **Customer Notes**: Saves and displays customer notes/instructions from orders

### Database Schema
Key tables:
- `stores`, `orders`, `order_items`, `assets`, `switch_jobs`, `aggregated_jobs`, `aggregated_job_items`
- `product_categories` (with `autopilot_preprint_enabled` boolean)
- `print_flows`, `products`, `inventory`, `backup_configs`

### API Endpoints

**Order Import:**
- `POST /api/orders/import` - Import new order with auto-autopilot processing

**Autopilot Control:**
- `POST /product_categories/:id/toggle_autopilot` - Enable/disable autopilot preprint for category

**Web UI:**
- `GET /product_categories` - List categories with autopilot status
- `POST /product_categories/:id/toggle_autopilot` - Quick toggle autopilot
- `GET /product_categories/:id/edit` - Edit category with autopilot checkbox
- `GET /orders` - List orders with delete button (fixed)

### Configuration Files
- `quick_start_ubuntu_safe.sh` - Safe database setup for Ubuntu (includes autopilot columns)
- `quick_start_linux.sh` - Database setup for Linux
- `.env` - Environment variables (FTP credentials, Switch endpoint, etc.)

## External Dependencies

- **PostgreSQL**: Primary database for all application data
- **Enfocus Switch**: External print automation software at http://192.168.1.162:51088
- **http gem**: HTTP client for asset downloads and Switch webhooks
- **sinatra-activerecord gem**: Database interactions
- **pg gem**: PostgreSQL adapter
- **dotenv gem**: Environment variable management
- **Chart.js**: Interactive charts for analytics
- **FTP Server**: Optional FTP-based order import

## Debugging Autopilot

If autopilot is not working, check logs for these messages:

**SUCCESS FLOW:**
```
[API] 🔷 About to find order {id}
[API] 🔶 Order found, calling AutopilotService.process_order
[AutopilotService] ⏱ STARTING: Processing order {code}
[AutopilotService] → Checking item {id} (SKU: {sku})
[AutopilotService] Category: {name}, Autopilot: true
[AutopilotService] ✓ SUCCESS: Item {id} sent to preprint!
[API] 🔵 AutopilotService completed
```

**FAILURE FLOW:**
```
[API] ❌ StandardError: {error_class} - {error_message}
[API] ❌ Backtrace: {stack_trace}
```

**POSSIBLE ISSUES:**
1. **No product found for item** - Check if order items have valid SKUs in products table
2. **No category found for product** - Check if product has category assignment
3. **Autopilot NOT enabled for this category** - Go to /product_categories and enable autopilot with ⚡ toggle
4. **Item cannot be sent to preprint** - Check item status and preprint_status values
