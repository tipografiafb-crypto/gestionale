# Print Order Orchestrator

## Overview

A local Ruby/Sinatra application for managing print orders from e-commerce platforms with Magenta Product Designer plugin integration. The system handles order imports from multiple stores, downloads and organizes print assets locally, integrates with Enfocus Switch for print job processing, and provides a web dashboard for order management and workflow tracking.

## User Preferences

Preferred communication style: Simple, everyday language.

## System Architecture

### Backend Framework
- **Sinatra 4.2** as the web framework with a modular route structure
- **ActiveRecord 7.2** as the ORM for database operations
- **Puma 6.6** as the web server
- Routes are organized by feature in `routes/` directory (orders, switch jobs, aggregation, analytics, etc.)

### Database Design
- **PostgreSQL** with ActiveRecord migrations in `db/migrate/`
- Core models: `Store`, `Order`, `OrderItem`, `Asset`, `Product`, `PrintFlow`, `SwitchWebhook`, `SwitchJob`
- Products link to categories and print flows for workflow routing
- Assets track downloaded files with local paths and download status

### Order Processing Pipeline
1. Orders imported via API from e-commerce platforms (WooCommerce with Lumise/Magenta customizer)
2. Print files and screenshots downloaded from remote URLs to local storage
3. Products matched by SKU to determine print flow routing
4. Jobs sent to Enfocus Switch via webhooks for preprint processing
5. Results received back and stored as new assets

### Storage Architecture
- Local file storage organized as `storage/{store_code}/{order_number}/{sku}/`
- Assets track both remote URLs and local file paths
- File download status tracked per asset

### Switch Integration
- Webhooks configured per print flow for different product types
- Autopilot service for automatic job submission when assets are ready
- Job status tracking (pending, sent, completed, failed)
- Results received via callback API endpoints

### Web Interface
- Bootstrap 5 frontend with ERB templates in `views/`
- Dashboard for order listing and status overview
- Order detail pages with asset previews
- Admin pages for products, print flows, webhooks, and print machines

## External Dependencies

### Database
- **PostgreSQL**: Primary data store for all application data

### E-commerce Integration
- **WooCommerce REST API**: Order data import from multiple store instances
- **Lumise/Magenta Designer**: Custom product artwork files referenced in orders

### Print Workflow
- **Enfocus Switch**: Print automation server receiving jobs via HTTP webhooks
- Switch webhooks configured with base URL and path prefix for job submission
- Callback endpoints receive processed results (PDFs, previews)

### File Sources
- **AWS S3**: Some stores use S3 for print file hosting
- **WooCommerce uploads**: Direct file downloads from store servers

### Background Services
- **FTP Poller**: Monitors FTP server for incoming order JSON files
- **Autopilot Service**: Automatic job submission based on product category settings