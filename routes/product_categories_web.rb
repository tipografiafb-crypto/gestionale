# @feature orders
# @domain web
# Product Categories management routes

class PrintOrchestrator < Sinatra::Base
  # GET /product_categories - List all categories
  get '/product_categories' do
    @categories = ProductCategory.ordered
    erb :product_categories_list
  end

  # GET /product_categories/new - New category form
  get '/product_categories/new' do
    @category = nil
    erb :product_category_form
  end

  # POST /product_categories - Create new category
  post '/product_categories' do
    category = ProductCategory.new(
      name: params[:name],
      description: params[:description],
      active: params[:active] == 'true'
    )

    if category.save
      redirect '/product_categories?success=created'
    else
      @category = category
      @error = category.errors.full_messages.join(', ')
      erb :product_category_form
    end
  end

  # GET /product_categories/:id/edit - Edit category form
  get '/product_categories/:id/edit' do
    @category = ProductCategory.find(params[:id])
    erb :product_category_form
  rescue ActiveRecord::RecordNotFound
    status 404
    erb :not_found
  end

  # PUT /product_categories/:id - Update category
  put '/product_categories/:id' do
    category = ProductCategory.find(params[:id])
    category.update(
      name: params[:name],
      description: params[:description],
      active: params[:active] == 'true'
    )

    if category.save
      redirect '/product_categories?success=updated'
    else
      @category = category
      @error = category.errors.full_messages.join(', ')
      erb :product_category_form
    end
  rescue ActiveRecord::RecordNotFound
    status 404
    erb :not_found
  end

  # DELETE /product_categories/:id - Delete category
  delete '/product_categories/:id' do
    ProductCategory.destroy(params[:id])
    redirect '/product_categories?success=deleted'
  rescue ActiveRecord::RecordNotFound
    status 404
  end
end
