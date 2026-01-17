require './app'

# Aumenta il limite di dimensione del corpo della richiesta per file di grandi dimensioni
# Rack::Utils.key_space_limit non è necessario qui, ma Sinatra/Puma gestiscono file grandi tramite file temporanei.
# Nota: Su Replit/Proxy esterni potrebbero esserci limiti invalicabili (es. 100MB-1GB).

use Rack::MethodOverride
run PrintOrchestrator

# Load aggregated jobs routes
require_relative 'routes/aggregated_jobs'
require_relative 'routes/aggregation_api'
