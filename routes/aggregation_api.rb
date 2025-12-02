# @feature aggregation
# @domain api
# API routes for aggregation callbacks from Switch

class PrintOrchestrator < Sinatra::Base
  # POST /api/v1/aggregation_callback - Callback from Switch when aggregation is complete
  post '/api/v1/aggregation_callback' do
    content_type :json
    
    begin
      payload = JSON.parse(request.body.read)
      puts "[AGGREGATION_CALLBACK] Received: #{payload.inspect}"
      
      aggregated_job_id = payload['aggregated_job_id'] || payload['job_id']
      file_url = payload['file_url'] || payload['url']
      filename = payload['filename']
      status = payload['status']
      
      unless aggregated_job_id
        return { success: false, error: 'Missing aggregated_job_id' }.to_json
      end
      
      job = AggregatedJob.find_by(id: aggregated_job_id)
      unless job
        return { success: false, error: 'Aggregated job not found' }.to_json
      end
      
      if status == 'completed' && file_url.present?
        job.receive_aggregated_file(file_url, filename)
        puts "[AGGREGATION_CALLBACK] Job #{aggregated_job_id} received aggregated file: #{file_url}"
        { success: true, message: 'Aggregated file received' }.to_json
      elsif status == 'failed'
        job.update(status: 'failed')
        { success: true, message: 'Aggregation marked as failed' }.to_json
      else
        { success: false, error: 'Invalid callback data' }.to_json
      end
      
    rescue JSON::ParserError => e
      { success: false, error: "Invalid JSON: #{e.message}" }.to_json
    rescue => e
      puts "[AGGREGATION_CALLBACK_ERROR] #{e.message}"
      { success: false, error: e.message }.to_json
    end
  end
  
  # POST /api/v1/aggregation_print_callback - Callback when aggregated print is complete
  post '/api/v1/aggregation_print_callback' do
    content_type :json
    
    begin
      payload = JSON.parse(request.body.read)
      puts "[AGGREGATION_PRINT_CALLBACK] Received: #{payload.inspect}"
      
      aggregated_job_id = payload['aggregated_job_id'] || payload['job_id']
      status = payload['status']
      
      unless aggregated_job_id
        return { success: false, error: 'Missing aggregated_job_id' }.to_json
      end
      
      job = AggregatedJob.find_by(id: aggregated_job_id)
      unless job
        return { success: false, error: 'Aggregated job not found' }.to_json
      end
      
      if status == 'completed'
        job.mark_print_completed
        puts "[AGGREGATION_PRINT_CALLBACK] Job #{aggregated_job_id} print completed"
        { success: true, message: 'Print completed' }.to_json
      elsif status == 'failed'
        job.update(status: 'failed')
        { success: true, message: 'Print marked as failed' }.to_json
      else
        { success: false, error: 'Invalid callback status' }.to_json
      end
      
    rescue JSON::ParserError => e
      { success: false, error: "Invalid JSON: #{e.message}" }.to_json
    rescue => e
      puts "[AGGREGATION_PRINT_CALLBACK_ERROR] #{e.message}"
      { success: false, error: e.message }.to_json
    end
  end
end
