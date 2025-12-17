# Print Order Orchestrator

## Overview
The Print Order Orchestrator is a Ruby-based local print order management system built with Sinatra and PostgreSQL. Its primary goal is to automate and streamline print production workflows for e-commerce orders. Key functionalities include downloading and organizing product images, integrating with Enfocus Switch for job processing, and tracking order statuses. The system provides a web interface for operational oversight, aiming to enhance efficiency and minimize manual tasks in print production. It is designed to manage print orders originating from various e-commerce platforms, offering a robust solution for print businesses.

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

## System Architecture

The project utilizes an Enterprise-Grade Module Routing System with a feature-based organization.

### Tech Stack
- **Ruby**: 3.2.2
- **Web Framework**: Sinatra 4.2
- **Database**: PostgreSQL (via ActiveRecord 7.2)
- **Server**: Puma 6.6 on port 5000
- **Frontend**: Bootstrap 5 with ERB templates

### Key Features
- **Autopilot Preprint System**: Configurable categories for automatic job submission to Switch preprint upon order arrival.
- **Order Management**: Supports order import via API and FTP, with mapping for WooCommerce JSON format. Includes duplicate order detection and improved inventory deduction for FTP imports.
- **Asset Management**: Handles local download and organization of product images, tracked in a dedicated `assets` table. Features an image offset editor for print files with transparency preservation.
- **Switch Integration**: Facilitates automated print workflows (preprint, print, label) through communication with Enfocus Switch.
- **Aggregated Jobs System**: Provides batch processing capabilities for multiple order items.
- **Print Workflow**: Manages print statuses and supports bulk print operations.
- **Analytics Dashboard**: Offers interactive charts for sales performance, top products, and category-wise sales.
- **Customer Notes**: Captures and displays customer instructions from orders.
- **Backup System**: Automated daily backup of the database to an external server.
- **Pagination**: Manual pagination implemented across all major list views (orders, products, stores, webhooks, line items, inventory) for improved performance and UI.

### Database Schema
Core tables include: `stores`, `orders`, `order_items`, `assets`, `switch_jobs`, `aggregated_jobs`, `aggregated_job_items`, `product_categories` (with `autopilot_preprint_enabled`), `print_flows`, `products`, `inventory`, and `backup_configs`.

### API Endpoints
- `POST /api/orders/import`: Imports new orders, triggering autopilot processing if configured.
- `POST /product_categories/:id/toggle_autopilot`: Toggles the autopilot preprint feature for a specific product category.
- `POST /assets/:id/adjust`: Saves adjusted image offsets for assets (receives base64 PNG, saves to disk).
- `POST /assets/:id/restore`: Restores original image from backup.

### Configuration Files
- `quick_start_ubuntu_safe.sh`: Script for safe database setup on Ubuntu.
- `quick_start_linux.sh`: General database setup script for Linux.
- `.env`: Manages environment variables such as FTP credentials and Switch endpoint.

## External Dependencies

- **PostgreSQL**: The primary relational database.
- **Enfocus Switch**: External print automation software, accessible at `http://192.168.1.162:51088`.
- **http gem**: Used as an HTTP client for asset downloads and interactions with Switch webhooks.
- **sinatra-activerecord gem**: Facilitates database interactions within the Sinatra framework.
- **pg gem**: PostgreSQL adapter for Ruby.
- **dotenv gem**: Manages environment variables for configuration.
- **Chart.js**: Utilized for rendering interactive charts in the analytics dashboard.
- **FTP Server**: An optional component for FTP-based order imports.

## Recent Work

### December 15, 2025 - System Logging Dashboard

#### ✅ **ADDED SYSTEM LOGS PAGE**:
  - **Feature**: Real-time system logging page to monitor all application events
  - **Location**: New route `/logs` - visible in web UI
  - **Capabilities**:
    - View last 500 log entries with auto-refresh every 30 seconds
    - Filter by log level (Info, Warn, Error, Debug)
    - Filter by category (FTP, Order, Switch, Asset, Import, System)
    - Shows total log count and last 24h entries
    - Color-coded badges (red for errors, yellow for warnings)
    - Timestamps and detailed messages
  - **Technical Details**:
    - New `Log` model with `level`, `category`, `message`, `details` fields
    - `AppLogger` utility class for simple logging throughout app: `AppLogger.info(category, message, details)`
    - Indexes on `level`, `category`, `created_at` for performance
    - PostgreSQL logs table with auto-pagination
  - **How to Use**:
    1. Click "Log di Sistema" in navbar or visit `/logs`
    2. View real-time events as they happen
    3. Filter by level or category to find specific issues
    4. Page auto-refreshes every 30 seconds
  - **Files Added**:
    - `models/log.rb` - Log model with scopes for filtering
    - `lib/app_logger.rb` - Simple logging utility
    - `views/logs.erb` - Responsive log viewer UI
    - `routes/web_ui.rb` - GET /logs route
  - **Integration Points**: 
    - FTP poller can call: `AppLogger.warn('ftp', 'Connection failed', error_details)`
    - Order import can call: `AppLogger.info('order', 'Order imported', order_code)`
    - Switch callbacks can call: `AppLogger.error('switch', 'Job failed', job_error)`
  - **Ready for Extension**: Use AppLogger throughout codebase to track system health

### December 15, 2025 - Image Offset & Zoom Editor with Transparency Support

