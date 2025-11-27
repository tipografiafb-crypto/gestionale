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
  # Receives JSON from Switch Base64 module with base64-encoded PDF
  post '/api/v1/reports_create' do
    content_type :json
    
    begin
      # Parse JSON from Switch Base64 module
      request.body.rewind
      data = JSON.parse(request.body.read) rescue {}
      
      # Extract from Switch JSON
      file_base64 = data['file']
      kind = data['kind']
      filename = data['filename']
      job_operation_id = data['job-operation-id']
      
      unless filename && file_base64
        status 400
        return { success: false, error: 'Missing filename or file data' }.to_json
      end
      
      # Extract order code and id_riga from filename
      # Format: eu{codice_ordine}-{id_riga}.pdf (e.g., eu12345-3.pdf)
      match = filename.to_s.match(/^eu(\d+)-(\d+)\.pdf$/i)
      unless match
        status 400
        return { success: false, error: 'Invalid filename format. Expected: eu{codice_ordine}-{id_riga}.pdf' }.to_json
      end
      
      codice_ordine = "EU#{match[1]}".upcase
      id_riga = match[2].to_i
      
      # Find the order and item
      order = Order.find_by(external_order_code: codice_ordine)
      unless order
        status 404
        return { success: false, error: "Order #{codice_ordine} not found" }.to_json
      end
      
      item = order.order_items.find_by(id: id_riga)
      unless item
        status 404
        return { success: false, error: "OrderItem #{id_riga} not found" }.to_json
      end
      
      # Decode base64 PDF and save to storage
      if file_base64.present?
        begin
          # Decode base64 to binary PDF data
          pdf_data = Base64.decode64(file_base64)
          
          store_code = order.store.code || order.store.id.to_s
          order_code_str = order.external_order_code
          sku = item.sku
          
          # Create storage directory if needed
          upload_dir = File.join(Dir.pwd, 'storage', store_code, order_code_str, sku)
          FileUtils.mkdir_p(upload_dir) unless Dir.exist?(upload_dir)
          
          # Save file with print_output prefix
          local_path = "storage/#{store_code}/#{order_code_str}/#{sku}/print_output_#{filename}"
          full_path = File.join(Dir.pwd, local_path)
          
          # Write decoded PDF content
          File.open(full_path, 'wb') { |f| f.write(pdf_data) }
          
          # Create Asset record for the print output
          asset = item.assets.build(
            original_url: filename,
            local_path: local_path,
            asset_type: 'print_output'
          )
          asset.save!
          
          puts "[SWITCH_REPORT] PDF decoded and saved for order #{codice_ordine}, item #{id_riga}: #{local_path}"
        rescue => e
          puts "[SWITCH_REPORT_ERROR] File decode error: #{e.message}"
          status 500
          return { success: false, error: "File decode error: #{e.message}" }.to_json
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
