# @feature autopilot
# @domain service
# Autopilot Service - Automatically sends items to Switch for preprint when category has autopilot enabled

require_relative 'switch_integration'

class AutopilotService
  def self.process_order(order)
    puts "[AutopilotService] ⏱ STARTING: Processing order #{order.external_order_code} for autopilot"
    puts "[AutopilotService] Order has #{order.order_items.count} items"
    
    # Mark order as in processing (same as manual route does)
    order.update(status: 'processing') if order.status == 'new'
    
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
    puts "[AutopilotService]   → Checking preprint readiness..."
    puts "[AutopilotService]     • preprint_status: #{item.preprint_status}"
    puts "[AutopilotService]     • assets count: #{item.assets.count}"
    puts "[AutopilotService]     • assets details:"
    item.assets.each do |asset|
      puts "[AutopilotService]       - #{asset.asset_type}: local_path=#{asset.local_path.inspect}, file_exists=#{asset.local_path ? File.exist?(asset.local_path_full) : 'N/A'}"
    end
    
    unless item.can_send_to_preprint?
      puts "[AutopilotService]   ✗ Item cannot be sent to preprint (status: #{item.preprint_status}, assets_ready: #{item.assets.empty? || item.assets.any?(&:downloaded?)})"
      return false
    end

    puts "[AutopilotService]   ✓ Autopilot enabled for category: #{category.name}"
    puts "[AutopilotService]   → Scheduling item #{item.id} (SKU: #{item.sku}) to send to Switch (60s delay)..."
    
    # Send to Switch in a background thread after 60 second delay
    # This allows multiple orders to be processed without blocking import
    Thread.new do
      puts "[AutopilotService] [ASYNC] Starting 60 second delay for item #{item.id}..."
      sleep(60)
      puts "[AutopilotService] [ASYNC] 60 second delay complete, sending to Switch for item #{item.id}"
      
      begin
        result = SwitchIntegration.new.send_to_preprint(item)
        
        if result&.dig(:success)
          puts "[AutopilotService] [ASYNC] ✓ SUCCESS: Item #{item.id} sent to preprint!"
        else
          error_msg = result&.dig(:error) || "Unknown error"
          puts "[AutopilotService] [ASYNC] ✗ Failed to send to Switch: #{error_msg}"
        end
      rescue => e
        puts "[AutopilotService] [ASYNC] ✗ FAILED with exception: #{e.message}"
        puts "[AutopilotService] [ASYNC] Backtrace: #{e.backtrace.first(3).join("\n")}"
      end
    end
    
    # Return immediately - order is scheduled for send, not sent yet
    puts "[AutopilotService]   ✓ Item scheduled for async send (60s delay)"
    return true
  end
end
