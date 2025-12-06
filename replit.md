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
