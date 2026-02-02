-- Complete database schema for Print Order Orchestrator
-- Updated on 2026-02-02 to match ConsolidatedSchema migration

-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- stores
CREATE TABLE IF NOT EXISTS stores (
  id SERIAL PRIMARY KEY,
  code VARCHAR NOT NULL UNIQUE,
  name VARCHAR NOT NULL,
  active BOOLEAN DEFAULT true,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- orders
CREATE TABLE IF NOT EXISTS orders (
  id SERIAL PRIMARY KEY,
  external_order_code VARCHAR NOT NULL,
  store_id BIGINT NOT NULL REFERENCES stores(id),
  status VARCHAR DEFAULT 'new' NOT NULL,
  source VARCHAR DEFAULT 'api',
  customer_name VARCHAR,
  customer_note TEXT,
  notes TEXT,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  UNIQUE(store_id, external_order_code)
);

-- order_items
CREATE TABLE IF NOT EXISTS order_items (
  id SERIAL PRIMARY KEY,
  order_id BIGINT NOT NULL REFERENCES orders(id),
  sku VARCHAR NOT NULL,
  quantity INTEGER DEFAULT 1 NOT NULL,
  raw_json TEXT,
  preprint_status VARCHAR DEFAULT 'pending',
  preprint_job_id VARCHAR,
  preprint_preview_url VARCHAR,
  print_status VARCHAR DEFAULT 'pending',
  print_job_id VARCHAR,
  preprint_completed_at TIMESTAMP,
  print_completed_at TIMESTAMP,
  preprint_print_flow_id BIGINT,
  scala VARCHAR DEFAULT '1:1',
  materiale VARCHAR,
  campi_custom JSON DEFAULT '{}',
  campi_webhook JSON DEFAULT '{}',
  print_machine_id BIGINT,
  position INTEGER DEFAULT 0,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- assets
CREATE TABLE IF NOT EXISTS assets (
  id SERIAL PRIMARY KEY,
  order_item_id BIGINT NOT NULL REFERENCES order_items(id),
  original_url VARCHAR NOT NULL,
  local_path VARCHAR,
  asset_type VARCHAR,
  deleted_at TIMESTAMP,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- products
CREATE TABLE IF NOT EXISTS products (
  id SERIAL PRIMARY KEY,
  sku VARCHAR NOT NULL UNIQUE,
  name VARCHAR NOT NULL,
  notes TEXT,
  active BOOLEAN DEFAULT true,
  product_category_id BIGINT,
  default_print_flow_id BIGINT,
  min_stock_level INTEGER DEFAULT 0,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- inventories
CREATE TABLE IF NOT EXISTS inventories (
  id SERIAL PRIMARY KEY,
  product_id INTEGER NOT NULL UNIQUE REFERENCES products(id),
  quantity_in_stock INTEGER DEFAULT 0,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- product_categories
CREATE TABLE IF NOT EXISTS product_categories (
  id SERIAL PRIMARY KEY,
  name VARCHAR NOT NULL,
  description TEXT,
  active BOOLEAN DEFAULT true,
  autopilot_preprint_enabled BOOLEAN DEFAULT false,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- switch_webhooks
CREATE TABLE IF NOT EXISTS switch_webhooks (
  id SERIAL PRIMARY KEY,
  name VARCHAR NOT NULL,
  hook_path VARCHAR NOT NULL,
  store_id BIGINT REFERENCES stores(id),
  active BOOLEAN DEFAULT true,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- print_flows
CREATE TABLE IF NOT EXISTS print_flows (
  id SERIAL PRIMARY KEY,
  name VARCHAR NOT NULL,
  notes TEXT,
  active BOOLEAN DEFAULT true,
  preprint_webhook_id BIGINT REFERENCES switch_webhooks(id),
  print_webhook_id BIGINT REFERENCES switch_webhooks(id),
  label_webhook_id BIGINT REFERENCES switch_webhooks(id),
  operation_id INTEGER,
  opzioni_stampa JSON DEFAULT '{}',
  azione_photoshop_enabled BOOLEAN DEFAULT false,
  azione_photoshop_options TEXT,
  default_azione_photoshop VARCHAR,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- switch_jobs
CREATE TABLE IF NOT EXISTS switch_jobs (
  id SERIAL PRIMARY KEY,
  order_id BIGINT NOT NULL REFERENCES orders(id),
  switch_job_id VARCHAR,
  status VARCHAR DEFAULT 'pending' NOT NULL,
  result_preview_url VARCHAR,
  log TEXT,
  job_operation_id INTEGER,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- print_machines
CREATE TABLE IF NOT EXISTS print_machines (
  id SERIAL PRIMARY KEY,
  name VARCHAR NOT NULL,
  description TEXT,
  active BOOLEAN DEFAULT true,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- print_flow_machines
CREATE TABLE IF NOT EXISTS print_flow_machines (
  id SERIAL PRIMARY KEY,
  print_flow_id BIGINT NOT NULL REFERENCES print_flows(id),
  print_machine_id BIGINT NOT NULL REFERENCES print_machines(id),
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- product_print_flows
CREATE TABLE IF NOT EXISTS product_print_flows (
  id SERIAL PRIMARY KEY,
  product_id BIGINT NOT NULL REFERENCES products(id),
  print_flow_id BIGINT NOT NULL REFERENCES print_flows(id),
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- aggregated_jobs
CREATE TABLE IF NOT EXISTS aggregated_jobs (
  id SERIAL PRIMARY KEY,
  name VARCHAR NOT NULL,
  status VARCHAR DEFAULT 'pending',
  nr_files INTEGER DEFAULT 0,
  print_flow_id INTEGER,
  aggregated_file_url TEXT,
  aggregated_filename VARCHAR,
  sent_at TIMESTAMP,
  aggregated_at TIMESTAMP,
  completed_at TIMESTAMP,
  notes TEXT,
  preprint_sent_at TIMESTAMP,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- aggregated_job_items
CREATE TABLE IF NOT EXISTS aggregated_job_items (
  id SERIAL PRIMARY KEY,
  aggregated_job_id INTEGER NOT NULL REFERENCES aggregated_jobs(id),
  order_item_id INTEGER NOT NULL REFERENCES order_items(id),
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- backup_configs
CREATE TABLE IF NOT EXISTS backup_configs (
  id SERIAL PRIMARY KEY,
  remote_ip VARCHAR,
  remote_path VARCHAR,
  ssh_username VARCHAR,
  ssh_password VARCHAR,
  ssh_port INTEGER DEFAULT 22,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- logs
CREATE TABLE IF NOT EXISTS logs (
  id SERIAL PRIMARY KEY,
  level VARCHAR,
  category VARCHAR,
  message TEXT,
  details TEXT,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- import_errors
CREATE TABLE IF NOT EXISTS import_errors (
  id SERIAL PRIMARY KEY,
  store_id BIGINT REFERENCES stores(id),
  filename VARCHAR,
  external_order_code VARCHAR,
  error_message TEXT,
  import_date TIMESTAMP,
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
