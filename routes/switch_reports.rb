# @feature switch
# @domain api
# Switch Reports Callback - Receives processing results from Enfocus Switch
# Endpoint: POST /api/v1/reports_create
# Called by Switch when jobs complete processing via the widegest_url mechanism

require 'json'

class PrintOrchestrator < Sinatra::Base
  # POST /api/v1/reports_create
  # Receive completed job results from Switch via widegest_url callback
  # This is where Switch sends the output files and processing results
  post '/api/v1/reports_create' do
    content_type :json
    
    begin
      data = JSON.parse(request.body.read)
      
      # Log incoming report
      warn "[Switch Report] Received: #{data.inspect}"
      
      # Extract key fields from Switch report
      order_code = data['codice_ordine']
      id_riga = data['id_riga']
      job_operation_id = data['job_operation_id']
      
      unless order_code && id_riga
        status 400
        return { success: false, error: 'Missing codice_ordine or id_riga' }.to_json
      end
      
      # Find the order and item
      order = Order.find_by(external_order_code: order_code)
      unless order
        status 404
        return { success: false, error: "Order #{order_code} not found" }.to_json
      end
      
      item = order.order_items.find_by(id: id_riga)
      unless item
        status 404
        return { success: false, error: "OrderItem #{id_riga} not found" }.to_json
      end
      
      # Update item with Switch results
      item.update(
        switch_job_operation_id: job_operation_id,
        print_status: 'completed'  # Mark as completed once Switch is done
      )
      
      # Log the update
      if order.switch_job
        order.switch_job.add_log("[#{Time.now.iso8601}] Report received for item #{id_riga}. Data: #{data.to_json}")
      end
      
      # Return success to Switch
      status 200
      {
        success: true,
        codice_ordine: order_code,
        id_riga: id_riga,
        message: 'Report received and processed',
        timestamp: Time.now.iso8601
      }.to_json
      
    rescue JSON::ParserError => e
      status 400
      { success: false, error: "Invalid JSON: #{e.message}" }.to_json
    rescue StandardError => e
      status 500
      { success: false, error: e.message }.to_json
    end
  end
end
