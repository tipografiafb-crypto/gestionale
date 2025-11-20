# @feature switch
# @domain api
# Switch API routes - Handles callbacks from Enfocus Switch
require 'json'

class PrintOrchestrator < Sinatra::Base
  # POST /api/switch/callback
  # Receive callback from Enfocus Switch
  post '/api/switch/callback' do
    content_type :json
    
    begin
      data = JSON.parse(request.body.read)
      
      # Find order by external code AND store code to prevent cross-store conflicts
      # Require store_code for proper scoping
      unless data['store_code'].present?
        status 400
        return { success: false, error: 'Missing required field: store_code' }.to_json
      end
      
      store = Store.find_by(code: data['store_code'])
      unless store
        status 404
        return { success: false, error: 'Store not found' }.to_json
      end
      
      order = Order.find_by(
        store_id: store.id,
        external_order_code: data['external_order_code']
      )
      
      unless order
        status 404
        return { success: false, error: 'Order not found' }.to_json
      end
      
      # Update order status
      new_status = map_switch_status(data['status'])
      order.update_status(new_status)
      
      # Update or create switch job
      switch_job = order.switch_job || order.create_switch_job
      
      switch_job.update(
        status: data['status'],
        result_preview_url: data['result_preview_url'],
        log: switch_job.log.to_s + "\n" + (data['log'] || 'Callback received')
      )
      
      status 200
      { 
        success: true,
        order_id: order.id,
        external_order_code: order.external_order_code,
        status: order.status
      }.to_json
      
    rescue JSON::ParserError => e
      status 400
      { success: false, error: "Invalid JSON: #{e.message}" }.to_json
    rescue StandardError => e
      status 500
      { success: false, error: e.message }.to_json
    end
  end

  private

  def map_switch_status(switch_status)
    case switch_status.to_s.downcase
    when 'done', 'completed'
      'done'
    when 'processing', 'in_progress'
      'processing'
    when 'failed', 'error'
      'error'
    else
      'processing'
    end
  end
end
