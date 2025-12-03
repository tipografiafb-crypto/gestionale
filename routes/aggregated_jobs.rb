# @feature aggregation
# @domain web-ui
# Routes for managing aggregated jobs

class PrintOrchestrator < Sinatra::Base
  # GET /aggregated_jobs - List all aggregated jobs
  get '/aggregated_jobs' do
    @aggregated_jobs = AggregatedJob.includes(:print_flow).order(created_at: :desc)
    @switch_webhooks = SwitchWebhook.ordered
    erb :aggregated_jobs_list
  end

  # GET /aggregated_jobs/new - Form to create aggregated job
  get '/aggregated_jobs/new' do
    # Mostra solo order items con preprint completato che non sono già aggregati
    already_aggregated_ids = AggregatedJobItem.pluck(:order_item_id)
    @available_items = OrderItem.where(preprint_status: 'completed', print_status: 'pending')
                                .where.not(id: already_aggregated_ids)
                                .includes(:order, :assets)
                                .order(created_at: :desc)
    @print_flows = PrintFlow.ordered
    @switch_webhooks = SwitchWebhook.ordered
    erb :aggregated_jobs_new
  end

  # POST /aggregated_jobs - Create aggregated job from selected items
  post '/aggregated_jobs' do
    item_ids = params[:item_ids] || []
    print_flow_id = params[:print_flow_id].presence
    
    return redirect '/aggregated_jobs/new?msg=error&text=Seleziona+almeno+1+line+item' if item_ids.count < 1
    return redirect '/aggregated_jobs/new?msg=error&text=Seleziona+un+flusso+di+stampa' unless print_flow_id

    begin
      items = OrderItem.where(id: item_ids, preprint_status: 'completed')
      return redirect '/aggregated_jobs/new?msg=error&text=Alcuni+item+non+hanno+preprint+completato' if items.count != item_ids.count

      job = AggregatedJob.create_from_items(
        items, 
        name: params[:name], 
        print_flow_id: print_flow_id
      )
      redirect "/aggregated_jobs/#{job.id}?msg=success&text=Aggregazione+creata+con+#{items.count}+file"
    rescue => e
      redirect "/aggregated_jobs/new?msg=error&text=Errore:+#{e.message}"
    end
  end

  # GET /aggregated_jobs/:id - View aggregated job details
  get '/aggregated_jobs/:id' do
    @aggregated_job = AggregatedJob.find(params[:id])
    @order_items = @aggregated_job.order_items.includes(:order, :assets)
    @switch_webhooks = SwitchWebhook.ordered
    @print_flows = PrintFlow.ordered
    
    # For preview, get the local file
    if @aggregated_job.status == 'preview_pending' && @aggregated_job.notes.present?
      @preview_file_path = @aggregated_job.notes
      @preview_file_exists = File.exist?(File.join(Dir.pwd, @preview_file_path))
    end
    
    erb :aggregated_job_detail
  end
  
  # GET /file/agg_:id/:filename - Serve aggregated job file for preview
  get '/file/agg_:id/:filename' do
    begin
      @aggregated_job = AggregatedJob.find(params[:id])
      filename = params[:filename]
      file_path = File.join(Dir.pwd, 'storage', 'aggregated', filename)
      
      if File.exist?(file_path)
        send_file file_path, disposition: 'inline', type: 'application/pdf'
      else
        puts "[FILE_SERVE_ERROR] File not found at: #{file_path}"
        status 404
        'File not found'
      end
    rescue => e
      puts "[FILE_SERVE_ERROR] #{e.message}"
      status 500
      'Error serving file'
    end
  end

  # POST /aggregated_jobs/:id/send_aggregation - Send files to Switch for aggregation
  post '/aggregated_jobs/:id/send_aggregation' do
    @aggregated_job = AggregatedJob.find(params[:id])
    webhook_path = params[:webhook_path]
    
    unless webhook_path.present?
      return redirect "/aggregated_jobs/#{@aggregated_job.id}?msg=error&text=Seleziona+un+webhook+per+l'aggregazione"
    end
    
    unless @aggregated_job.status == 'pending'
      return redirect "/aggregated_jobs/#{@aggregated_job.id}?msg=error&text=Job+già+inviato"
    end

    result = @aggregated_job.send_aggregation_to_switch(webhook_path)
    
    if result[:success]
      redirect "/aggregated_jobs/#{@aggregated_job.id}?msg=success&text=#{URI.encode_www_form_component(result[:message])}"
    else
      redirect "/aggregated_jobs/#{@aggregated_job.id}?msg=error&text=#{URI.encode_www_form_component(result[:error])}"
    end
  end

  # POST /aggregated_jobs/:id/mark_completed - Manually mark as completed
  post '/aggregated_jobs/:id/mark_completed' do
    @aggregated_job = AggregatedJob.find(params[:id])
    @aggregated_job.mark_print_completed
    redirect "/aggregated_jobs/#{@aggregated_job.id}?msg=success&text=Aggregazione+completata"
  end

  # POST /aggregated_jobs/:id/send_preprint - Send files to Switch for aggregation (only when pending)
  post '/aggregated_jobs/:id/send_preprint' do
    @aggregated_job = AggregatedJob.find(params[:id])
    
    unless @aggregated_job.status == 'pending'
      return redirect "/aggregated_jobs/#{@aggregated_job.id}?msg=error&text=Job+già+in+anteprima"
    end
    
    # Aggregate files using preprint_webhook from print_flow
    unless @aggregated_job.print_flow&.preprint_webhook
      return redirect "/aggregated_jobs/#{@aggregated_job.id}?msg=error&text=Print+flow+non+ha+webhook+di+pre-stampa"
    end
    
    result = @aggregated_job.send_aggregation_to_switch(@aggregated_job.print_flow.preprint_webhook.hook_path)
    
    if result[:success]
      redirect "/aggregated_jobs/#{@aggregated_job.id}?msg=success&text=#{URI.encode_www_form_component(result[:message])}"
    else
      redirect "/aggregated_jobs/#{@aggregated_job.id}?msg=error&text=#{URI.encode_www_form_component(result[:error])}"
    end
  end

  # POST /aggregated_jobs/:id/confirm_preprint - Confirm preprint (mark as reviewed and ready for print)
  post '/aggregated_jobs/:id/confirm_preprint' do
    @aggregated_job = AggregatedJob.find(params[:id])
    
    unless @aggregated_job.status == 'preview_pending'
      return redirect "/aggregated_jobs/#{@aggregated_job.id}?msg=error&text=Job+non+in+anteprima"
    end
    
    @aggregated_job.update(preprint_sent_at: Time.current)
    redirect "/aggregated_jobs/#{@aggregated_job.id}?msg=success&text=Pre-stampa+confermata"
  end

  # POST /aggregated_jobs/:id/send_print - Send aggregated file to Switch for print (post-confirmation)
  post '/aggregated_jobs/:id/send_print' do
    @aggregated_job = AggregatedJob.find(params[:id])
    print_machine_id = params[:print_machine_id]
    
    # Must be in preview_pending state (after preprint confirmation)
    unless @aggregated_job.status == 'preview_pending'
      return redirect "/aggregated_jobs/#{@aggregated_job.id}?msg=error&text=Job+non+in+stato+preview_pending"
    end
    
    # Must have preprint confirmed
    unless @aggregated_job.preprint_sent_at.present?
      return redirect "/aggregated_jobs/#{@aggregated_job.id}?msg=error&text=Pre-stampa+non+confermata"
    end
    
    unless print_machine_id.present?
      return redirect "/aggregated_jobs/#{@aggregated_job.id}?msg=error&text=Seleziona+una+stampante"
    end
    
    unless @aggregated_job.print_flow&.print_webhook
      return redirect "/aggregated_jobs/#{@aggregated_job.id}?msg=error&text=Webhook+di+stampa+non+configurato+nel+flusso"
    end
    
    # Get the aggregated file URL (from callback or fallback)
    file_url = @aggregated_job.aggregated_file_url
    if !file_url.present? && @aggregated_job.notes.present?
      file_url = "/file/agg_#{@aggregated_job.id}/#{@aggregated_job.notes}"
    end
    
    unless file_url.present?
      return redirect "/aggregated_jobs/#{@aggregated_job.id}?msg=error&text=File+aggregato+non+disponibile"
    end
    
    webhook_path = @aggregated_job.print_flow.print_webhook.hook_path
    server_url = ENV['SERVER_BASE_URL'] || 'http://localhost:5000'
    
    # Build Switch payload (same as normal order items)
    product = @aggregated_job.order_items.first&.product
    job_data = {
      aggregated_job_id: @aggregated_job.id,
      id_riga: @aggregated_job.id,
      codice_ordine: "AGG-#{@aggregated_job.id}",
      product: "#{product&.sku} - #{product&.name}",
      operation_id: 2,  # 1=prepress, 2=stampa, 3=etichetta
      job_operation_id: "agg-print-#{@aggregated_job.id}",
      url: file_url,
      widegest_url: "#{server_url}/api/v1/aggregation_print_callback",
      filename: @aggregated_job.aggregated_filename || "aggregated_#{@aggregated_job.id}.pdf",
      quantita: @aggregated_job.order_items.sum(:quantity),
      materiale: product&.notes || '',
      print_machine_id: print_machine_id,
      campi_custom: {},
      opzioni_stampa: {},
      taglio: false,
      stampa: true,
      plancia: false,
      scala: '1:1'
    }
    
    begin
      result = SwitchClient.send_to_switch(
        webhook_path: webhook_path,
        job_data: job_data
      )
      
      if result[:success]
        @aggregated_job.update(status: 'printing')
        redirect "/aggregated_jobs/#{@aggregated_job.id}?msg=success&text=File+inviato+a+stampa"
      else
        redirect "/aggregated_jobs/#{@aggregated_job.id}?msg=error&text=#{URI.encode_www_form_component(result[:error])}"
      end
    rescue => e
      puts "[SEND_PRINT_ERROR] #{e.class}: #{e.message}"
      redirect "/aggregated_jobs/#{@aggregated_job.id}?msg=error&text=#{URI.encode_www_form_component('Errore: ' + e.message)}"
    end
  end

  # POST /aggregated_jobs/:id/send_label - Send aggregated file to Switch for label
  post '/aggregated_jobs/:id/send_label' do
    @aggregated_job = AggregatedJob.find(params[:id])
    
    unless @aggregated_job.status == 'preview_pending'
      return redirect "/aggregated_jobs/#{@aggregated_job.id}?msg=error&text=Job+non+in+anteprima"
    end

    result = @aggregated_job.send_to_switch_operation('label')
    
    if result[:success]
      redirect "/aggregated_jobs/#{@aggregated_job.id}?msg=success&text=#{URI.encode_www_form_component(result[:message])}"
    else
      redirect "/aggregated_jobs/#{@aggregated_job.id}?msg=error&text=#{URI.encode_www_form_component(result[:error])}"
    end
  end

  # POST /aggregated_jobs/:id/reset - Reset aggregation to pending
  post '/aggregated_jobs/:id/reset' do
    @aggregated_job = AggregatedJob.find(params[:id])
    @aggregated_job.reset_aggregation
    redirect "/aggregated_jobs/#{@aggregated_job.id}?msg=success&text=Aggregazione+resettata+a+In+Attesa"
  end

  # DELETE /aggregated_jobs/:id - Delete aggregated job
  delete '/aggregated_jobs/:id' do
    @aggregated_job = AggregatedJob.find(params[:id])
    
    if @aggregated_job.status == 'completed'
      return redirect "/aggregated_jobs?msg=error&text=Non+puoi+eliminare+un+job+completato"
    end

    @aggregated_job.destroy
    redirect '/aggregated_jobs?msg=success&text=Aggregazione+eliminata'
  end

  # GET /aggregated_jobs/:id/print - Print aggregated job card
  get '/aggregated_jobs/:id/print' do
    @aggregated_job = AggregatedJob.find(params[:id])
    @order_items = @aggregated_job.order_items.includes(:order, :assets)
    erb :print_aggregated_job_card, layout: false
  rescue ActiveRecord::RecordNotFound
    status 404
    'Aggregation not found'
  end
end
