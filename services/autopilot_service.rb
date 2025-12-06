# @feature autopilot
# @domain service
# Autopilot Service - Automatically sends items to Switch for preprint when category has autopilot enabled

class AutopilotService
  def self.process_order(order)
    puts "[AutopilotService] Processing order #{order.external_order_code} for autopilot"
    
    order.order_items.each do |item|
      process_item(item)
    end
  end

  def self.process_item(item)
    product = item.product
    return unless product

    category = product.product_category
    return unless category && category.autopilot_preprint_enabled

    # Check if item can be sent to preprint
    unless item.can_send_to_preprint?
      puts "[AutopilotService] Item #{item.id} cannot be sent (status: #{item.preprint_status})"
      return
    end

    puts "[AutopilotService] ✓ Autopilot enabled for category: #{category.name}"
    puts "[AutopilotService] Sending item #{item.id} (SKU: #{item.sku}) to preprint automatically"

    # Send to Switch for preprint
    begin
      SwitchIntegration.new.send_to_preprint(item)
      puts "[AutopilotService] ✓ Successfully sent item #{item.id} to preprint"
    rescue => e
      puts "[AutopilotService] ✗ Failed to send item #{item.id} to preprint: #{e.message}"
    end
  end
end
