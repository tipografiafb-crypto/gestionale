# @feature orders
# @domain web
# Print Flows management routes - Manage two-step print workflows

class PrintOrchestrator < Sinatra::Base
  # GET /print_flows - List all print flows
  get '/print_flows' do
    @flows = PrintFlow.includes(event_routes: :automation_flow).order(created_at: :desc)
    erb :print_flows_list
  end

  # GET /print_flows/new - New print flow form
  get '/print_flows/new' do
    @flow = nil
    @webhooks = SwitchWebhook.all.order(name: :asc)
    @automation_flows = AutomationFlow.includes(:active_version).ordered
    @machines = PrintMachine.ordered
    erb :print_flow_form
  end

  # POST /print_flows - Create new print flow
  post '/print_flows' do
    flow = PrintFlow.new(
      name: params[:name],
      preprint_executor: params[:preprint_executor].presence || 'webhook',
      preprint_webhook_id: params[:preprint_webhook_id],
      preprint_automation_flow_id: params[:preprint_automation_flow_id],
      print_executor: params[:print_executor].presence || 'webhook',
      print_webhook_id: params[:print_webhook_id],
      print_automation_flow_id: params[:print_automation_flow_id],
      label_executor: params[:label_executor].presence || 'none',
      label_webhook_id: params[:label_webhook_id],
      label_automation_flow_id: params[:label_automation_flow_id],
      notes: params[:notes],
      azione_photoshop_enabled: params[:azione_photoshop_enabled] == '1',
      azione_photoshop_options: params[:azione_photoshop_options],
      default_azione_photoshop: params[:default_azione_photoshop]
    )

    if save_print_flow_with_events(flow)
      redirect '/print_flows?success=created'
    else
      @flow = flow
      @webhooks = SwitchWebhook.all.order(name: :asc)
      @automation_flows = AutomationFlow.includes(:active_version).ordered
      @machines = PrintMachine.ordered
      @error = flow.errors.full_messages.join(', ')
      erb :print_flow_form
    end
  end

  # GET /print_flows/:id/edit - Edit print flow form
  get '/print_flows/:id/edit' do
    @flow = PrintFlow.find(params[:id])
    @webhooks = SwitchWebhook.all.order(name: :asc)
    @automation_flows = AutomationFlow.includes(:active_version).ordered
    @machines = PrintMachine.ordered
    erb :print_flow_form
  rescue ActiveRecord::RecordNotFound
    status 404
    erb :not_found
  end

  # PUT /print_flows/:id - Update print flow
  put '/print_flows/:id' do
    flow = PrintFlow.find(params[:id])
    flow.assign_attributes(
      name: params[:name],
      preprint_executor: params[:preprint_executor].presence || 'webhook',
      preprint_webhook_id: params[:preprint_webhook_id],
      preprint_automation_flow_id: params[:preprint_automation_flow_id],
      print_executor: params[:print_executor].presence || 'webhook',
      print_webhook_id: params[:print_webhook_id],
      print_automation_flow_id: params[:print_automation_flow_id],
      label_executor: params[:label_executor].presence || 'none',
      label_webhook_id: params[:label_webhook_id],
      label_automation_flow_id: params[:label_automation_flow_id],
      notes: params[:notes],
      azione_photoshop_enabled: params[:azione_photoshop_enabled] == '1',
      azione_photoshop_options: params[:azione_photoshop_options],
      default_azione_photoshop: params[:default_azione_photoshop]
    )

    if save_print_flow_with_events(flow)
      # Update machine associations
      flow.print_flow_machines.destroy_all
      machine_ids = params[:machine_ids] || []
      machine_ids.each do |machine_id|
        PrintFlowMachine.create(print_flow_id: flow.id, print_machine_id: machine_id)
      end
      
      redirect '/print_flows?success=updated'
    else
      @flow = flow
      @machines = PrintMachine.ordered
      @webhooks = SwitchWebhook.all.order(name: :asc)
      @automation_flows = AutomationFlow.includes(:active_version).ordered
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

  private

  def save_print_flow_with_events(flow)
    PrintFlow.transaction do
      flow.save!
      sync_print_flow_events!(flow)
    end
    true
  rescue ActiveRecord::RecordInvalid => e
    e.record.errors.each { |error| flow.errors.add(:base, error.full_message) } unless e.record == flow
    false
  end

  def sync_print_flow_events!(flow)
    keys = Array(params[:custom_event_keys])
    labels = Array(params[:custom_event_labels])
    automation_ids = Array(params[:custom_event_automation_flow_ids])
    route_ids = Array(params[:custom_event_route_ids])
    retained_ids = []

    keys.each_index do |index|
      event_key = keys[index].to_s.strip
      next if event_key.empty? && automation_ids[index].to_s.empty?

      route = flow.event_routes.find_by(id: route_ids[index].presence) || flow.event_routes.build
      route.assign_attributes(
        event_key: event_key,
        label: labels[index].to_s.strip.presence,
        automation_flow_id: automation_ids[index],
        active: true
      )
      route.save!
      retained_ids << route.id
    end

    flow.event_routes.where.not(id: retained_ids).destroy_all
  end
end
