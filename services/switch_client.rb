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
    # Validate webhook_path
    unless webhook_path.present?
      return { success: false, error: 'Missing webhook_path' }
    end
    
    # Generate job_id from payload (operation_id + codice_ordine + id_riga + timestamp)
    generated_job_id = generate_job_id(job_data)
    
    # Simulation mode for testing
    if ENV['SWITCH_SIMULATION'] == 'true'
      return load_simulation_response(generated_job_id)
    end

    begin
      # Build full Switch webhook URL
      switch_base = ENV['SWITCH_WEBHOOK_URL'] || 'http://localhost:9999/'
      switch_base = "#{switch_base}/" unless switch_base.end_with?('/')
      full_url = "#{switch_base}#{webhook_path}".gsub(/\/+/, '/').sub(%r{/(?=:)}, '://')
      
      response = HTTP
        .timeout(30)
        .headers('Content-Type' => 'application/json')
        .post(full_url, json: job_data)

      if response.status.success?
        { success: true, job_id: generated_job_id, message: 'Sent to Switch' }
      else
        { success: false, error: "Switch returned #{response.status}" }
      end
    rescue StandardError => e
      { success: false, error: e.message }
    end
  end

  private

  def self.generate_job_id(job_data)
    operation_map = { 1 => 'PREPRINT', 2 => 'PRINT', 3 => 'LABEL' }
    operation_name = operation_map[job_data[:operation_id]] || 'JOB'
    codice = job_data[:codice_ordine].to_s.gsub(/[^0-9A-Z]/i, '')
    id_riga = job_data[:id_riga]
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
    ENV['SWITCH_WEBHOOK_URL'] || 'http://localhost:9999/webhook'
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
