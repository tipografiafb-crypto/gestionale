-- Seed data - Creates demo data on first run
-- This runs after the schema is created

-- Only insert if tables are empty
DO $$
BEGIN
  -- Insert stores
  IF (SELECT COUNT(*) FROM stores) = 0 THEN
    INSERT INTO stores (id, code, name, active) VALUES
      (1, 'magenta_001', 'Negozio Demo', true),
      (4, 'TPH_ES', 'TPH ES', true),
      (5, 'TPH_EU', 'TPH EU', true);
    SELECT setval('stores_id_seq', 5);
  END IF;

  -- Insert product categories
  IF (SELECT COUNT(*) FROM product_categories) = 0 THEN
    INSERT INTO product_categories (id, name, description, active) VALUES
      (1, 'Plettri', '', true);
    SELECT setval('product_categories_id_seq', 1);
  END IF;

  -- Insert switch webhooks
  IF (SELECT COUNT(*) FROM switch_webhooks) = 0 THEN
    INSERT INTO switch_webhooks (id, name, hook_path, store_id, active) VALUES
      (1, 'Test', '/test', NULL, true);
    SELECT setval('switch_webhooks_id_seq', 1);
  END IF;

  -- Insert print flows
  IF (SELECT COUNT(*) FROM print_flows) = 0 THEN
    INSERT INTO print_flows (id, name, notes, preprint_webhook_id, print_webhook_id, label_webhook_id, active) VALUES
      (1, 'Plettri', '', 1, 1, NULL, true),
      (2, 'Plettri bianchi', '', 1, 1, 1, true);
    SELECT setval('print_flows_id_seq', 2);
  END IF;

  -- Insert print machines
  IF (SELECT COUNT(*) FROM print_machines) = 0 THEN
    INSERT INTO print_machines (id, name, description, active) VALUES
      (1, 'signracer', '', true);
    SELECT setval('print_machines_id_seq', 1);
  END IF;

  -- Insert products
  IF (SELECT COUNT(*) FROM products) = 0 THEN
    INSERT INTO products (id, sku, name, notes, product_category_id, default_print_flow_id, active) VALUES
      (7, 'TPH500', 'Pippo', '', 1, 1, true);
    SELECT setval('products_id_seq', 7);
  END IF;

  -- Insert inventory records
  IF (SELECT COUNT(*) FROM inventory) = 0 THEN
    INSERT INTO inventory (product_id, quantity_in_stock) VALUES
      (7, 100);
    SELECT setval('inventory_id_seq', 1);
  END IF;

END $$;
