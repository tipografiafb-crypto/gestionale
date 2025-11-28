# @feature orders
# @domain web
# Products management routes - Register and manage SKU to webhook routing
require 'csv'

class PrintOrchestrator < Sinatra::Base
  # GET /products/import - CSV import form
  get '/products/import' do
    erb :products_import
  end

  # POST /products/import - Process CSV upload
  post '/products/import' do
    unless params[:csv_file] && params[:csv_file][:tempfile]
      @error = "Nessun file selezionato"
      return erb :products_import
    end

    file = params[:csv_file][:tempfile]
    results = { successful: 0, skipped: 0, errors: 0 }
    error_details = []

    begin
      csv_content = file.read.force_encoding('utf-8')
      rows = CSV.parse(csv_content, headers: true)

      rows.each_with_index do |row, index|
        line_num = index + 2  # +2 because header is line 1, data starts at 2

        begin
          sku = row['sku']&.strip&.upcase
          name = row['name']&.strip
          notes = row['notes']&.strip
          category_name = row['category_name']&.strip
          active = row['active']&.strip&.downcase != 'false'
          print_flow_names = row['print_flow_names']&.strip
          default_print_flow_name = row['default_print_flow_name']&.strip

          # Validate required fields
          unless sku.present?
            error_details << "Riga #{line_num}: SKU mancante"
            results[:errors] += 1
            next
          end

          unless name.present?
            error_details << "Riga #{line_num} (#{sku}): Nome mancante"
            results[:errors] += 1
            next
          end

          # Find category if provided
          category = nil
          if category_name.present?
            category = ProductCategory.find_by(name: category_name)
            unless category
              error_details << "Riga #{line_num} (#{sku}): Categoria '#{category_name}' non trovata"
            end
          end

          # Find print flows if provided
          print_flows = []
          default_print_flow = nil
          
          if print_flow_names.present?
            flow_names_list = print_flow_names.split('|').map(&:strip)
            flow_names_list.each do |flow_name|
              flow = PrintFlow.find_by(name: flow_name)
              if flow
                print_flows << flow
              else
                error_details << "Riga #{line_num} (#{sku}): Flusso di stampa '#{flow_name}' non trovato"
              end
            end
            
            # Find default print flow if specified
            if default_print_flow_name.present?
              default_print_flow = PrintFlow.find_by(name: default_print_flow_name)
              unless default_print_flow
                error_details << "Riga #{line_num} (#{sku}): Flusso di stampa default '#{default_print_flow_name}' non trovato"
              end
            elsif print_flows.any?
              # Use first flow as default if not specified
              default_print_flow = print_flows.first
            end
          end

          # Find existing product or create new
          product = Product.find_by(sku: sku) || Product.new(sku: sku)
          
          # Update product attributes
          product.assign_attributes(
            name: name,
            notes: notes,
            product_category_id: category&.id,
            active: active,
            default_print_flow_id: default_print_flow&.id
          )

          if product.save
            # Update print flows association (remove old ones first)
            product.product_print_flows.destroy_all
            # Associate new print flows if provided
            if print_flows.any?
              print_flows.each do |flow|
                ProductPrintFlow.create(product_id: product.id, print_flow_id: flow.id)
              end
            end
            results[:successful] += 1
          else
            error_details << "Riga #{line_num} (#{sku}): #{product.errors.full_messages.join(', ')}"
            results[:errors] += 1
          end

        rescue => e
          error_details << "Riga #{line_num}: #{e.message}"
          results[:errors] += 1
        end
      end

      @results = results
      @error_details = error_details

    rescue CSV::ParserError => e
      @error = "Errore nel parsing del CSV: #{e.message}"
    rescue => e
      @error = "Errore durante l'importazione: #{e.message}"
    end

    erb :products_import
  end

  # GET /products/import/template - Download CSV template
  get '/products/import/template' do
    content_type 'text/csv'
    attachment 'prodotti_template.csv'

    csv_data = "sku,name,notes,category_name,active,print_flow_names,default_print_flow_name\n"
    csv_data += "TPH001-71,Plettri Flow,Plettri piccoli,Plettri,true,Flusso A|Flusso B,Flusso A\n"
    csv_data += "TPH205-88,Maglietta,T-shirt cotone,Abbigliamento,true,Flusso C,Flusso C\n"
    csv_data += "TPH500,Tazza,Stampa ceramica,Tazze,true,,\n"

    csv_data
  end

  # GET /products/export - Export all products to CSV
  get '/products/export' do
    content_type 'text/csv'
    attachment 'prodotti_export.csv'

    csv_string = CSV.generate do |csv|
      csv << ['sku', 'name', 'notes', 'category_name', 'active', 'print_flow_names', 'default_print_flow_name']
      
      Product.all.order(:sku).each do |product|
        category_name = product.product_category&.name
        
        # Get associated print flows
        flows = product.print_flows.order(:name)
        flow_names = flows.map(&:name).join('|')
        default_flow_name = product.default_print_flow&.name
        
        csv << [
          product.sku,
          product.name,
          product.notes || '',
          category_name || '',
          product.active ? 'true' : 'false',
          flow_names,
          default_flow_name || ''
        ]
      end
    end
    
    csv_string
  end

  # GET /products - List all products with search filtering
  get '/products' do
    @products = Product.all
    
    # Filter by search term (SKU, name, or category)
    if params[:search].present?
      search_term = params[:search].downcase
      @products = @products.select do |product|
        product.sku.downcase.include?(search_term) ||
        product.name.downcase.include?(search_term) ||
        (product.product_category && product.product_category.name.downcase.include?(search_term))
      end
    end
    
    @products = @products.sort_by { |p| p.created_at }.reverse
    @categories = ProductCategory.ordered
    @search_term = params[:search]
    erb :products_list
  end

  # GET /products/new - New product form
  get '/products/new' do
    @product = nil
    @flows = PrintFlow.all.order(name: :asc)
    @categories = ProductCategory.all.ordered
    erb :product_form
  end

  # POST /products - Create new product
  post '/products' do
    flow_ids = (params[:print_flow_ids] || []).reject(&:empty?)
    default_flow_id = params[:default_print_flow_id].presence
    
    # If no default flow selected, use the first selected flow
    default_flow_id ||= flow_ids.first if flow_ids.present?
    
    product = Product.new(
      sku: params[:sku].upcase,
      name: params[:name],
      default_print_flow_id: default_flow_id,
      product_category_id: params[:product_category_id].presence,
      notes: params[:notes],
      min_stock_level: params[:min_stock_level].to_i.presence
    )

    if product.save
      if flow_ids.present?
        flow_ids.each do |flow_id|
          ProductPrintFlow.create(product_id: product.id, print_flow_id: flow_id)
        end
      end
      redirect '/products?success=created'
    else
      @product = product
      @flows = PrintFlow.all.order(name: :asc)
      @categories = ProductCategory.all.ordered
      @error = product.errors.full_messages.join(', ')
      erb :product_form
    end
  end

  # GET /products/:id/edit - Edit product form
  get '/products/:id/edit' do
    @product = Product.find(params[:id])
    @flows = PrintFlow.all.order(name: :asc)
    @categories = ProductCategory.all.ordered
    erb :product_form
  rescue ActiveRecord::RecordNotFound
    status 404
    erb :not_found
  end

  # PUT /products/:id - Update product
  put '/products/:id' do
    product = Product.find(params[:id])
    flow_ids = (params[:print_flow_ids] || []).reject(&:empty?)
    default_flow_id = params[:default_print_flow_id].presence
    
    # If no default flow selected, use the first selected flow
    default_flow_id ||= flow_ids.first if flow_ids.present?
    
    product.update(
      sku: params[:sku].upcase,
      name: params[:name],
      default_print_flow_id: default_flow_id,
      product_category_id: params[:product_category_id].presence,
      notes: params[:notes],
      min_stock_level: params[:min_stock_level].to_i.presence
    )

    if product.save
      # Update print flow associations
      product.product_print_flows.destroy_all
      if flow_ids.present?
        flow_ids.each do |flow_id|
          ProductPrintFlow.create(product_id: product.id, print_flow_id: flow_id)
        end
      end
      redirect '/products?success=updated'
    else
      @product = product
      @flows = PrintFlow.all.order(name: :asc)
      @categories = ProductCategory.all.ordered
      @error = product.errors.full_messages.join(', ')
      erb :product_form
    end
  rescue ActiveRecord::RecordNotFound
    status 404
    erb :not_found
  end

  # DELETE /products/:id - Delete product
  delete '/products/:id' do
    Product.destroy(params[:id])
    redirect '/products?success=deleted'
  rescue ActiveRecord::RecordNotFound
    status 404
  end

  # POST /products/:id/duplicate - Duplicate product with all configurations
  post '/products/:id/duplicate' do
    content_type :json
    
    begin
      product = Product.find(params[:id])
      duplicated = product.duplicate
      
      if duplicated
        { success: true, id: duplicated.id, sku: duplicated.sku }.to_json
      else
        status 400
        { success: false, error: 'Duplicazione fallita' }.to_json
      end
    rescue ActiveRecord::RecordNotFound
      status 404
      { success: false, error: 'Prodotto non trovato' }.to_json
    rescue => e
      status 500
      { success: false, error: e.message }.to_json
    end
  end
end
