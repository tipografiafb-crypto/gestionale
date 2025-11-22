# @feature ui
# @domain web
# Web UI routes - HTML interface for operators
require 'json'
require 'mini_magick'

class PrintOrchestrator < Sinatra::Base
  # GET / - Redirect to orders list
  get '/' do
    redirect '/orders'
  end

  # GET /orders - List all orders with filtering
  get '/orders' do
    @stores = Store.where(active: true).ordered
    
    @orders = Order.includes(:store, :switch_job).recent
    @orders = @orders.by_store(params[:store_id]) if params[:store_id].present?
    @orders = @orders.by_order_code(params[:order_code]) if params[:order_code].present?
    @orders = @orders.by_date(params[:order_date]) if params[:order_date].present?
    @orders = @orders.limit(100)
    
    @filter_store = params[:store_id]
    @filter_order_code = params[:order_code]
    @filter_order_date = params[:order_date]
    
    erb :orders_list
  end

  # GET /orders/new - Form for manual order entry
  get '/orders/new' do
    @stores = Store.where(active: true).ordered
    @products = Product.where(active: true).ordered
    erb :new_order
  end

  # POST /orders - Create order manually
  post '/orders' do
    store = Store.find(params[:store_id])
    
    begin
      order = Order.new(
        store_id: store.id,
        external_order_code: params[:order_code],
        status: 'new'
      )
      
      unless order.save
        redirect "/orders/new?error=#{order.errors.full_messages.join(',')}"
      end

      # Add items
      if params[:items].present?
        params[:items].each_with_index do |item_params, index|
          next if item_params[:sku].blank?
          
          product = Product.find_by(sku: item_params[:sku])
          if product.nil?
            order.destroy
            redirect "/orders/new?error=SKU non trovato: #{item_params[:sku]}"
          end

          order_item = order.order_items.build(
            sku: item_params[:sku],
            quantity: item_params[:quantity].to_i,
            raw_json: {
              sku: item_params[:sku],
              quantity: item_params[:quantity],
              product_name: product.name
            }.to_json
          )
          order_item.save!

          # Handle file upload
          file = item_params[:file]
          if file.present? && file.is_a?(Hash) && file[:filename].present?
            begin
              # Create storage directory if needed
              store_code = store.code || store.id.to_s
              order_code = params[:order_code]
              sku = item_params[:sku]
              upload_dir = File.join(Dir.pwd, 'storage', store_code, order_code, sku)
              FileUtils.mkdir_p(upload_dir) unless Dir.exist?(upload_dir)
              
              # Save file
              filename = File.basename(file[:filename])
              local_path = "storage/#{store_code}/#{order_code}/#{sku}/#{filename}"
              full_path = File.join(Dir.pwd, local_path)
              
              # Read and write file content
              content = file[:tempfile].read
              File.open(full_path, 'wb') { |f| f.write(content) }
              
              # Create Asset record (manual orders only have print assets)
              asset = order_item.assets.build(
                original_url: filename,
                local_path: local_path,
                asset_type: 'print'
              )
              asset.save!
            rescue => e
              # Log error but continue
              warn "File upload error for #{item_params[:sku]}: #{e.message}"
            end
          end
        end
      end

      if order.order_items.empty?
        order.destroy
        redirect "/orders/new?error=Aggiungere almeno un item"
      end

      redirect "/orders/#{order.id}"
    rescue => e
      redirect "/orders/new?error=#{e.message}"
    end
  end

  # GET /orders/:id - Order detail
  get '/orders/:id' do
    @order = Order.includes(:store, { order_items: :assets }, :switch_job).find(params[:id])
    erb :order_detail
  rescue ActiveRecord::RecordNotFound
    status 404
    erb :not_found
  end

  # POST /orders/:id/download - Trigger asset download (web form)
  post '/orders/:id/download' do
    order = Order.find(params[:id])
    downloader = AssetDownloader.new(order)
    downloader.download_all
    
    redirect "/orders/#{params[:id]}"
  rescue ActiveRecord::RecordNotFound
    status 404
    erb :not_found
  end

  # POST /orders/:id/send - Trigger send to Switch (web form)
  post '/orders/:id/send' do
    order = Order.find(params[:id])
    client = SwitchClient.new(order)
    client.send_to_switch
    
    redirect "/orders/#{params[:id]}"
  rescue ActiveRecord::RecordNotFound
    status 404
    erb :not_found
  end

  # DELETE /orders/:id - Delete order
  delete '/orders/:id' do
    order = Order.find(params[:id])
    order.destroy
    redirect '/orders'
  rescue ActiveRecord::RecordNotFound
    status 404
    erb :not_found
  end

  # POST /orders/:id/duplicate - Duplicate order for reprinting
  post '/orders/:id/duplicate' do
    order = Order.find(params[:id])
    new_order = order.duplicate
    redirect "/orders/#{new_order.id}"
  rescue ActiveRecord::RecordNotFound
    status 404
    erb :not_found
  end

  # POST /orders/:order_id/items/:item_id/assets/:asset_id/transform - Transform PNG asset
  post '/orders/:order_id/items/:item_id/assets/:asset_id/transform' do
    order = Order.find(params[:order_id])
    item = order.order_items.find(params[:item_id])
    asset = item.assets.find(params[:asset_id])

    offset_x = params[:offset_x].to_i
    offset_y = params[:offset_y].to_i
    zoom = params[:zoom].to_f / 100.0

    begin
      # Load and process image with ImageMagick
      image = MiniMagick::Image.open(asset.local_path_full)
      
      # Apply zoom (resize)
      new_width = (image.width * zoom).round
      new_height = (image.height * zoom).round
      image.resize("#{new_width}x#{new_height}!")
      
      # Apply offset (create canvas and composite)
      canvas_width = (image.width + (offset_x.abs * 2)).round
      canvas_height = (image.height + (offset_y.abs * 2)).round
      left = offset_x >= 0 ? offset_x : offset_x.abs
      top = offset_y >= 0 ? offset_y : offset_y.abs
      
      image.background('white').gravity('Center').extent("#{canvas_width}x#{canvas_height}+#{left}+#{top}")
      
      # Save back to original path
      image.write(asset.local_path_full)
      
      redirect "/orders/#{order.id}?msg=success&text=Asset+modificato+con+successo"
    rescue => e
      redirect "/orders/#{order.id}?msg=error&text=#{URI.encode_www_form_component('Errore modifica: ' + e.message)}"
    end
  end

  # GET /file/:id - Serve downloaded asset file
  get '/file/:id' do
    asset = Asset.find(params[:id])
    
    if asset.downloaded? && File.exist?(asset.local_path_full)
      send_file asset.local_path_full
    else
      status 404
      body 'File not found'
    end
  rescue ActiveRecord::RecordNotFound
    status 404
    body 'Asset not found'
  end
end
