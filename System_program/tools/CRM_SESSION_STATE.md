# CRM Integration Session State - Summary

**Date**: 2026-02-27
**Status**: Implementation Complete & Verified Local

## Overview
Successfully integrated CRM features into the `gestionale` application. The system now pulls customer and financial data from WordPress via FTP polling and displays it in a dedicated CRM dashboard.

## Key Components Implemented

### 1. WordPress Plugin (`wp-order-sync`)
- **`includes/sync.php`**: 
    - Added `wos_generate_crm_json()` to create a JSON payload for CRM.
    - Added `wos_sync_order_to_ftp()` update to upload a second JSON (`crm_order_*.json`) to a `/crm/` subfolder.
    - Added `wos_sync_crm_data_only()` for historical data recovery without re-sending production orders.
- **`includes/settings.php`**:
    - Added CRM toggle and FTP CRM path settings.
    - Added "Sincronizza TUTTI gli ordini Processing per CRM (storico)" button for bulk export.

### 2. Rails Backend (`gestionale`)
- **Database**:
    - Tables: `customers`, `sales`, `sale_items`.
    - Integrated schema into `install.sh`, `install_fresh.sh`, and `quick_start_ubuntu_safe.sh`.
- **Models**:
    - `Customer`: Handles `upsert_from_crm` logic and statistics (total spent, order count).
    - `Sale` & `SaleItem`: Represent the financial orders.
- **Service**:
    - `CRMPoller`: Background thread polling FTP `/crm/` directory. Handles JSON parsing, data transaction, and file management (imported/failed).
- **UI (Bootstrap 5)**:
    - Dashboard (`/crm`): KPIs, Revenue Chart (30d), Top Customers, Recent Sales. Supports **Site Filtering**.
    - Customers List (`/crm/customers`): Search, Site Filter, Sorting.
    - Sales List (`/crm/sales`): Order lookup, Date range filters.
    - Customer Details: Sales history and editable notes.

### 3. Manual Tools
- **`scripts/manual_crm_import.rb`**: Utility script to manually import a CRM JSON file for testing/recovery.

## Resume Instructions
1.  **Deployment**: Use `./quick_start_ubuntu_safe.sh` on the Ubuntu server to apply the new schema and update gems.
2.  **Plugin Setup**: Ensure CRM is enabled in WordPress settings and the FTP path points to the `/crm/` subdirectory of the main order folder.
3.  **Polling**: The `CRMPoller` starts automatically with the app. Default interval is 120s (configurable via `CRM_POLL_INTERVAL`).

## Latest Task Completed
- Added site-based filtering to the CRM Dashboard and Customer List.
- Verified manual import with real WooCommerce JSON data.

---
*Session closed by Antigravity AI.*
