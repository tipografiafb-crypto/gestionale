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
      data = JSON.parse(content)
      
      # Import using transaction (same logic as API)
      result = ActiveRecord::Base.transaction do
        store = Store.find_or_create_by_code(
          data['store_id'],
          data['store_name']
        )
        
        order = Order.create!(
          store: store,
          external_order_code: data['external_order_code'],
          status: 'new',
          source: 'ftp'  # Track that it came from FTP
        )
        
        data['items'].each do |item_data|
          order_item = order.order_items.create!(
            sku: item_data['sku'],
            quantity: item_data['quantity']
          )
          
          order_item.store_json_data(item_data) if item_data.keys.length > 2
          order_item.save
          
          item_data['image_urls'].each_with_index do |url, index|
            asset_type = determine_asset_type(url, index)
            order_item.assets.create!(
              original_url: url,
              asset_type: asset_type
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
      
      puts "[FTPPoller] ✓ Imported order: #{result[:external_order_code]} (ID: #{result[:order_id]})"
      
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
    end
  end

  def determine_asset_type(url, index)
    filename = url.downcase
    return 'front' if filename.include?('front')
    return 'back' if filename.include?('back')
    return 'mask' if filename.include?('mask')
    
    case index
    when 0 then 'front'
    when 1 then 'back'
    else "asset_#{index + 1}"
    end
  end
end
