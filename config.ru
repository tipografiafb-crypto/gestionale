require './app'
require 'rack/cors'

use Rack::Cors do
  allow do
    origins '*'
    resource '*', headers: :any, methods: [:get, :post, :put, :patch, :delete, :options]
  end
end

use Rack::MethodOverride
run PrintOrchestrator

# Load aggregated jobs routes
require_relative 'routes/aggregated_jobs'
require_relative 'routes/aggregation_api'
