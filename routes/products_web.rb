# @feature orders
# @domain web
# Products management routes - Register and manage SKU to webhook routing

class PrintOrchestrator < Sinatra::Base
  # GET /products - List all products
  get '/products' do
    @products = Product.all.order(created_at: :desc)
    @categories = ProductCategory.ordered
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
end
