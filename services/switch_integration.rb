# @feature autopilot
# @domain services
# SwitchIntegration - Wrapper for sending OrderItems to Switch preprint

require_relative 'switch_client'

class SwitchIntegration
  def send_to_preprint(order_item)
    puts "[SwitchIntegration] Preparing to send item #{order_item.id} to Switch preprint"
    
    # Build job payload for Switch
    job_data = build_preprint_payload(order_item)
    
    puts "[SwitchIntegration] Job data prepared: #{job_data.inspect}"
    
    # Send to Switch via static method
    result = SwitchClient.send_to_switch(
      webhook_path: '/jobs/preprint',
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
    category = product&.product_category

    {
      operation_id: 1, # 1 = PREPRINT, 2 = PRINT, 3 = LABEL
      codice_ordine: order.external_order_code,
      id_riga: order_item.id,
      sku: order_item.sku,
      quantity: order_item.quantity,
      product_name: product&.name || 'Unknown',
      category: category&.name || 'Unknown',
      print_files: order_item.switch_print_assets.map(&:original_url),
      timestamp: Time.current.to_i
    }
  end
end
