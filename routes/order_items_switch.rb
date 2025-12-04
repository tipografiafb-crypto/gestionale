# @feature orders
# @domain web
# Order Items Switch integration routes - Two-phase workflow (preprint → print)

class PrintOrchestrator < Sinatra::Base
  # POST /orders/:order_id/items/:item_id/send_preprint - Send item to preprint phase
  post '/orders/:order_id/items/:item_id/send_preprint' do
    puts "\n[DEBUG_PREPRINT_START] Order: #{params[:order_id]}, Item: #{params[:item_id]}"
    
    order = Order.find(params[:order_id])
    item = order.order_items.find(params[:item_id])
    
    # Mark order as in processing when user starts working on an item
    order.update(status: 'processing') if order.status == 'new'

    # Get selected print flow or use default
    print_flow_id = params[:print_flow_id] || item.product&.default_print_flow_id
    puts "[DEBUG_PREPRINT] print_flow_id: #{print_flow_id.inspect}"
    print_flow = PrintFlow.find_by(id: print_flow_id)
    puts "[DEBUG_PREPRINT] print_flow found: #{print_flow.present?}"
    
    unless print_flow
      redirect "/orders/#{order.id}/items/#{item.id}?msg=error&text=Flusso+di+stampa+non+trovato"
    end
    
    puts "[DEBUG_PREPRINT] preprint_webhook: #{print_flow.preprint_webhook.inspect}"
    unless print_flow.preprint_webhook
      redirect "/orders/#{order.id}/items/#{item.id}?msg=error&text=Webhook+pre-stampa+non+configurato"
    end
    
    webhook_hook_path = print_flow.preprint_webhook&.hook_path
    puts "[DEBUG_PREPRINT] webhook_hook_path: #{webhook_hook_path.inspect}"
    unless webhook_hook_path.present?
      redirect "/orders/#{order.id}/items/#{item.id}?msg=error&text=Path+webhook+pre-stampa+vuoto"
    end

    # Get percentuale and azione_photoshop from form and build campi_webhook
    percentuale = params[:percentuale].to_i rescue 0
    azione_photoshop = params[:azione_photoshop]&.strip
    
    campi_webhook = { percentuale: percentuale.to_s }
    campi_webhook["azione photoshop"] = azione_photoshop if azione_photoshop.present?
    
    # Store selected print flow in item
    item.update(
      preprint_print_flow_id: print_flow.id, 
      preprint_status: 'processing',
      campi_webhook: campi_webhook
    )

    # Get all print assets (assets are auto-downloaded during import)
    print_assets = item.switch_print_assets
    unless print_assets.any?
      item.update(preprint_status: 'failed')
      redirect "/orders/#{order.id}/items/#{item.id}?msg=error&text=Nessun+asset+trovato+per+questo+item"
    end

    product = item.product
    server_url = ENV['SERVER_BASE_URL'] || 'http://localhost:5000'
    
    # Send each print asset to preprint webhook
    begin
      errors = []
      successful_assets = []
      
      print_assets.each do |print_asset|
        puts "[DEBUG_PREPRINT] Processing asset: #{print_asset.id}"
        # Build Switch payload according to SWITCH_WORKFLOW.md
        job_data = {
          id_riga: item.item_number,
          codice_ordine: order.external_order_code,
          product: "#{product&.sku} - #{product&.name}",
          operation_id: 1,  # 1=prepress, 2=stampa, 3=etichetta
          job_operation_id: item.id.to_s,
          url: "#{server_url}/api/assets/#{print_asset.id}/download",
          widegest_url: "#{server_url}/api/v1/reports_create",
          filename: item.switch_filename_for_asset(print_asset) || "#{order.external_order_code.downcase}-#{item.id}.png",
          quantita: item.quantity,
          materiale: product&.notes || 'N/A',
          campi_custom: {},
          opzioni_stampa: {},
          campi_webhook: campi_webhook
        }

        puts "[DEBUG_PREPRINT] Calling SwitchClient.send_to_switch with webhook_path: #{webhook_hook_path.inspect}"
        result = SwitchClient.send_to_switch(
          webhook_path: webhook_hook_path,
          job_data: job_data
        )
        puts "[DEBUG_PREPRINT] Result: #{result.inspect}"
        
        if result[:success]
          successful_assets << print_asset.id
        else
          errors << result[:error]
        end
      end
      
      if errors.any?
        item.update(preprint_status: 'failed')
        redirect "/orders/#{order.id}/items/#{item.id}?msg=error&text=#{URI.encode_www_form_component('Errore invio: ' + errors.join(', '))}"
      else
        item.update(preprint_status: 'processing', preprint_job_id: successful_assets.join(','))
        redirect "/orders/#{order.id}/items/#{item.id}?msg=success&text=#{successful_assets.length}+asset+inviati+a+pre-stampa"
      end
    rescue => e
      item.update(preprint_status: 'failed')
      puts "[PREPRINT_ERROR] #{e.class}: #{e.message}"
      puts "[PREPRINT_ERROR_INSPECT] #{e.inspect}"
      puts "[PREPRINT_BACKTRACE]"
      e.backtrace.each { |line| puts "  #{line}" }
      
      error_msg = begin
        msg = e.message.to_s
        msg.length > 50 ? msg[0..50] + "..." : msg
      rescue => msg_error
        "Errore sconosciuto: #{e.class}"
      end
      
      redirect "/orders/#{order.id}/items/#{item.id}?msg=error&text=#{URI.encode_www_form_component('Errore invio: ' + error_msg)}"
    end
  end

  # POST /orders/:order_id/items/:item_id/confirm_preprint - Manually confirm preprint completion
  post '/orders/:order_id/items/:item_id/confirm_preprint' do
    order = Order.find(params[:order_id])
    item = order.order_items.find(params[:item_id])

    unless item.preprint_status == 'processing'
      redirect "/orders/#{order.id}/items/#{item.id}?msg=error&text=Questo+item+non+è+in+fase+di+pre-stampa"
    end

    item.update(preprint_status: 'completed', preprint_completed_at: Time.now)
    redirect "/orders/#{order.id}/items/#{item.id}?msg=success&text=Pre-stampa+confermata+manualmente"
  rescue => e
    redirect "/orders/#{order.id}/items/#{item.id}?msg=error&text=#{URI.encode_www_form_component('Errore conferma: ' + e.message)}"
  end

  # POST /orders/:order_id/items/:item_id/reset - Reset item to initial state
  post '/orders/:order_id/items/:item_id/reset' do
    order = Order.find(params[:order_id])
    item = order.order_items.find(params[:item_id])

    # Delete all previous Switch output files
    item.assets.where(asset_type: 'print_output').destroy_all
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
    
    # Mark order as in processing when user starts working on an item
    order.update(status: 'processing') if order.status == 'new'

    # Get selected print machine
    print_machine_id = params[:print_machine_id]
    print_machine = PrintMachine.find_by(id: print_machine_id) if print_machine_id.present?
    
    unless print_machine
      redirect "/orders/#{order.id}/items/#{item.id}?msg=error&text=Macchina+di+stampa+non+selezionata"
    end
    
    # Update status and machine
    item.update(print_status: 'processing', print_machine_id: print_machine.id)

    # Get print flow and print webhook
    print_flow = item.print_flow
    unless print_flow&.print_webhook
      item.update(print_status: 'failed')
      redirect "/orders/#{order.id}/items/#{item.id}?msg=error&text=Flusso+di+stampa+non+configurato"
    end

    # Get the preprint output PDF (print_output asset)
    print_output_asset = item.assets.where(asset_type: 'print_output').first
    unless print_output_asset
      item.update(print_status: 'failed')
      redirect "/orders/#{order.id}/items/#{item.id}?msg=error&text=File+preprint+non+trovato"
    end

    product = item.product
    server_url = ENV['SERVER_BASE_URL'] || 'http://localhost:5000'
    
    # Send the preprint output PDF to print webhook
    begin
      # Build Switch payload with only nome_macchina (simplified)
      job_data = {
        id_riga: item.item_number,
        codice_ordine: order.external_order_code,
        product: "#{product&.sku} - #{product&.name}",
        operation_id: 2,  # 2=stampa
        job_operation_id: item.id.to_s,
        url: "#{server_url}/api/assets/#{print_output_asset.id}/download",
        widegest_url: "#{server_url}/api/v1/reports_create",
        filename: print_output_asset.original_url || "#{order.external_order_code.downcase}-#{item.id}-print.pdf",
        nome_macchina: print_machine.name,
        campi_webhook: item.campi_webhook || {}
      }

      puts "[PRINT] Sending to Switch: #{job_data.inspect}"
      
      result = SwitchClient.send_to_switch(
        webhook_path: print_flow.print_webhook&.hook_path,
        job_data: job_data
      )
      
      if result[:success]
        item.update(print_status: 'processing')
        redirect "/orders/#{order.id}/items/#{item.id}?msg=success&text=PDF+inviato+in+stampa"
      else
        item.update(print_status: 'failed')
        redirect "/orders/#{order.id}/items/#{item.id}?msg=error&text=#{URI.encode_www_form_component('Errore invio: ' + result[:error].to_s)}"
      end
    rescue => e
      item.update(print_status: 'failed')
      error_msg = e.message.length > 50 ? e.message[0..50] + "..." : e.message
      puts "[PRINT_ERROR] #{e.class}: #{e.message}"
      redirect "/orders/#{order.id}/items/#{item.id}?msg=error&text=#{URI.encode_www_form_component('Errore invio: ' + error_msg)}"
    end
  end

  # POST /orders/:order_id/items/:item_id/confirm_print - Manually confirm print completion
  post '/orders/:order_id/items/:item_id/confirm_print' do
    order = Order.find(params[:order_id])
    item = order.order_items.find(params[:item_id])

    # Accept both 'processing' (single item) and 'ripped' (bulk print) statuses
    unless %w[processing ripped].include?(item.print_status)
      redirect "/orders/#{order.id}/items/#{item.id}?msg=error&text=Questo+item+non+è+in+fase+di+stampa"
    end

    item.update(print_status: 'completed', print_completed_at: Time.now)
    redirect "/orders/#{order.id}/items/#{item.id}?msg=success&text=Stampa+confermata,+item+completato"
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

    # Get print flow and label webhook
    print_flow = item.print_flow
    unless print_flow&.label_webhook
      redirect "/orders/#{order.id}/items/#{item.id}?msg=error&text=Webhook+etichetta+non+configurato"
    end

    # Get all print assets (assets are auto-downloaded during import)
    print_assets = item.switch_print_assets
    unless print_assets.any?
      redirect "/orders/#{order.id}/items/#{item.id}?msg=error&text=Nessun+asset+trovato+per+questo+item"
    end

    product = item.product
    server_url = ENV['SERVER_BASE_URL'] || 'http://localhost:5000'
    
    # Send each print asset to label webhook
    begin
      errors = []
      successful_assets = []
      
      print_assets.each do |print_asset|
        # Build Switch payload according to SWITCH_WORKFLOW.md
        job_data = {
          id_riga: item.item_number,
          codice_ordine: order.external_order_code,
          product: "#{product&.sku} - #{product&.name}",
          operation_id: 3,  # 1=prepress, 2=stampa, 3=etichetta
          job_operation_id: item.id.to_s,
          url: "#{server_url}/api/assets/#{print_asset.id}/download",
          widegest_url: "#{server_url}/api/v1/reports_create",
          filename: item.switch_filename_for_asset(print_asset) || "#{order.external_order_code.downcase}-#{item.id}.png",
          nome_macchina: print_machine.name,
          quantita: item.quantity,
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
          successful_assets << print_asset.id
        else
          errors << result[:error]
        end
      end
      
      if errors.any?
        redirect "/orders/#{order.id}/items/#{item.id}?msg=error&text=#{URI.encode_www_form_component('Errore invio: ' + errors.join(', '))}"
      else
        redirect "/orders/#{order.id}/items/#{item.id}?msg=success&text=#{successful_assets.length}+etichetta+inviate+con+successo"
      end
    rescue => e
      error_msg = e.message.length > 50 ? e.message[0..50] + "..." : e.message
      redirect "/orders/#{order.id}/items/#{item.id}?msg=error&text=#{URI.encode_www_form_component('Errore invio: ' + error_msg)}"
    end
  end
end
