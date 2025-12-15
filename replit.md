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
- **Asset Management**: Handles local download and organization of product images, tracked in a dedicated `assets` table. Features an image offset editor for print files.
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

### December 15, 2025 - Image Offset Editor

#### ✅ **ADDED IMAGE OFFSET EDITOR FOR PRINT FILES**:
  - **Feature**: Operators can adjust the position of print file images using X/Y offset sliders
  - **Location**: Order Item Detail page (`/orders/:order_id/items/:item_id`) - new "Modifica Offset" button (arrows icon) on print file images
  - **How to use**: 
    1. Open an order and click on a job
    2. In "File di Stampa", find an image file (PNG, JPG, etc.)
    3. Click the yellow arrows button to open the editor
    4. Adjust X/Y offset with sliders or number inputs
    5. Click "Salva Immagine" to save
  - **Backup Strategy**:
    - Original file is **preserved on disk** (never deleted)
    - Modified version saved as `filename_adjusted_<timestamp>.png`
    - Database asset points to new modified version
    - If needed, original can be recovered from filesystem
  - **Implementation**:
    1. Added `#imageAdjustModal` modal with HTML5 Canvas for real-time preview
    2. X and Y offset sliders (-200 to +200 px) with number inputs for precise values
    3. JavaScript draws image with offset on canvas, fills background with white
    4. POST `/assets/:id/adjust` route saves adjusted image with unique timestamp
  - **Files Modified**:
    - `views/order_item_detail.erb` - Added modal, button, and JavaScript
    - `routes/web_ui.rb` - Added POST `/assets/:id/adjust` endpoint
