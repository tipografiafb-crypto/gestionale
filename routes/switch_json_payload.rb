# @feature switch
# @domain api
# Switch JSON Payload API - Provides job data for Switch to retrieve via HTTP
# Endpoint: GET /api/switch/json_payload?job_id=XXX
# Switch calls this when it needs job details to process (pull-based model)

require 'json'

class PrintOrchestrator < Sinatra::Base
  # GET /api/switch/json_payload
  # Provide job payload for Switch to retrieve and process
  # Parameters:
  #   job_id: The job ID (format: PREPRINT-ORD{order_id}-IT{item_id}-{timestamp})
  get '/api/switch/json_payload' do
    content_type :json
    
    begin
      job_id = params[:job_id]
      
      unless job_id.present?
        status 400
        return { success: false, error: 'Missing required parameter: job_id' }.to_json
      end
      
      # Parse job_id to extract order_id and item_id
      # Format: PREPRINT-ORD{order_id}-IT{item_id}-{timestamp}
      match = job_id.to_s.match(/PREPRINT-ORD(\d+)-IT(\d+)-/)
      unless match
        status 400
        return { success: false, error: 'Invalid job_id format' }.to_json
      end
      
      order_id = match[1].to_i
      item_id = match[2].to_i
      
      # Find order and item
      order = Order.find_by(id: order_id)
      unless order
        status 404
        return { success: false, error: 'Order not found' }.to_json
      end
      
      item = order.order_items.find_by(id: item_id)
      unless item
        status 404
        return { success: false, error: 'Order item not found' }.to_json
      end
      
      # Build Switch payload
      payload = build_switch_json_payload(order, item, job_id)
      
      status 200
      payload.to_json
      
    rescue StandardError => e
      status 500
      { success: false, error: e.message }.to_json
    end
  end
  
  private
  
  def build_switch_json_payload(order, item, job_id)
    # Get product info
    product = item.product
    print_flow = item.print_flow
    
    # Get primary asset (print asset)
    primary_asset = item.assets.find { |a| a.asset_type == 'print' && a.downloaded? }
    
    # Get Switch filename for primary asset
    switch_filename = primary_asset ? item.switch_filename_for_asset(primary_asset) : nil
    
    # Build the payload matching Switch expectations
    payload = {
      id_riga: item.id,
      codice_ordine: order.external_order_code,
      product: product ? "#{product.sku} - #{product.name}" : item.sku,
      operation_id: print_flow&.operation_id,
      job_operation_id: nil, # Will be set by Switch
      url: primary_asset ? asset_download_url(primary_asset) : nil,
      widegest_url: nil, # Not used in our workflow
      filename: switch_filename,
      scala: item.scala || "1:1",
      quantita: item.quantity,
      materiale: item.materiale,
      macchina: item.print_machine&.name, # Print machine name
      campi_custom: item.campi_custom || {},
      opzioni_stampa: print_flow&.opzioni_stampa || {},
      campi_webhook: item.campi_webhook || { percentuale: "0" },
      metadata: {
        job_id: job_id,
        order_id: order.id,
        item_id: item.id,
        store_code: order.store.code,
        created_at: Time.now.iso8601
      }
    }
    
    # Add secondary asset info if it's a two-stage workflow
    secondary_assets = item.switch_print_assets[1..-1]
    if secondary_assets.present?
      secondary_asset = secondary_assets.first
      payload[:secondary_url] = asset_download_url(secondary_asset) if secondary_asset
      payload[:secondary_filename] = item.switch_filename_for_asset(secondary_asset) if secondary_asset
    end
    
    payload
  end
  
  def asset_download_url(asset)
    # Build full URL for asset download
    # This is called by Switch to retrieve the file
    base_url = ENV['ASSET_BASE_URL'] || "http://localhost:5000"
    "#{base_url}/api/assets/#{asset.id}/download"
  end
end
