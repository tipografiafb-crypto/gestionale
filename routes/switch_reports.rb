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
      raw_body = request.body.read
      data = JSON.parse(raw_body) rescue {}
      
      # Extract from Switch JSON
      file_base64 = data['file']
      kind = data['kind']
      filename = data['filename']
      job_operation_id = data['job-operation-id']
      
      # DEBUG LOGGING
      puts "[SWITCH_REPORT_DEBUG] Received request"
      puts "[SWITCH_REPORT_DEBUG] kind: #{kind.inspect}"
      puts "[SWITCH_REPORT_DEBUG] filename: #{filename.inspect}"
      puts "[SWITCH_REPORT_DEBUG] job-operation-id: #{job_operation_id.inspect}"
      puts "[SWITCH_REPORT_DEBUG] file size: #{file_base64&.length} bytes"
      
      unless filename && file_base64
        status 400
        puts "[SWITCH_REPORT_ERROR] Missing filename or file data"
        return { success: false, error: 'Missing filename or file data' }.to_json
      end
      
      # job_operation_id is the OrderItem ID (sent from order_items_switch.rb)
      item_id = job_operation_id.to_s.strip.to_i
      
      unless item_id > 0
        status 400
        puts "[SWITCH_REPORT_ERROR] Invalid job-operation-id: #{job_operation_id.inspect}"
        return { success: false, error: 'Invalid job-operation-id format' }.to_json
      end
      
      # Find OrderItem directly by ID
      item = OrderItem.find_by(id: item_id)
      unless item
        status 404
        puts "[SWITCH_REPORT_ERROR] OrderItem #{item_id} not found"
        return { success: false, error: "OrderItem #{item_id} not found" }.to_json
      end
      
      order = item.order
      puts "[SWITCH_REPORT_DEBUG] Found OrderItem #{item.id} from order #{order.id}"
      
      # Decode base64 PDF and save to storage
      saved_file_path = nil
      
      if file_base64.present?
        begin
          # Decode base64 to binary PDF data
          pdf_data = Base64.decode64(file_base64)
          
          if order && item
            # Save to order-specific directory
            store_code = order.store.code || order.store.id.to_s
            order_code_str = order.external_order_code
            sku = item.sku
            
            upload_dir = File.join(Dir.pwd, 'storage', store_code, order_code_str, sku)
            saved_file_path = "storage/#{store_code}/#{order_code_str}/#{sku}/#{filename}"
            
            puts "[SWITCH_REPORT_DEBUG] Saving to order directory: #{saved_file_path}"
          else
            # Save to pending directory (order doesn't exist yet or item not found)
            upload_dir = File.join(Dir.pwd, 'storage', 'pending', item_id.to_s)
            saved_file_path = "storage/pending/#{item_id}/#{filename}"
            
            puts "[SWITCH_REPORT_DEBUG] Order/item not in DB, saving to pending directory: #{saved_file_path}"
          end
          
          # Create storage directory if needed
          FileUtils.mkdir_p(upload_dir) unless Dir.exist?(upload_dir)
          
          # Save file
          full_path = File.join(Dir.pwd, saved_file_path)
          File.open(full_path, 'wb') { |f| f.write(pdf_data) }
          puts "[SWITCH_REPORT] PDF decoded and saved: #{saved_file_path}"
          
          # Delete previous Switch output files for this item (keep only the latest)
          item.assets.where(asset_type: 'print_output').destroy_all
          puts "[SWITCH_REPORT] Deleted previous print_output assets for item #{item.id}"
          
          # Create Asset record for preview display
          asset = item.assets.build(
            original_url: filename,
            local_path: saved_file_path,
            asset_type: 'print_output'
          )
          asset.save!
          puts "[SWITCH_REPORT] Asset created: #{asset.id} with local_path: #{saved_file_path}"
          
          # Asset ID can be used directly in preview URL: /file/{asset.id}
          preview_url = "/file/#{asset.id}"
          puts "[SWITCH_REPORT] Preview URL ready: #{preview_url}"
          
        rescue => e
          puts "[SWITCH_REPORT_ERROR] File decode error: #{e.message}"
          status 500
          return { success: false, error: "File decode error: #{e.message}" }.to_json
        end
      end
      
      # Return success to Switch with file location
      status 200
      
      # Build response with file path info
      response_data = {
        success: true,
        message: 'Report received and processed',
        filename: filename,
        file_path: saved_file_path,
        timestamp: Time.now.iso8601
      }
      
      # Add order info if available
      if order
        response_data[:codice_ordine] = order.external_order_code
      end
      
      response_data.to_json
      
    rescue JSON::ParserError => e
      status 400
      { success: false, error: "Invalid JSON: #{e.message}" }.to_json
    rescue StandardError => e
      status 500
      { success: false, error: e.message }.to_json
    end
  end
end
