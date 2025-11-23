-- Initialize database with proper cleanup
-- This script runs automatically when PostgreSQL starts for the first time

-- Drop schema if exists to ensure clean state
DROP SCHEMA IF EXISTS public CASCADE;
CREATE SCHEMA public;

-- Grant default permissions
GRANT ALL ON SCHEMA public TO public;
