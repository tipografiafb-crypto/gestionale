# @feature integration
# @domain service
# FTP Poller - Polls FTP directory every 60 seconds for new order JSON files

require 'net/ftp'
require 'json'

class FTPPoller
  def initialize
    @ftp_host = ENV['FTP_HOST']
    @ftp_user = ENV['FTP_USER']
    @ftp_pass = ENV['FTP_PASS']
    @ftp_port = ENV['FTP_PORT']&.to_i || 21
    @ftp_path = ENV['FTP_PATH'] || '/orders'
    @poll_interval = ENV['FTP_POLL_INTERVAL']&.to_i || 60
    @processed_files = Set.new
  end

  def start
    return unless valid_config?
    
    puts "[FTPPoller] Starting FTP polling - Host: #{@ftp_host}, Path: #{@ftp_path}, Interval: #{@poll_interval}s"
    
    Thread.new do
      loop do
        begin
          poll_once
        rescue => e
          puts "[FTPPoller] ERROR: #{e.message}"
          puts e.backtrace.join("\n")
        end
        
        sleep @poll_interval
      end
    end
  end

  private

  def valid_config?
    if @ftp_host.nil? || @ftp_user.nil? || @ftp_pass.nil?
      puts "[FTPPoller] FTP credentials not configured. Polling disabled."
      return false
    end
    true
  end

  def poll_once
    ftp = connect
    return unless ftp
    
    begin
      ftp.chdir(@ftp_path)
      files = ftp.nlst('*.json')
      
      files.each do |filename|
        next if @processed_files.include?(filename)
        
        puts "[FTPPoller] Found new file: #{filename}"
        process_file(ftp, filename)
        @processed_files.add(filename)
      end
    ensure
      ftp.close
    end
  end

  def connect
    ftp = Net::FTP.new(@ftp_host, port: @ftp_port, username: @ftp_user, password: @ftp_pass)
    ftp.passive = true
    ftp
  rescue => e
    puts "[FTPPoller] Connection failed: #{e.message}"
    nil
  end

  def process_file(ftp, filename)
    begin
      # Download file content to memory
      content = ""
      ftp.retrbinary("RETR #{filename}", 4096) { |data| content += data }
      
      # Parse JSON
      raw_data = JSON.parse(content)
      
      # Convert WooCommerce format to standard format
      data = normalize_order_data(raw_data)
      
      # Import using transaction
      result = ActiveRecord::Base.transaction do
        store = Store.find_or_create_by_code(
          data['store_id'],
          data['store_name']
        )
        
        order = Order.create!(
          store: store,
          external_order_code: data['external_order_code'],
          status: 'new',
          source: 'ftp',
          customer_name: data['customer_name'],
          customer_note: data['customer_note']
        )
        
        data['items'].each do |item_data|
          order_item = order.order_items.create!(
            sku: item_data['sku'].presence || "SKU-#{order.id}-#{order_item.count + 1}",
            quantity: item_data['quantity']
          )
          
          order_item.store_json_data(item_data)
          order_item.save
          
          # Create assets from product image
          if item_data['product_image_url'].present?
            order_item.assets.create!(
              original_url: item_data['product_image_url'],
              asset_type: 'product_image'
            )
          end
          
          # Create assets from print files
          item_data['print_files'].each_with_index do |url, index|
            order_item.assets.create!(
              original_url: url,
              asset_type: "print_file_#{index + 1}"
            )
          end
          
          # Create assets from screenshots
          item_data['screenshots'].each_with_index do |url, index|
            order_item.assets.create!(
              original_url: url,
              asset_type: "screenshot_#{index + 1}"
            )
          end
        end
        
        {
          order_id: order.id,
          external_order_code: order.external_order_code,
          items_count: order.order_items.count,
          assets_count: order.assets.count
        }
      end
      
      puts "[FTPPoller] ✓ Imported order: #{result[:external_order_code]} (ID: #{result[:order_id]}) - #{result[:items_count]} items, #{result[:assets_count]} assets"
      
      # Optional: Delete file after successful import
      if ENV['FTP_DELETE_AFTER_IMPORT'].downcase == 'true'
        ftp.delete(filename)
        puts "[FTPPoller] Deleted: #{filename}"
      end
      
    rescue JSON::ParserError => e
      puts "[FTPPoller] Invalid JSON in #{filename}: #{e.message}"
    rescue ActiveRecord::RecordInvalid => e
      puts "[FTPPoller] Database error for #{filename}: #{e.message}"
    rescue => e
      puts "[FTPPoller] Failed to process #{filename}: #{e.message}"
      puts e.backtrace.join("\n")
    end
  end

  # Convert WooCommerce/Lumise JSON format to standard format
  def normalize_order_data(raw_data)
    {
      'store_id' => raw_data['site_name']&.gsub(/\s+/, '_') || 'unknown',
      'store_name' => raw_data['site_name'] || 'Unknown Store',
      'external_order_code' => raw_data['number'] || raw_data['id'],
      'customer_name' => raw_data['customer_name'],
      'customer_note' => raw_data['customer_note'],
      'items' => normalize_items(raw_data)
    }
  end

  # Normalize line items and associate with print files/screenshots
  def normalize_items(raw_data)
    print_files_map = build_assets_map(raw_data['print_files_with_cart_id'])
    screenshots_map = build_assets_map(raw_data['screenshots_with_cart_id'])
    
    raw_data['line_items'].map do |item|
      lumise_data = item['meta_data']&.dig('lumise_data') || {}
      cart_id = lumise_data['cart_id']
      
      {
        'sku' => item['sku'],
        'quantity' => item['quantity'],
        'product_name' => lumise_data['product_name'] || 'Unknown Product',
        'product_image_url' => item['image']&.dig('src'),
        'print_files' => print_files_map[cart_id] || [],
        'screenshots' => screenshots_map[cart_id] || [],
        'raw_data' => lumise_data
      }
    end
  end

  # Build a map of cart_id => [urls]
  def build_assets_map(assets_with_cart_id)
    return {} unless assets_with_cart_id.is_a?(Array)
    
    map = {}
    assets_with_cart_id.each do |item|
      cart_id = item['cart_id']
      urls = item['print_files'] || item['screenshots'] || []
      map[cart_id] = urls
    end
    map
  end
end
