# @feature orders
# @domain web
# Order Items Switch integration routes - Two-phase workflow (preprint → print)

class PrintOrchestrator < Sinatra::Base
  # POST /orders/:order_id/items/:item_id/send_preprint - Send item to preprint phase
  post '/orders/:order_id/items/:item_id/send_preprint' do
    order = Order.find(params[:order_id])
    item = order.order_items.find(params[:item_id])

    unless item.can_send_to_preprint?
      flash[:error] = "Non puoi inviare questo item a pre-stampa"
      redirect "/orders/#{order.id}"
    end

    # Update status
    item.update(preprint_status: 'processing')

    # Get print flow and preprint webhook
    print_flow = item.print_flow
    unless print_flow&.preprint_webhook
      item.update(preprint_status: 'failed')
      flash[:error] = "Flusso di stampa non configurato per questo prodotto"
      redirect "/orders/#{order.id}"
    end

    # Prepare job data for Switch
    job_data = {
      job_id: "PREPRINT-ORD#{order.id}-IT#{item.id}-#{Time.now.to_i}",
      order_code: order.external_order_code,
      item_sku: item.sku,
      quantity: item.quantity,
      assets: item.assets.where(downloaded: true).map { |a| a.local_path_full }
    }

    # Send to preprint webhook
    begin
      SwitchClient.send_to_switch(
        webhook_path: print_flow.preprint_webhook.hook_path,
        job_data: job_data
      )
      
      item.update(
        preprint_status: 'completed',
        preprint_job_id: job_data[:job_id]
      )
      flash[:success] = "Item inviato a pre-stampa ✓"
    rescue => e
      item.update(preprint_status: 'failed')
      flash[:error] = "Errore nell'invio a pre-stampa: #{e.message}"
    end

    redirect "/orders/#{order.id}"
  end

  # POST /orders/:order_id/items/:item_id/send_print - Send item to print phase
  post '/orders/:order_id/items/:item_id/send_print' do
    order = Order.find(params[:order_id])
    item = order.order_items.find(params[:item_id])

    unless item.can_send_to_print?
      flash[:error] = "Non puoi inviare questo item in stampa"
      redirect "/orders/#{order.id}"
    end

    # Update status
    item.update(print_status: 'processing')

    # Get print flow and print webhook
    print_flow = item.print_flow
    unless print_flow&.print_webhook
      item.update(print_status: 'failed')
      flash[:error] = "Flusso di stampa non configurato per questo prodotto"
      redirect "/orders/#{order.id}"
    end

    # Prepare job data for Switch
    job_data = {
      job_id: "PRINT-ORD#{order.id}-IT#{item.id}-#{Time.now.to_i}",
      preprint_job_id: item.preprint_job_id,
      order_code: order.external_order_code,
      item_sku: item.sku,
      quantity: item.quantity,
      assets: item.assets.where(downloaded: true).map { |a| a.local_path_full }
    }

    # Send to print webhook
    begin
      SwitchClient.send_to_switch(
        webhook_path: print_flow.print_webhook.hook_path,
        job_data: job_data
      )
      
      item.update(
        print_status: 'completed',
        print_job_id: job_data[:job_id]
      )
      flash[:success] = "Item inviato in stampa ✓"
    rescue => e
      item.update(print_status: 'failed')
      flash[:error] = "Errore nell'invio in stampa: #{e.message}"
    end

    redirect "/orders/#{order.id}"
  end
end
