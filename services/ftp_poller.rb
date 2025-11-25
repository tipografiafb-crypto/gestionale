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
      puts "[FTPPoller] Changing to directory: #{@ftp_path}"
      ftp.chdir(@ftp_path)
      
      # Try to get file list - try nlst first, fallback to list
      files = get_json_files(ftp)
      
      if files.empty?
        puts "[FTPPoller] No .json files found in #{@ftp_path}"
        return
      end
      
      puts "[FTPPoller] Found #{files.length} JSON file(s)"
      
      files.each do |filename|
        next if @processed_files.include?(filename)
        
        puts "[FTPPoller] Processing: #{filename}"
        process_file(ftp, filename)
        @processed_files.add(filename)
      end
    rescue => e
      puts "[FTPPoller] Error during polling: #{e.message}"
    ensure
      ftp.close rescue nil
    end
  end

  def get_json_files(ftp)
    # Try nlst first (more efficient)
    begin
      return ftp.nlst('*.json')
    rescue => e
      puts "[FTPPoller] nlst failed: #{e.message}, trying list..."
    end
    
    # Fallback to list and filter
    begin
      list_output = ftp.list('*.json')
      return list_output.map { |line| line.split.last }.compact
    rescue => e
      puts "[FTPPoller] list also failed: #{e.message}"
    end
    
    []
  end

  def connect
    ftp = Net::FTP.new(@ftp_host, port: @ftp_port, username: @ftp_user, password: @ftp_pass)
    ftp.passive = true
    puts "[FTPPoller] ✓ Connected to #{@ftp_host}:#{@ftp_port}"
    ftp
  rescue => e
    puts "[FTPPoller] ✗ Connection failed: #{e.message}"
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
      
      # Validate store exists and is active
      store = Store.find_by_code(data['store_id'])
      unless store
        error_msg = "Store not found or inactive: #{data['store_id']}"
        puts "[FTPPoller] ✗ #{error_msg}"
        move_file_to_failed(ftp, filename, error_msg)
        return
      end
      
      # Validate all products exist before importing
      missing_skus = []
      data['items'].each do |item_data|
        unless Product.exists?(sku: item_data['sku'])
          missing_skus << item_data['sku']
        end
      end
      
      if missing_skus.any?
        error_msg = "Products not found: #{missing_skus.join(', ')}"
        puts "[FTPPoller] ✗ #{error_msg}"
        move_file_to_failed(ftp, filename, error_msg)
        return
      end
      
      # Import using transaction
      result = ActiveRecord::Base.transaction do
        order = Order.create!(
          store: store,
          external_order_code: data['external_order_code'],
          status: 'new',
          source: 'ftp'
        )
        
        data['items'].each_with_index do |item_data, idx|
          order_item = order.order_items.create!(
            sku: item_data['sku'],
            quantity: item_data['quantity']
          )
          
          order_item.store_json_data(item_data)
          order_item.save
          
          # Create assets from print files (skip product_image)
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
      
      # Auto-download all assets immediately after import
      order = Order.find(result[:order_id])
      downloader = AssetDownloader.new(order)
      download_results = downloader.download_all
      
      puts "[FTPPoller] ✓ Imported order: #{result[:external_order_code]} (ID: #{result[:order_id]}) - #{result[:items_count]} items, #{result[:assets_count]} assets"
      puts "[FTPPoller] ✓ Downloaded: #{download_results[:downloaded]}, Errors: #{download_results[:errors]}, Skipped: #{download_results[:skipped]}"
      
      # Move file to imported folder after successful import
      move_file_to_imported(ftp, filename)
      
    rescue JSON::ParserError => e
      puts "[FTPPoller] ✗ Invalid JSON in #{filename}: #{e.message}"
      move_file_to_failed(ftp, filename, "Invalid JSON: #{e.message}")
    rescue ActiveRecord::RecordInvalid => e
      puts "[FTPPoller] ✗ Database error for #{filename}: #{e.message}"
      move_file_to_failed(ftp, filename, "Database error: #{e.message}")
    rescue => e
      puts "[FTPPoller] ✗ Failed to process #{filename}: #{e.message}"
      move_file_to_failed(ftp, filename, e.message)
    end
  end

  def move_file_to_imported(ftp, filename)
    begin
      # Create imported folder if not exists
      ftp.mkdir('imported_order_test') rescue nil
      ftp.rename(filename, "imported_order_test/#{filename}")
      puts "[FTPPoller] ✓ Moved #{filename} to imported_order_test/"
    rescue => e
      puts "[FTPPoller] ⚠ Could not move file to imported folder: #{e.message}"
    end
  end

  def move_file_to_failed(ftp, filename, error_message = nil)
    begin
      # Save error record
      external_code = filename.gsub(/\.json$/, '')
      ImportError.create!(
        filename: filename,
        external_order_code: external_code,
        error_message: error_message || "Unknown error"
      )
      
      # Create failed folder if not exists
      ftp.mkdir('failed_orders_test') rescue nil
      ftp.rename(filename, "failed_orders_test/#{filename}")
      puts "[FTPPoller] ✓ Moved #{filename} to failed_orders_test/"
    rescue => e
      puts "[FTPPoller] ⚠ Could not move file to failed folder: #{e.message}"
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
      meta_data = item['meta_data']
      lumise_data = if meta_data.is_a?(Hash)
                      meta_data['lumise_data'] || {}
                    else
                      {}
                    end
      
      # Try to find cart_id from multiple sources
      cart_id = lumise_data['cart_id'] ||
                (meta_data.is_a?(Hash) && meta_data['_wc_ai_customization']&.dig('artwork_id')) ||
                nil
      
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
