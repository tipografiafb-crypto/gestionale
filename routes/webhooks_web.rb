# @feature switch
# @domain web
# Webhooks management routes - Register and manage Switch webhook endpoints

class PrintOrchestrator < Sinatra::Base
  # GET /webhooks - List all webhooks
  get '/webhooks' do
    all_webhooks = SwitchWebhook.all.order(created_at: :desc)
    
    # Manual pagination
    page = (params[:page] || 1).to_i
    per_page = 25
    @total_pages = (all_webhooks.length.to_f / per_page).ceil
    @current_page = page
    start_idx = (page - 1) * per_page
    @webhooks = all_webhooks[start_idx, per_page]
    
    erb :webhooks_list
  end

  # GET /webhooks/new - New webhook form
  get '/webhooks/new' do
    @webhook = nil
    @stores = Store.all.order(name: :asc)
    erb :webhook_form
  end

  # POST /webhooks - Create new webhook
  post '/webhooks' do
    webhook = SwitchWebhook.new(
      name: params[:name],
      hook_path: params[:hook_path],
      store_id: params[:store_id].presence
    )

    if webhook.save
      redirect '/webhooks?success=created'
    else
      @webhook = webhook
      @stores = Store.all.order(name: :asc)
      @error = webhook.errors.full_messages.join(', ')
      erb :webhook_form
    end
  end

  # POST /webhooks/ - Create new webhook (with trailing slash)
  post '/webhooks/' do
    webhook = SwitchWebhook.new(
      name: params[:name],
      hook_path: params[:hook_path],
      store_id: params[:store_id].presence
    )

    if webhook.save
      redirect '/webhooks?success=created'
    else
      @webhook = webhook
      @stores = Store.all.order(name: :asc)
      @error = webhook.errors.full_messages.join(', ')
      erb :webhook_form
    end
  end

  # GET /webhooks/:id/edit - Edit webhook form
  get '/webhooks/:id/edit' do
    @webhook = SwitchWebhook.find(params[:id])
    @stores = Store.all.order(name: :asc)
    erb :webhook_form
  rescue ActiveRecord::RecordNotFound
    status 404
    erb :not_found
  end

  # PUT /webhooks/:id - Update webhook
  put '/webhooks/:id' do
    webhook = SwitchWebhook.find(params[:id])
    webhook.update(
      name: params[:name],
      hook_path: params[:hook_path],
      store_id: params[:store_id].presence
    )

    if webhook.save
      redirect '/webhooks?success=updated'
    else
      @webhook = webhook
      @stores = Store.all.order(name: :asc)
      @error = webhook.errors.full_messages.join(', ')
      erb :webhook_form
    end
  rescue ActiveRecord::RecordNotFound
    status 404
    erb :not_found
  end

  # DELETE /webhooks/:id - Delete webhook
  delete '/webhooks/:id' do
    SwitchWebhook.destroy(params[:id])
    redirect '/webhooks?success=deleted'
  rescue ActiveRecord::RecordNotFound
    status 404
  end
end
