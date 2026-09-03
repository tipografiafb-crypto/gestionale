# @feature orders
# @domain web
# Order Items Switch integration routes - Two-phase workflow (preprint → print)

class PrintOrchestrator < Sinatra::Base
  # POST /orders/:order_id/items/:item_id/send_preprint - Send item to preprint phase
  post '/orders/:order_id/items/:item_id/send_preprint' do
    order = Order.find(params[:order_id])
    item = order.order_items.find(params[:item_id])
    print_flow_id = params[:print_flow_id] || item.product&.default_print_flow_id
    print_flow = PrintFlow.find_by(id: print_flow_id)
    unless print_flow
      redirect "/orders/#{order.id}/items/#{item.id}?msg=error&text=Flusso+di+stampa+non+trovato"
    end

    azione_photoshop = params[:azione_photoshop]&.strip
    requested_quantity = params[:preprint_quantity].to_s.strip
    quantity_override = nil
    if requested_quantity.present? && item.product&.allow_preprint_quantity_override
      quantity_override = Integer(requested_quantity, 10) rescue nil
      if quantity_override.nil? || quantity_override < 1
        redirect "/orders/#{order.id}/items/#{item.id}?msg=error&text=Quantità+prestampa+non+valida"
      end
    end

    result = DesignGroupWorkflow.new(item).send_preprint!(
      print_flow: print_flow,
      percentuale: params[:percentuale],
      azione_photoshop: azione_photoshop,
      quantity_override: quantity_override
    )
    message = "#{result[:rows]} righe collegate inviate a pre-stampa (#{result[:jobs]} lavorazioni)"
    redirect "/orders/#{order.id}/items/#{item.id}?msg=success&text=#{URI.encode_www_form_component(message)}"
  rescue DesignGroupWorkflow::Error => e
    redirect "/orders/#{order.id}/items/#{item.id}?msg=error&text=#{URI.encode_www_form_component(e.message)}"
  end

  # POST /orders/:order_id/items/:item_id/confirm_preprint - Manually confirm preprint completion
  post '/orders/:order_id/items/:item_id/confirm_preprint' do
    order = Order.find(params[:order_id])
    item = order.order_items.find(params[:item_id])

    result = DesignGroupWorkflow.new(item).confirm_preprint!
    message = "Pre-stampa confermata per #{result[:rows]} righe collegate"
    redirect "/orders/#{order.id}/items/#{item.id}?msg=success&text=#{URI.encode_www_form_component(message)}"
  rescue => e
    redirect "/orders/#{order.id}/items/#{item.id}?msg=error&text=#{URI.encode_www_form_component('Errore conferma: ' + e.message)}"
  end

  # POST /orders/:order_id/items/:item_id/reset - Reset item to initial state
  post '/orders/:order_id/items/:item_id/reset' do
    order = Order.find(params[:order_id])
    item = order.order_items.find(params[:item_id])

    # Keep historical automation runs readable while removing obsolete outputs.
    # The run context and artifacts retain the full audit trail after this link is cleared.
    previous_outputs = item.assets.where(asset_type: 'print_output')
    AutomationRun.where(source_asset_id: previous_outputs.select(:id)).update_all(source_asset_id: nil)
    previous_outputs.destroy_all
    puts "[RESET] Deleted print_output assets for item #{item.id}"

    item.update(
      preprint_status: 'pending',
      preprint_job_id: nil,
      preprint_preview_url: nil,
      print_status: 'pending',
      print_job_id: nil
    )

    redirect "/orders/#{order.id}/items/#{item.id}?msg=success&text=Item+reset+completato"
  rescue => e
    redirect "/orders/#{order.id}/items/#{item.id}?msg=error&text=Errore+reset:+#{URI.encode_www_form_component(e.message)}"
  end

  # POST /orders/:order_id/items/:item_id/send_print - Send item to print phase (uses preprint output PDF)
  post '/orders/:order_id/items/:item_id/send_print' do
    order = Order.find(params[:order_id])
    item = order.order_items.find(params[:item_id])
    print_machine = PrintMachine.find_by(id: params[:print_machine_id]) if params[:print_machine_id].present?
    unless print_machine
      redirect "/orders/#{order.id}/items/#{item.id}?msg=error&text=Macchina+di+stampa+non+selezionata"
    end

    result = DesignGroupWorkflow.new(item).send_print!(print_machine: print_machine)
    message = "#{result[:rows]} righe collegate inviate a stampa (#{result[:jobs]} lavorazioni)"
    redirect "/orders/#{order.id}/items/#{item.id}?msg=success&text=#{URI.encode_www_form_component(message)}"
  rescue DesignGroupWorkflow::Error => e
    redirect "/orders/#{order.id}/items/#{item.id}?msg=error&text=#{URI.encode_www_form_component(e.message)}"
  end

  # POST /orders/:order_id/items/:item_id/confirm_print - Manually confirm print completion
  post '/orders/:order_id/items/:item_id/confirm_print' do
    order = Order.find(params[:order_id])
    item = order.order_items.find(params[:item_id])

    result = DesignGroupWorkflow.new(item).confirm_print!
    message = "Stampa confermata per #{result[:rows]} righe collegate"
    redirect "/orders/#{order.id}/items/#{item.id}?msg=success&text=#{URI.encode_www_form_component(message)}"
  rescue => e
    redirect "/orders/#{order.id}/items/#{item.id}?msg=error&text=#{URI.encode_www_form_component('Errore conferma: ' + e.message)}"
  end

  # POST /orders/:order_id/items/:item_id/send_label - Send item to label webhook
  post '/orders/:order_id/items/:item_id/send_label' do
    order = Order.find(params[:order_id])
    item = order.order_items.find(params[:item_id])
    
    # Mark order as in processing when user starts working on an item
    order.update(status: 'processing') if order.status == 'new'

    # Get selected print machine
    print_machine_id = params[:print_machine_id]
    print_machine = PrintMachine.find_by(id: print_machine_id) if print_machine_id.present?
    
    unless print_machine
      redirect "/orders/#{order.id}/items/#{item.id}?msg=error&text=Stampante+non+selezionata"
    end

    # Get print flow and configured executor
    print_flow = item.print_flow
    unless print_flow
      redirect "/orders/#{order.id}/items/#{item.id}?msg=error&text=Flusso+di+stampa+non+configurato"
    end

    if print_flow.executor_for('label') == 'automation'
      begin
        AutomationActionDispatcher.dispatch!(
          print_flow: print_flow,
          action: 'label',
          order_item: item,
          assets: [],
          print_machine: print_machine
        )
        redirect "/orders/#{order.id}/items/#{item.id}?msg=success&text=Flusso+interno+etichetta+avviato"
      rescue StandardError => e
        redirect "/orders/#{order.id}/items/#{item.id}?msg=error&text=#{URI.encode_www_form_component('Errore flusso interno: ' + e.message)}"
      end
    end

    unless print_flow.executor_for('label') == 'webhook' && print_flow.label_webhook&.hook_path.present?
      redirect "/orders/#{order.id}/items/#{item.id}?msg=error&text=Azione+etichetta+non+configurata"
    end

    # Switch usa il primo asset come lavoro di ingresso, anche se l'etichetta
    # contiene soltanto i metadati dell'ordine.
    print_assets = item.switch_print_assets
    unless print_assets.any?
      redirect "/orders/#{order.id}/items/#{item.id}?msg=error&text=Nessun+asset+trovato+per+questo+item"
    end

    product = item.product
    server_url = ENV['SERVER_BASE_URL'] || 'http://localhost:5000'
    
    # Send single label payload (same structure as before, just send once)
    begin
      # Get first print asset for the URL
      first_asset = print_assets.first
      
      # Build Switch payload according to SWITCH_WORKFLOW.md
      job_data = {
        id_riga: item.item_number,
        codice_ordine: order.external_order_code,
        product: "#{product&.sku} - #{product&.name}",
        operation_id: 3,  # 1=prepress, 2=stampa, 3=etichetta
        job_operation_id: item.id.to_s,
        url: "#{server_url}/api/assets/#{first_asset.id}/download",
        widegest_url: "#{server_url}/api/v1/reports_create",
        filename: item.switch_filename_for_asset(first_asset) || "#{order.external_order_code.downcase}-#{item.id}.png",
        nome_macchina: print_machine.name,
        quantita: item.workflow_quantity,
        materiale: product&.notes || 'N/A',
        campi_custom: {},
        opzioni_stampa: {},
        campi_webhook: item.campi_webhook || {}
      }

      result = SwitchClient.send_to_switch(
        webhook_path: print_flow.label_webhook&.hook_path,
        job_data: job_data
      )
      
      if result[:success]
        redirect "/orders/#{order.id}/items/#{item.id}?msg=success&text=Etichetta+inviata+con+successo"
      else
        redirect "/orders/#{order.id}/items/#{item.id}?msg=error&text=#{URI.encode_www_form_component('Errore invio: ' + result[:error].to_s)}"
      end
    rescue => e
      error_msg = e.message.length > 50 ? e.message[0..50] + "..." : e.message
      redirect "/orders/#{order.id}/items/#{item.id}?msg=error&text=#{URI.encode_www_form_component('Errore invio: ' + error_msg)}"
    end
  end
end
