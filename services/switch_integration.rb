# @feature autopilot
# @domain services
# SwitchIntegration - Executes the SAME preprint logic as manual send_preprint route
# Retrieves the preprint endpoint dynamically from the product's default print flow
# Sends EACH print asset individually (same as manual route)

require_relative 'switch_client'

class SwitchIntegration
  def send_to_preprint(order_item)
    puts "[SwitchIntegration] Preparing to send item #{order_item.id} to Switch preprint"
    
    order = order_item.order
    
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
    
    # Store print flow and campi_webhook (same as manual route does)
    campi_webhook = { "percentuale" => "0" }
    order_item.update(
      preprint_print_flow_id: print_flow.id,
      preprint_status: 'processing',
      campi_webhook: campi_webhook
    )
    
    # Get all print assets (same as manual route)
    print_assets = order_item.switch_print_assets
    unless print_assets.any?
      puts "[SwitchIntegration] ✗ No print assets found for item #{order_item.id}"
      order_item.update(preprint_status: 'failed')
      return { success: false, error: 'No print assets found' }
    end
    
    # Send EACH asset individually (same as manual route - lines 66-97)
    begin
      errors = []
      successful_assets = []
      server_url = ENV['SERVER_BASE_URL'] || 'http://localhost:5000'
      
      print_assets.each do |print_asset|
        puts "[SwitchIntegration] Processing asset: #{print_asset.id}"
        
        # Build Switch payload EXACTLY as manual route does
        job_data = {
          id_riga: order_item.item_number,
          codice_ordine: order.external_order_code,
          product: "#{product&.sku} - #{product&.name}",
          operation_id: 1,  # 1=prepress
          job_operation_id: order_item.id.to_s,
          url: "#{server_url}/api/assets/#{print_asset.id}/download",
          widegest_url: "#{server_url}/api/v1/reports_create",
          filename: order_item.switch_filename_for_asset(print_asset) || "#{order.external_order_code.downcase}-#{order_item.id}.png",
          quantita: order_item.quantity,
          materiale: product&.notes || 'N/A',
          campi_custom: {},
          opzioni_stampa: {},
          campi_webhook: campi_webhook
        }
        
        puts "[SwitchIntegration] Calling SwitchClient.send_to_switch with webhook_path: #{webhook_path.inspect}"
        result = SwitchClient.send_to_switch(
          webhook_path: webhook_path,
          job_data: job_data
        )
        puts "[SwitchIntegration] Result: #{result.inspect}"
        
        if result[:success]
          successful_assets << print_asset.id
        else
          errors << result[:error]
        end
      end
      
      if errors.any?
        order_item.update(preprint_status: 'failed')
        puts "[SwitchIntegration] ✗ Failed to send some assets: #{errors.join(', ')}"
        return { success: false, error: errors.join(', ') }
      else
        order_item.update(preprint_status: 'processing', preprint_job_id: successful_assets.join(','))
        puts "[SwitchIntegration] ✓ Successfully sent #{successful_assets.length} asset(s) to Switch"
        return { success: true, message: "Sent #{successful_assets.length} asset(s) to Switch", job_ids: successful_assets }
      end
    rescue => e
      order_item.update(preprint_status: 'failed')
      puts "[SwitchIntegration] ✗ Exception: #{e.class}: #{e.message}"
      puts "[SwitchIntegration] Backtrace: #{e.backtrace.first(3).join("\n")}"
      return { success: false, error: "#{e.class}: #{e.message}" }
    end
  end
end
