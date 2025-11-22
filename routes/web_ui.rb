# @feature ui
# @domain web
# Web UI routes - HTML interface for operators
require 'json'

class PrintOrchestrator < Sinatra::Base
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

  # GET /orders/:id - Order detail
  get '/orders/:id' do
    @order = Order.includes(:store, { order_items: :assets }, :switch_job).find(params[:id])
    erb :order_detail
  rescue ActiveRecord::RecordNotFound
    status 404
    erb :not_found
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

  # DELETE /orders/:id - Delete order
  delete '/orders/:id' do
    order = Order.find(params[:id])
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
end
