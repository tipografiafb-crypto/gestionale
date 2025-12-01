CREATE TABLE IF NOT EXISTS backup_configs (
  id SERIAL PRIMARY KEY,
  remote_ip VARCHAR(255),
  remote_path VARCHAR(1024),
  ssh_username VARCHAR(255),
  ssh_password VARCHAR(1024),
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Add columns if they don't exist (for existing databases)
ALTER TABLE backup_configs ADD COLUMN ssh_username VARCHAR(255) DEFAULT NULL;
ALTER TABLE backup_configs ADD COLUMN ssh_password VARCHAR(1024) DEFAULT NULL;
