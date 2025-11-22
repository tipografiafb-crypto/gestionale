# @feature orders
# @domain web
# Print Flows management routes - Manage two-step print workflows

class PrintOrchestrator < Sinatra::Base
  # GET /print_flows - List all print flows
  get '/print_flows' do
    @flows = PrintFlow.all.order(created_at: :desc)
    erb :print_flows_list
  end

  # GET /print_flows/new - New print flow form
  get '/print_flows/new' do
    @flow = nil
    @webhooks = SwitchWebhook.active.order(name: :asc)
    erb :print_flow_form
  end

  # POST /print_flows - Create new print flow
  post '/print_flows' do
    flow = PrintFlow.new(
      name: params[:name],
      preprint_webhook_id: params[:preprint_webhook_id],
      print_webhook_id: params[:print_webhook_id],
      label_webhook_id: params[:label_webhook_id],
      notes: params[:notes],
      active: params[:active] == 'true'
    )

    if flow.save
      redirect '/print_flows?success=created'
    else
      @flow = flow
      @webhooks = SwitchWebhook.active.order(name: :asc)
      @error = flow.errors.full_messages.join(', ')
      erb :print_flow_form
    end
  end

  # GET /print_flows/:id/edit - Edit print flow form
  get '/print_flows/:id/edit' do
    @flow = PrintFlow.find(params[:id])
    @webhooks = SwitchWebhook.active.order(name: :asc)
    erb :print_flow_form
  rescue ActiveRecord::RecordNotFound
    status 404
    erb :not_found
  end

  # PUT /print_flows/:id - Update print flow
  put '/print_flows/:id' do
    flow = PrintFlow.find(params[:id])
    flow.update(
      name: params[:name],
      preprint_webhook_id: params[:preprint_webhook_id],
      print_webhook_id: params[:print_webhook_id],
      label_webhook_id: params[:label_webhook_id],
      notes: params[:notes],
      active: params[:active] == 'true'
    )

    if flow.save
      redirect '/print_flows?success=updated'
    else
      @flow = flow
      @error = flow.errors.full_messages.join(', ')
      erb :print_flow_form
    end
  rescue ActiveRecord::RecordNotFound
    status 404
    erb :not_found
  end

  # DELETE /print_flows/:id - Delete print flow
  delete '/print_flows/:id' do
    PrintFlow.destroy(params[:id])
    redirect '/print_flows?success=deleted'
  rescue ActiveRecord::RecordNotFound
    status 404
  end
end
