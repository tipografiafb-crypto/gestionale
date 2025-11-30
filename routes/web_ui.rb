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
    
    @orders = Order.includes(:store, :switch_job, :order_items).recent
    @orders = @orders.by_store(params[:store_id]) if params[:store_id].present?
    @orders = @orders.by_order_code(params[:order_code]) if params[:order_code].present?
    @orders = @orders.by_date(params[:order_date]) if params[:order_date].present?
    @orders = @orders.limit(100)
    
    # Try to load import errors, but gracefully handle if table doesn't exist
    @import_errors = []
    begin
      @import_errors = ImportError.recent
      @import_errors = @import_errors.where('external_order_code ILIKE ?', "%#{params[:error_order_code]}%") if params[:error_order_code].present?
      @import_errors = @import_errors.by_date(params[:error_date]) if params[:error_date].present?
      @import_errors = @import_errors.limit(100)
    rescue ActiveRecord::StatementInvalid => e
      # Table doesn't exist yet - migrations not run on this database
      puts "[WARNING] import_errors table not found. Run migrations: bundle exec rake db:migrate"
      @import_errors = []
    end
    
    @filter_store = params[:store_id]
    @filter_order_code = params[:order_code]
    @filter_order_date = params[:order_date]
    @filter_error_order_code = params[:error_order_code]
    @filter_error_date = params[:error_date]
    
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

          quantity = item_params[:quantity].to_i
          order_item = order.order_items.build(
            sku: item_params[:sku],
            quantity: quantity,
            raw_json: {
              sku: item_params[:sku],
              quantity: quantity,
              product_name: product.name
            }.to_json
          )
          order_item.save!

          # Deduct from inventory
          if product.inventory
            product.inventory.remove_stock(quantity)
          end

          # Handle multiple file uploads
          files = item_params[:files] || []
          files.each_with_index do |file, file_index|
            next if file.blank? || !file.is_a?(Hash) || file[:filename].blank?
            
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
              # Tag with print_file_1, print_file_2, etc. to match FTPPoller convention
              existing_print_files = order_item.assets.select { |a| a.asset_type&.start_with?('print_file') }.count
              asset_index = existing_print_files + 1
              
              asset = order_item.assets.build(
                original_url: filename,
                local_path: local_path,
                asset_type: "print_file_#{asset_index}"
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

  # GET /orders/:id - Order detail (list of jobs)
  get '/orders/:id' do
    @order = Order.includes(:store, { order_items: :assets }, :switch_job).find(params[:id])
    erb :order_detail
  rescue ActiveRecord::RecordNotFound
    status 404
    erb :not_found
  end

  # POST /orders/:id/force_close - Force close an order
  post '/orders/:id/force_close' do
    @order = Order.find(params[:id])
    @order.update(status: 'done')
    @order.order_items.each do |item|
      item.update(preprint_status: 'completed', preprint_completed_at: Time.now, print_status: 'completed', print_completed_at: Time.now)
    end
    redirect "/orders"
  rescue => e
    redirect "/orders?error=#{e.message}"
  end

  # GET /orders/:order_id/items/:item_id - Order item detail (job detail)
  get '/orders/:order_id/items/:item_id' do
    @order = Order.includes(:store).find(params[:order_id])
    @item = @order.order_items.includes(:assets, :preprint_job, :print_job).find(params[:item_id])
    erb :order_item_detail
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

  # GET /orders/:order_id/items/:item_id/preprint_result_section - Preprint result section (for polling)
  get '/orders/:order_id/items/:item_id/preprint_result_section' do
    @order = Order.find(params[:order_id])
    @item = @order.order_items.includes(:assets).find(params[:item_id])
    
    # Get the Switch output file (created when Switch returns the file)
    print_output_asset = @item.assets.where(asset_type: 'print_output').first
    
    html = ""
    
    # If preprint is processing but no file yet, show processing bar
    if @item.preprint_status == 'processing' && !print_output_asset
      html = <<~HTML
        <div style="display: flex; gap: 10px; align-items: center;">
          <div style="flex: 1;">
            <div style="display: flex; align-items: center; gap: 8px;">
              <span style="font-size: 14px; font-weight: bold;">🔄 Elaborando in Switch...</span>
              <div style="flex: 1; height: 4px; background: #e9ecef; border-radius: 2px; overflow: hidden;">
                <div style="height: 100%; background: linear-gradient(90deg, #0d6efd, #0dcaf0); animation: progress 1.5s infinite; width: 30%;"></div>
              </div>
            </div>
          </div>
        </div>
      HTML
    # If file exists (from Switch), show result button and confirm button
    elsif print_output_asset && @item.preprint_status == 'processing'
      html = <<~HTML
        <div style="display: flex; gap: 10px; align-items: center;">
          <a href="/file/#{print_output_asset.id}" class="btn btn-outline-secondary" target="_blank" title="Switch result file: #{print_output_asset.original_url}">
            📄 Result
          </a>
          <form action="/orders/#{@order.id}/items/#{@item.id}/confirm_preprint" method="post" class="d-inline">
            <button type="submit" class="btn btn-success">
              ✓ Conferma Pre-stampa
            </button>
          </form>
        </div>
      HTML
    # If preprint is completed and file exists, show only result button (user can still view file)
    elsif print_output_asset && @item.preprint_status == 'completed'
      html = <<~HTML
        <div style="display: flex; gap: 10px; align-items: center;">
          <a href="/file/#{print_output_asset.id}" class="btn btn-outline-secondary" target="_blank" title="Switch result file: #{print_output_asset.original_url}">
            📄 Result
          </a>
          <span style="font-size: 12px; color: #6c757d;">✓ Pre-stampa confermata</span>
        </div>
      HTML
    end
    
    html
  rescue ActiveRecord::RecordNotFound
    status 404
    ''
  end

  # GET /orders/:order_id/items/:item_id/print_result_section - Print result section (for polling)
  get '/orders/:order_id/items/:item_id/print_result_section' do
    @order = Order.find(params[:order_id])
    @item = @order.order_items.includes(:assets).find(params[:item_id])
    
    # Get the Switch output file from print phase (asset_type: 'print_result' or similar)
    # For now, we check if a new print_output was created after print_status changed to processing
    print_result_asset = @item.assets.where(asset_type: 'print_output').order(:created_at).last
    
    html = ""
    
    # If print is processing but no result file yet, show processing bar
    if @item.print_status == 'processing' && !print_result_asset
      html = <<~HTML
        <div style="display: flex; gap: 10px; align-items: center;">
          <div style="flex: 1;">
            <div style="display: flex; align-items: center; gap: 8px;">
              <span style="font-size: 14px; font-weight: bold;">🔄 Elaborando in Switch...</span>
              <div style="flex: 1; height: 4px; background: #e9ecef; border-radius: 2px; overflow: hidden;">
                <div style="height: 100%; background: linear-gradient(90deg, #0d6efd, #0dcaf0); animation: progress 1.5s infinite; width: 30%;"></div>
              </div>
            </div>
          </div>
        </div>
      HTML
    # If file exists (from Switch), show result button and confirm button
    elsif print_result_asset && @item.print_status == 'processing'
      html = <<~HTML
        <div style="display: flex; gap: 10px; align-items: center;">
          <a href="/file/#{print_result_asset.id}" class="btn btn-outline-secondary" target="_blank" title="Switch result file: #{print_result_asset.original_url}">
            📄 Result
          </a>
          <form action="/orders/#{@order.id}/items/#{@item.id}/confirm_print" method="post" class="d-inline">
            <button type="submit" class="btn btn-success">
              ✓ Conferma Stampa
            </button>
          </form>
        </div>
      HTML
    # If print is completed and file exists, show only result button (user can still view file)
    elsif print_result_asset && @item.print_status == 'completed'
      html = <<~HTML
        <div style="display: flex; gap: 10px; align-items: center;">
          <a href="/file/#{print_result_asset.id}" class="btn btn-outline-secondary" target="_blank" title="Switch result file: #{print_result_asset.original_url}">
            📄 Result
          </a>
          <span style="font-size: 12px; color: #6c757d;">✓ Stampa confermata</span>
        </div>
      HTML
    end
    
    html
  rescue ActiveRecord::RecordNotFound
    status 404
    ''
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

  # POST /orders/:order_id/items/:item_id/upload - Upload print file
  post '/orders/:order_id/items/:item_id/upload' do
    puts "[UPLOAD] ✅ Route called! Order: #{params[:order_id]}, Item: #{params[:item_id]}"
    puts "[UPLOAD] File: #{params[:file].class} - #{!params[:file].nil?}"
    
    begin
      order = Order.find(params[:order_id])
      item = order.order_items.find(params[:item_id])
      file = params[:file]
      
      if file && file[:filename]
        puts "[UPLOAD] Processing file: #{file[:filename]}"
        
        unless valid_file_extension?(file[:filename])
          puts "[UPLOAD] Invalid extension"
          return redirect "/orders/#{order.id}/items/#{item.id}?error=invalid_file"
        end
        
        store_code = order.store.code || order.store.id.to_s
        order_code = order.external_order_code
        sku = item.sku
        upload_dir = File.join(Dir.pwd, 'storage', store_code, order_code, sku)
        FileUtils.mkdir_p(upload_dir)
        
        filename = File.basename(file[:filename])
        local_path = "storage/#{store_code}/#{order_code}/#{sku}/#{filename}"
        full_path = File.join(Dir.pwd, local_path)
        
        File.write(full_path, file[:tempfile].read)
        
        # Create new asset
        asset = item.assets.create(
          asset_type: 'print_file',
          original_url: "file:#{filename}",
          local_path: local_path
        )
        
        puts "[UPLOAD] ✅ Asset #{asset.id} created for item #{item.id}"
      end
    rescue => e
      puts "[UPLOAD] ❌ ERROR: #{e.message}"
      puts e.backtrace.take(3)
    end
    
    redirect "/orders/#{order.id}/items/#{item.id}"
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

  # GET /line_items - List all order items from in-progress orders with multiple filters
  get '/line_items' do
    # Get only orders that are in progress (not done/error)
    in_progress_orders = Order.where("status NOT IN ('done', 'error')").includes(:store, :order_items)
    
    # Get all stores for dropdown
    @stores = Store.all.order(:name)
    
    # Get all order items from these orders, with their associated order and product
    @line_items = []
    in_progress_orders.each do |order|
      order.order_items.each do |item|
        @line_items << {
          item: item,
          order: order,
          product_name: item.product&.name || item.sku,
          sku: item.sku
        }
      end
    end
    
    # Store filter values
    @filter_order_date = params[:order_date]
    @filter_order_code = params[:order_code]
    @filter_store = params[:store_id]
    @filter_product_name = params[:product_name]
    @filter_sku = params[:sku]
    
    # Apply filters
    # Filter by date
    if @filter_order_date.present?
      filter_date = Date.parse(@filter_order_date)
      @line_items = @line_items.select { |li| li[:order].created_at.to_date == filter_date }
    end
    
    # Filter by order code
    if @filter_order_code.present?
      @line_items = @line_items.select { |li| li[:order].external_order_code.downcase.include?(@filter_order_code.downcase) }
    end
    
    # Filter by store
    if @filter_store.present?
      @line_items = @line_items.select { |li| li[:order].store_id.to_s == @filter_store }
    end
    
    # Filter by product name
    if @filter_product_name.present?
      @line_items = @line_items.select { |li| li[:product_name].downcase.include?(@filter_product_name.downcase) }
    end
    
    # Filter by SKU
    if @filter_sku.present?
      @line_items = @line_items.select { |li| li[:sku].downcase.include?(@filter_sku.downcase) }
    end
    
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
          inv.quantity_in_stock <= 0
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

  # POST /orders/:order_id/items/:item_id/reset - Reset item workflow
  post '/orders/:order_id/items/:item_id/reset' do
    begin
      order = Order.find(params[:order_id])
      item = order.order_items.find(params[:item_id])
      
      # Delete all Switch output files (this ensures the processing bar appears again next time)
      item.assets.where(asset_type: 'print_output').destroy_all
      puts "[RESET] Deleted print_output assets for item #{item.id}"
      
      # Reset workflow statuses to pending - only update fields that exist
      reset_data = {
        preprint_status: 'pending',
        print_status: 'pending'
      }
      
      # Add optional fields if they exist in the table
      if OrderItem.column_names.include?('preprint_preview_url')
        reset_data[:preprint_preview_url] = nil
      end
      if OrderItem.column_names.include?('preprint_started_at')
        reset_data[:preprint_started_at] = nil
      end
      if OrderItem.column_names.include?('preprint_completed_at')
        reset_data[:preprint_completed_at] = nil
      end
      if OrderItem.column_names.include?('preprint_print_flow_id')
        reset_data[:preprint_print_flow_id] = nil
      end
      if OrderItem.column_names.include?('print_started_at')
        reset_data[:print_started_at] = nil
      end
      if OrderItem.column_names.include?('print_completed_at')
        reset_data[:print_completed_at] = nil
      end
      if OrderItem.column_names.include?('print_machine_id')
        reset_data[:print_machine_id] = nil
      end
      
      item.update(reset_data)
      redirect "/orders/#{order.id}/items/#{item.id}?msg=success&text=Item%20reimpostato%20al%20workflow%20iniziale"
    rescue => e
      puts "[RESET_ERROR] #{e.class}: #{e.message}"
      puts e.backtrace.join("\n")
      error_msg = e.message.to_s.gsub(' ', '%20').gsub("'", '%27')[0..100]
      redirect "/orders/#{params[:order_id]}/items/#{params[:item_id]}?msg=error&text=#{error_msg}"
    end
  end

  # POST /import_errors/clear_all - Delete all import errors
  post '/import_errors/clear_all' do
    begin
      deleted_count = ImportError.delete_all
      redirect "/orders?msg=success&text=#{URI.encode_www_form_component(deleted_count.to_s + ' errori cancellati')}"
    rescue => e
      redirect "/orders?msg=error&text=#{URI.encode_www_form_component('Errore cancellazione: ' + e.message)}"
    end
  end

  # POST /import_errors/:id/delete - Delete single import error
  post '/import_errors/:id/delete' do
    begin
      error = ImportError.find(params[:id])
      error.destroy
      redirect "/orders?msg=success&text=Errore+cancellato"
    rescue => e
      redirect "/orders?msg=error&text=#{URI.encode_www_form_component('Errore cancellazione: ' + e.message)}"
    end
  end
end
