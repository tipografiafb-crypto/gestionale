# 🖨️ Print Order Orchestrator!

A local Ruby application for managing print orders from e-commerce platforms with Magenta Product Designer plugin integration.

## Features

✅ **Order Management**
- Import orders from e-commerce platforms via API
- Store order data with PostgreSQL
- Track order status through workflow

✅ **Asset Storage**
- Download images from remote URLs
- Organize files locally by store/order/SKU
- Track download status

✅ **Enfocus Switch Integration**
- Send jobs to Switch via webhook
- Receive job results and previews
- Track job status and logs

✅ **Web Interface**
- View all orders in a clean table
- See order details with item and asset previews
- Trigger downloads and Switch jobs with buttons

## Tech Stack

- **Language**: Ruby 3.2
- **Framework**: Sinatra 4.2
- **Database**: PostgreSQL (via ActiveRecord 7.2)
- **Server**: Puma 6.6
- **Frontend**: HTML + Bootstrap 5

## Quick Start

### Prerequisites

This project runs on Replit with Ruby 3.2 and PostgreSQL configured.

### Installation

1. Install dependencies:
```bash
bundle install
```

2. Set up database:
```bash
bundle exec rake db:create db:migrate
```

3. Configure environment variables (copy `.env.example` to `.env`):
```bash
DATABASE_URL=postgresql://localhost/print_orchestrator_development
SWITCH_WEBHOOK_URL=http://your-switch-server/webhook
SWITCH_API_KEY=your_api_key
```

4. Start the server:
```bash
bundle exec puma -p 5000 -b tcp://0.0.0.0 config.ru
```

The application will be available at `http://localhost:5000`

## API Documentation

### Import Order

**Endpoint**: `POST /api/orders/import`

**Request Body**:
```json
{
  "store_id": "TPH_DE",
  "external_order_code": "DE11132",
  "items": [
    {
      "sku": "PICK-ROCK-1MM",
      "quantity": 100,
      "image_urls": [
        "https://example.com/orders/DE11132/front.png",
        "https://example.com/orders/DE11132/back.png"
      ]
    }
  ]
}
```

**Response**:
```json
{
  "success": true,
  "order_id": 1,
  "external_order_code": "DE11132",
  "items_count": 1,
  "assets_count": 2
}
```

### Download Assets

**Endpoint**: `POST /api/orders/:id/download_assets`

**Response**:
```json
{
  "success": true,
  "results": {
    "downloaded": 2,
    "errors": 0,
    "skipped": 0,
    "messages": [...]
  }
}
```

### Send to Switch

**Endpoint**: `POST /api/orders/:id/send_to_switch`

**Response**:
```json
{
  "success": true,
  "job_id": "switch-123",
  "message": "Sent to Switch successfully"
}
```

### Switch Callback

**Endpoint**: `POST /api/switch/callback`

**Request Body**:
```json
{
  "external_order_code": "DE11132",
  "status": "done",
  "result_preview_url": "http://switch-server/output/DE11132/preview.pdf",
  "log": "Processing completed successfully"
}
```

## Project Structure

```
├── app.rb                      # Main application file
├── config.ru                   # Rack configuration
├── Gemfile                     # Ruby dependencies
│
├── config/
│   └── database.yml            # Database configuration
│
├── db/
│   └── migrate/                # Database migrations
│
├── models/                     # ActiveRecord models
│   ├── store.rb
│   ├── order.rb
│   ├── order_item.rb
│   ├── asset.rb
│   └── switch_job.rb
│
├── services/                   # Business logic
│   ├── asset_downloader.rb
│   └── switch_client.rb
│
├── routes/                     # Route handlers
│   ├── orders_api.rb
│   ├── switch_api.rb
│   └── web_ui.rb
│
├── views/                      # ERB templates
│   ├── layout.erb
│   ├── orders_list.erb
│   ├── order_detail.erb
│   └── not_found.erb
│
├── storage/                    # Local file storage
│
└── System_program/             # AI Agent workflow system
    ├── FEATURE_MAPPING.md
    ├── SYSTEM_STATUS.md
    └── scope/                  # Feature scope definitions
```

## Database Schema

### Stores
- Represents e-commerce stores (TPH_IT, TPH_DE, etc.)

### Orders
- Main order entity from e-commerce platforms
- Status: new → sent_to_switch → processing → done/error

### OrderItems
- Individual items within an order
- Contains SKU, quantity, and optional JSON data

### Assets
- Images and files for order items
- Tracks download status and local paths

### SwitchJobs
- Tracks jobs sent to Enfocus Switch
- Stores results, previews, and logs

## Extension Guide

### Adding New Features

1. **Read the Agent Workflow**: Check `AGENT_WORKFLOW.md` for feature targeting guidelines

2. **Choose Your Feature**: Select from `orders`, `storage`, `switch`, `ui`, `integration`, or `quality`

3. **Check Scope Files**: Review `System_program/scope/<feature>.allow` and `.deny` files

4. **Make Surgical Changes**: Modify only files within your feature scope

### Adding New Models

1. Create migration in `db/migrate/`
2. Create model file in `models/`
3. Add validations and associations
4. Run migration: `bundle exec rake db:migrate`

### Adding New API Endpoints

1. Add route in appropriate file (`routes/orders_api.rb`, etc.)
2. Implement business logic in service if needed
3. Return consistent JSON format
4. Update this README with endpoint documentation

### Adding New Services

1. Create service file in `services/`
2. Follow single responsibility principle
3. Add comments with `@feature` and `@domain` tags
4. Write tests (when test framework is added)

## Environment Variables

| Variable | Description | Required |
|----------|-------------|----------|
| DATABASE_URL | PostgreSQL connection string | Yes |
| SWITCH_WEBHOOK_URL | Enfocus Switch webhook endpoint | Yes |
| SWITCH_API_KEY | API key for Switch | No |
| PORT | Server port (default: 5000) | No |
| RACK_ENV | Environment (development/production) | No |

## Development

### Running Migrations

```bash
# Create migration
bundle exec rake db:create_migration NAME=your_migration_name

# Run migrations
bundle exec rake db:migrate

# Rollback last migration
bundle exec rake db:rollback
```

### Console Access

```bash
# Open IRB with app loaded
bundle exec irb -r ./app.rb
```

### Logs

Server logs are available in the Replit console or workflow logs.

## Production Deployment

This application is designed to run on Replit. The workflow is already configured to start Puma on port 5000.

For custom deployment:
1. Set environment variables
2. Run migrations
3. Start Puma with appropriate config
4. Set up reverse proxy (nginx) if needed

## Troubleshooting

### Database Connection Issues
- Check DATABASE_URL environment variable
- Verify PostgreSQL is running
- Run migrations if schema is missing

### Asset Download Fails
- Check image URLs are accessible
- Verify storage directory has write permissions
- Check HTTP timeout settings in `asset_downloader.rb`

### Switch Integration Issues
- Verify SWITCH_WEBHOOK_URL is correct
- Check SWITCH_API_KEY if authentication required
- Review Switch job logs in web interface

## License

Proprietary - All rights reserved

## Support

For issues and questions, consult:
- `AGENT_WORKFLOW.md` for development workflow
- `System_program/FEATURE_MAPPING.md` for feature organization
- `System_program/SYSTEM_STATUS.md` for system health
