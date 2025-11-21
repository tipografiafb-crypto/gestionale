require 'sinatra/base'
require 'sinatra/activerecord'
require 'sinatra/contrib'
require 'dotenv/load'
require 'json'
require 'time'

class PrintOrchestrator < Sinatra::Base
  register Sinatra::ActiveRecordExtension

  configure do
    set :root, File.dirname(__FILE__)
    set :views, Proc.new { File.join(root, 'views') }
    set :public_folder, Proc.new { File.join(root, 'public') }
    set :database_file, 'config/database.yml'
    set :bind, '0.0.0.0'
    set :port, ENV['PORT'] || 5000
    
    # Allow Replit domains (wildcard subdomains)
    set :host_authorization, permitted_hosts: [
      'localhost',
      '.replit.dev',   # All *.replit.dev subdomains
      '.repl.co'       # All *.repl.co subdomains
    ]
  end

  # Load models
  require_relative 'models/store'
  require_relative 'models/order'
  require_relative 'models/order_item'
  require_relative 'models/asset'
  require_relative 'models/switch_job'
  require_relative 'models/switch_webhook'
  require_relative 'models/print_flow'
  require_relative 'models/product'

  # Load services
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
  require_relative 'routes/web_ui'
  require_relative 'routes/print_flows_web'
  require_relative 'routes/webhooks_web'
  require_relative 'routes/products_web'
  
  # Start FTP poller in background (if configured)
  configure do
    FTPPoller.new.start
  end
end
