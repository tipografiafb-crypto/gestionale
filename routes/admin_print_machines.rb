# @feature quality
# @domain web
# Admin routes for managing print machines

class PrintOrchestrator < Sinatra::Base
  # GET /admin/print_machines - List all print machines
  get '/admin/print_machines' do
    @machines = PrintMachine.ordered
    erb :admin_print_machines_list
  end

  # GET /admin/print_machines/new - Form to create new machine
  get '/admin/print_machines/new' do
    @machine = PrintMachine.new
    erb :admin_print_machines_form
  end

  # POST /admin/print_machines - Create new machine
  post '/admin/print_machines' do
    @machine = PrintMachine.new(
      name: params[:name],
      description: params[:description],
      active: params[:active] == 'on'
    )

    if @machine.save
      redirect "/admin/print_machines?msg=success&text=Macchina+creata+con+successo"
    else
      @error_message = @machine.errors.full_messages.join(', ')
      erb :admin_print_machines_form
    end
  end

  # GET /admin/print_machines/:id/edit - Form to edit machine
  get '/admin/print_machines/:id/edit' do
    @machine = PrintMachine.find(params[:id])
    erb :admin_print_machines_form
  end

  # PUT /admin/print_machines/:id - Update machine
  put '/admin/print_machines/:id' do
    @machine = PrintMachine.find(params[:id])

    if @machine.update(
      name: params[:name],
      description: params[:description],
      active: params[:active] == 'on'
    )
      redirect "/admin/print_machines?msg=success&text=Macchina+aggiornata+con+successo"
    else
      @error_message = @machine.errors.full_messages.join(', ')
      erb :admin_print_machines_form
    end
  end

  # DELETE /admin/print_machines/:id - Delete machine
  delete '/admin/print_machines/:id' do
    @machine = PrintMachine.find(params[:id])
    
    if @machine.destroy
      redirect "/admin/print_machines?msg=success&text=Macchina+eliminata"
    else
      redirect "/admin/print_machines?msg=error&text=Errore+eliminazione+macchina"
    end
  end

  # GET /admin/print_machines/:id/link_flows - Link machine to print flows
  get '/admin/print_machines/:id/link_flows' do
    @machine = PrintMachine.find(params[:id])
    @print_flows = PrintFlow.ordered
    @linked_flow_ids = @machine.print_flows.pluck(:id)
    erb :admin_machine_link_flows
  end

  # POST /admin/print_machines/:id/link_flows - Update machine-flow associations
  post '/admin/print_machines/:id/link_flows' do
    @machine = PrintMachine.find(params[:id])
    selected_flow_ids = params[:flow_ids] || []

    # Remove old associations
    @machine.print_flow_machines.destroy_all

    # Create new associations
    selected_flow_ids.each do |flow_id|
      PrintFlowMachine.create(print_flow_id: flow_id, print_machine_id: @machine.id)
    end

    redirect "/admin/print_machines?msg=success&text=Associazioni+aggiornate"
  end
end
