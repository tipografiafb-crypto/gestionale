# @feature orders
# @domain web
# Order Items Switch integration routes - Two-phase workflow (preprint → print)

class PrintOrchestrator < Sinatra::Base
  # POST /orders/:order_id/items/:item_id/send_preprint - Send item to preprint phase
  post '/orders/:order_id/items/:item_id/send_preprint' do
    order = Order.find(params[:order_id])
    item = order.order_items.find(params[:item_id])

    unless item.can_send_to_preprint?
      redirect "/orders/#{order.id}?msg=error&text=Non+puoi+inviare+questo+item+a+pre-stampa"
    end

    # Get selected print flow or use default
    print_flow_id = params[:print_flow_id] || item.product&.default_print_flow_id
    print_flow = PrintFlow.find_by(id: print_flow_id)
    
    unless print_flow&.preprint_webhook
      redirect "/orders/#{order.id}?msg=error&text=Flusso+di+stampa+non+configurato"
    end

    # Get percentuale from form and build campi_webhook
    percentuale = params[:percentuale].to_i rescue 0
    campi_webhook = { percentuale: percentuale.to_s }
    
    # Store selected print flow in item
    item.update(
      preprint_print_flow_id: print_flow.id, 
      preprint_status: 'processing',
      campi_webhook: campi_webhook
    )

    # Prepare correct payload for Switch - PREPRESS (operation_id=1)
    # Get first print asset to create payload
    print_asset = item.assets.find { |a| a.downloaded? && a.asset_type == 'print' }
    unless print_asset
      item.update(preprint_status: 'failed')
      redirect "/orders/#{order.id}?msg=error&text=Nessun+asset+scaricato"
    end

    product = item.product
    server_url = ENV['SERVER_BASE_URL'] || 'http://localhost:5000'
    
    # Build Switch payload according to SWITCH_WORKFLOW.md
    job_data = {
      id_riga: item.item_number,
      codice_ordine: order.external_order_code,
      product: "#{product&.sku} - #{product&.name}",
      operation_id: 1,  # 1=prepress, 2=stampa, 3=etichetta
      job_operation_id: nil,
      url: "#{server_url}/api/assets/#{print_asset.id}/download",
      widegest_url: "#{server_url}/api/v1/reports_create",
      filename: item.switch_filename_for_asset(print_asset) || "#{order.external_order_code}_#{item.item_number}.png",
      quantita: item.quantity,
      materiale: product&.description || 'N/A',
      campi_custom: item.campi_custom || {},
      opzioni_stampa: item.opzioni_stampa || {},
      campi_webhook: campi_webhook
    }

    # Send to preprint webhook
    begin
      result = SwitchClient.send_to_switch(
        webhook_path: print_flow.preprint_webhook.hook_path,
        job_data: job_data
      )
      
      if result[:success]
        item.update(
          preprint_status: 'processing',
          preprint_job_id: result[:job_id]
        )
        redirect "/orders/#{order.id}?msg=success&text=Item+inviato+a+pre-stampa,+controlla+e+conferma"
      else
        item.update(preprint_status: 'failed')
        redirect "/orders/#{order.id}?msg=error&text=#{URI.encode_www_form_component('Errore: ' + result[:error].to_s)}"
      end
    rescue => e
      item.update(preprint_status: 'failed')
      error_msg = e.message.length > 50 ? e.message[0..50] + "..." : e.message
      redirect "/orders/#{order.id}?msg=error&text=#{URI.encode_www_form_component('Errore invio: ' + error_msg)}"
    end
  end

  # POST /orders/:order_id/items/:item_id/confirm_preprint - Manually confirm preprint completion
  post '/orders/:order_id/items/:item_id/confirm_preprint' do
    order = Order.find(params[:order_id])
    item = order.order_items.find(params[:item_id])

    unless item.preprint_status == 'processing'
      redirect "/orders/#{order.id}?msg=error&text=Questo+item+non+è+in+fase+di+pre-stampa"
    end

    item.update(preprint_status: 'completed', preprint_completed_at: Time.now)
    redirect "/orders/#{order.id}?msg=success&text=Pre-stampa+confermata+manualmente"
  rescue => e
    redirect "/orders/#{order.id}?msg=error&text=#{URI.encode_www_form_component('Errore conferma: ' + e.message)}"
  end

  # POST /orders/:order_id/items/:item_id/reset - Reset item to initial state
  post '/orders/:order_id/items/:item_id/reset' do
    order = Order.find(params[:order_id])
    item = order.order_items.find(params[:item_id])

    item.update(
      preprint_status: 'pending',
      preprint_job_id: nil,
      preprint_preview_url: nil,
      print_status: 'pending',
      print_job_id: nil
    )

    redirect "/orders/#{order.id}?msg=success&text=Item+reset+completato"
  rescue => e
    redirect "/orders/#{order.id}?msg=error&text=Errore+reset:+#{URI.encode_www_form_component(e.message)}"
  end

  # POST /orders/:order_id/items/:item_id/send_print - Send item to print phase
  post '/orders/:order_id/items/:item_id/send_print' do
    order = Order.find(params[:order_id])
    item = order.order_items.find(params[:item_id])

    unless item.can_send_to_print?
      redirect "/orders/#{order.id}?msg=error&text=Non+puoi+inviare+questo+item+in+stampa"
    end

    # Get selected print machine
    print_machine_id = params[:print_machine_id]
    print_machine = PrintMachine.find_by(id: print_machine_id) if print_machine_id.present?
    
    # Update status and machine
    item.update(print_status: 'processing', print_machine_id: print_machine&.id)

    # Get print flow and print webhook
    print_flow = item.print_flow
    unless print_flow&.print_webhook
      item.update(print_status: 'failed')
      redirect "/orders/#{order.id}?msg=error&text=Flusso+di+stampa+non+configurato"
    end

    # Prepare correct payload for Switch - STAMPA (operation_id=2)
    # Get first print asset to create payload
    print_asset = item.assets.find { |a| a.downloaded? && a.asset_type == 'print' }
    unless print_asset
      item.update(print_status: 'failed')
      redirect "/orders/#{order.id}?msg=error&text=Nessun+asset+scaricato"
    end

    product = item.product
    server_url = ENV['SERVER_BASE_URL'] || 'http://localhost:5000'
    
    # Build Switch payload according to SWITCH_WORKFLOW.md
    job_data = {
      id_riga: item.item_number,
      codice_ordine: order.external_order_code,
      product: "#{product&.sku} - #{product&.name}",
      operation_id: 2,  # 1=prepress, 2=stampa, 3=etichetta
      job_operation_id: nil,
      url: "#{server_url}/api/assets/#{print_asset.id}/download",
      widegest_url: "#{server_url}/api/v1/reports_create",
      filename: item.switch_filename_for_asset(print_asset) || "#{order.external_order_code}_#{item.item_number}.png",
      quantita: item.quantity,
      materiale: product&.description || 'N/A',
      campi_custom: item.campi_custom || {},
      opzioni_stampa: item.opzioni_stampa || {},
      campi_webhook: item.campi_webhook || {}
    }

    # Send to print webhook
    begin
      result = SwitchClient.send_to_switch(
        webhook_path: print_flow.print_webhook.hook_path,
        job_data: job_data
      )
      
      if result[:success]
        item.update(print_status: 'processing', print_started_at: Time.now)
        redirect "/orders/#{order.id}?msg=success&text=Item+inviato+in+stampa,+controlla+e+conferma"
      else
        item.update(print_status: 'failed')
        redirect "/orders/#{order.id}?msg=error&text=#{URI.encode_www_form_component('Errore: ' + result[:error].to_s)}"
      end
    rescue => e
      item.update(print_status: 'failed')
      error_msg = e.message.length > 50 ? e.message[0..50] + "..." : e.message
      redirect "/orders/#{order.id}?msg=error&text=#{URI.encode_www_form_component('Errore invio: ' + error_msg)}"
    end
  end

  # POST /orders/:order_id/items/:item_id/confirm_print - Manually confirm print completion
  post '/orders/:order_id/items/:item_id/confirm_print' do
    order = Order.find(params[:order_id])
    item = order.order_items.find(params[:item_id])

    unless item.print_status == 'processing'
      redirect "/orders/#{order.id}?msg=error&text=Questo+item+non+è+in+fase+di+stampa"
    end

    item.update(print_status: 'completed', print_completed_at: Time.now)
    redirect "/orders/#{order.id}?msg=success&text=Stampa+confermata,+item+completato"
  rescue => e
    redirect "/orders/#{order.id}?msg=error&text=#{URI.encode_www_form_component('Errore conferma: ' + e.message)}"
  end

  # POST /orders/:order_id/items/:item_id/send_label - Send item to label webhook
  post '/orders/:order_id/items/:item_id/send_label' do
    order = Order.find(params[:order_id])
    item = order.order_items.find(params[:item_id])

    # Get print flow and label webhook
    print_flow = item.print_flow
    unless print_flow&.label_webhook
      redirect "/orders/#{order.id}?msg=error&text=Webhook+etichetta+non+configurato"
    end

    # Prepare correct payload for Switch - ETICHETTA (operation_id=3)
    # Get first print asset to create payload
    print_asset = item.assets.find { |a| a.downloaded? && a.asset_type == 'print' }
    unless print_asset
      redirect "/orders/#{order.id}?msg=error&text=Nessun+asset+scaricato"
    end

    product = item.product
    server_url = ENV['SERVER_BASE_URL'] || 'http://localhost:5000'
    
    # Build Switch payload according to SWITCH_WORKFLOW.md
    job_data = {
      id_riga: item.item_number,
      codice_ordine: order.external_order_code,
      product: "#{product&.sku} - #{product&.name}",
      operation_id: 3,  # 1=prepress, 2=stampa, 3=etichetta
      job_operation_id: nil,
      url: "#{server_url}/api/assets/#{print_asset.id}/download",
      widegest_url: "#{server_url}/api/v1/reports_create",
      filename: item.switch_filename_for_asset(print_asset) || "#{order.external_order_code}_#{item.item_number}.png",
      quantita: item.quantity,
      materiale: product&.description || 'N/A',
      campi_custom: item.campi_custom || {},
      opzioni_stampa: item.opzioni_stampa || {},
      campi_webhook: item.campi_webhook || {}
    }

    # Send to label webhook
    begin
      result = SwitchClient.send_to_switch(
        webhook_path: print_flow.label_webhook.hook_path,
        job_data: job_data
      )
      
      if result[:success]
        redirect "/orders/#{order.id}?msg=success&text=Etichetta+inviata+con+successo"
      else
        redirect "/orders/#{order.id}?msg=error&text=#{URI.encode_www_form_component('Errore: ' + result[:error].to_s)}"
      end
    rescue => e
      error_msg = e.message.length > 50 ? e.message[0..50] + "..." : e.message
      redirect "/orders/#{order.id}?msg=error&text=#{URI.encode_www_form_component('Errore invio: ' + error_msg)}"
    end
  end
end
