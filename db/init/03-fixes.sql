-- Fix missing columns that may not exist
ALTER TABLE IF EXISTS print_flows ADD COLUMN IF NOT EXISTS active BOOLEAN DEFAULT true;
ALTER TABLE IF EXISTS product_categories ADD COLUMN IF NOT EXISTS active BOOLEAN DEFAULT true;
ALTER TABLE IF EXISTS print_machines ADD COLUMN IF NOT EXISTS active BOOLEAN DEFAULT true;
ALTER TABLE IF EXISTS stores ADD COLUMN IF NOT EXISTS active BOOLEAN DEFAULT true;
ALTER TABLE IF EXISTS products ADD COLUMN IF NOT EXISTS active BOOLEAN DEFAULT true;
ALTER TABLE IF EXISTS switch_webhooks ADD COLUMN IF NOT EXISTS active BOOLEAN DEFAULT true;
ALTER TABLE IF EXISTS switch_webhooks ADD COLUMN IF NOT EXISTS store_id INTEGER REFERENCES stores(id);

-- Create unique index on switch_webhooks if not exists
CREATE UNIQUE INDEX IF NOT EXISTS index_switch_webhooks_on_name_and_store_id ON switch_webhooks(name, store_id);
