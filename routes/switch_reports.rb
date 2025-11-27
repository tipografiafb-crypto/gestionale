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
          
          # Filename pattern: "code-id_riga.ext" e.g., "eu12345-3.pdf"
          # Where: code = codice_ordine, id_riga = external line item ID from gestionale
          filename_match = filename.match(/^([a-zA-Z0-9]+)-(\d+)/)
          unless filename_match
            status 400
            puts "[SWITCH_REPORT_ERROR] Cannot extract order info from filename: #{filename.inspect}"
            puts "[SWITCH_REPORT_ERROR] Expected filename format: {order_code}-{id_riga}.ext"
            return { success: false, error: "Invalid filename format. Expected: {order_code}-{id_riga}.ext" }.to_json
          end
          
          order_code = filename_match[1]
          external_id_riga = filename_match[2].to_i
          
          puts "[SWITCH_REPORT_DEBUG] Extracted order code '#{order_code}' and external_id_riga #{external_id_riga} from filename"
          
          # Find order by external code - but don't fail if not found
          order = Order.find_by(external_order_code: order_code)
          item = nil
          
          if order
            # Look for OrderItem that matches the external_id_riga
            item = order.order_items.find_by(id: external_id_riga)
            if item
              puts "[SWITCH_REPORT_DEBUG] Successfully mapped to order #{order.id}, item #{external_id_riga}"
            else
              puts "[SWITCH_REPORT_WARN] OrderItem id=#{external_id_riga} not found in order #{order_code}, will save to pending"
              item = nil
            end
          else
            puts "[SWITCH_REPORT_WARN] Order with code '#{order_code}' not in database, will save to pending"
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
          
          # Create Asset record only if item exists
          if item
            asset = item.assets.build(
              original_url: filename,
              local_path: saved_file_path,
              asset_type: 'print_output'
            )
            asset.save!
            
            # Update item with Switch results
            item.update(print_status: 'completed')
            
            # Log the update
            if order.switch_job
              order.switch_job.add_log("[#{Time.now.iso8601}] Report received for item (#{filename}). Job Op: #{job_operation_id}")
            end
          else
            # Save PendingFile record for later linking when order is imported
            if order_code && external_id_riga
              PendingFile.create(
                external_order_code: order_code,
                external_id_riga: external_id_riga,
                filename: filename,
                file_path: saved_file_path,
                kind: kind,
                status: 'pending'
              )
              puts "[SWITCH_REPORT_DEBUG] Created PendingFile record: order=#{order_code}, id_riga=#{external_id_riga}"
            end
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
