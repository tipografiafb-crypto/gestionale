# @feature orders
# @domain web
# Stores management routes - Configure authorized e-commerce stores

class PrintOrchestrator < Sinatra::Base
  # GET /stores - List all stores
  get '/stores' do
    all_stores = Store.order(code: :asc)
    
    # Manual pagination
    page = (params[:page] || 1).to_i
    per_page = 25
    @total_pages = (all_stores.length.to_f / per_page).ceil
    @current_page = page
    start_idx = (page - 1) * per_page
    @stores = all_stores[start_idx, per_page]
    
    erb :stores_list
  end

  # GET /stores/new - New store form
  get '/stores/new' do
    @store = nil
    erb :store_form
  end

  # POST /stores - Create new store
  post '/stores' do
    store = Store.new(
      code: params[:code].upcase.strip,
      name: params[:name].strip,
      active: params[:active] == 'true'
    )

    if store.save
      redirect '/stores?success=created'
    else
      @store = store
      @error = store.errors.full_messages.join(', ')
      erb :store_form
    end
  end

  # GET /stores/:id/edit - Edit store form
  get '/stores/:id/edit' do
    @store = Store.find(params[:id])
    erb :store_form
  rescue ActiveRecord::RecordNotFound
    status 404
    erb :not_found
  end

  # PUT /stores/:id - Update store
  put '/stores/:id' do
    store = Store.find(params[:id])
    store.update(
      code: params[:code].upcase.strip,
      name: params[:name].strip,
      active: params[:active] == 'true'
    )

    if store.save
      redirect '/stores?success=updated'
    else
      @store = store
      @error = store.errors.full_messages.join(', ')
      erb :store_form
    end
  rescue ActiveRecord::RecordNotFound
    status 404
    erb :not_found
  end

  # DELETE /stores/:id - Delete store
  delete '/stores/:id' do
    store = Store.find(params[:id])
    if store.orders.any?
      redirect '/stores?msg=error&text=Non+puoi+eliminare+un+negozio+con+ordini'
    else
      Store.destroy(params[:id])
      redirect '/stores?success=deleted'
    end
  rescue ActiveRecord::RecordNotFound
    status 404
  end
end
