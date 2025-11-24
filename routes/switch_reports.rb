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
  # Can receive either multipart form data with file or JSON payload
  post '/api/v1/reports_create' do
    content_type :json
    
    begin
      # Try to parse as multipart form data first (Switch sends file)
      order_code = params['codice_ordine']
      id_riga = params['id_riga']&.to_i
      job_operation_id = params['job_operation_id']
      file_upload = params['file']
      
      # Fallback to JSON if form data not present
      if order_code.nil?
        data = JSON.parse(request.body.read) rescue {}
        order_code = data['codice_ordine']
        id_riga = data['id_riga']&.to_i
        job_operation_id = data['job_operation_id']
      end
      
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
      
      # Handle file upload from Switch (PDF output)
      if file_upload.present? && file_upload.is_a?(Hash) && file_upload[:filename].present?
        begin
          store_code = order.store.code || order.store.id.to_s
          order_code_str = order.external_order_code
          sku = item.sku
          
          # Create storage directory if needed
          upload_dir = File.join(Dir.pwd, 'storage', store_code, order_code_str, sku)
          FileUtils.mkdir_p(upload_dir) unless Dir.exist?(upload_dir)
          
          # Save file with print_output prefix
          filename = File.basename(file_upload[:filename])
          local_path = "storage/#{store_code}/#{order_code_str}/#{sku}/print_output_#{filename}"
          full_path = File.join(Dir.pwd, local_path)
          
          # Read and write file content
          content = file_upload[:tempfile].read
          File.open(full_path, 'wb') { |f| f.write(content) }
          
          # Create Asset record for the print output
          asset = item.assets.build(
            original_url: file_upload[:filename],
            local_path: local_path,
            asset_type: 'print_output'
          )
          asset.save!
          
          warn "[Switch Report] File saved for order #{order_code}, item #{id_riga}: #{local_path}"
        rescue => e
          warn "[Switch Report] File upload error: #{e.message}"
          # Continue anyway - file save is not critical for status update
        end
      end
      
      # Update item with Switch results
      item.update(
        switch_job_operation_id: job_operation_id,
        print_status: 'completed'  # Mark as completed once Switch is done
      )
      
      # Log the update
      if order.switch_job
        order.switch_job.add_log("[#{Time.now.iso8601}] Report received for item #{id_riga}. Job Op: #{job_operation_id}")
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
