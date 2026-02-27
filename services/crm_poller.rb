# @feature crm
# @domain service
# CRM Poller - Polls FTP /crm/ directory for CRM JSON files (customer + financial data)
# Runs independently of the production FTPPoller

require 'net/ftp'
require 'json'

class CRMPoller
  def initialize
    @ftp_host = ENV['FTP_HOST']
    @ftp_user = ENV['FTP_USER']
    @ftp_pass = ENV['FTP_PASS']
    @ftp_port = ENV['FTP_PORT']&.to_i || 21
    @ftp_path = ENV['FTP_CRM_PATH'] || (ENV['FTP_PATH'] ? "#{ENV['FTP_PATH'].chomp('/')}/crm" : '/orders/crm')
    @poll_interval = ENV['CRM_POLL_INTERVAL']&.to_i || 120
    @processed_files = Set.new
  end

  def start
    return unless valid_config?

    puts "[CRMPoller] Starting CRM polling - Host: #{@ftp_host}, Path: #{@ftp_path}, Interval: #{@poll_interval}s"

    Thread.new do
      loop do
        begin
          poll_once
        rescue => e
          puts "[CRMPoller] ERROR: #{e.message}"
          puts e.backtrace.first(5).join("\n")
        end

        sleep @poll_interval
      end
    end
  end

  private

  def valid_config?
    if @ftp_host.nil? || @ftp_user.nil? || @ftp_pass.nil?
      puts "[CRMPoller] FTP credentials not configured. CRM polling disabled."
      return false
    end
    true
  end

  def poll_once
    ftp = connect
    return unless ftp

    begin
      # Ensure the CRM directory exists
      begin
        ftp.chdir(@ftp_path)
      rescue Net::FTPPermError => e
        puts "[CRMPoller] CRM directory #{@ftp_path} not found yet, skipping."
        return
      end

      files = get_crm_files(ftp)

      if files.empty?
        return
      end

      puts "[CRMPoller] Found #{files.length} CRM file(s)"

      files.each do |filename|
        next if @processed_files.include?(filename)

        puts "[CRMPoller] Processing: #{filename}"
        success = process_crm_file(ftp, filename)
        @processed_files.add(filename) if success
      end
    rescue => e
      puts "[CRMPoller] Error during polling: #{e.message}"
    ensure
      ftp.close rescue nil
    end
  end

  def get_crm_files(ftp)
    begin
      return ftp.nlst('crm_*.json')
    rescue => e
      puts "[CRMPoller] nlst failed: #{e.message}, trying list..."
    end

    begin
      list_output = ftp.list('crm_*.json')
      return list_output.map { |line| line.split.last }.compact
    rescue => e
      puts "[CRMPoller] list also failed: #{e.message}"
    end

    []
  end

  def connect
    ftp = Net::FTP.new(@ftp_host, port: @ftp_port, username: @ftp_user, password: @ftp_pass)
    ftp.passive = true
    ftp
  rescue => e
    puts "[CRMPoller] ✗ Connection failed: #{e.message}"
    nil
  end

  def process_crm_file(ftp, filename)
    begin
      content = ""
      ftp.retrbinary("RETR #{filename}", 4096) { |data| content += data }

      data = JSON.parse(content)

      unless data['type'] == 'crm_order'
        puts "[CRMPoller] ✗ Unknown type in #{filename}: #{data['type']}"
        move_to_failed(ftp, filename, "Unknown type: #{data['type']}")
        return false
      end

      # Validate store
      store_code = data['site_name']&.gsub(/\s+/, '_')
      store = Store.find_by_code(store_code)

      # Check for duplicate
      if store && Sale.exists?(external_order_code: data['order_number'], store_id: store.id)
        puts "[CRMPoller] ✗ Sale already imported: #{data['order_number']}"
        move_to_failed(ftp, filename, "Sale already imported: #{data['order_number']}")
        return false
      end

      # Import using transaction
      ActiveRecord::Base.transaction do
        # Upsert customer
        customer = Customer.upsert_from_crm(data, store)

        unless customer
          raise "Customer data missing or invalid email"
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

        puts "[CRMPoller] ✓ Imported CRM data: Order #{data['order_number']}, Customer: #{customer.full_name} (#{customer.email})"
      end

      move_to_imported(ftp, filename)
      true

    rescue JSON::ParserError => e
      puts "[CRMPoller] ✗ Invalid JSON in #{filename}: #{e.message}"
      move_to_failed(ftp, filename, "Invalid JSON: #{e.message}")
      false
    rescue => e
      puts "[CRMPoller] ✗ Failed to process #{filename}: #{e.message}"
      move_to_failed(ftp, filename, e.message)
      false
    end
  end

  def move_to_imported(ftp, filename)
    begin
      ftp.mkdir('imported') rescue nil
      ftp.rename(filename, "imported/#{filename}")
      puts "[CRMPoller] ✓ Moved #{filename} to imported/"
    rescue => e
      puts "[CRMPoller] ⚠ Could not move file: #{e.message}"
    end
  end

  def move_to_failed(ftp, filename, error_message = nil)
    begin
      ftp.mkdir('failed') rescue nil
      ftp.rename(filename, "failed/#{filename}")
      puts "[CRMPoller] ✓ Moved #{filename} to failed/"
    rescue => e
      puts "[CRMPoller] ⚠ Could not move file: #{e.message}"
    end
  end
end
