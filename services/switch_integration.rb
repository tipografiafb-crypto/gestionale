# @feature autopilot
# @domain services
# SwitchIntegration - Wrapper for sending OrderItems to Switch preprint
# Uses the SAME payload format as manual send (build_payload in SwitchClient)
# Retrieves the preprint endpoint dynamically from the product's default print flow

require_relative 'switch_client'

class SwitchIntegration
  def send_to_preprint(order_item)
    puts "[SwitchIntegration] Preparing to send item #{order_item.id} to Switch preprint"
    
    # Get the preprint webhook endpoint from product's default print flow
    product = order_item.product
    unless product
      puts "[SwitchIntegration] ✗ No product found for item #{order_item.id}"
      return { success: false, error: 'No product found' }
    end
    
    # Get default print flow for this product
    print_flow = product.default_print_flow
    unless print_flow
      puts "[SwitchIntegration] ✗ No default print flow configured for product #{product.sku}"
      return { success: false, error: 'No default print flow configured' }
    end
    
    # Get preprint webhook from print flow
    preprint_webhook = print_flow.preprint_webhook
    unless preprint_webhook
      puts "[SwitchIntegration] ✗ No preprint webhook configured for print flow #{print_flow.name}"
      return { success: false, error: 'No preprint webhook configured' }
    end
    
    webhook_path = preprint_webhook.hook_path
    puts "[SwitchIntegration] Using webhook endpoint: #{webhook_path} (from print flow: #{print_flow.name})"
    
    # Build job payload for Switch - SAME FORMAT as manual send
    job_data = build_preprint_payload(order_item)
    
    puts "[SwitchIntegration] Job data prepared: #{job_data.inspect}"
    
    # Send to Switch using the webhook endpoint from print flow
    result = SwitchClient.send_to_switch(
      webhook_path: webhook_path,
      job_data: job_data
    )
    
    if result[:success]
      puts "[SwitchIntegration] ✓ Successfully sent to Switch: #{result[:message]}"
      # Update order item status to 'processing' if successful
      order_item.update(preprint_status: 'processing') if order_item.preprint_status == 'pending'
    else
      puts "[SwitchIntegration] ✗ Failed to send to Switch: #{result[:error]}"
    end
    
    result
  end

  private

  def build_preprint_payload(order_item)
    order = order_item.order
    product = order_item.product
    primary_asset = order_item.assets.first
    
    # Use SAME payload format as manual send (from SwitchClient.build_payload)
    {
      id_riga: order_item.id,
      codice_ordine: order.external_order_code,
      product: product ? "#{product.sku} - #{product.name}" : order_item.sku,
      operation_id: 1, # 1 = PREPRINT operation
      job_operation_id: "autopilot-order-#{order.id}-item-#{order_item.id}",
      url: "#{gestionale_base_url}/api/assets/#{primary_asset&.id}/download",
      widegest_url: "#{server_base_url}/api/v1/reports_create",
      filename: primary_asset&.filename_from_url || "#{order.external_order_code}_#{order_item.id}.png",
      quantita: order_item.quantity,
      materiale: product&.material || "N/A",
      campi_custom: {},
      opzioni_stampa: {},
      campi_webhook: {}
    }
  end

  def server_base_url
    ENV['SERVER_BASE_URL'] || 'http://localhost:5000'
  end

  def gestionale_base_url
    # URL for downloading assets from Gestionale (external management system)
    ENV['GESTIONALE_BASE_URL'] || 'http://192.168.1.55:5000'
  end
end
