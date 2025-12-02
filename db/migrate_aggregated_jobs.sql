-- Aggregated Jobs table
CREATE TABLE IF NOT EXISTS aggregated_jobs (
  id SERIAL PRIMARY KEY,
  name VARCHAR(255) NOT NULL,
  status VARCHAR(50) DEFAULT 'pending',
  nr_files INTEGER DEFAULT 0,
  print_flow_id INTEGER REFERENCES print_flows(id) ON DELETE SET NULL,
  aggregated_file_url TEXT,
  aggregated_filename VARCHAR(255),
  sent_at TIMESTAMP,
  aggregated_at TIMESTAMP,
  completed_at TIMESTAMP,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Add columns if they don't exist (for existing databases)
ALTER TABLE aggregated_jobs ADD COLUMN IF NOT EXISTS aggregated_file_url TEXT;
ALTER TABLE aggregated_jobs ADD COLUMN IF NOT EXISTS aggregated_filename VARCHAR(255);
ALTER TABLE aggregated_jobs ADD COLUMN IF NOT EXISTS aggregated_at TIMESTAMP;
ALTER TABLE aggregated_jobs ADD COLUMN IF NOT EXISTS completed_at TIMESTAMP;

-- Aggregated Job Items table (join table)
CREATE TABLE IF NOT EXISTS aggregated_job_items (
  id SERIAL PRIMARY KEY,
  aggregated_job_id INTEGER NOT NULL REFERENCES aggregated_jobs(id) ON DELETE CASCADE,
  order_item_id INTEGER NOT NULL REFERENCES order_items(id) ON DELETE CASCADE,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  UNIQUE(aggregated_job_id, order_item_id)
);

-- Indexes for performance
CREATE INDEX IF NOT EXISTS idx_aggregated_jobs_status ON aggregated_jobs(status);
CREATE INDEX IF NOT EXISTS idx_aggregated_job_items_job_id ON aggregated_job_items(aggregated_job_id);
CREATE INDEX IF NOT EXISTS idx_aggregated_job_items_item_id ON aggregated_job_items(order_item_id);
