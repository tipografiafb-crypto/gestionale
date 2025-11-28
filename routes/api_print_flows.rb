# @feature orders
# @domain api
# API endpoints for Print Flows - JSON endpoints for frontend

class PrintOrchestrator < Sinatra::Base
  # GET /api/print_flows/:id/azione_photoshop_options
  # Returns azione photoshop options for a print flow
  get '/api/print_flows/:id/azione_photoshop_options' do
    content_type :json
    
    flow = PrintFlow.find_by(id: params[:id])
    
    unless flow
      status 404
      return { error: 'Print flow not found' }.to_json
    end
    
    {
      enabled: flow.azione_photoshop_enabled || false,
      options: flow.azione_photoshop_options_list || [],
      default: flow.default_azione_photoshop
    }.to_json
  end
end
