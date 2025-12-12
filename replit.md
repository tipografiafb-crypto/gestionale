# Print Order Orchestrator

## Overview
The Print Order Orchestrator is a Ruby-based local print order management system using Sinatra and PostgreSQL. Its core function is to automate and streamline print production workflows for e-commerce orders. Key capabilities include downloading and organizing product images, integrating with Enfocus Switch for job processing, and tracking order statuses. The system offers a web interface for operational oversight, aiming to boost efficiency and minimize manual tasks in print production. It is designed to manage print orders originating from e-commerce platforms, offering a robust solution for print businesses.

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

The project employs an Enterprise-Grade Module Routing System with a feature-based organization.

### Tech Stack
- **Ruby**: 3.2.2
- **Web Framework**: Sinatra 4.2
- **Database**: PostgreSQL (via ActiveRecord 7.2)
- **Server**: Puma 6.6 on port 5000
- **Frontend**: Bootstrap 5 with ERB templates

### Key Features
- **Autopilot Preprint System**: Configurable categories for automatic job submission to Switch preprint upon order arrival.
- **Order Management**: Supports order import via API and FTP, with mapping for WooCommerce JSON format.
- **Asset Management**: Handles local download and organization of product images, tracked in a dedicated `assets` table.
- **Switch Integration**: Facilitates automated print workflows (preprint, print, label) through communication with Enfocus Switch.
- **Aggregated Jobs System**: Provides batch processing capabilities for multiple order items.
- **Print Workflow**: Manages print statuses and supports bulk print operations.
- **Analytics Dashboard**: Offers interactive charts for sales performance, top products, and category-wise sales.
- **Customer Notes**: Captures and displays customer instructions from orders.

### Database Schema
Core tables include: `stores`, `orders`, `order_items`, `assets`, `switch_jobs`, `aggregated_jobs`, `aggregated_job_items`, `product_categories` (with `autopilot_preprint_enabled`), `print_flows`, `products`, `inventory`, and `backup_configs`.

### API Endpoints
- `POST /api/orders/import`: Imports new orders, triggering autopilot processing if configured.
- `POST /product_categories/:id/toggle_autopilot`: Toggles the autopilot preprint feature for a specific product category.

### Configuration Files
- `quick_start_ubuntu_safe.sh`: Script for safe database setup on Ubuntu, including autopilot column creation.
- `quick_start_linux.sh`: General database setup script for Linux.
- `.env`: Manages environment variables such as FTP credentials and Switch endpoint.

## External Dependencies

- **PostgreSQL**: The primary relational database for all application data.
- **Enfocus Switch**: External print automation software, accessible at `http://192.168.1.162:51088`.
- **http gem**: Used as an HTTP client for asset downloads and interactions with Switch webhooks.
- **sinatra-activerecord gem**: Facilitates database interactions within the Sinatra framework.
- **pg gem**: PostgreSQL adapter for Ruby.
- **dotenv gem**: Manages environment variables for configuration.
- **Chart.js**: Utilized for rendering interactive charts in the analytics dashboard.
- **FTP Server**: An optional component for FTP-based order imports.

## Recent Work

### December 11, 2025 - Fixed Multiple Inventory & Order Edit Issues

#### ✅ **FIXED ORDER ITEM UPDATE LOGIC - PRESERVE ASSETS WHEN SKU CHANGES**
  - **Problem**: When editing an order and changing a product SKU, all attached files were destroyed
  - **Root cause**: Route was using `destroy_all` which deleted ALL OrderItems and their Assets, then recreated them from scratch
  - **Solution**: Added OrderItem ID tracking and smart update logic (lines 207-249)
  - **Implementation**:
    1. Added hidden field `<input type="hidden" name="items[][id]">` to form to track each OrderItem ID (views/new_order.erb line 46)
    2. Changed logic to: extract item IDs from request, delete only items NOT in request, update existing items instead of recreating
    3. Result: SKU/quantity changes now preserve all Assets - files are never destroyed unless explicitly deleted
  - **Key changes**:
    - `item_ids_in_request` = extract IDs from form submission
    - `@order.order_items.where.not(id: item_ids_in_request).destroy_all` = delete only removed items
    - Check `if item_params[:id].present?` and call `.update()` instead of creating new OrderItem

#### ✅ **FIXED INVENTORY FILTER NIL COMPARISON**: 
  - **Problem**: Sottoscorta/Disponibili tabs crashed when min_stock_level was nil
  - **Fix**: Added `min_stock_level &&` check before all comparisons
  - **Result**: Filter buttons work correctly, safe display with 'Non impostato' fallback

#### ✅ **FIXED FTP POLLER RETRY LOGIC**: 
  - **Problem**: Failed imports marked as processed, preventing retry on re-upload
  - **Fix**: `process_file()` now returns true/false; only successful imports tracked
  - **Result**: Failed orders can be re-uploaded and reprocessed automatically

#### ✅ **ADDED DUPLICATE ORDER DETECTION IN FTP POLLER**:
  - **Problem**: FTP poller would attempt to import orders that had already been imported, causing duplicate entries
  - **Solution**: Added check before processing - if `external_order_code` already exists in DB, file moved to failed folder (services/ftp_poller.rb lines 132-138)
  - **Implementation**: Check `Order.exists?(external_order_code: data['external_order_code'])` before creating new order
  - **Result**: Duplicate files automatically moved to `failed_orders_test/` with error reason "Order already imported: {code}"

#### ✅ **ADDED "RITARDO" (DELAYED) TAB TO /orders PAGE**:
  - **Problem**: Need to alert operators about orders that are taking too long to complete
  - **Solution**: Added new "Ritardo" tab showing orders created more than 7 days ago that haven't been completed
  - **Implementation**:
    1. Route GET /orders (routes/web_ui.rb lines 37-42): Calculate @delayed_orders filtered by status ['new', 'sent_to_switch', 'processing']
    2. View views/orders_list.erb (lines 82-87, 171-254): Add tab button with count badge, display delayed orders in yellow highlight table
  - **Key Details**: 
    - Threshold: 7 days (configurable via `delay_threshold = 7.days` in route)
    - Orders keep their original status, only displayed separately as alert
    - Yellow header and light yellow row highlighting for visual distinction
  - **Result**: Operators see clear visual alert for orders needing attention, all orders preserve their original status