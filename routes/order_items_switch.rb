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

    # Update status
    item.update(preprint_status: 'processing')

    # Get print flow and preprint webhook
    print_flow = item.print_flow
    unless print_flow&.preprint_webhook
      item.update(preprint_status: 'failed')
      redirect "/orders/#{order.id}?msg=error&text=Flusso+di+stampa+non+configurato"
    end

    # Prepare job data for Switch - only send print assets (not preview)
    downloaded_assets = item.assets.select { |a| a.downloaded? && a.asset_type == 'print' }
    job_data = {
      job_id: "PREPRINT-ORD#{order.id}-IT#{item.id}-#{Time.now.to_i}",
      order_code: order.external_order_code,
      item_sku: item.sku,
      quantity: item.quantity,
      assets: downloaded_assets.map { |a| a.local_path_full }
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

    # Update status
    item.update(print_status: 'processing')

    # Get print flow and print webhook
    print_flow = item.print_flow
    unless print_flow&.print_webhook
      item.update(print_status: 'failed')
      redirect "/orders/#{order.id}?msg=error&text=Flusso+di+stampa+non+configurato"
    end

    # Prepare job data for Switch - only send print assets (not preview)
    downloaded_assets = item.assets.select { |a| a.downloaded? && a.asset_type == 'print' }
    job_data = {
      job_id: "PRINT-ORD#{order.id}-IT#{item.id}-#{Time.now.to_i}",
      preprint_job_id: item.preprint_job_id,
      order_code: order.external_order_code,
      item_sku: item.sku,
      quantity: item.quantity,
      assets: downloaded_assets.map { |a| a.local_path_full }
    }

    # Send to print webhook
    begin
      result = SwitchClient.send_to_switch(
        webhook_path: print_flow.print_webhook.hook_path,
        job_data: job_data
      )
      
      if result[:success]
        item.update(
          print_status: 'processing',
          print_job_id: result[:job_id]
        )
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

    # Prepare job data for label
    downloaded_assets = item.assets.select { |a| a.downloaded? && a.asset_type == 'print' }
    job_data = {
      job_id: "LABEL-ORD#{order.id}-IT#{item.id}-#{Time.now.to_i}",
      order_code: order.external_order_code,
      item_sku: item.sku,
      quantity: item.quantity,
      assets: downloaded_assets.map { |a| a.local_path_full }
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
