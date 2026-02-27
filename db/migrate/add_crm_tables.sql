-- CRM Tables Migration
-- Run with: psql -d your_database -f db/migrate/add_crm_tables.sql

-- Customers table
CREATE TABLE IF NOT EXISTS customers (
    id BIGSERIAL PRIMARY KEY,
    email VARCHAR(255) NOT NULL UNIQUE,
    first_name VARCHAR(255),
    last_name VARCHAR(255),
    phone VARCHAR(50),
    billing_address TEXT,
    shipping_address TEXT,
    total_spent DECIMAL(10,2) DEFAULT 0,
    order_count INTEGER DEFAULT 0,
    first_order_at TIMESTAMP,
    last_order_at TIMESTAMP,
    store_id BIGINT REFERENCES stores(id),
    notes TEXT,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS index_customers_on_email ON customers(email);
CREATE INDEX IF NOT EXISTS index_customers_on_store_id ON customers(store_id);
CREATE INDEX IF NOT EXISTS index_customers_on_last_order_at ON customers(last_order_at);

-- Sales table
CREATE TABLE IF NOT EXISTS sales (
    id BIGSERIAL PRIMARY KEY,
    customer_id BIGINT NOT NULL REFERENCES customers(id),
    store_id BIGINT REFERENCES stores(id),
    external_order_code VARCHAR(255) NOT NULL,
    order_date TIMESTAMP,
    total DECIMAL(10,2) DEFAULT 0,
    tax DECIMAL(10,2) DEFAULT 0,
    shipping DECIMAL(10,2) DEFAULT 0,
    discount DECIMAL(10,2) DEFAULT 0,
    payment_method VARCHAR(100),
    currency VARCHAR(10) DEFAULT 'EUR',
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE UNIQUE INDEX IF NOT EXISTS index_sales_on_store_and_order ON sales(store_id, external_order_code);
CREATE INDEX IF NOT EXISTS index_sales_on_customer_id ON sales(customer_id);
CREATE INDEX IF NOT EXISTS index_sales_on_order_date ON sales(order_date);

-- Sale Items table
CREATE TABLE IF NOT EXISTS sale_items (
    id BIGSERIAL PRIMARY KEY,
    sale_id BIGINT NOT NULL REFERENCES sales(id) ON DELETE CASCADE,
    sku VARCHAR(255),
    product_name VARCHAR(255),
    quantity INTEGER DEFAULT 1,
    line_total DECIMAL(10,2) DEFAULT 0,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS index_sale_items_on_sale_id ON sale_items(sale_id);
CREATE INDEX IF NOT EXISTS index_sale_items_on_sku ON sale_items(sku);
