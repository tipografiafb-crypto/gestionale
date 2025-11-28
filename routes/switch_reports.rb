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
        # Fall back to CURRENT format: just the OrderItem database ID
        item_id = job_id_str.to_i
        
        if item_id > 0
          puts "[SWITCH_REPORT_DEBUG] Parsed CURRENT format job_id (item_id #{item_id})"
          
          # Find the OrderItem directly by database ID from job_operation_id
          item = OrderItem.find_by(id: item_id)
          
          if item
            order = item.order
            puts "[SWITCH_REPORT_DEBUG] Successfully found OrderItem #{item.id} (order #{order.id})"
          else
            puts "[SWITCH_REPORT_WARN] OrderItem id=#{item_id} not found"
            item = nil
            order = nil
          end
        else
          status 400
          puts "[SWITCH_REPORT_ERROR] Invalid job-operation-id: #{job_operation_id.inspect}"
          return { success: false, error: 'Invalid job-operation-id format' }.to_json
        end
      end
      
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
            # Use external_id_riga to ensure we can link to correct item later
            upload_dir = File.join(Dir.pwd, 'storage', 'pending', order_code.to_s)
            saved_file_path = "storage/pending/#{order_code}/#{filename}"
            
            puts "[SWITCH_REPORT_DEBUG] Order/item not in DB, saving to pending directory: #{saved_file_path}"
          end
          
          # Create storage directory if needed
          FileUtils.mkdir_p(upload_dir) unless Dir.exist?(upload_dir)
          
          # Save file
          full_path = File.join(Dir.pwd, saved_file_path)
          File.open(full_path, 'wb') { |f| f.write(pdf_data) }
          puts "[SWITCH_REPORT] PDF decoded and saved: #{saved_file_path}"
          
          # Create Asset record and update SwitchJob with preview URL
          if item
            asset = item.assets.build(
              original_url: filename,
              local_path: saved_file_path,
              asset_type: 'print_output'
            )
            asset.save!
            
            # Generate preview URL accessible from web
            preview_url = "/file/#{asset.id}"
            
            # Determine which job (preprint or print) based on filename or kind
            # Try to update the most recent job that doesn't have a result yet
            if item.print_job && !item.print_job.result_preview_url.present?
              item.print_job.update(result_preview_url: preview_url)
              puts "[SWITCH_REPORT] Updated print_job with preview_url: #{preview_url}"
            elsif item.preprint_job && !item.preprint_job.result_preview_url.present?
              item.preprint_job.update(result_preview_url: preview_url)
              puts "[SWITCH_REPORT] Updated preprint_job with preview_url: #{preview_url}"
            end
            
            # Update item with Switch results
            item.update(print_status: 'completed')
            
            # Log the update
            if order.switch_job
              order.switch_job.add_log("[#{Time.now.iso8601}] Report received for item (#{filename}). Job Op: #{job_operation_id}. Preview: #{preview_url}")
            end
          else
            # Item not found - this shouldn't happen in normal operation
            # since job_operation_id always comes from an OrderItem we created
            puts "[SWITCH_REPORT_WARN] Could not save asset to item or order"
          end
          
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
      if filename_match
        response_data[:codice_ordine] ||= filename_match[1]
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
