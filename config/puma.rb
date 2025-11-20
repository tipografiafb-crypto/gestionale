# Puma configuration for Replit

# Thread configuration
threads_count = ENV.fetch('RAILS_MAX_THREADS', 5)
threads threads_count, threads_count

# Bind to all interfaces on port 5000 (required for Replit)
port ENV.fetch('PORT', 5000)

# Environment
environment ENV.fetch('RACK_ENV', 'development')
