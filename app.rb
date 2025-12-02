require 'sinatra/base'
require 'sinatra/activerecord'
require 'sinatra/contrib'
require 'dotenv'
require 'json'
require 'time'

# Load environment variables from .env file
dotenv_path = File.expand_path('.env', __dir__)
puts "[DEBUG_DOTENV] Loading .env from: #{dotenv_path}"
puts "[DEBUG_DOTENV] File exists: #{File.exist?(dotenv_path)}"
Dotenv.load(dotenv_path)
puts "[DEBUG_DOTENV] GESTIONALE_BASE_URL: #{ENV['GESTIONALE_BASE_URL'].inspect}"
puts "[DEBUG_DOTENV] SWITCH_WEBHOOK_BASE_URL: #{ENV['SWITCH_WEBHOOK_BASE_URL'].inspect}"
puts "[DEBUG_DOTENV] SWITCH_WEBHOOK_PREFIX: #{ENV['SWITCH_WEBHOOK_PREFIX'].inspect}"

class PrintOrchestrator < Sinatra::Base
  register Sinatra::ActiveRecordExtension

  # Enable method override for PUT/DELETE requests from forms
  use Rack::MethodOverride

  configure do
    set :root, File.dirname(__FILE__)
    set :views, Proc.new { File.join(root, 'views') }
    set :public_folder, Proc.new { File.join(root, 'public') }
    set :database_file, 'config/database.yml'
    set :bind, '0.0.0.0'
    set :port, ENV['PORT'] || 5000
    
    # Host authorization - allow specific hosts
    allowed_hosts = [
      'localhost',
      '127.0.0.1',
      '.replit.dev',   # All *.replit.dev subdomains
      '.repl.co',      # All *.repl.co subdomains
      # Allow private network ranges for local deployment
      IPAddr.new('192.168.0.0/16'),   # 192.168.0.0 - 192.168.255.255
      IPAddr.new('10.0.0.0/8'),       # 10.0.0.0 - 10.255.255.255
      IPAddr.new('172.16.0.0/12'),    # 172.16.0.0 - 172.31.255.255
    ]
    
    set :host_authorization, permitted_hosts: allowed_hosts
  end

  # Disable browser caching for all responses
  before do
    cache_control :no_cache, :no_store, :must_revalidate
    headers 'Pragma' => 'no-cache'
    headers 'Expires' => '0'
    
    # LOG ALL REQUESTS
    if request.post?
      puts "[REQUEST] POST #{request.path} - Content-Type: #{request.content_type}"
      puts "[REQUEST] Params keys: #{params.keys.inspect}"
      puts "[REQUEST] File param: #{params[:file].class if params[:file]}"
    end
  end

  # Load models
  require_relative 'models/store'
  require_relative 'models/order'
  require_relative 'models/order_item'
  require_relative 'models/asset'
  require_relative 'models/switch_job'
  require_relative 'models/switch_webhook'
  require_relative 'models/print_flow'
  require_relative 'models/product_category'
  require_relative 'models/product'
  require_relative 'models/product_print_flow'
  require_relative 'models/print_machine'
  require_relative 'models/print_flow_machine'
  require_relative 'models/inventory'
  require_relative 'models/import_error'
  require_relative 'models/pending_file'
  require_relative 'models/backup_config'
  require_relative 'models/aggregated_job'
  require_relative 'models/aggregated_job_item'

  # Load services
  require_relative 'lib/backup'
  require_relative 'services/asset_downloader'
  require_relative 'services/switch_client'
  require_relative 'services/ftp_poller'

  # Serve local asset files
  get '/file/:id' do
    begin
      asset = Asset.find(params[:id])
      
      if asset.downloaded? && File.exist?(asset.local_path_full)
        send_file asset.local_path_full
      else
        status 404
        'File not found'
      end
    rescue ActiveRecord::RecordNotFound
      status 404
      'Asset not found'
    end
  end

  # Download asset file
  get '/assets/:id/download' do
    begin
      asset = Asset.find(params[:id])
      
      if asset.downloaded? && File.exist?(asset.local_path_full)
        send_file asset.local_path_full, disposition: 'attachment'
      else
        redirect request.referer || '/orders'
      end
    rescue ActiveRecord::RecordNotFound
      redirect request.referer || '/orders'
    end
  end

  # Delete asset file
  delete '/assets/:id' do
    begin
      asset = Asset.find(params[:id])
      order_id = asset.order_item.order_id
      
      if asset.downloaded? && File.exist?(asset.local_path_full)
        File.delete(asset.local_path_full)
        asset.update(local_path: nil)
      end
      
      redirect "/orders/#{order_id}"
    rescue => e
      redirect "/orders"
    end
  end

  # Health check endpoint
  get '/health' do
    content_type :json
    {
      status: 'ok',
      timestamp: Time.now.iso8601,
      database: ActiveRecord::Base.connection.active? ? 'connected' : 'disconnected'
    }.to_json
  end

  # Load routes
  require_relative 'routes/orders_api'
  require_relative 'routes/switch_api'
  require_relative 'routes/switch_callback'
  require_relative 'routes/switch_json_payload'
  require_relative 'routes/switch_asset_download'
  require_relative 'routes/web_ui'
  require_relative 'routes/stores_web'
  require_relative 'routes/print_flows_web'
  require_relative 'routes/product_categories_web'
  require_relative 'routes/webhooks_web'
  require_relative 'routes/products_web'
  require_relative 'routes/order_items_switch'
  require_relative 'routes/admin_print_machines'
  require_relative 'routes/admin_cleanup_web'
  require_relative 'routes/switch_reports'
  require_relative 'routes/pdf_proxy'
  require_relative 'routes/api_print_flows'
  
  # Start FTP poller in background (if configured)
  configure do
    FTPPoller.new.start
  end
end
