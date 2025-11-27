# @feature switch
# @domain services
# SwitchClient - Handles communication with Enfocus Switch
require 'http'
require 'json'

class SwitchClient
  attr_reader :order, :switch_job

  def initialize(order)
    @order = order
    @switch_job = order.switch_job || order.build_switch_job
  end

  # Send order to Switch (or simulate if SWITCH_SIMULATION=true)
  def send_to_switch
    # Simulation mode for testing
    if ENV['SWITCH_SIMULATION'] == 'true'
      return simulate_success
    end

    # Check if order is ready
    unless @order.ready_for_switch?
      return { success: false, error: 'Order not ready (assets not downloaded)' }
    end

    begin
      # Prepare payload - each item becomes a separate entry
      payloads = build_payload

      # Send each item to Switch webhook
      payloads.each do |payload|
        response = HTTP
          .timeout(30)
          .headers(
            'Content-Type' => 'application/json',
            'X-API-Key' => ENV['SWITCH_API_KEY'] || ''
          )
          .post(switch_webhook_url, json: payload)

        # Process response
        if response.status.success?
          handle_success(response)
        else
          handle_error(response)
        end
      end

      # Final success message
      { success: true, message: "Sent #{payloads.length} item(s) to Switch" }

    rescue StandardError => e
      handle_exception(e)
    end
  end

  # Static method for item-level Send to Switch with simulation support
  def self.send_to_switch(webhook_path:, job_data:)
    # Validate inputs
    unless webhook_path&.present?
      return { success: false, error: 'Missing webhook_path' }
    end
    
    unless job_data&.is_a?(Hash)
      return { success: false, error: 'Invalid job_data format' }
    end
    
    unless job_data[:codice_ordine]&.present?
      return { success: false, error: 'Missing codice_ordine in job_data' }
    end
    
    # Generate job_id from payload (operation_id + codice_ordine + id_riga + timestamp)
    generated_job_id = generate_job_id(job_data)
    
    # Simulation mode for testing
    if ENV['SWITCH_SIMULATION'] == 'true'
      return load_simulation_response(generated_job_id)
    end

    begin
      # Build full Switch webhook URL using same logic as SwitchWebhook model
      switch_base = ENV['SWITCH_WEBHOOK_BASE_URL'].to_s.strip.presence || 'http://192.168.1.162:51080'
      webhook_prefix = ENV['SWITCH_WEBHOOK_PREFIX'].to_s.strip
      
      puts "[SWITCH_CLIENT_DEBUG] ENV['SWITCH_WEBHOOK_BASE_URL']: #{ENV['SWITCH_WEBHOOK_BASE_URL'].inspect}"
      puts "[SWITCH_CLIENT_DEBUG] ENV['SWITCH_WEBHOOK_PREFIX']: #{ENV['SWITCH_WEBHOOK_PREFIX'].inspect}"
      puts "[SWITCH_CLIENT_DEBUG] switch_base (after processing): #{switch_base}"
      puts "[SWITCH_CLIENT_DEBUG] webhook_prefix (after processing): #{webhook_prefix.inspect}"
      
      # Safely build URL with webhook_path validation
      webhook_path_str = webhook_path.to_s.strip
      return { success: false, error: 'Invalid webhook_path' } if webhook_path_str.empty?
      
      # Build URL properly: remove trailing slash from base, ensure path starts with /
      switch_base = switch_base.chomp('/')
      webhook_path_str = "/#{webhook_path_str}" unless webhook_path_str.start_with?('/')
      
      # Add webhook prefix if configured (e.g., "/scripting" for v7, "" for v6)
      webhook_path_str = "#{webhook_prefix}#{webhook_path_str}" unless webhook_path_str.start_with?(webhook_prefix) && webhook_prefix.present?
      
      full_url = "#{switch_base}#{webhook_path_str}"
      
      puts "[SWITCH_CLIENT_DEBUG] Full URL: #{full_url}"
      puts "[SWITCH_CLIENT_DEBUG] Payload: #{job_data.to_json}"
      
      response = HTTP
        .timeout(30)
        .headers('Content-Type' => 'application/json')
        .post(full_url, json: job_data)

      puts "[SWITCH_CLIENT_DEBUG] Response Status: #{response.status}"
      puts "[SWITCH_CLIENT_DEBUG] Response Body: #{response.body}"

      if response.status.success?
        { success: true, job_id: generated_job_id, message: 'Sent to Switch' }
      else
        { success: false, error: "Switch returned #{response.status}" }
      end
    rescue StandardError => e
      puts "[SWITCH_CLIENT_ERROR] #{e.class}: #{e.message}"
      puts "[SWITCH_CLIENT_BACKTRACE] #{e.backtrace.first(5).join("\n")}"
      { success: false, error: "#{e.class}: #{e.message}" }
    end
  end

  private

  def self.generate_job_id(job_data)
    return 'JOB-INVALID-0-0' unless job_data.is_a?(Hash)
    
    operation_map = { 1 => 'PREPRINT', 2 => 'PRINT', 3 => 'LABEL' }
    operation_name = operation_map[job_data[:operation_id]&.to_i] || 'JOB'
    
    codice_ordine = job_data[:codice_ordine].to_s.strip
    return 'JOB-EMPTY-0-0' if codice_ordine.empty?
    
    codice = codice_ordine.gsub(/[^0-9A-Z]/i, '')
    id_riga = job_data[:id_riga].to_s.strip
    timestamp = Time.now.to_i
    
    "#{operation_name}-#{codice}-#{id_riga}-#{timestamp}"
  end

  def self.load_simulation_response(job_id)
    sim_file = File.join(Dir.pwd, 'config', 'switch_simulation.json')
    if File.exist?(sim_file)
      sim_data = JSON.parse(File.read(sim_file))
      { 
        success: true, 
        job_id: job_id,
        message: sim_data['message'] || 'Simulazione riuscita'
      }
    else
      { 
        success: true, 
        job_id: job_id, 
        message: 'Simulazione attiva (file non trovato)'
      }
    end
  rescue JSON::ParserError
    { success: true, job_id: job_id, message: 'Simulazione attiva' }
  end

  private

  def switch_webhook_url
    ENV['SWITCH_WEBHOOK_BASE_URL'] || 'http://192.168.1.162:51080'
  end

  def server_base_url
    ENV['SERVER_BASE_URL'] || 'http://localhost:5000'
  end

  def build_payload
    # Build payload in Switch format for each item
    @order.order_items.map.with_index do |item, idx|
      product = item.product
      primary_asset = item.assets.first
      
      {
        id_riga: item.id,
        codice_ordine: @order.external_order_code,
        product: product ? "#{product.sku} - #{product.name}" : item.sku,
        operation_id: idx + 1,
        job_operation_id: nil,  # Filled by Switch
        url: "#{server_base_url}/api/assets/#{primary_asset&.id}/download",
        widegest_url: "#{server_base_url}/api/v1/reports_create",  # ← Switch callback endpoint
        filename: primary_asset&.filename || "#{@order.external_order_code}_#{idx + 1}.png",
        quantita: item.quantity,
        materiale: product&.material || "Non specificato",
        campi_custom: {},
        opzioni_stampa: {},
        campi_webhook: {}
      }
    end
  end

  def handle_success(response)
    body = JSON.parse(response.body.to_s) rescue {}
    
    @switch_job.update(
      status: 'sent',
      switch_job_id: body['job_id']
    )
    @switch_job.add_log("Successfully sent to Switch. Job ID: #{body['job_id']}")
    
    @order.update_status('sent_to_switch')

    { success: true, job_id: body['job_id'], message: 'Sent to Switch successfully' }
  end

  def handle_error(response)
    error_message = "Switch returned #{response.status}: #{response.body}"
    @switch_job.update(status: 'failed')
    @switch_job.add_log(error_message)
    @order.update_status('error')

    { success: false, error: error_message }
  end

  def handle_exception(exception)
    error_message = "Exception: #{exception.message}"
    @switch_job.update(status: 'failed')
    @switch_job.add_log(error_message)
    @order.update_status('error')

    { success: false, error: error_message }
  end
end