#### ✅ **ADDED IMAGE OFFSET & ZOOM EDITOR FOR PRINT FILES**:
  - **Feature**: Operators can adjust the position and scale of print file images using offset sliders and zoom control while preserving transparency
  - **Location**: Order Item Detail page (`/orders/:order_id/items/:item_id`) - "Modifica Offset" button (yellow arrows icon) on print file images
  - **Controls**:
    - **Zoom**: 0.5x to 2x magnification (slider with 0.01 step + number input)
    - **Offset X**: -200 to +200 px horizontal position
    - **Offset Y**: -200 to +200 px vertical position
    - **Reset button**: Resets both zoom and offsets to defaults (1x, 0, 0)
  - **How to use**: 
    1. Open an order and click on a job
    2. In "File di Stampa", find an image file (PNG, JPG, etc.)
    3. Click the yellow arrows button (Modifica Offset)
    4. Adjust zoom with slider or number input (0.5x - 2x)
    5. Adjust X/Y offset with sliders or number inputs (-200 to +200 px)
    6. Click "Salva Immagine" to save
  - **Restore Feature**:
    - Click the history/back button to restore the original image from backup
    - Requires confirmation to prevent accidental overwrites
  - **Backup Strategy**:
    - Original file preserved as `filename_original_backup.png` (created once per image)
    - Modified version overwrites original (same filename, same asset ID)
    - Database asset record stays unchanged
    - Transparency is fully preserved in PNG exports
  - **Technical Implementation**:
    1. Canvas displays image with white background for preview (zoom + offset applied with `destination-over` composite)
    2. Zoom is applied via `ctx.scale(currentZoom, currentZoom)` for smooth scaling
    3. When saving, a temporary canvas is created WITHOUT the white background
    4. Only the image with zoom and offset is drawn on the temporary canvas
    5. Exported as PNG which fully preserves transparency channels
    6. JavaScript syncs sliders ↔ number inputs in real-time
    7. POST `/assets/:id/adjust` saves base64 PNG to disk with backup (only offset saved, not zoom)
    8. POST `/assets/:id/restore` recovers from backup
  - **Files Modified**:
    - `views/order_item_detail.erb` - Modal UI with zoom controls, Canvas preview, sync logic for both zoom and offset, temporary canvas without background for saving
    - `routes/web_ui.rb` - Two endpoints: /adjust (save with backup) and /restore (recover)
  - **Result**: Operators can visually scale and position images before printing, with full transparency support and one-click restore. Transparency is correctly preserved in saved PNG files.

### December 17, 2025 - Auto-Close Order When All Items Completed

#### ✅ **FIXED: ORDER AUTO-COMPLETES WHEN ALL ITEMS PRINT-CONFIRMED**:
  - **Issue**: Order remained in 'processing' status even after all line items were print-confirmed. Required manual "forza chiusura" to mark order as done.
  - **Fix**: Added automatic order status update in POST `/orders/:order_id/items/:item_id/confirm_print` route
  - **How it works**:
    1. When operator confirms print completion on an item (click "Stampa confermata")
    2. Item is marked as `print_status: 'completed'`
    3. System checks if ALL items in the order are now completed
    4. If yes, order is automatically updated to `status: 'done'`
  - **Result**: Orders now automatically transition to completed status without manual intervention
  - **Files Modified**:
    - `routes/order_items_switch.rb` - Added check in confirm_print route to auto-complete order

### December 17, 2025 - Item Numbering Fix: Position-Based Ordering

#### ✅ **FIXED: ORDER ITEMS NOW DISPLAY & NUMBER IN CORRECT JSON IMPORT ORDER**:
  - **Issue**: Order items were displayed in mismatched order compared to JSON import. Item numbering (used for file naming: `IT9410-1.png`, `IT9410-2.png`, etc.) was based on database ID order, not JSON array position order.
  - **Root Cause**: `item_number` method counted items with `id <= current_id` (ID-based ordering), causing mismatch when items had non-sequential IDs. Views used `.each` without explicit ordering.
  - **Solution**: Added `position` field to track JSON import order, with fallback to legacy ID-based logic for existing orders.
  - **How it works**:
    1. **Database**: New `position` integer field (created via migration `20251217100300_add_position_to_order_items.rb`) stores position (1, 2, 3...) based on JSON array index
    2. **Import Logic**: FTP poller and manual order creation now save `position: idx + 1` when creating order items
    3. **Item Numbering**: `item_number` method returns position if set, falls back to ID-based counting for legacy data
    4. **Display Order**: Views now use `.ordered` scope (orders by position ASC) to display items in correct sequence
    5. **File Naming**: Switch filenames now correctly match visual order: `IT9410-1.png`, `IT9410-2.png`, etc.
  - **Files Modified**:
    - `db/migrate/20251217100300_add_position_to_order_items.rb` - New migration adding position column with index
    - `models/order_item.rb` - Updated `item_number` method with fallback, added `.ordered` scope
    - `routes/web_ui.rb` - Save position when creating order items (2 locations: POST /orders, PATCH /orders/:id)
    - `services/ftp_poller.rb` - Save position during FTP JSON import
    - `views/order_detail.erb` - Use `.ordered` scope to display items by position
  - **Migration Status**: Migration file `20251217100300_add_position_to_order_items.rb` ready to run. If position field doesn't exist yet, fallback logic ensures backward compatibility with existing orders.
