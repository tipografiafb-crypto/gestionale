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

## System Architecture

The project follows an Enterprise-Grade Module Routing System with a feature-based organization.

### Tech Stack
- **Ruby**: 3.2.2
- **Web Framework**: Sinatra 4.2
- **Database**: PostgreSQL (via ActiveRecord 7.2)
- **Server**: Puma 6.6 on port 5000
- **Frontend**: Bootstrap 5 with ERB templates

### UI/UX Decisions
The web interface for operators (`ui` module) is built using ERB templates and Bootstrap 5 for a responsive and functional design. The system includes an Analytics Dashboard with interactive charts (Chart.js) for daily sales, top products, sales by category, and weekly comparisons, along with filtering capabilities. Order detail pages include editable notes for operators.

### Technical Implementations
- **Order Management**: Handles order import via API and FTP, supporting WooCommerce JSON format mapping.
- **Asset Management**: Downloads and organizes product images locally, tracking them via `assets` table.
- **Switch Integration**: Communicates with Enfocus Switch for automated print workflow, supporting preprint, print, and label operations with standardized webhook payloads.
- **Aggregated Jobs System**: Implements batch processing for multiple items, moving through statuses like pending, aggregating, aggregated, printing, and completed.
- **Print Workflow**: Manages print statuses (e.g., 'ripped', 'processing', 'completed') and facilitates bulk print operations.
- **Database Schema**: Utilizes ActiveRecord for PostgreSQL, with tables for `stores`, `orders`, `order_items`, `assets`, `switch_jobs`, `aggregated_jobs`, and `aggregated_job_items`.

### System Design Choices
The project emphasizes a modular structure, separating concerns into distinct modules like `orders`, `storage`, `switch`, `ui`, `integration`, and `quality`. This design supports targeted development and maintenance, guided by a system_program structure for AI agent workflows.

## External Dependencies

- **PostgreSQL**: Primary database for all application data, configured via Replit's built-in database service.
- **Enfocus Switch**: External print automation software. The system integrates with Switch via webhooks for sending job requests (preprint, print, label) and receiving callbacks.
- **http gem**: Used as an HTTP client for external service interactions, including asset downloads and sending webhooks to Switch.
- **sinatra-activerecord gem**: Facilitates database interactions with PostgreSQL.
- **pg gem**: PostgreSQL adapter for Ruby.
- **dotenv gem**: Manages environment variables for configuration.
- **Chart.js**: JavaScript library used for rendering interactive charts in the analytics dashboard.
- **FTP Server (Optional)**: For optional FTP-based order import, requiring `FTP_HOST`, `FTP_USER`, `FTP_PASS`, etc., environment variables.