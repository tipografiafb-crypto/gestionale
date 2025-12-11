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

### December 11, 2025 - Fixed FTP Polling Retry Logic for Failed Imports
- ✅ **FIXED FTP POLLER RETRY LOGIC**: 
  - **Previous**: Files marked as processed even if import failed, preventing retry
  - **Problem**: If ordine failed and was re-uploaded for retry, poller would skip it
  - **Root cause**: `@processed_files` Set was tracking ALL files, not just successful imports
  - **Fix**: `process_file()` now returns `true/false` based on success
  - **Result**: Only successful imports are added to `@processed_files`
  - **Behavior**: Failed imports can be re-uploaded and will be processed again
  - **Example**: Order fails → move to failed folder → fix issue → re-upload → poller processes it ✓

## Recent Work (Autopilot Fixes)

### December 9, 2025 - Autopilot Payload Fixed (IDENTICAL to Manual Send) + Filename Bug Fixed
- ✅ **FIXED FILENAME COUNTRY CODE BUG**: 
  - **Previous**: Files were always named "EU{number}" instead of using the actual country code from order
  - **Example**: Order "DE11273" became "EU11273-1.png" instead of "DE11273-1.png"
  - **Root cause**: `switch_filename_for_asset()` hardcoded "eu" prefix instead of reading from JSON `id` field
  - **Fix**: Now uses `external_order_code` directly from JSON (e.g., "IT9395" from `id` field)
  - **Result**: Files now correctly named with full order code: "IT9395-1.png", "DE11273-1_F.png", etc.
  - **Applies to**: Both manual send AND autopilot (they use same method)
  - **Why safer**: Uses value directly from JSON instead of string manipulation - no parsing errors

### December 9, 2025 - Autopilot Payload Fixed (IDENTICAL to Manual Send + Order Status Update)
- ✅ **AUTOPILOT NOW EXECUTES IDENTICAL LOGIC TO MANUAL SEND**:
  - Copies EXACT payload structure from `/orders/:order_id/items/:item_id/send_preprint` route
  - Sends EACH print asset individually (not just first asset)
  - Uses correct field mappings from manual route
  - **Updates order status from 'new' → 'processing'** (same as manual route)
  
- ✅ **FIXED PAYLOAD FIELDS**:
  - `id_riga`: Uses `item.item_number` (not `item.id`)
  - `job_operation_id`: Simple `item.id.to_s` (not prefixed)
  - `filename`: Dynamic per asset via `item.switch_filename_for_asset(print_asset)` (not hardcoded)
  - `materiale`: From `product&.notes || 'N/A'` (not custom `product.material()` method)
  - `url`: Server base URL `/api/assets/#{asset.id}/download` (not gestionale)
  - `campi_webhook`: Includes `{ "percentuale" => "0" }` (not empty)
  - `preprint_print_flow_id`: Stored in order_item (same as manual)
  - `preprint_job_id`: Comma-separated list of successful asset IDs
  
- ✅ **FIXED ORDER STATUS UPDATE**: 
  - AutopilotService updates order status to 'processing' ONLY if at least one item is actually sent
  - Orders with NO items having autopilot enabled remain in status 'new'
  - These stay visible in the "Nuovi" (new orders) tab for manual processing
  - Uses logic: Check all items first, then update status only if `processed_count > 0`
  
- ✅ **DYNAMIC ENDPOINT RETRIEVAL**: 
  - For each order item, retrieves: `product.default_print_flow.preprint_webhook.hook_path`
  - E.g.: `/plettro_automatico`, `/custom_endpoint`, etc. - whatever configured in print flow
  - Validates all steps: product → default_print_flow → preprint_webhook → hook_path
  - Graceful error handling if any step missing
  
- ✅ **ADDED 60-SECOND DELAY BEFORE SWITCH SEND (ASYNC, NON-BLOCKING)**:
  - AutopilotService schedules send to Switch in background thread (60 second delay)
  - Non-blocking: import returns immediately, delay happens in background
  - Ensures all files are completely downloaded to the server
  - Prevents premature Switch send while files are still downloading
  - Multiple orders can be imported simultaneously without interference
  - Each order's thread waits 60 seconds independently before sending to Switch
  - Logged with [ASYNC] prefix for background operations

- 🎯 **AUTOPILOT NOW 100% COMPATIBLE WITH MANUAL SEND**:
  - Identical payload format = guaranteed Switch compatibility
  - Sends multiple assets per item (same as manual)
  - Same field mappings and URL structures
  - Error handling mirrors manual route logic
  - Order status updates correctly ('new' → 'processing')
  - 60-second delay ensures server-side file downloads complete

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
