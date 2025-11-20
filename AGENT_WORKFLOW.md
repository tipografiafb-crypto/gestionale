# Agent Workflow & Operational Guidelines

> **Location**: This file contains the complete operational workflow for AI agents working on the Print Order Orchestrator.
> 
> **Purpose**: Detailed instructions for surgical AI targeting, module routing, and feature-based development.

## 🚀 ENTERPRISE-GRADE MODULE ROUTING SYSTEM

### 🎯 Surgical AI Targeting Workflow

1.  **Feature Targeting**: Always specify which feature you're working on:
    ```
    Feature Target: [orders|switch|storage|ui|integration|quality]
    ```

2.  **Pre-Work Checklist** (Universal Mapping System):
    **Core Analysis Files** (located in `System_program/`):
    *   Read `System_program/FEATURE_MAPPING.md` to identify the right modules
    *   Check `System_program/SYSTEM_STATUS.md` for current health status

    **Safety & Scope Controls**:
    *   Check `System_program/scope/<feature>.allow` for permitted files
    *   Review `System_program/scope/<feature>.deny` for forbidden areas

3.  **Request Template for New Chats**:
    ```
    🎯 FEATURE-TARGETED REQUEST FOR PRINT ORCHESTRATOR

    **Feature Target**: [select specific feature]
    **Objective**: [describe the modification]
    **Constraints**: Use only modules for the selected feature

    **Instructions for AI**:
    1. Read System_program/FEATURE_MAPPING.md for the right modules
    2. Consult System_program/scope/[feature].allow for permitted files
    3. Make surgical changes only to relevant files
    ```

4.  **Safety Protections**:
    *   ✅ Feature isolation (work only in defined scope)
    *   ✅ File permission checking (.allow/.deny files)
    *   ✅ Minimal blast radius (targeted changes)

## 📂 Feature Definitions

### Feature: `orders`
**Description**: Order management, import, and data models
**Scope**:
- Models: `Store`, `Order`, `OrderItem`
- Routes: `routes/orders_api.rb`
- Services: Order-related business logic

### Feature: `storage`
**Description**: Asset management, image downloads
**Scope**:
- Model: `Asset`
- Service: `services/asset_downloader.rb`
- Storage directory management

### Feature: `switch`
**Description**: Enfocus Switch integration
**Scope**:
- Model: `SwitchJob`
- Service: `services/switch_client.rb`
- Routes: `routes/switch_api.rb`

### Feature: `ui`
**Description**: Web interface for operators
**Scope**:
- Routes: `routes/web_ui.rb`
- Views: All `.erb` files in `views/`
- Frontend assets

### Feature: `integration`
**Description**: External API integrations and webhooks
**Scope**:
- API endpoints
- Webhook handlers
- External service clients

### Feature: `quality`
**Description**: Code quality, testing, and refactoring
**Scope**:
- Code improvements
- Test files
- Documentation updates

## 🎪 Example Surgical Requests

*   "Feature target: orders. Add validation for duplicate order codes"
*   "Feature target: storage. Implement retry logic for failed downloads"
*   "Feature target: switch. Add logging for Switch webhook responses"
*   "Feature target: ui. Improve order status badges with better colors"

## 📋 Development Guidelines

### Code Organization
- Follow Ruby conventions and best practices
- Keep models, services, and routes separated
- Use feature tags in comments (`@feature`, `@domain`)
- Maintain single responsibility principle

### Database Changes
- Always create migrations for schema changes
- Never modify database directly
- Use ActiveRecord validations
- Keep migrations reversible when possible

### API Design
- RESTful endpoints where appropriate
- Consistent JSON response format
- Proper HTTP status codes
- Include error messages in responses

### Testing (Future)
- Unit tests for models and services
- Integration tests for API endpoints
- End-to-end tests for critical workflows

## Recent Changes

*   **✅ INITIAL MVP** (Nov 2025): Created complete Print Order Orchestrator with order management, asset downloads, Switch integration, and web UI.
