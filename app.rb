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
    
    # Disable protection for Replit iframe embedding
    disable :protection
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
  require_relative 'routes/web_ui'
  require_relative 'routes/stores_web'
  require_relative 'routes/print_flows_web'
  require_relative 'routes/product_categories_web'
  require_relative 'routes/webhooks_web'
  require_relative 'routes/products_web'
  require_relative 'routes/order_items_switch'
  
  # Start FTP poller in background (if configured)
  configure do
    FTPPoller.new.start
  end
end
