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
      
      # DEBUG: Log incoming data for troubleshooting
      puts "[IMPORT DEBUG] ===== INCOMING JSON ====="
      puts "[IMPORT DEBUG] #{data.to_json}"
      puts "[IMPORT DEBUG] ===== END JSON ====="
      puts "[IMPORT DEBUG] customer_note value: #{data['customer_note'].inspect}"
      puts "[IMPORT DEBUG] site_name value: #{data['site_name'].inspect}"
      puts "[IMPORT DEBUG] id value: #{data['id'].inspect}"
      puts "[IMPORT DEBUG] line_items count: #{(data['line_items'] || []).count}"
      
      # Map WooCommerce format to internal format
      # Handle both direct API format and WooCommerce JSON format
      if data['site_name'] && !data['store_id']
        # Extract store code from site_name (e.g., "TPH DE" → "TPH_DE")
        data['store_id'] = data['site_name'].upcase.gsub(' ', '_')
      end
      
      if data['line_items'] && !data['items']
        data['items'] = data['line_items']
      end
      
      if (data['id'] || data['number']) && !data['external_order_code']
        data['external_order_code'] = data['id'] || data['number']
      end
      
      puts "[IMPORT DEBUG] After mapping - store_id: #{data['store_id'].inspect}, external_order_code: #{data['external_order_code'].inspect}, customer_note: #{data['customer_note'].inspect}"
      
      # Validate store exists and is active
      store = Store.find_by_code(data['store_id'])
      unless store
        status 422
        return { success: false, error: "Store not found or inactive: #{data['store_id']}" }.to_json
      end
      
      # Validate all products exist
      products_not_found = []
      data['items'].each do |item_data|
        unless Product.exists?(sku: item_data['sku'])
          products_not_found << item_data['sku']
        end
      end
      
      unless products_not_found.empty?
        status 422
        return { success: false, error: "Products not found: #{products_not_found.join(', ')}" }.to_json
      end
      
      # Build lookup maps for print files and screenshots by cart_id
      print_files_map = {}
      screenshots_map = {}
      
      (data['print_files_with_cart_id'] || []).each do |entry|
        print_files_map[entry['cart_id']] = entry['print_files'] || []
      end
      
      (data['screenshots_with_cart_id'] || []).each do |entry|
        screenshots_map[entry['cart_id']] = entry['screenshots'] || []
      end
      
      # Wrap all database operations in a transaction for data integrity
      result = ActiveRecord::Base.transaction do
        # Create order
        order = Order.create!(
          store: store,
          external_order_code: data['external_order_code'],
          customer_note: data['customer_note'],
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
          
          # Deduct from inventory
          product = Product.find_by(sku: item_data['sku'])
          if product && product.inventory
            product.inventory.remove_stock(item_data['quantity'])
          end
          
          # Get cart_id from meta_data for file mapping
          cart_id = extract_cart_id(item_data)
          
          # Create print file assets
          (print_files_map[cart_id] || []).each do |url|
            order_item.assets.create!(
              original_url: url,
              asset_type: 'print'
            )
          end
          
          # Create screenshot assets
          (screenshots_map[cart_id] || []).each do |url|
            order_item.assets.create!(
              original_url: url,
              asset_type: 'screenshot'
            )
          end
          
          # Create assets from legacy image_urls if present
          (item_data['image_urls'] || []).each_with_index do |url, index|
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

  # POST /api/v1/bulk_preprint_item - Send single item to preprint (for bulk operations)
  # Sets preprint_status to 'processing'
  post '/api/v1/bulk_preprint_item' do
    content_type :json
    
    begin
      data = JSON.parse(request.body.read)
      
      order_id = data['order_id']
      item_id = data['item_id']
      print_flow_id = data['print_flow_id']
      
      unless order_id && item_id && print_flow_id
        return { success: false, error: 'Parametri mancanti (order_id, item_id, print_flow_id)' }.to_json
      end
      
      order = Order.find_by(id: order_id)
      unless order
        return { success: false, error: 'Ordine non trovato' }.to_json
      end
      
      item = order.order_items.find_by(id: item_id)
      unless item
        return { success: false, error: 'Item non trovato' }.to_json
      end
      
      print_flow = PrintFlow.find_by(id: print_flow_id)
      unless print_flow
        return { success: false, error: 'Flusso di stampa non trovato' }.to_json
      end
      
      # Check if item is ready for preprint (pending status)
      unless item.preprint_status == 'pending'
        return { success: false, error: "Item non in attesa di pre-stampa (stato: #{item.preprint_status})" }.to_json
      end
      
      # Check if print flow has preprint webhook
      unless print_flow&.preprint_webhook
        return { success: false, error: 'Flusso di stampa non configurato per pre-stampa' }.to_json
      end
      
      # Get all print files (same as single item flow)
      print_assets = item.switch_print_assets
      unless print_assets.any?
        return { success: false, error: 'File grafico non trovato' }.to_json
      end
      
      product = item.product
      server_url = ENV['SERVER_BASE_URL'] || 'http://localhost:5000'
      
      # Send each print asset to preprint (same as single item flow!)
      errors = []
      successful_assets = []
      
      print_assets.each do |print_asset|
        # Build Switch payload for preprint - IDENTICAL TO SINGLE ITEM!
        job_data = {
          id_riga: item.item_number,
          codice_ordine: order.external_order_code,
          product: "#{product&.sku} - #{product&.name}",
          operation_id: 1,  # 1=prepress, 2=stampa, 3=etichetta
          job_operation_id: item.id.to_s,
          url: "#{server_url}/api/assets/#{print_asset.id}/download",
          widegest_url: "#{server_url}/api/v1/reports_create",
          filename: item.switch_filename_for_asset(print_asset) || "#{order.external_order_code.downcase}-#{item.id}.png",
          quantita: item.quantity,
          materiale: product&.notes || 'N/A',
          campi_custom: {},
          opzioni_stampa: {},
          campi_webhook: { percentuale: '0' }
        }
        
        puts "[BULK_PREPRINT] Sending item #{item.id}, asset #{print_asset.id} to Switch: #{job_data.inspect}"
        
        result = SwitchClient.send_to_switch(
          webhook_path: print_flow.preprint_webhook&.hook_path,
          job_data: job_data
        )
        
        if result[:success]
          successful_assets << print_asset.id
        else
          errors << result[:error]
        end
      end
      
      if errors.any?
        { success: false, error: "Alcuni asset hanno generato errori: #{errors.join(', ')}" }.to_json
      else
        # Update item status to 'processing' and store print flow
        item.update(preprint_status: 'processing', preprint_print_flow_id: print_flow.id, preprint_job_id: successful_assets.join(','))
        
        # Mark order as processing if it was new
        order.update(status: 'processing') if order.status == 'new'
        
        { success: true, message: "#{successful_assets.length} asset(s) inviato(i) a pre-stampa" }.to_json
      end
    rescue JSON::ParserError
      status 400
      { success: false, error: 'JSON non valido' }.to_json
    rescue => e
      puts "[BULK_PREPRINT_ERROR] #{e.class}: #{e.message}"
      status 500
      { success: false, error: e.message }.to_json
    end
  end

  # POST /api/v1/bulk_print_item - Send single item to print (for bulk operations)
  # Sets status to 'ripped' instead of 'processing'
  post '/api/v1/bulk_print_item' do
    content_type :json
    
    begin
      data = JSON.parse(request.body.read)
      
      order_id = data['order_id']
      item_id = data['item_id']
      print_machine_id = data['print_machine_id']
      
      unless order_id && item_id && print_machine_id
        return { success: false, error: 'Parametri mancanti (order_id, item_id, print_machine_id)' }.to_json
      end
      
      order = Order.find_by(id: order_id)
      unless order
        return { success: false, error: 'Ordine non trovato' }.to_json
      end
      
      item = order.order_items.find_by(id: item_id)
      unless item
        return { success: false, error: 'Item non trovato' }.to_json
      end
      
      print_machine = PrintMachine.find_by(id: print_machine_id)
      unless print_machine
        return { success: false, error: 'Macchina di stampa non trovata' }.to_json
      end
      
      # Check if item is ready for print (preprint completed)
      unless item.preprint_status == 'completed'
        return { success: false, error: 'Pre-stampa non completata per questo item' }.to_json
      end
      
      # Check if item is in pending print status
      unless item.print_status == 'pending'
        return { success: false, error: "Item non in attesa di stampa (stato: #{item.print_status})" }.to_json
      end
      
      # Get print flow and print webhook
      print_flow = item.print_flow
      unless print_flow&.print_webhook
        return { success: false, error: 'Flusso di stampa non configurato' }.to_json
      end
      
      # Get the preprint output PDF (print_output asset)
      print_output_asset = item.assets.where(asset_type: 'print_output').first
      unless print_output_asset
        return { success: false, error: 'File preprint non trovato' }.to_json
      end
      
      product = item.product
      server_url = ENV['SERVER_BASE_URL'] || 'http://localhost:5000'
      
      # Build Switch payload
      job_data = {
        id_riga: item.item_number,
        codice_ordine: order.external_order_code,
        product: "#{product&.sku} - #{product&.name}",
        operation_id: 2,  # 2=stampa
        job_operation_id: item.id.to_s,
        url: "#{server_url}/api/assets/#{print_output_asset.id}/download",
        widegest_url: "#{server_url}/api/v1/reports_create",
        filename: print_output_asset.original_url || "#{order.external_order_code.downcase}-#{item.id}-print.pdf",
        nome_macchina: print_machine.name,
        campi_webhook: item.campi_webhook || {}
      }
      
      puts "[BULK_PRINT] Sending item #{item.id} to Switch: #{job_data.inspect}"
      
      result = SwitchClient.send_to_switch(
        webhook_path: print_flow.print_webhook&.hook_path,
        job_data: job_data
      )
      
      if result[:success]
        # Update item status to 'ripped' and store print machine
        item.update(print_status: 'ripped', print_machine_id: print_machine.id)
        
        # Mark order as processing if it was new
        order.update(status: 'processing') if order.status == 'new'
        
        { success: true, message: 'Item inviato a stampa' }.to_json
      else
        { success: false, error: result[:error] || 'Errore invio a Switch' }.to_json
      end
    rescue JSON::ParserError
      status 400
      { success: false, error: 'JSON non valido' }.to_json
    rescue => e
      puts "[BULK_PRINT_ERROR] #{e.class}: #{e.message}"
      status 500
      { success: false, error: e.message }.to_json
    end
  end

  private

  def extract_cart_id(item_data)
    # Try to extract cart_id from various metadata locations
    if item_data['meta_data']&.is_a?(Hash)
      # Check Lumise data
      if item_data['meta_data']['lumise_data']&.is_a?(Hash)
        return item_data['meta_data']['lumise_data']['cart_id']
      end
      
      # Check AI customization data
      if item_data['meta_data']['_wc_ai_customization']&.is_a?(Hash)
        return item_data['meta_data']['_wc_ai_customization']['artwork_id']
      end
    end
    
    nil
  end

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
