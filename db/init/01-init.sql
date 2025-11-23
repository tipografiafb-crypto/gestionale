-- Initialize database with proper cleanup
-- This script runs automatically when PostgreSQL starts for the first time

-- Drop schema if exists to ensure clean state
DROP SCHEMA IF EXISTS public CASCADE;
CREATE SCHEMA public;

-- Grant default permissions
GRANT ALL ON SCHEMA public TO public;

-- Grant permissions to orchestrator_user on databases and schema
ALTER DEFAULT PRIVILEGES FOR ROLE postgres GRANT ALL ON SCHEMAS TO orchestrator_user;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres GRANT ALL ON TABLES TO orchestrator_user;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres GRANT ALL ON SEQUENCES TO orchestrator_user;

-- Ensure orchestrator_user can connect to the database
GRANT CONNECT ON DATABASE print_orchestrator_dev TO orchestrator_user;
GRANT USAGE ON SCHEMA public TO orchestrator_user;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO orchestrator_user;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO orchestrator_user;
