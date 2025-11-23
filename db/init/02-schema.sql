-- Complete database schema for Print Order Orchestrator
-- Created in correct dependency order to avoid migration conflicts

-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Stores
CREATE TABLE IF NOT EXISTS stores (
  id SERIAL PRIMARY KEY,
  code VARCHAR NOT NULL UNIQUE,
  name VARCHAR NOT NULL,
  active BOOLEAN DEFAULT true,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Orders
CREATE TABLE IF NOT EXISTS orders (
  id SERIAL PRIMARY KEY,
  external_order_code VARCHAR NOT NULL,
  store_id INTEGER NOT NULL REFERENCES stores(id),
  status VARCHAR DEFAULT 'new',
  source VARCHAR,
  customer_name VARCHAR,
  customer_email VARCHAR,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  UNIQUE(store_id, external_order_code)
);

-- Order Items
CREATE TABLE IF NOT EXISTS order_items (
  id SERIAL PRIMARY KEY,
  order_id INTEGER NOT NULL REFERENCES orders(id),
  sku VARCHAR NOT NULL,
  quantity INTEGER DEFAULT 1,
  raw_json TEXT,
  preprint_status VARCHAR,
  print_status VARCHAR,
  preprint_print_flow_id INTEGER,
  print_print_flow_id INTEGER,
  print_machine_id INTEGER,
  preprint_job_id INTEGER,
  print_job_id INTEGER,
  preprint_completed_at TIMESTAMP,
  print_completed_at TIMESTAMP,
  campi_webhook JSONB,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Assets
CREATE TABLE IF NOT EXISTS assets (
  id SERIAL PRIMARY KEY,
  order_item_id INTEGER NOT NULL REFERENCES order_items(id),
  original_url VARCHAR NOT NULL,
  local_path VARCHAR,
  asset_type VARCHAR,
  downloaded BOOLEAN DEFAULT false,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Switch Jobs
CREATE TABLE IF NOT EXISTS switch_jobs (
  id SERIAL PRIMARY KEY,
  order_id INTEGER NOT NULL REFERENCES orders(id),
  switch_job_id VARCHAR,
  status VARCHAR DEFAULT 'pending',
  result_preview_url VARCHAR,
  job_operation_id VARCHAR,
  result_files JSONB,
  log TEXT,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Product Categories
CREATE TABLE IF NOT EXISTS product_categories (
  id SERIAL PRIMARY KEY,
  name VARCHAR NOT NULL,
  active BOOLEAN DEFAULT true,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Switch Webhooks
CREATE TABLE IF NOT EXISTS switch_webhooks (
  id SERIAL PRIMARY KEY,
  name VARCHAR NOT NULL,
  hook_path VARCHAR NOT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Print Flows
CREATE TABLE IF NOT EXISTS print_flows (
  id SERIAL PRIMARY KEY,
  name VARCHAR NOT NULL,
  active BOOLEAN DEFAULT true,
  preprint_webhook_id INTEGER REFERENCES switch_webhooks(id),
  print_webhook_id INTEGER REFERENCES switch_webhooks(id),
  label_webhook_id INTEGER REFERENCES switch_webhooks(id),
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Products
CREATE TABLE IF NOT EXISTS products (
  id SERIAL PRIMARY KEY,
  sku VARCHAR NOT NULL UNIQUE,
  name VARCHAR,
  notes TEXT,
  active BOOLEAN DEFAULT true,
  print_flow_id INTEGER REFERENCES print_flows(id),
  default_print_flow_id INTEGER REFERENCES print_flows(id),
  product_category_id INTEGER REFERENCES product_categories(id),
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Product Print Flows (many-to-many)
CREATE TABLE IF NOT EXISTS product_print_flows (
  id SERIAL PRIMARY KEY,
  product_id INTEGER NOT NULL REFERENCES products(id),
  print_flow_id INTEGER NOT NULL REFERENCES print_flows(id),
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Print Machines
CREATE TABLE IF NOT EXISTS print_machines (
  id SERIAL PRIMARY KEY,
  name VARCHAR NOT NULL,
  description TEXT,
  active BOOLEAN DEFAULT true,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Print Flow Machines (many-to-many)
CREATE TABLE IF NOT EXISTS print_flow_machines (
  id SERIAL PRIMARY KEY,
  print_flow_id INTEGER NOT NULL REFERENCES print_flows(id),
  print_machine_id INTEGER NOT NULL REFERENCES print_machines(id),
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create indexes for performance
CREATE INDEX IF NOT EXISTS idx_orders_store_id ON orders(store_id);
CREATE INDEX IF NOT EXISTS idx_order_items_order_id ON order_items(order_id);
CREATE INDEX IF NOT EXISTS idx_assets_order_item_id ON assets(order_item_id);
CREATE INDEX IF NOT EXISTS idx_switch_jobs_order_id ON switch_jobs(order_id);
CREATE INDEX IF NOT EXISTS idx_products_sku ON products(sku);
CREATE INDEX IF NOT EXISTS idx_product_print_flows_product_id ON product_print_flows(product_id);
CREATE INDEX IF NOT EXISTS idx_print_flow_machines_print_flow_id ON print_flow_machines(print_flow_id);
