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

#### ✅ **FIXED FOREIGN KEY VIOLATION IN ORDER EDIT (ERR_RESPONSE_HEADERS_MULTIPLE_LOCATION)**
  - **Problem**: PUT /orders/:id returned ERR_RESPONSE_HEADERS_MULTIPLE_LOCATION browser error - invalid response with multiple Location headers
  - **Root cause**: Used `delete_all` which bypassed dependent destroy callbacks, causing foreign key constraint error when trying to delete OrderItems with linked Assets
  - **Error**: `PG::ForeignKeyViolation: Key (id)=(48) is still referenced from table "assets"`
  - **Fix**: Changed `@order.order_items.delete_all` to `@order.order_items.destroy_all` (line 208)
  - **Logic**: `destroy_all` triggers `dependent: :destroy` callbacks in OrderItem model, cascading asset deletion before item deletion
  - **Result**: Order edit form now saves successfully - items and assets properly deleted, no constraint violations, redirect works

#### ✅ **FIXED INVENTORY FILTER NIL COMPARISON**: 
  - **Problem**: Sottoscorta/Disponibili tabs crashed when min_stock_level was nil
  - **Fix**: Added `min_stock_level &&` check before all comparisons
  - **Result**: Filter buttons work correctly, safe display with 'Non impostato' fallback

#### ✅ **FIXED FTP POLLER RETRY LOGIC**: 
  - **Problem**: Failed imports marked as processed, preventing retry on re-upload
  - **Fix**: `process_file()` now returns true/false; only successful imports tracked
  - **Result**: Failed orders can be re-uploaded and reprocessed automatically