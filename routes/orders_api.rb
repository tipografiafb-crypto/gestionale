# @feature orders
# @domain api
# Orders API routes - Handles order import and management
require 'json'

class PrintOrchestrator < Sinatra::Base
  # POST /api/orders/import
  # Import new order from e-commerce platform
  post '/api/orders/import' do
    content_type :json
    
    begin
      data = JSON.parse(request.body.read)
      
      # Wrap all database operations in a transaction for data integrity
      result = ActiveRecord::Base.transaction do
        # Find or create store
        store = Store.find_or_create_by_code(
          data['store_id'],
          data['store_name']
        )
        
        # Create order
        order = Order.create!(
          store: store,
          external_order_code: data['external_order_code'],
          status: 'new'
        )
        
        # Create order items and assets
        data['items'].each do |item_data|
          order_item = order.order_items.create!(
            sku: item_data['sku'],
            quantity: item_data['quantity']
          )
          
          # Store raw JSON if present
          order_item.store_json_data(item_data) if item_data.keys.length > 2
          order_item.save
          
          # Create assets from image URLs
          item_data['image_urls'].each_with_index do |url, index|
            # Try to determine asset type from URL or position
            asset_type = determine_asset_type(url, index)
            
            order_item.assets.create!(
              original_url: url,
              asset_type: asset_type
            )
          end
        end
        
        # Capture counts inside transaction before commit
        {
          order_id: order.id,
          external_order_code: order.external_order_code,
          items_count: order.order_items.count,
          assets_count: order.assets.count
        }
      end
      
      status 200
      { 
        success: true
      }.merge(result).to_json
      
    rescue JSON::ParserError => e
      status 400
      { success: false, error: "Invalid JSON: #{e.message}" }.to_json
    rescue ActiveRecord::RecordInvalid => e
      status 422
      { success: false, error: e.message }.to_json
    rescue StandardError => e
      status 500
      { success: false, error: "Server error: #{e.message}" }.to_json
    end
  end

  # POST /api/orders/:id/download_assets
  # Download all assets for an order
  post '/api/orders/:id/download_assets' do
    content_type :json
    
    begin
      order = Order.find(params[:id])
      downloader = AssetDownloader.new(order)
      results = downloader.download_all
      
      status 200
      { success: true, results: results }.to_json
      
    rescue ActiveRecord::RecordNotFound
      status 404
      { success: false, error: 'Order not found' }.to_json
    rescue StandardError => e
      status 500
      { success: false, error: e.message }.to_json
    end
  end

  # POST /api/orders/:id/send_to_switch
  # Send order to Enfocus Switch
  post '/api/orders/:id/send_to_switch' do
    content_type :json
    
    begin
      order = Order.find(params[:id])
      client = SwitchClient.new(order)
      result = client.send_to_switch
      
      if result[:success]
        status 200
      else
        status 422
      end
      
      result.to_json
      
    rescue ActiveRecord::RecordNotFound
      status 404
      { success: false, error: 'Order not found' }.to_json
    rescue StandardError => e
      status 500
      { success: false, error: e.message }.to_json
    end
  end

  private

  def determine_asset_type(url, index)
    # Try to determine from filename
    filename = url.downcase
    return 'front' if filename.include?('front')
    return 'back' if filename.include?('back')
    return 'mask' if filename.include?('mask')
    
    # Fallback to index-based naming
    case index
    when 0 then 'front'
    when 1 then 'back'
    else "asset_#{index + 1}"
    end
  end
end
