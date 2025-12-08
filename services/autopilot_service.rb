# @feature autopilot
# @domain service
# Autopilot Service - Automatically sends items to Switch for preprint when category has autopilot enabled

class AutopilotService
  def self.process_order(order)
    puts "[AutopilotService] ⏱ STARTING: Processing order #{order.external_order_code} for autopilot"
    puts "[AutopilotService] Order has #{order.order_items.count} items"
    
    processed_count = 0
    order.order_items.each do |item|
      if process_item(item)
        processed_count += 1
      end
    end
    
    puts "[AutopilotService] ✓ DONE: #{processed_count} items sent to autopilot"
  end

  def self.process_item(item)
    puts "[AutopilotService] → Checking item #{item.id} (SKU: #{item.sku})"
    
    product = item.product
    unless product
      puts "[AutopilotService]   ✗ No product found for item #{item.id}"
      return false
    end
    
    puts "[AutopilotService]   ✓ Product found: #{product.name}"

    category = product.product_category
    unless category
      puts "[AutopilotService]   ✗ No category found for product #{product.id}"
      return false
    end
    
    puts "[AutopilotService]   Category: #{category.name}, Autopilot: #{category.autopilot_preprint_enabled}"
    
    unless category.autopilot_preprint_enabled
      puts "[AutopilotService]   ✗ Autopilot NOT enabled for this category"
      return false
    end

    # Check if item can be sent to preprint
    unless item.can_send_to_preprint?
      puts "[AutopilotService]   ✗ Item cannot be sent to preprint (status: #{item.preprint_status})"
      return false
    end

    puts "[AutopilotService]   ✓ Autopilot enabled for category: #{category.name}"
    puts "[AutopilotService]   → Sending item #{item.id} (SKU: #{item.sku}) to preprint automatically..."

    # Send to Switch for preprint
    begin
      SwitchIntegration.new.send_to_preprint(item)
      puts "[AutopilotService]   ✓ SUCCESS: Item #{item.id} sent to preprint!"
      return true
    rescue => e
      puts "[AutopilotService]   ✗ FAILED: #{e.message}"
      puts "[AutopilotService]   Backtrace: #{e.backtrace.first(3).join("\n")}"
      return false
    end
  end
end
