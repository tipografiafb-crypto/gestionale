# @feature ui
# @domain web
# Web UI routes - HTML interface for operators
require 'json'

class PrintOrchestrator < Sinatra::Base
  # GET / - Redirect to orders list
  get '/' do
    redirect '/orders'
  end

  # GET /orders - List all orders
  get '/orders' do
    @orders = Order.includes(:store, :switch_job).recent.limit(100)
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
end
