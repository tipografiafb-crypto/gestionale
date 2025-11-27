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
      
      # Parse job_operation_id - supports TWO formats:
      # NEW FORMAT: "order-{order_id}-item-{position}"
      # OLD FORMAT: just the operation position number (1, 2, 3...)
      
      job_id_str = job_operation_id.to_s.strip
      item = nil
      order = nil
      
      # Try NEW format first
      job_id_match = job_id_str.match(/^order-(\d+)-item-(\d+)$/)
      if job_id_match
        puts "[SWITCH_REPORT_DEBUG] Parsed NEW format job_id"
        order_id = job_id_match[1].to_i
        item_position = job_id_match[2].to_i
        
        order = Order.find_by(id: order_id)
        unless order
          status 404
          puts "[SWITCH_REPORT_ERROR] Order #{order_id} not found!"
          return { success: false, error: "Order #{order_id} not found" }.to_json
        end
        
        item = order.order_items.order(:id)[item_position - 1]
        unless item
          status 404
          puts "[SWITCH_REPORT_ERROR] Item position #{item_position} not found in order #{order_id}!"
          puts "[SWITCH_REPORT_ERROR] Order has #{order.order_items.count} items"
          return { success: false, error: "OrderItem at position #{item_position} not found in order #{order_id}" }.to_json
        end
      else
        # Fall back to OLD format: just a number (operation position)
        # Extract order context from filename pattern: "{order_code}-{position}.ext"
        item_position = job_id_str.to_i
        
        if item_position > 0 && filename
          puts "[SWITCH_REPORT_DEBUG] Parsed OLD format job_id (position #{item_position})"
          puts "[SWITCH_REPORT_DEBUG] Attempting to extract order code from filename: #{filename}"
          
          # Filename pattern: "code-position.ext" e.g., "eu12345-1.pdf"
          filename_match = filename.match(/^([a-zA-Z0-9]+)-(\d+)/)
          if filename_match
            order_code = filename_match[1]
            filename_position = filename_match[2].to_i
            
            puts "[SWITCH_REPORT_DEBUG] Extracted order code '#{order_code}' and position #{filename_position} from filename"
            
            # Find order by external code
            order = Order.find_by(external_order_code: order_code)
            item = nil
            
            if order
              # Use filename position as the item position (more reliable than job-operation-id)
              item = order.order_items.order(:id)[filename_position - 1]
              unless item
                status 404
                puts "[SWITCH_REPORT_ERROR] Item position #{filename_position} not found in order #{order_code}!"
                puts "[SWITCH_REPORT_ERROR] Order has #{order.order_items.count} items"
                return { success: false, error: "OrderItem at position #{filename_position} not found in order #{order_code}" }.to_json
              end
              puts "[SWITCH_REPORT_DEBUG] Successfully mapped to order #{order.id}, item position #{filename_position}"
            else
              # Order not found - but file still needs to be saved!
              # This can happen when Switch sends files before order is imported
              puts "[SWITCH_REPORT_WARN] Order with code '#{order_code}' not in database yet - saving file anyway"
              puts "[SWITCH_REPORT_WARN] File will be saved to pending directory for later linking"
            end
          else
            status 400
            puts "[SWITCH_REPORT_ERROR] Cannot extract order info from filename: #{filename.inspect}"
            puts "[SWITCH_REPORT_ERROR] Expected filename format: {order_code}-{position}.ext"
            return { success: false, error: "Invalid filename format. Expected: {order_code}-{position}.ext" }.to_json
          end
        else
          status 400
          puts "[SWITCH_REPORT_ERROR] Invalid job-operation-id: #{job_operation_id.inspect}"
          return { success: false, error: 'Invalid job-operation-id format' }.to_json
        end
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
          
          # Save file with exact filename from Switch (no prefix)
          local_path = "storage/#{store_code}/#{order_code_str}/#{sku}/#{filename}"
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
          
          puts "[SWITCH_REPORT] PDF decoded and saved for order #{order_code_str}, item #{id_riga}: #{local_path}"
        rescue => e
          puts "[SWITCH_REPORT_ERROR] File decode error: #{e.message}"
          status 500
          return { success: false, error: "File decode error: #{e.message}" }.to_json
        end
      end
      
      # Update item with Switch results
      item.update(print_status: 'completed')
      
      # Log the update
      if order.switch_job
        order.switch_job.add_log("[#{Time.now.iso8601}] Report received for item #{id_riga} (#{filename}). Job Op: #{job_operation_id}")
      end
      
      # Return success to Switch
      status 200
      {
        success: true,
        codice_ordine: order.external_order_code,
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
