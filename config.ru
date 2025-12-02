require './app'

use Rack::MethodOverride
run PrintOrchestrator

# Load aggregated jobs routes
require_relative 'routes/aggregated_jobs'
require_relative 'routes/aggregation_api'
