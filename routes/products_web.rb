# @feature orders
# @domain web
# Products management routes - Register and manage SKU to webhook routing

class PrintOrchestrator < Sinatra::Base
  # GET /products - List all products
  get '/products' do
    @products = Product.all.order(created_at: :desc)
    erb :products_list
  end

  # GET /products/new - New product form
  get '/products/new' do
    @product = nil
    @webhooks = SwitchWebhook.active.order(name: :asc)
    erb :product_form
  end

  # POST /products - Create new product
  post '/products' do
    product = Product.new(
      sku: params[:sku].upcase,
      switch_webhook_id: params[:switch_webhook_id],
      notes: params[:notes],
      active: params[:active] == 'true'
    )

    if product.save
      redirect '/products?success=created'
    else
      @product = product
      @webhooks = SwitchWebhook.active.order(name: :asc)
      @error = product.errors.full_messages.join(', ')
      erb :product_form
    end
  end

  # GET /products/:id/edit - Edit product form
  get '/products/:id/edit' do
    @product = Product.find(params[:id])
    @webhooks = SwitchWebhook.active.order(name: :asc)
    erb :product_form
  rescue ActiveRecord::RecordNotFound
    status 404
    erb :not_found
  end

  # PUT /products/:id - Update product
  put '/products/:id' do
    product = Product.find(params[:id])
    product.update(
      sku: params[:sku].upcase,
      switch_webhook_id: params[:switch_webhook_id],
      notes: params[:notes],
      active: params[:active] == 'true'
    )

    if product.save
      redirect '/products?success=updated'
    else
      @product = product
      @webhooks = SwitchWebhook.active.order(name: :asc)
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
