# @feature orders
# @domain web
# Products management routes - Register and manage SKU to webhook routing

class PrintOrchestrator < Sinatra::Base
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
    @flows = PrintFlow.active.order(name: :asc)
    @categories = ProductCategory.active.ordered
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
      min_stock_level: params[:min_stock_level].to_i,
      active: params[:active] == 'true'
    )

    if product.save
      product.print_flow_ids = flow_ids
      redirect '/products?success=created'
    else
      @product = product
      @flows = PrintFlow.active.order(name: :asc)
      @categories = ProductCategory.active.ordered
      @error = product.errors.full_messages.join(', ')
      erb :product_form
    end
  end

  # GET /products/:id/edit - Edit product form
  get '/products/:id/edit' do
    @product = Product.find(params[:id])
    @flows = PrintFlow.active.order(name: :asc)
    @categories = ProductCategory.active.ordered
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
      min_stock_level: params[:min_stock_level].to_i,
      active: params[:active] == 'true'
    )

    if product.save
      product.print_flow_ids = flow_ids
      redirect '/products?success=updated'
    else
      @product = product
      @flows = PrintFlow.active.order(name: :asc)
      @categories = ProductCategory.active.ordered
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
