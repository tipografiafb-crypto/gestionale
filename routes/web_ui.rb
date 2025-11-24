# @feature ui
# @domain web
# Web UI routes - HTML interface for operators
require 'json'

class PrintOrchestrator < Sinatra::Base
  VALID_FILE_EXTENSIONS = %w[png jpg jpeg pdf].freeze

  def valid_file_extension?(filename)
    ext = File.extname(filename).downcase.sub(/^\./, '')
    VALID_FILE_EXTENSIONS.include?(ext)
  end

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
              # Validate file extension
              unless valid_file_extension?(file[:filename])
                order.destroy
                redirect "/orders/new?error=Tipo file non consentito per #{item_params[:sku]}. Solo PNG, JPG, JPEG, PDF"
              end

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

  # GET /orders/:order_id/items/:item_id/print - Print item card
  get '/orders/:order_id/items/:item_id/print' do
    @order = Order.includes(:store).find(params[:order_id])
    @item = @order.order_items.includes(:assets).find(params[:item_id])
    erb :print_item_card, layout: false
  rescue ActiveRecord::RecordNotFound
    status 404
    'Item not found'
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

  # POST /orders/:order_id/items/:item_id/upload_asset - Re-upload asset file
  post '/orders/:order_id/items/:item_id/upload_asset' do
    order = Order.find(params[:order_id])
    item = order.order_items.find(params[:item_id])
    asset = Asset.find(params[:asset_id])
    
    file = params[:file]
    if file.present? && file.is_a?(Hash) && file[:filename].present?
      begin
        # Validate file extension
        unless valid_file_extension?(file[:filename])
          redirect "/orders/#{order.id}?msg=error&text=#{URI.encode_www_form_component('Tipo file non consentito. Solo PNG, JPG, JPEG, PDF')}"
        end

        store_code = order.store.code || order.store.id.to_s
        order_code = order.external_order_code
        sku = item.sku
        upload_dir = File.join(Dir.pwd, 'storage', store_code, order_code, sku)
        FileUtils.mkdir_p(upload_dir) unless Dir.exist?(upload_dir)
        
        filename = File.basename(file[:filename])
        local_path = "storage/#{store_code}/#{order_code}/#{sku}/#{filename}"
        full_path = File.join(Dir.pwd, local_path)
        
        content = file[:tempfile].read
        File.open(full_path, 'wb') { |f| f.write(content) }
        
        asset.update(local_path: local_path)
      rescue => e
        warn "File upload error for #{sku}: #{e.message}"
      end
    end
    
    redirect "/orders/#{order.id}"
  rescue => e
    redirect "/orders"
  end

  # DELETE /orders/:id - Delete order
  delete '/orders/:id' do
    order = Order.find(params[:id])
    
    # Restore inventory before deleting order
    order.order_items.each do |item|
      product = Product.find_by(sku: item.sku)
      if product && product.inventory
        product.inventory.add_stock(item.quantity)
      end
    end
    
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

  # GET /line_items - List all order items from in-progress orders with product search
  get '/line_items' do
    # Get only orders that are in progress (not done/error)
    in_progress_orders = Order.where("status NOT IN ('done', 'error')").includes(:store, :order_items)
    
    # Get all order items from these orders, with their associated order and product
    @line_items = []
    in_progress_orders.each do |order|
      order.order_items.each do |item|
        @line_items << {
          item: item,
          order: order,
          product_name: item.product&.name || item.sku
        }
      end
    end
    
    # Filter by product name if search param is provided
    if params[:search].present?
      search_term = params[:search].downcase
      @line_items = @line_items.select { |li| li[:product_name].downcase.include?(search_term) }
    end
    
    @search_term = params[:search]
    erb :line_items
  end

  # GET /inventory - Manage warehouse stock
  get '/inventory' do
    @inventory_items = Inventory.includes(:product).all
    
    # Filter by status if provided (disponibili, sottoscorta, finiti)
    @status_filter = params[:status]
    if @status_filter.present?
      @inventory_items = @inventory_items.select do |inv|
        case @status_filter
        when 'finiti'
          inv.quantity_in_stock == 0
        when 'sottoscorta'
          inv.quantity_in_stock > 0 && inv.quantity_in_stock < inv.product.min_stock_level
        when 'disponibili'
          inv.quantity_in_stock >= inv.product.min_stock_level
        else
          true
        end
      end
    end
    
    # Filter by SKU or product name if search param is provided
    if params[:search].present?
      search_term = params[:search].downcase
      @inventory_items = @inventory_items.select do |inv|
        inv.product.sku.downcase.include?(search_term) || 
        inv.product.name.downcase.include?(search_term)
      end
    end
    
    @search_term = params[:search]
    erb :inventory
  end

  # POST /inventory/:id/add - Add stock
  post '/inventory/:id/add' do
    inventory = Inventory.find(params[:id])
    quantity = params[:quantity].to_i
    
    if quantity > 0
      inventory.add_stock(quantity)
      redirect "/inventory?msg=success&text=Aggiunto%20#{quantity}%20prodotti"
    else
      redirect "/inventory?msg=error&text=Quantità%20non%20valida"
    end
  rescue => e
    redirect "/inventory?msg=error&text=Errore%20nell'aggiunta"
  end

  # POST /inventory/:id/remove - Remove stock
  post '/inventory/:id/remove' do
    inventory = Inventory.find(params[:id])
    quantity = params[:quantity].to_i
    
    if quantity > 0 && inventory.remove_stock(quantity)
      redirect "/inventory?msg=success&text=Rimosso%20#{quantity}%20prodotti"
    else
      redirect "/inventory?msg=error&text=Quantità%20insufficiente%20o%20non%20valida"
    end
  rescue => e
    redirect "/inventory?msg=error&text=Errore%20nella%20rimozione"
  end
end
