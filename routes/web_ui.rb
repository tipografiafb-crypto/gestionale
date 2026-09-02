# @feature ui
# @domain web
# Web UI routes - HTML interface for operators
require 'json'
require 'open3'
require 'tmpdir'
require 'fileutils'
require 'tempfile'

class PrintOrchestrator < Sinatra::Base
  VALID_FILE_EXTENSIONS = %w[png jpg jpeg pdf svg dxf ai eps].freeze

  def valid_file_extension?(filename)
    ext = File.extname(filename).downcase.sub(/^\./, '')
    VALID_FILE_EXTENSIONS.include?(ext)
  end

  def png_path_info(path, target_dpi = 300)
    return nil unless path && File.extname(path).downcase == '.png' && File.exist?(path)
    File.open(path, 'rb') do |file|
      return nil unless file.read(8) == "\x89PNG\r\n\x1a\n".b

      width = nil
      height = nil
      declared_dpi = nil

      until file.eof?
        length_bytes = file.read(4)
        break unless length_bytes && length_bytes.bytesize == 4

        length = length_bytes.unpack1('N')
        chunk_type = file.read(4)
        data = file.read(length)
        file.read(4)

        if chunk_type == 'IHDR'
          width, height = data.unpack('NN')
        elsif chunk_type == 'pHYs' && data.bytesize >= 9
          x_pixels_per_unit, _y_pixels_per_unit, unit = data.unpack('NNC')
          declared_dpi = x_pixels_per_unit * 0.0254 if unit == 1
        end

        break if width && height && declared_dpi
        break if chunk_type == 'IDAT'
      end

      return nil unless width && height

      {
        width_px: width,
        height_px: height,
        declared_dpi: declared_dpi,
        target_dpi: target_dpi,
        print_width_cm: width.to_f / target_dpi * 2.54,
        print_height_cm: height.to_f / target_dpi * 2.54
      }
    end
  rescue => e
    puts "[PNG_INFO] Error reading #{path}: #{e.message}"
    nil
  end

  def png_print_info(asset, target_dpi = 300)
    return nil unless asset&.downloaded?

    png_path_info(asset.local_path_full, target_dpi)
  end

  def halftone_source_backup_path(asset)
    path = asset&.local_path_full
    return nil unless path

    dir = File.dirname(path)
    basename = File.basename(path, '.*')
    extension = File.extname(path)
    File.join(dir, "#{basename}_dtf_original#{extension}")
  end

  def halftone_source_path(asset)
    # Halftone is another editor in the same chain: always consume the
    # current operational file. The DTF backup is retained solely for restore.
    asset.local_path_full
  end

  def ensure_halftone_backup!(asset, source_path)
    backup_path = halftone_source_backup_path(asset)
    return backup_path if backup_path && File.file?(backup_path)

    original_path = ImageEditService.backup_path(asset)
    backup_source = original_path && File.file?(original_path) ? original_path : source_path
    FileUtils.copy(backup_source, backup_path) if backup_source && backup_path
    backup_path
  end

  def halftone_command(input_path, output_path, request_params, preview: false)
    target_dpi_raw = request_params['target_dpi'].presence || request_params['dpi'].presence
    target_dpi = numeric_param({ 'target_dpi' => target_dpi_raw }, 'target_dpi', 300, min: 1).to_i
    lpi = numeric_param(request_params, 'lpi', 35, min: 1, max: 120)
    angle = numeric_param(request_params, 'angle', 22.5, min: 0, max: 90)
    min_dot_default = truthy_param?(request_params, 'dotChk') ? request_params['dotPx'].presence || 3 : 0
    min_dot_px = numeric_param(request_params, 'min_dot_px', min_dot_default, min: 0, max: 50)
    dot_shape = request_params['dot_shape'].presence || request_params['spot'].presence || 'round'
    highlight_mode = request_params['highlight_mode'].presence || request_params['dotMode'].presence || 'drop'
    # The photographic DTF method is the default in both UI modes.  The
    # fabric checkbox only enables the optional Lab garment transition.
    tone_mode = request_params['tone_mode'].presence || 'dtf_difference'
    invert = truthy_param?(request_params, 'invert')
    saturation_raw = request_params['saturation'].presence || request_params['sat']
    saturation_raw = saturation_raw.to_f / 100.0 if request_params['saturation'].blank? && request_params['sat'].present?
    saturation = numeric_param({ 'saturation' => saturation_raw }, 'saturation', 1.0, min: 0, max: 3)
    contrast = numeric_param(request_params, 'contrast', 1.0, min: 0, max: 3)
    brightness = numeric_param(request_params, 'brightness', 0, min: -100, max: 100)
    knockout_strength = numeric_param(request_params, 'knockout_strength', 0, min: 0, max: 1)
    antialias_px = numeric_param(request_params, 'antialias_px', 0, min: 0, max: 5)
    mask_black = numeric_param(request_params, 'mask_black', request_params['lvB'].presence || 0, min: 0, max: 254)
    mask_white = numeric_param(request_params, 'mask_white', request_params['lvW'].presence || 255, min: mask_black + 1, max: 255)
    mask_gamma = numeric_param(request_params, 'mask_gamma', request_params['lvG'].presence || 1.0, min: 0.1, max: 10)
    output_black = numeric_param(request_params, 'output_black', request_params['lvOB'].presence || 0, min: 0, max: 255)
    output_white = numeric_param(request_params, 'output_white', request_params['lvOW'].presence || 255, min: output_black, max: 255)
    max_coverage = numeric_param(request_params, 'max_coverage', request_params['cap'].presence || 100, min: 0, max: 100)
    knockout_inner = numeric_param(request_params, 'knockout_inner', request_params['fabricInner'].presence || 3, min: 0, max: 99)
    knockout_outer = numeric_param(request_params, 'knockout_outer', request_params['fabricOuter'].presence || 30, min: knockout_inner + 0.1, max: 100)
    resize_width_cm = numeric_param(request_params, 'resize_width_cm', request_params['printw'].presence || 0, min: 0, max: 300)
    resize_height_cm = numeric_param(request_params, 'resize_height_cm', 0, min: 0, max: 300)
    # A garment reference is always present. Black is the default and follows
    # the established black-shirt separation; choosing another colour enables
    # the perceptual garment transition automatically.
    shirt_color = request_params['shirt_color'].presence || request_params['fabricCol'].presence || '#000000'
    shirt_color = '#000000' unless tone_mode == 'dtf_difference'

    dtf_python = ENV['DTF_PYTHON'].presence || File.join(settings.root, '.venv', 'bin', 'python')
    dtf_python = 'python3' unless File.executable?(dtf_python)

    command = [
      dtf_python, '-m', 'tools.dtf_halftone.cli',
      input_path,
      output_path,
      '--target-dpi', target_dpi.to_s,
      '--lpi', lpi.to_s,
      '--angle', angle.to_s,
      '--dot-shape', dot_shape,
      '--min-dot-px', min_dot_px.to_s,
      '--max-coverage', max_coverage.to_s,
      '--highlight-mode', highlight_mode,
      '--tone-mode', tone_mode,
      '--saturation', saturation.to_s,
      '--contrast', contrast.to_s,
      '--brightness', brightness.to_s,
      '--knockout-strength', knockout_strength.to_s,
      '--knockout-inner', knockout_inner.to_s,
      '--knockout-outer', knockout_outer.to_s,
      '--antialias-px', antialias_px.to_s,
      '--mask-black', mask_black.to_s,
      '--mask-white', mask_white.to_s,
      '--mask-gamma', mask_gamma.to_s,
      '--output-black', output_black.to_s,
      '--output-white', output_white.to_s,
      '--json'
    ]
    command << '--invert' if invert
    command.concat(['--shirt-color', shirt_color]) if shirt_color
    command.concat(['--resize-width-cm', resize_width_cm.to_s]) if resize_width_cm.positive?
    command.concat(['--resize-height-cm', resize_height_cm.to_s]) if resize_height_cm.positive?
    command
  end

  def numeric_param(request_params, key, default, min: nil, max: nil)
    raw_value = request_params[key].presence
    value = raw_value ? Float(raw_value) : (default.nil? ? default : Float(default))
    value = min if min && value < min
    value = max if max && value > max
    value
  rescue ArgumentError, TypeError
    default
  end

  def truthy_param?(request_params, key)
    value = request_params[key]
    return false if value.nil?

    %w[1 true yes on].include?(value.to_s.downcase)
  end

  # GET / - Redirect to orders list
  get '/' do
    redirect '/orders'
  end

  # GET /logs - System logs viewer
  get '/logs' do
    @logs = Log.recent.limit(500)
    @logs = @logs.by_level(params[:level]) if params[:level].present?
    @logs = @logs.by_category(params[:category]) if params[:category].present?
    @total_logs = Log.count
    @logs_24h = Log.last_24h.count
    
    erb :logs
  end

  # GET /orders - List all orders with filtering
  get '/orders' do
    @stores = Store.where(active: true).ordered
    
    @orders = Order.includes(:store, :switch_job, :order_items).recent
    @orders = @orders.by_store(params[:store_id]) if params[:store_id].present?
    @orders = @orders.by_order_code(params[:order_code]) if params[:order_code].present?
    @orders = @orders.by_date(params[:order_date]) if params[:order_date].present?
    
    # Sort by date
    sort_order = params[:sort] == 'desc' ? 'desc' : 'asc'
    @orders = @orders.sort_by(&:created_at)
    @orders = @orders.reverse if sort_order == 'desc'
    
    # Group by status BEFORE pagination
    @new_orders = @orders.select { |o| o.status == 'new' }
    @in_progress_orders = @orders.select { |o| %w[sent_to_switch processing].include?(o.status) }
    @completed_orders = @orders.select { |o| %w[done error].include?(o.status) }
    
    # Paginate each group separately (25 per page)
    per_page = 25
    
    # New orders pagination
    page = (params[:page] || 1).to_i
    @new_total_pages = (@new_orders.length.to_f / per_page).ceil
    @new_current_page = page
    start_idx = (page - 1) * per_page
    @new_orders_paginated = @new_orders[start_idx, per_page]
    
    # In Progress pagination
    in_prog_page = (params[:in_prog_page] || 1).to_i
    @in_prog_total_pages = (@in_progress_orders.length.to_f / per_page).ceil
    @in_prog_current_page = in_prog_page
    in_prog_start = (in_prog_page - 1) * per_page
    @in_progress_orders_paginated = @in_progress_orders[in_prog_start, per_page]
    
    # Completed pagination
    completed_page = (params[:completed_page] || 1).to_i
    @completed_total_pages = (@completed_orders.length.to_f / per_page).ceil
    @completed_current_page = completed_page
    completed_start = (completed_page - 1) * per_page
    @completed_orders_paginated = @completed_orders[completed_start, per_page]
    
    # Calculate delayed orders (from all orders, not just paginated)
    # Exclude completed orders (done/error) even if they were delayed
    delay_threshold = 7.days
    @delayed_orders = @orders.select do |order|
      (Time.now - order.created_at) > delay_threshold && 
      %w[new sent_to_switch processing].include?(order.status) &&
      !%w[done error].include?(order.status)
    end
    
    # Try to load import errors, but gracefully handle if table doesn't exist
    @import_errors = []
    @import_errors_total_count = 0
    begin
      @import_errors = ImportError.recent
      @import_errors = @import_errors.where('external_order_code ILIKE ?', "%#{params[:error_order_code]}%") if params[:error_order_code].present?
      @import_errors = @import_errors.by_date(params[:error_date]) if params[:error_date].present?
      
      # Save total count BEFORE pagination
      @import_errors_total_count = @import_errors.length
      
      # Manual pagination for import errors
      error_page = (params[:error_page] || 1).to_i
      @error_total_pages = (@import_errors_total_count.to_f / 25).ceil
      @error_current_page = error_page
      error_start = (error_page - 1) * 25
      @import_errors = @import_errors[error_start, 25]
    rescue ActiveRecord::StatementInvalid => e
      # Table doesn't exist yet - migrations not run on this database
      puts "[WARNING] import_errors table not found. Run migrations: bundle exec rake db:migrate"
      @import_errors = []
    end
    
    @filter_store = params[:store_id]
    @filter_order_code = params[:order_code]
    @filter_order_date = params[:order_date]
    @filter_sort = params[:sort]
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
            position: index + 1,
            raw_json: {
              sku: item_params[:sku],
              quantity: quantity,
              product_name: product.name
            }.to_json
          )
          order_item.save!

          # Deduct from inventory
          if product
            inventory_product = product.is_dependent && product.master_product ? product.master_product : product
            if inventory_product.inventory
              inventory_product.inventory.remove_stock(quantity)
            end
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
              
              # Handle cut file upload
              if item_params[:cut_file_upload] == 'true'
                asset = order_item.assets.build(
                  original_url: filename,
                  local_path: local_path,
                  asset_type: 'cut'
                )
                asset.save!
                ImageEditService.ensure_original_backup!(asset)
              else
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
                ImageEditService.ensure_original_backup!(asset)
              end
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

  # GET /orders/:id/print - Print order card
  get '/orders/:id/print' do
    @order = Order.includes(:store, { order_items: :assets }).find(params[:id])
    erb :print_order_card, layout: false
  rescue ActiveRecord::RecordNotFound
    status 404
    'Order not found'
  end

  # GET /orders/:id/edit - Form for editing order
  get '/orders/:id/edit' do
    @order = Order.includes(:store, { order_items: :assets }).find(params[:id])
    @stores = Store.where(active: true).ordered
    @products = Product.where(active: true).ordered
    erb :new_order
  rescue ActiveRecord::RecordNotFound
    status 404
    erb :not_found
  end

  # PUT /orders/:id - Update order
  put '/orders/:id' do
    @order = Order.find(params[:id])
    store = Store.find(params[:store_id])
    
    begin
      @order.update(external_order_code: params[:order_code])
      
      # Update items
      if params[:items].present?
        # Track which item IDs are in the update request
        item_ids_in_request = params[:items].map { |ip| ip[:id].to_i }.select { |id| id.positive? }
        
        # Delete items that are NOT in the request (preserve items in request and their assets)
        @order.order_items.where.not(id: item_ids_in_request).destroy_all
        
        params[:items].each_with_index do |item_params, index|
          next if item_params[:sku].blank?
          
          product = Product.find_by(sku: item_params[:sku])
          if product.nil?
            return redirect "/orders/#{@order.id}/edit?error=SKU non trovato: #{item_params[:sku]}"
          end

          quantity = item_params[:quantity].to_i
          
          # If item has an ID, update existing; otherwise create new
          if item_params[:id].present? && item_params[:id].to_i.positive?
            order_item = @order.order_items.find_by(id: item_params[:id].to_i)
            if order_item
              order_item.update(
                sku: item_params[:sku],
                quantity: quantity,
                raw_json: {
                  sku: item_params[:sku],
                  quantity: quantity,
                  product_name: product.name
                }.to_json
              )
            end
          else
            # Create new item (added dynamically in form)
            # Position is: last position + 1
            next_position = @order.order_items.maximum(:position).to_i + 1
            order_item = @order.order_items.build(
              sku: item_params[:sku],
              quantity: quantity,
              position: next_position,
              raw_json: {
                sku: item_params[:sku],
                quantity: quantity,
                product_name: product.name
              }.to_json
            )
            order_item.save!
          end

          # Delete specific asset IDs if provided
          delete_asset_ids = item_params[:delete_asset_ids] || []
          delete_asset_ids = delete_asset_ids.first if delete_asset_ids.is_a?(Array) && delete_asset_ids.first.is_a?(Array) # Handle nested arrays if any
          
          delete_asset_ids.each do |asset_id|
            next if asset_id.blank?
            asset = Asset.find_by(id: asset_id)
            if asset && asset.order_item_id == order_item.id
              full_asset_path = File.join(Dir.pwd, asset.local_path)
              File.delete(full_asset_path) if asset.local_path.present? && File.exist?(full_asset_path)
              asset.destroy
            end
          end

          # Handle multiple file uploads
          files = item_params[:files] || []
          files.each_with_index do |file, file_index|
            next if file.blank? || !file.is_a?(Hash) || file[:filename].blank?
            
            begin
              unless valid_file_extension?(file[:filename])
                return redirect "/orders/#{@order.id}/edit?error=Tipo file non consentito per #{item_params[:sku]}. Solo PNG, JPG, JPEG, PDF"
              end

              store_code = store.code || store.id.to_s
              order_code = params[:order_code]
              sku = item_params[:sku]
              upload_dir = File.join(Dir.pwd, 'storage', store_code, order_code, sku)
              FileUtils.mkdir_p(upload_dir) unless Dir.exist?(upload_dir)
              
              filename = File.basename(file[:filename])
              local_path = "storage/#{store_code}/#{order_code}/#{sku}/#{filename}"
              full_path = File.join(Dir.pwd, local_path)
              
              content = file[:tempfile].read
              File.open(full_path, 'wb') { |f| f.write(content) }
              
              # Handle cut file upload
              if item_params[:cut_file_upload] == 'true'
                asset = order_item.assets.build(
                  original_url: filename,
                  local_path: local_path,
                  asset_type: 'cut'
                )
                asset.save!
                ImageEditService.ensure_original_backup!(asset)
              else
                existing_print_files = order_item.assets.select { |a| a.asset_type&.start_with?('print_file') }.count
                asset_index = existing_print_files + 1
                
                asset = order_item.assets.build(
                  original_url: filename,
                  local_path: local_path,
                  asset_type: "print_file_#{asset_index}"
                )
                asset.save!
                ImageEditService.ensure_original_backup!(asset)
              end
            rescue => e
              warn "File upload error for #{item_params[:sku]}: #{e.message}"
            end
          end
        end
      end

      if @order.order_items.empty?
        return redirect "/orders/#{@order.id}/edit?error=Aggiungere almeno un item"
      end
    rescue => e
      return redirect "/orders/#{@order.id}/edit?error=#{e.message}"
    end
    
    # Redirect only after all updates are successful
    redirect "/orders/#{@order.id}"
  end

  # PATCH /orders/:id/update_notes - Update order notes
  patch '/orders/:id/update_notes' do
    content_type :json
    @order = Order.find(params[:id])
    @order.update(customer_note: params[:customer_note])
    { success: true, message: 'Note salvate' }.to_json
  rescue => e
    status 400
    { success: false, error: e.message }.to_json
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
    @latest_automation_run = @item.automation_runs
                                  .where(parent_run_id: nil)
                                  .order(created_at: :desc)
                                  .first
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
    
    # If print is processing/ripped but no result file yet, show processing bar
    if %w[processing ripped].include?(@item.print_status) && !print_result_asset
      status_label = @item.print_status == 'ripped' ? '🔄 Rippato - In coda stampa...' : '🔄 Elaborando in Switch...'
      html = <<~HTML
        <div style="display: flex; gap: 10px; align-items: center;">
          <div style="flex: 1;">
            <div style="display: flex; align-items: center; gap: 8px;">
              <span style="font-size: 14px; font-weight: bold;">#{status_label}</span>
              <div style="flex: 1; height: 4px; background: #e9ecef; border-radius: 2px; overflow: hidden;">
                <div style="height: 100%; background: linear-gradient(90deg, #6f42c1, #0dcaf0); animation: progress 1.5s infinite; width: 30%;"></div>
              </div>
            </div>
          </div>
          <form action="/orders/#{@order.id}/items/#{@item.id}/confirm_print" method="post" class="d-inline">
            <button type="submit" class="btn btn-success btn-sm">
              ✓ Conferma Stampa
            </button>
          </form>
        </div>
      HTML
    # If file exists (from Switch), show result button and confirm button
    elsif print_result_asset && %w[processing ripped].include?(@item.print_status)
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

  # POST /orders/:order_id/items/:item_id/upload_cut - Upload cut file
  post '/orders/:order_id/items/:item_id/upload_cut' do
    puts "[UPLOAD_CUT] Route called! Order: #{params[:order_id]}, Item: #{params[:item_id]}"
    
    begin
      order = Order.find(params[:order_id])
      item = order.order_items.find(params[:item_id])
      file = params[:file]
      
      valid_cut_extensions = %w[svg pdf dxf ai eps].freeze
      
      if file && file[:filename]
        puts "[UPLOAD_CUT] Processing file: #{file[:filename]}"
        
        ext = File.extname(file[:filename]).downcase.sub(/^\./, '')
        unless valid_cut_extensions.include?(ext)
          puts "[UPLOAD_CUT] Invalid extension: #{ext}"
          return redirect "/orders/#{order.id}/items/#{item.id}?error=invalid_cut_file"
        end
        
        store_code = order.store.code || order.store.id.to_s
        order_code = order.external_order_code
        sku = item.sku
        upload_dir = File.join(Dir.pwd, 'storage', store_code, order_code, sku)
        FileUtils.mkdir_p(upload_dir)
        
        filename = File.basename(file[:filename])
        local_path = "storage/#{store_code}/#{order_code}/#{sku}/#{filename}"
        full_path = File.join(Dir.pwd, local_path)
        
        File.binwrite(full_path, file[:tempfile].read)
        
        # Create new cut asset
        asset = item.assets.create(
          asset_type: 'cut',
          original_url: "file:#{filename}",
          local_path: local_path
        )
        
        puts "[UPLOAD_CUT] Cut asset #{asset.id} created for item #{item.id}"
      end
    rescue => e
      puts "[UPLOAD_CUT] ERROR: #{e.message}"
      puts e.backtrace.take(3)
    end
    
    redirect "/orders/#{order.id}/items/#{item.id}"
  end

  # GET /assets/:id/halftone - Operator controls for DTF halftone processing
  get '/assets/:id/halftone' do
    begin
      @asset = Asset.find(params[:id])
      @item = @asset.order_item
      @order = @item.order
      @png_info = png_print_info(@asset)
      @halftone_presets = HalftonePreset.ordered.map do |preset|
        {
          id: preset.id,
          name: preset.name,
          settings: preset.settings_hash
        }
      end

      unless @asset.downloaded? && File.exist?(@asset.local_path_full)
        return redirect "/orders/#{@order.id}/items/#{@item.id}?error=asset_missing"
      end

      unless File.extname(@asset.local_path_full).downcase == '.png'
        return redirect "/orders/#{@order.id}/items/#{@item.id}?error=halftone_requires_png"
      end

      erb :halftone_form
    rescue ActiveRecord::RecordNotFound
      redirect '/orders?error=asset_not_found'
    end
  end

  # GET /assets/:id/halftone/source - Original source used for repeated halftone edits
  get '/assets/:id/halftone/source' do
    begin
      asset = Asset.find(params[:id])
      source_path = halftone_source_path(asset)

      if source_path && File.exist?(source_path)
        send_file source_path
      else
        status 404
        'source_not_found'
      end
    rescue ActiveRecord::RecordNotFound
      status 404
      'asset_not_found'
    end
  end

  # POST /halftone_presets - Save or update a custom DTF halftone preset
  post '/halftone_presets' do
    content_type :json

    begin
      request.body.rewind
      data = JSON.parse(request.body.read)
      name = data['name'].to_s.strip
      settings = data['settings']

      if name.empty?
        status 422
        return { success: false, error: 'Nome preset obbligatorio' }.to_json
      end

      unless settings.is_a?(Hash)
        status 422
        return { success: false, error: 'Parametri preset non validi' }.to_json
      end

      preset = HalftonePreset.find_or_initialize_by(name: name)
      preset.settings = settings
      preset.save!

      {
        success: true,
        preset: {
          id: preset.id,
          name: preset.name,
          settings: preset.settings_hash
        }
      }.to_json
    rescue JSON::ParserError
      status 400
      { success: false, error: 'JSON non valido' }.to_json
    rescue => e
      status 500
      { success: false, error: e.message }.to_json
    end
  end

  # DELETE /halftone_presets/:id - Delete a custom DTF halftone preset
  delete '/halftone_presets/:id' do
    content_type :json

    begin
      preset = HalftonePreset.find(params[:id])
      preset.destroy
      { success: true }.to_json
    rescue ActiveRecord::RecordNotFound
      status 404
      { success: false, error: 'Preset non trovato' }.to_json
    rescue => e
      status 500
      { success: false, error: e.message }.to_json
    end
  end

  # POST /assets/:id/halftone/preview - Fast preview without creating an asset
  post '/assets/:id/halftone/preview' do
    begin
      asset = Asset.find(params[:id])
      unless asset.downloaded? && File.exist?(asset.local_path_full)
        status 404
        return 'asset_missing'
      end

      unless File.extname(asset.local_path_full).downcase == '.png'
        status 415
        return 'halftone_requires_png'
      end

      source_path = halftone_source_path(asset)
      Dir.mktmpdir('dtf-halftone-preview') do |tmpdir|
        output_path = File.join(tmpdir, "preview_#{asset.id}.png")
        command = halftone_command(source_path, output_path, params, preview: true)
        stdout, stderr, cmd_status = Open3.capture3(*command, chdir: Dir.pwd)

        unless cmd_status.success? && File.exist?(output_path)
          puts "[DTF_HALFTONE_PREVIEW] Error processing asset #{asset.id}: #{stderr}"
          status 500
          return stderr.presence || stdout.presence || 'preview_failed'
        end

        content_type 'image/png'
        return File.binread(output_path)
      end
    rescue ActiveRecord::RecordNotFound
      status 404
      'asset_not_found'
    rescue => e
      puts "[DTF_HALFTONE_PREVIEW] Error: #{e.message}"
      status 500
      'preview_failed'
    end
  end

  # POST /assets/:id/halftone/mask_preview - Grayscale mask before halftone screening
  post '/assets/:id/halftone/mask_preview' do
    begin
      asset = Asset.find(params[:id])
      unless asset.downloaded? && File.exist?(asset.local_path_full)
        status 404
        return 'asset_missing'
      end

      unless File.extname(asset.local_path_full).downcase == '.png'
        status 415
        return 'halftone_requires_png'
      end

      source_path = halftone_source_path(asset)
      Dir.mktmpdir('dtf-halftone-mask-preview') do |tmpdir|
        output_path = File.join(tmpdir, "mask_preview_#{asset.id}.png")
        command = halftone_command(source_path, output_path, params, preview: true)
        command << '--mask-preview'
        stdout, stderr, cmd_status = Open3.capture3(*command, chdir: Dir.pwd)

        unless cmd_status.success? && File.exist?(output_path)
          puts "[DTF_HALFTONE_MASK_PREVIEW] Error processing asset #{asset.id}: #{stderr}"
          status 500
          return stderr.presence || stdout.presence || 'mask_preview_failed'
        end

        content_type 'image/png'
        return File.binread(output_path)
      end
    rescue ActiveRecord::RecordNotFound
      status 404
      'asset_not_found'
    rescue => e
      puts "[DTF_HALFTONE_MASK_PREVIEW] Error: #{e.message}"
      status 500
      'mask_preview_failed'
    end
  end

  # POST /assets/:id/halftone - Replace the operational print file, preserving the original source
  post '/assets/:id/halftone' do
    begin
      asset = Asset.find(params[:id])
      item = asset.order_item
      order = item.order

      unless asset.downloaded? && File.exist?(asset.local_path_full)
        return redirect "/orders/#{order.id}/items/#{item.id}?error=asset_missing"
      end

      unless File.extname(asset.local_path_full).downcase == '.png'
        return redirect "/orders/#{order.id}/items/#{item.id}?error=halftone_requires_png"
      end

      upload = params[:png] || params['png']
      settings_raw = params[:settings] || params['settings']
      settings = begin
        settings_raw.present? ? JSON.parse(settings_raw.to_s) : {}
      rescue JSON::ParserError
        {}
      end

      # Production export uses the authoritative server engine. The browser PNG
      # remains accepted below for legacy clients and older saved jobs.
      if settings['server_render'].to_s == '1'
        operational_path = asset.local_path_full
        source_path = halftone_source_path(asset)
        source_backup_path = ensure_halftone_backup!(asset, source_path)
        tmp_output_path = File.join(File.dirname(operational_path), ".#{File.basename(operational_path, '.*')}_dtf_server_tmp_#{Time.now.strftime('%Y%m%d%H%M%S')}.png")
        # Every Levels adjustment must start from the untouched DTF source;
        # processing an already screened PNG compounds its alpha mask.
        render_source_path = source_backup_path && File.file?(source_backup_path) ? source_backup_path : source_path
        command = halftone_command(render_source_path, tmp_output_path, settings)
        stdout, stderr, cmd_status = Open3.capture3(*command, chdir: Dir.pwd)
        unless cmd_status.success? && File.exist?(tmp_output_path)
          File.delete(tmp_output_path) if File.exist?(tmp_output_path)
          status 500
          return { success: false, error: stderr.presence || 'server_render_failed' }.to_json
        end
        FileUtils.mv(tmp_output_path, operational_path)
        DesignGrouping.propagate_file!(asset, operational_path)
        puts "[DTF_HALFTONE_SERVER] Replaced asset #{asset.id} from source backup #{source_backup_path}: #{stdout}"
        return { success: true, redirect_url: "/orders/#{order.id}/items/#{item.id}?success=halftone_updated" }.to_json
      end

      if upload
        content_type :json
        tempfile = nil
        if upload.respond_to?(:[])
          tempfile = upload[:tempfile] || upload['tempfile']
        elsif upload.respond_to?(:tempfile)
          tempfile = upload.tempfile
        end

        unless tempfile && File.exist?(tempfile.path)
          status 422
          return { success: false, error: 'png_missing' }.to_json
        end

        if File.size(tempfile.path) > 200 * 1024 * 1024
          status 413
          return { success: false, error: 'png_too_large' }.to_json
        end

        tempfile.rewind
        signature = tempfile.read(8)
        tempfile.rewind
        unless signature == "\x89PNG\r\n\x1a\n".b
          status 422
          return { success: false, error: 'invalid_png' }.to_json
        end

        operational_path = asset.local_path_full
        source_path = halftone_source_path(asset)
        source_backup_path = ensure_halftone_backup!(asset, source_path)

        tmp_output_path = File.join(
          File.dirname(operational_path),
          ".#{File.basename(operational_path, '.*')}_dtf_canvas_tmp_#{Time.now.strftime('%Y%m%d%H%M%S')}.png"
        )
        FileUtils.copy(tempfile.path, tmp_output_path)
        FileUtils.mv(tmp_output_path, operational_path)
        DesignGrouping.propagate_file!(asset, operational_path)

        puts "[DTF_HALFTONE_BROWSER] Replaced asset #{asset.id} from canvas export; source backup #{source_backup_path}"
        return {
          success: true,
          redirect_url: "/orders/#{order.id}/items/#{item.id}?success=halftone_updated"
        }.to_json
      end

      operational_path = asset.local_path_full
      source_path = halftone_source_path(asset)
      source_backup_path = ensure_halftone_backup!(asset, source_path)

      tmp_output_path = File.join(File.dirname(operational_path), ".#{File.basename(operational_path, '.*')}_dtf_halftone_tmp_#{Time.now.strftime('%Y%m%d%H%M%S')}.png")
      command = halftone_command(source_path, tmp_output_path, params)

      stdout, stderr, cmd_status = Open3.capture3(*command, chdir: Dir.pwd)
      unless cmd_status.success? && File.exist?(tmp_output_path)
        File.delete(tmp_output_path) if File.exist?(tmp_output_path)
        puts "[DTF_HALFTONE] Error processing asset #{asset.id}: #{stderr}"
        return redirect "/orders/#{order.id}/items/#{item.id}?error=halftone_failed"
      end

      FileUtils.mv(tmp_output_path, operational_path)
      DesignGrouping.propagate_file!(asset, operational_path)

      puts "[DTF_HALFTONE] Replaced asset #{asset.id} from source backup #{source_backup_path}: #{stdout}"
      redirect "/orders/#{order.id}/items/#{item.id}?success=halftone_updated"
    rescue ActiveRecord::RecordNotFound
      redirect '/orders?error=asset_not_found'
    rescue => e
      puts "[DTF_HALFTONE] Error: #{e.message}"
      puts e.backtrace.take(3)
      redirect '/orders?error=halftone_failed'
    end
  end

  # POST /assets/:id/halftone/browser_export - Save the browser-rendered canvas PNG
  post '/assets/:id/halftone/browser_export' do
    content_type :json

    begin
      asset = Asset.find(params[:id])
      item = asset.order_item
      order = item.order

      unless asset.downloaded? && File.exist?(asset.local_path_full)
        status 404
        return { success: false, error: 'asset_missing' }.to_json
      end

      unless File.extname(asset.local_path_full).downcase == '.png'
        status 415
        return { success: false, error: 'halftone_requires_png' }.to_json
      end

      upload = params[:png] || params['png']
      tempfile = nil
      if upload.respond_to?(:[])
        tempfile = upload[:tempfile] || upload['tempfile']
      elsif upload.respond_to?(:tempfile)
        tempfile = upload.tempfile
      end
      unless tempfile && File.exist?(tempfile.path)
        status 422
        return { success: false, error: 'png_missing' }.to_json
      end

      if File.size(tempfile.path) > 200 * 1024 * 1024
        status 413
        return { success: false, error: 'png_too_large' }.to_json
      end

      tempfile.rewind
      signature = tempfile.read(8)
      tempfile.rewind
      unless signature == "\x89PNG\r\n\x1a\n".b
        status 422
        return { success: false, error: 'invalid_png' }.to_json
      end

      operational_path = asset.local_path_full
      source_path = halftone_source_path(asset)
      source_backup_path = ensure_halftone_backup!(asset, source_path)

      tmp_output_path = File.join(
        File.dirname(operational_path),
        ".#{File.basename(operational_path, '.*')}_dtf_canvas_tmp_#{Time.now.strftime('%Y%m%d%H%M%S')}.png"
      )
      FileUtils.copy(tempfile.path, tmp_output_path)
      FileUtils.mv(tmp_output_path, operational_path)
      DesignGrouping.propagate_file!(asset, operational_path)

      puts "[DTF_HALFTONE_BROWSER] Replaced asset #{asset.id} from canvas export; source backup #{source_backup_path}"
      {
        success: true,
        redirect_url: "/orders/#{order.id}/items/#{item.id}?success=halftone_updated"
      }.to_json
    rescue ActiveRecord::RecordNotFound
      status 404
      { success: false, error: 'asset_not_found' }.to_json
    rescue => e
      FileUtils.rm_f(tmp_output_path) if defined?(tmp_output_path) && tmp_output_path && File.exist?(tmp_output_path)
      puts "[DTF_HALFTONE_BROWSER] Error: #{e.message}"
      status 500
      { success: false, error: 'halftone_failed' }.to_json
    end
  end

  # POST /assets/:id/delete - Delete asset file
  post '/assets/:id/delete' do
    begin
      asset = Asset.find(params[:id])
      order_id = params[:order_id]
      item_id = params[:item_id]
      
      # Delete file from disk if it exists
      if asset.local_path.present? && File.exist?(asset.local_path_full)
        dtf_backup_path = halftone_source_backup_path(asset)
        edit_backup_path = ImageEditService.backup_path(asset)
        File.delete(asset.local_path_full)
        puts "[DELETE] ✅ File deleted: #{asset.local_path_full}"
        if dtf_backup_path && File.exist?(dtf_backup_path)
          FileUtils.rm_f(dtf_backup_path)
          puts "[DELETE] ✅ DTF source backup deleted: #{dtf_backup_path}"
        end
        if edit_backup_path && File.exist?(edit_backup_path)
          FileUtils.rm_f(edit_backup_path)
          puts "[DELETE] ✅ Image editor source backup deleted: #{edit_backup_path}"
        end
      end
      
      # Delete asset from database
      asset.destroy
      puts "[DELETE] ✅ Asset #{params[:id]} deleted from database"
      
      # Redirect back to item page if order_id and item_id provided
      if order_id.present? && item_id.present?
        puts "[DELETE] Redirecting to /orders/#{order_id}/items/#{item_id}"
        redirect "/orders/#{order_id}/items/#{item_id}"
      else
        puts "[DELETE] Redirecting to /orders"
        redirect '/orders'
      end
    rescue => e
      puts "[DELETE] ❌ Error deleting asset: #{e.message}"
      puts e.backtrace.take(3)
      redirect '/orders'
    end
  end

  # POST /assets/:id/restore - Restore original image from backup
  post '/assets/:id/restore' do
    begin
      asset = Asset.find(params[:id])
      order_id = params[:order_id]
      item_id = params[:item_id]
      
      original_path = asset.local_path_full
      backup_path = ImageEditService.backup_path(asset)
      dtf_backup_path = halftone_source_backup_path(asset)
      backup_path = dtf_backup_path if !File.exist?(backup_path) && dtf_backup_path && File.exist?(dtf_backup_path)
      
      unless File.exist?(backup_path)
        redirect "/orders/#{order_id}/items/#{item_id}?error=No backup available for this image"
        return
      end
      
      # Restore backup by copying it back to original path
      FileUtils.copy(backup_path, original_path)
      asset.update!(image_edit_data: {}) if asset.respond_to?(:image_edit_data)
      
      puts "[RESTORE] ✅ Image restored from backup: #{original_path}"
      
      # Redirect back to item page
      if order_id.present? && item_id.present?
        redirect "/orders/#{order_id}/items/#{item_id}?success=Image restored to original"
      else
        redirect '/orders'
      end
    rescue => e
      puts "[RESTORE] ❌ Error restoring image: #{e.message}"
      puts e.backtrace.take(3)
      redirect '/orders?error=Failed to restore image'
    end
  end


  # GET /assets/:id/edit-state - Original source and non-destructive editor recipe
  get '/assets/:id/edit-state' do
    content_type :json

    begin
      asset = Asset.find(params[:id])
      source_path = halftone_source_path(asset)
      unless source_path && File.file?(source_path) && File.extname(source_path).downcase == '.png'
        status 422
        return { success: false, error: 'L’editor è disponibile per i file PNG' }.to_json
      end

      source_info = png_path_info(source_path)
      unless source_info
        status 422
        return { success: false, error: 'Impossibile leggere le dimensioni del PNG originale' }.to_json
      end

      {
        success: true,
        source_url: "/assets/#{asset.id}/edit-source?v=#{File.mtime(source_path).to_i}",
        source_width: source_info[:width_px],
        source_height: source_info[:height_px],
        dpi: (source_info[:declared_dpi] || source_info[:target_dpi]).round(3),
        edit_data: asset.image_edit_data.presence || {}
      }.to_json
    rescue ActiveRecord::RecordNotFound
      status 404
      { success: false, error: 'File non trovato' }.to_json
    rescue => e
      puts "[IMAGE_EDITOR] State error: #{e.message}"
      status 500
      { success: false, error: e.message }.to_json
    end
  end

  # GET /assets/:id/edit-source - Immutable source used to reopen the editor
  get '/assets/:id/edit-source' do
    asset = Asset.find(params[:id])
    source_path = ImageEditService.source_path(asset)
    halt 404, 'File originale non disponibile' unless source_path && File.file?(source_path)

    content_type 'image/png'
    send_file source_path, disposition: 'inline'
  end

  # POST /assets/:id/adjust - Save fixed-canvas or cropped PNG and its edit recipe
  post '/assets/:id/adjust' do
    content_type :json
    
    begin
      asset = Asset.find(params[:id])
      
      # Parse JSON body
      request.body.rewind
      data = JSON.parse(request.body.read)
      image_binary = ImageEditService.decode_png_data_url(data['image_data'])
      rendered_dimensions = ImageEditService.png_dimensions(image_binary)
      raise ArgumentError, 'Il PNG prodotto non contiene dimensioni valide' unless rendered_dimensions

      original_path = asset.local_path_full
      raise ArgumentError, 'Il file operativo deve essere un PNG' unless File.extname(original_path).downcase == '.png'

      source_path = ImageEditService.source_path(asset)
      source_dimensions = ImageEditService.png_dimensions(source_path)
      raise ArgumentError, 'Impossibile leggere il PNG originale' unless source_dimensions

      requested_width = ImageEditService.integer(data.dig('recipe', 'output_width'), rendered_dimensions[0])
      requested_height = ImageEditService.integer(data.dig('recipe', 'output_height'), rendered_dimensions[1])
      ImageEditService.validate_dimensions!(requested_width, requested_height, 'di uscita')
      output_dimensions = [requested_width, requested_height]

      if output_dimensions != rendered_dimensions
        image_binary = ImageEditService.resize_png_lanczos(
          image_binary,
          width: requested_width,
          height: requested_height,
          dpi: data.dig('recipe', 'dpi') || 300
        )
      end

      recipe = ImageEditService.normalize_recipe(
        data['recipe'],
        output_dimensions: output_dimensions,
        source_dimensions: source_dimensions
      )
      recipe['render_engine'] = output_dimensions == rendered_dimensions ? 'fabric_canvas' : 'imagemagick_lanczos'
      backup_path = ImageEditService.backup_path(asset)
      unless File.exist?(backup_path)
        FileUtils.copy(source_path, backup_path)
        puts "[ADJUST] Backup created: #{backup_path}"
      end

      Tempfile.create(['image-adjust-', '.png'], File.dirname(original_path)) do |temporary|
        temporary.binmode
        temporary.write(image_binary)
        temporary.flush
        temporary.fsync
        FileUtils.mv(temporary.path, original_path)
      end
      asset.update!(image_edit_data: recipe)

      propagated = []
      if data['apply_to_group'] == true
        propagated = DesignGrouping.propagate_asset!(asset, image_binary, recipe)
      end

      puts "[ADJUST] Image saved in #{recipe['mode']} mode: #{output_dimensions.join('x')} px - #{original_path}"
      puts "[ADJUST] Backup available at: #{backup_path}"

      {
        success: true,
        message: 'Immagine salvata',
        backup_available: true,
        width: output_dimensions[0],
        height: output_dimensions[1],
        mode: recipe['mode'],
        design_group_key: asset.order_item.effective_design_group_key,
        propagated_count: propagated.length
      }.to_json
    rescue ActiveRecord::RecordNotFound
      status 404
      { success: false, error: 'Asset not found' }.to_json
    rescue => e
      puts "[ADJUST] Error: #{e.message}"
      puts e.backtrace.take(3)
      status 500
      { success: false, error: e.message }.to_json
    end
  end

  # DELETE /orders/:id - Delete order
  delete '/orders/:id' do
    order = Order.find(params[:id])

    ActiveRecord::Base.transaction do
      # Restore inventory only if the order is actually deleted. If a
      # dependent record blocks deletion, the whole operation rolls back.
      order.order_items.each do |item|
        product = Product.find_by(sku: item.sku)
        product.inventory.add_stock(item.quantity) if product&.inventory
      end

      order.destroy!
    end
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
    
    # Get all product categories for dropdown
    @product_categories = ProductCategory.where(active: true).ordered
    
    # Get all active print machines for bulk print modal
    @print_machines = PrintMachine.active.ordered
    
    # Get all print flows for bulk preprint modal
    @print_flows = PrintFlow.ordered
    
    # Get all order items from these orders, with their associated order and product
    # EXCLUDE completed items (print_status == 'completed')
    @line_items = []
    in_progress_orders.each do |order|
      order.order_items.each do |item|
        # Skip completed items
        next if item.print_status == 'completed'
        
        product = item.product
        category_name = product&.product_category&.name || 'Non categorizzato'
        
        @line_items << {
          item: item,
          order: order,
          product_name: product&.name || item.sku,
          category_name: category_name,
          category_id: product&.product_category_id,
          sku: item.sku
        }
      end
    end
    
    # Store filter values
    @filter_order_date = params[:order_date]
    @filter_order_code = params[:order_code]
    @filter_store = params[:store_id]
    @filter_category_id = params[:category_id]
    @filter_product_name = params[:product_name]
    @filter_sku = params[:sku]
    @filter_status = params[:status_filter]
    
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
    
    # Filter by category
    if @filter_category_id.present?
      @line_items = @line_items.select { |li| li[:category_id].to_s == @filter_category_id }
    end
    
    # Filter by product name
    if @filter_product_name.present?
      @line_items = @line_items.select { |li| li[:product_name].downcase.include?(@filter_product_name.downcase) }
    end
    
    # Filter by SKU
    if @filter_sku.present?
      @line_items = @line_items.select { |li| li[:sku].downcase.include?(@filter_sku.downcase) }
    end
    
    # Filter by workflow status
    if @filter_status.present? && @filter_status != ''
      case @filter_status
      when 'nuovo'
        @line_items = @line_items.select { |li| li[:item].preprint_status == 'pending' && li[:item].print_status == 'pending' }
      when 'pre-stampa'
        @line_items = @line_items.select { |li| li[:item].preprint_status != 'pending' && li[:item].preprint_status != 'completed' }
      when 'stampa'
        # Include items awaiting print (pending) and items currently printing (processing)
        @line_items = @line_items.select { |li| li[:item].preprint_status == 'completed' && %w[pending processing].include?(li[:item].print_status) }
      when 'rippato'
        @line_items = @line_items.select { |li| li[:item].print_status == 'ripped' }
      end
    end
    
    # Manual pagination (25 per page)
    per_page = 25
    page = (params[:page] || 1).to_i
    @total_line_items = @line_items.length
    @total_pages = (@total_line_items.to_f / per_page).ceil
    @current_page = page
    start_idx = (page - 1) * per_page
    @line_items_paginated = @line_items[start_idx, per_page]
    
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
          inv.product.min_stock_level && inv.quantity_in_stock > 0 && inv.quantity_in_stock < inv.product.min_stock_level
        when 'disponibili'
          inv.product.min_stock_level && inv.quantity_in_stock >= inv.product.min_stock_level
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
    
    # Manual pagination (25 per page)
    per_page = 25
    page = (params[:page] || 1).to_i
    @total_inventory_items = @inventory_items.length
    @inventory_total_pages = (@total_inventory_items.to_f / per_page).ceil
    @inventory_current_page = page
    start_idx = (page - 1) * per_page
    @inventory_items_paginated = @inventory_items[start_idx, per_page]
    
    @search_term = params[:search]
    erb :inventory
  end

  # POST /inventory/:id/add - Add stock
  post '/inventory/:id/add' do
    inventory = Inventory.find(params[:id])
    quantity = params[:quantity].to_i
    
    if quantity > 0
      inventory.add_stock(quantity)
      redirect "/inventory?msg=success&text=Aggiunto%20#{quantity}%20prodotti%23inventory"
    else
      redirect "/inventory?msg=error&text=Quantità%20non%20valida%23inventory"
    end
  rescue => e
    redirect "/inventory?msg=error&text=Errore%20nell'aggiunta%23inventory"
  end

  # POST /inventory/:id/remove - Remove stock
  post '/inventory/:id/remove' do
    inventory = Inventory.find(params[:id])
    quantity = params[:quantity].to_i
    
    if quantity > 0 && inventory.remove_stock(quantity)
      redirect "/inventory?msg=success&text=Rimosso%20#{quantity}%20prodotti%23inventory"
    else
      redirect "/inventory?msg=error&text=Quantità%20insufficiente%20o%20non%20valida%23inventory"
    end
  rescue => e
    redirect "/inventory?msg=error&text=Errore%20nella%20rimozione%23inventory"
  end

  # POST /orders/:order_id/items/:item_id/reset - Reset item workflow
  post '/orders/:order_id/items/:item_id/reset' do
    begin
      order = Order.find(params[:order_id])
      item = order.order_items.find(params[:item_id])
      
      # Remove obsolete outputs without breaking the audit history of internal runs.
      previous_outputs = item.assets.where(asset_type: 'print_output')
      AutomationRun.where(source_asset_id: previous_outputs.select(:id)).update_all(source_asset_id: nil)
      previous_outputs.destroy_all
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
