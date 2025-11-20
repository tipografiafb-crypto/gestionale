# Print Order Orchestrator - Replit Project

## Overview

Local print order management system built with Ruby, Sinatra, and PostgreSQL. Integrates with Magenta Product Designer and Enfocus Switch for automated print workflow.

## Project Status

✅ **MVP Complete** (November 2025)
- Database schema and migrations
- Order import API
- Asset download service
- Switch integration
- Web interface
- Agent workflow system

## Recent Work

### November 20, 2025
- Initial project setup with Ruby 3.2 and Sinatra 4.2
- Created all database models and migrations
- Implemented API endpoints for order management
- Built services for asset downloads and Switch integration
- Created web UI with Bootstrap
- Established System_program structure for AI agent workflows
- Configured Puma workflow on port 5000

## Structure

The project follows an Enterprise-Grade Module Routing System with feature-based organization:

- **orders**: Order management and data models
- **storage**: Asset downloads and file management
- **switch**: Enfocus Switch integration
- **ui**: Web interface for operators
- **integration**: Core application and external APIs
- **quality**: Code quality and documentation

See `AGENT_WORKFLOW.md` for detailed workflow guidelines.

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

## Architecture

### Tech Stack
- **Ruby**: 3.2.2
- **Web Framework**: Sinatra 4.2
- **Database**: PostgreSQL (via ActiveRecord 7.2)
- **Server**: Puma 6.6 on port 5000
- **Frontend**: Bootstrap 5 with ERB templates

### Key Dependencies
- sinatra-activerecord - Database integration
- http - HTTP client for downloads and webhooks
- pg - PostgreSQL adapter
- dotenv - Environment configuration

## Database

PostgreSQL database configured via Replit's built-in database service.

Tables:
- `stores` - E-commerce stores
- `orders` - Print orders
- `order_items` - Items within orders
- `assets` - Images and files
- `switch_jobs` - Switch job tracking

Run migrations:
```bash
bundle exec rake db:migrate
```

## Workflows

**Print Orchestrator** (Port 5000)
- Command: `bundle exec puma -p 5000 -b tcp://0.0.0.0 config.ru`
- Output: webview
- Status: Running

## Environment Variables

Required:
- `DATABASE_URL` - PostgreSQL connection (auto-configured)
- `SWITCH_WEBHOOK_URL` - Enfocus Switch webhook endpoint

Optional:
- `SWITCH_API_KEY` - Switch API authentication
- `PORT` - Server port (default: 5000)
- `RACK_ENV` - Environment mode

## Extension Guidelines

When adding features:

1. **Choose Feature Target**: Select from orders, storage, switch, ui, integration, or quality
2. **Check Scope**: Review `System_program/scope/<feature>.allow` and `.deny`
3. **Make Changes**: Modify only permitted files
4. **Test**: Verify functionality through web UI or API
5. **Document**: Update relevant documentation

See `README.md` for detailed API documentation and examples.

## Testing

To test the system:

1. **Import Order**: POST to `/api/orders/import` with order JSON
2. **View Orders**: Visit `/orders` in web browser
3. **Download Assets**: Click "Download" button or POST to `/api/orders/:id/download_assets`
4. **Send to Switch**: Click "Send to Switch" or POST to `/api/orders/:id/send_to_switch`
5. **Check Results**: View order detail page for status and previews

## Common Tasks

### Create New Migration
```bash
bundle exec rake db:create_migration NAME=add_field_to_orders
```

### Reset Database
```bash
bundle exec rake db:drop db:create db:migrate
```

### Check Database Status
Visit `/health` endpoint for system status.

### View Logs
Check Replit workflow logs or console output.

## Next Steps

Planned improvements:
- Add authentication/authorization
- Implement background job processing
- Add comprehensive test suite
- Enhance error handling and logging
- Create admin panel for configuration
- Add monitoring and alerting

## Notes

- The workflow system (`System_program/`) enables AI agents to work surgically on specific features
- All models use ActiveRecord associations for clean data access
- Services encapsulate business logic separate from routes
- Views use ERB templates with Bootstrap for responsive design
- API returns consistent JSON format with `success` and `error` fields
