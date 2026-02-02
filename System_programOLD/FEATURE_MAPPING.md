# Feature Mapping

> **Auto-generated**: Last updated 2025-11-20
> 
> **Purpose**: Map features to their corresponding files and modules

## Feature: `orders`

**Description**: Order management, import, and data models

**Files**:
- `models/store.rb` - Store model
- `models/order.rb` - Order model
- `models/order_item.rb` - OrderItem model
- `routes/orders_api.rb` - Orders API endpoints
- `db/migrate/001_create_stores.rb` - Store migration
- `db/migrate/002_create_orders.rb` - Order migration
- `db/migrate/003_create_order_items.rb` - OrderItem migration

**API Endpoints**:
- `POST /api/orders/import` - Import new order
- `POST /api/orders/:id/download_assets` - Download assets
- `POST /api/orders/:id/send_to_switch` - Send to Switch

## Feature: `storage`

**Description**: Asset management and image downloads

**Files**:
- `models/asset.rb` - Asset model
- `services/asset_downloader.rb` - Asset download service
- `db/migrate/004_create_assets.rb` - Asset migration
- `storage/` - Local file storage directory

**Responsibilities**:
- Download images from URLs
- Store files locally
- Track download status
- Manage file paths

## Feature: `switch`

**Description**: Enfocus Switch integration

**Files**:
- `models/switch_job.rb` - SwitchJob model
- `services/switch_client.rb` - Switch API client
- `routes/switch_api.rb` - Switch webhook handler
- `db/migrate/005_create_switch_jobs.rb` - SwitchJob migration

**API Endpoints**:
- `POST /api/switch/callback` - Receive Switch callbacks

**Responsibilities**:
- Send jobs to Switch
- Receive job results
- Track job status
- Handle callbacks

## Feature: `ui`

**Description**: Web interface for operators

**Files**:
- `routes/web_ui.rb` - Web UI routes
- `views/layout.erb` - Layout template
- `views/orders_list.erb` - Orders list view
- `views/order_detail.erb` - Order detail view
- `views/not_found.erb` - 404 page

**Routes**:
- `GET /` - Redirect to orders
- `GET /orders` - List all orders
- `GET /orders/:id` - Order detail
- `POST /orders/:id/download` - Download trigger
- `POST /orders/:id/send` - Send to Switch trigger

## Feature: `integration`

**Description**: External integrations and core application

**Files**:
- `app.rb` - Main application
- `config.ru` - Rack configuration
- `config/database.yml` - Database config
- `Gemfile` - Ruby dependencies

## Feature: `quality`

**Description**: Code quality, testing, and documentation

**Files**:
- `README.md` - Project documentation
- `replit.md` - Replit-specific info
- `AGENT_WORKFLOW.md` - Agent workflow guide
- `System_program/` - System documentation

## Cross-Feature Dependencies

### Database Models
All features depend on the database models:
- `orders` → `storage` (Order has many Assets through OrderItems)
- `orders` → `switch` (Order has one SwitchJob)
- `storage` → `orders` (Asset belongs to OrderItem)
- `switch` → `orders` (SwitchJob belongs to Order)

### Services
- `storage.AssetDownloader` uses `orders.Order`, `storage.Asset`
- `switch.SwitchClient` uses `orders.Order`, `switch.SwitchJob`

### Views
- UI features depend on all models for display
