# @feature switch
# @domain api
# Switch Callback Handler - Receives processing results from Enfocus Switch
# Endpoint: POST /api/switch/callback
# Called by Switch when a job completes processing

require 'json'

class PrintOrchestrator < Sinatra::Base
  # POST /api/switch/callback
  # Receive callback from Switch when job processing completes
  # Expected JSON payload:
  # {
  #   "job_id": "PREPRINT-ORD{order_id}-IT{item_id}-{timestamp}",
  #   "status": "completed" | "failed",
  #   "result_preview_url": "http://...",
  #   "job_operation_id": "Switch operation ID",
  #   "result_files": ["file1.pdf", "file2.pdf"],
  #   "error_message": "if failed"
  # }
  post '/api/switch/callback' do
    content_type :json
    
    begin
      data = JSON.parse(request.body.read)
      
      # Validate required fields
      unless data['job_id'].present?
        status 400
        return { success: false, error: 'Missing required field: job_id' }.to_json
      end
      
      # Parse job_id to extract order_id, item_id, and phase
      # Format: PREPRINT-ORD{order_id}-IT{item_id}-{timestamp} or PRINT-...
      job_id = data['job_id']
      phase_match = job_id.match(/^(PREPRINT|PRINT)-ORD(\d+)-IT(\d+)-/)
      
      unless phase_match
        status 400
        return { success: false, error: 'Invalid job_id format' }.to_json
      end
      
      phase = phase_match[1].downcase  # 'preprint' or 'print'
      order_id = phase_match[2].to_i
      item_id = phase_match[3].to_i
      
      # Find order and item
      order = Order.find_by(id: order_id)
      unless order
        status 404
        return { success: false, error: "Order #{order_id} not found" }.to_json
      end
      
      item = order.order_items.find_by(id: item_id)
      unless item
        status 404
        return { success: false, error: "OrderItem #{item_id} not found" }.to_json
      end
      
      # Determine new status based on Switch response
      callback_status = data['status'].to_s.downcase
      new_status = case callback_status
                   when 'completed', 'success'
                     'completed'
                   when 'failed', 'error'
                     'failed'
                   else
                     'processing'
                   end
      
      # Update the appropriate job and status based on phase
      case phase
      when 'preprint'
        item.update(
          preprint_status: new_status,
          preprint_completed_at: (new_status == 'completed' ? Time.now : nil)
        )
        
        # Update or create preprint job
        if item.preprint_job
          item.preprint_job.update(
            status: new_status,
            result_preview_url: data['result_preview_url'],
            job_operation_id: data['job_operation_id'],
            result_files: data['result_files']&.to_json
          )
        else
          preprint_job = SwitchJob.create!(
            order_id: order_id,
            status: new_status,
            result_preview_url: data['result_preview_url'],
            job_operation_id: data['job_operation_id'],
            result_files: data['result_files']&.to_json,
            log: "[#{Time.now.iso8601}] Preprint job #{job_id} #{new_status}"
          )
          item.update(preprint_job_id: preprint_job.id)
        end
        
      when 'print'
        item.update(
          print_status: new_status,
          print_completed_at: (new_status == 'completed' ? Time.now : nil)
        )
        
        # Update or create print job
        if item.print_job
          item.print_job.update(
            status: new_status,
            result_preview_url: data['result_preview_url'],
            job_operation_id: data['job_operation_id'],
            result_files: data['result_files']&.to_json
          )
        else
          print_job = SwitchJob.create!(
            order_id: order_id,
            status: new_status,
            result_preview_url: data['result_preview_url'],
            job_operation_id: data['job_operation_id'],
            result_files: data['result_files']&.to_json,
            log: "[#{Time.now.iso8601}] Print job #{job_id} #{new_status}"
          )
          item.update(print_job_id: print_job.id)
        end
      end
      
      # Log error if present
      if data['error_message'].present?
        log_msg = "[#{Time.now.iso8601}] ERROR: #{data['error_message']}"
        case phase
        when 'preprint'
          item.preprint_job&.add_log(log_msg)
        when 'print'
          item.print_job&.add_log(log_msg)
        end
      end
      
      # Return success response
      status 200
      {
        success: true,
        order_id: order_id,
        item_id: item_id,
        phase: phase,
        new_status: new_status,
        timestamp: Time.now.iso8601
      }.to_json
      
    rescue JSON::ParserError => e
      status 400
      { success: false, error: "Invalid JSON: #{e.message}" }.to_json
    rescue StandardError => e
      status 500
      { success: false, error: e.message, trace: e.backtrace.first(3) }.to_json
    end
  end
  
  # GET /api/switch/callback/status/:job_id - Check job status
  get '/api/switch/callback/status/:job_id' do
    content_type :json
    
    begin
      job_id = params[:job_id]
      
      # Parse job_id
      phase_match = job_id.match(/^(PREPRINT|PRINT)-ORD(\d+)-IT(\d+)-/)
      unless phase_match
        status 400
        return { success: false, error: 'Invalid job_id format' }.to_json
      end
      
      phase = phase_match[1].downcase
      order_id = phase_match[2].to_i
      item_id = phase_match[3].to_i
      
      order = Order.find_by(id: order_id)
      unless order
        status 404
        return { success: false, error: "Order not found" }.to_json
      end
      
      item = order.order_items.find_by(id: item_id)
      unless item
        status 404
        return { success: false, error: "OrderItem not found" }.to_json
      end
      
      current_status = case phase
                       when 'preprint'
                         item.preprint_status
                       when 'print'
                         item.print_status
                       end
      
      status 200
      {
        success: true,
        job_id: job_id,
        phase: phase,
        status: current_status,
        preview_url: case phase
                     when 'preprint'
                       item.preprint_job&.result_preview_url
                     when 'print'
                       item.print_job&.result_preview_url
                     end
      }.to_json
      
    rescue StandardError => e
      status 500
      { success: false, error: e.message }.to_json
    end
  end
end
