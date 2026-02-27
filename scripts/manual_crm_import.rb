# @feature crm
# @domain tools
# Manual CRM Importer - Loads a CRM JSON file directly into the database
# Usage: /usr/local/opt/ruby@3.2/bin/ruby scripts/manual_crm_import.rb path/to/file.json

require_relative '../app'
require 'json'

class ManualCRMImporter
  def self.import(file_path)
    unless File.exist?(file_path)
      puts "❌ Error: File not found at #{file_path}"
      return
    end

    begin
      content = File.read(file_path)
      data = JSON.parse(content)

      unless data['type'] == 'crm_order'
        puts "❌ Error: Unknown JSON type '#{data['type']}'. Expected 'crm_order'."
        return
      end

      store_code = data['site_name']&.gsub(/\s+/, '_')
      store = Store.find_by_code(store_code)
      
      if store.nil?
        puts "⚠️ Warning: Store '#{store_code}' not found. Creating a temporary store record..."
        store = Store.create!(code: store_code, name: data['site_name'] || store_code)
      end

      # Check for duplicate
      if Sale.exists?(external_order_code: data['order_number'], store_id: store.id)
        puts "⚠️ Warning: Sale already imported for order #{data['order_number']} in store #{store.code}. Skipping."
        return
      end

      ActiveRecord::Base.transaction do
        # Upsert customer
        customer = Customer.upsert_from_crm(data, store)

        unless customer
          raise "Failed to upsert customer (missing data or invalid email)"
        end

        # Create sale
        order_date = data['order_date'] ? Time.parse(data['order_date']) : Time.now
        financials = data['financials'] || {}

        sale = Sale.create!(
          customer: customer,
          store: store,
          external_order_code: data['order_number'],
          order_date: order_date,
          total: financials['total']&.to_f || 0,
          tax: financials['tax']&.to_f || 0,
          shipping: financials['shipping']&.to_f || 0,
          discount: financials['discount']&.to_f || 0,
          payment_method: financials['payment_method'],
          currency: financials['currency'] || 'EUR'
        )

        # Create sale items
        (data['products'] || []).each do |product|
          sale.sale_items.create!(
            sku: product['sku'],
            product_name: product['name'],
            quantity: product['quantity']&.to_i || 1,
            line_total: product['line_total']&.to_f || 0
          )
        end

        puts "✅ Successfully imported CRM data!"
        puts "   - Order: #{data['order_number']}"
        puts "   - Customer: #{customer.full_name} (#{customer.email})"
        puts "   - Total: #{sale.currency} #{sale.total}"
      end

    rescue JSON::ParserError => e
      puts "❌ Error: Invalid JSON format - #{e.message}"
    rescue => e
      puts "❌ Error: #{e.message}"
      puts e.backtrace.first(5).join("\n")
    end
  end
end

if __FILE__ == $0
  if ARGV.empty?
    puts "Usage: ruby scripts/manual_crm_import.rb <path_to_json_file>"
  else
    ManualCRMImporter.import(ARGV[0])
  end
end
