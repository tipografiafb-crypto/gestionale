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
    @print_flows = PrintFlow.ordered.select(&:aggregation_capable?)
    @switch_webhooks = SwitchWebhook.ordered
    erb :aggregated_jobs_new
  end

  # Lightweight polling endpoint used by the aggregation detail page.  The
  # page can refresh itself when the asynchronous board creation completes.
  get '/aggregated_jobs/:id/status' do
    content_type :json
    job = AggregatedJob.find(params[:id])
    latest_run = AutomationRun
                  .where("context -> 'aggregation' ->> 'id' = ?", job.id.to_s)
                  .order(created_at: :desc)
                  .first
    JSON.generate(
      id: job.id,
      status: job.status,
      status_label: job.status_label,
      aggregated_file_url: job.aggregated_file_url,
      aggregated_filename: job.aggregated_filename,
      aggregated_at: job.aggregated_at&.iso8601,
      identification_sheet_file_url: job.identification_sheet_file_url,
      updated_at: job.updated_at&.iso8601,
      latest_run_status: latest_run&.status,
      latest_error: latest_run&.error_message
    )
  rescue ActiveRecord::RecordNotFound
    status 404
    JSON.generate(error: 'Aggregazione non trovata')
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
    @aggregation_collection = AutomationGroupCollection
                              .where("metadata ->> 'aggregation_id' = ?", @aggregated_job.id.to_s)
                              .order(created_at: :desc)
                              .first
    @aggregation_runs = AutomationRun
                        .includes(automation_flow_version: :automation_flow)
                        .where("context -> 'aggregation' ->> 'id' = ?", @aggregated_job.id.to_s)
                        .order(created_at: :desc)
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

  # POST /aggregated_jobs/:id/mark_completed - Manually mark as completed
  post '/aggregated_jobs/:id/mark_completed' do
    @aggregated_job = AggregatedJob.find(params[:id])
    @aggregated_job.mark_print_completed
    redirect "/aggregated_jobs/#{@aggregated_job.id}?msg=success&text=Aggregazione+completata"
  end

  # POST /aggregated_jobs/:id/send_aggregation - Create the aggregate board
  post '/aggregated_jobs/:id/send_aggregation' do
    @aggregated_job = AggregatedJob.find(params[:id])
    unless @aggregated_job.status == 'pending'
      return redirect "/aggregated_jobs/#{@aggregated_job.id}?msg=error&text=La+plancia+è+già+stata+avviata"
    end

    result = case @aggregated_job.print_flow&.preprint_executor
             when 'automation'
               @aggregated_job.start_internal_aggregation!
             when 'webhook'
               webhook = @aggregated_job.print_flow.preprint_webhook
               if webhook
                 @aggregated_job.send_aggregation_to_switch(webhook.hook_path)
               else
                 {success: false, error: 'Webhook Aggregazione non configurato'}
               end
             else
               {success: false, error: 'Azione Aggregazione non configurata'}
             end

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

  # POST /aggregated_jobs/:id/send_print - Send the completed board to print
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
    
    machine = @aggregated_job.print_flow&.print_machines&.find_by(id: print_machine_id)
    unless machine
      return redirect "/aggregated_jobs/#{@aggregated_job.id}?msg=error&text=Stampante+non+disponibile+nel+flusso"
    end

    result = case @aggregated_job.print_flow.print_executor
             when 'automation'
               @aggregated_job.start_internal_file_operation!('print', print_machine: machine)
             when 'webhook'
               webhook = @aggregated_job.print_flow.print_webhook
               webhook ? @aggregated_job.send_to_switch_operation('print', machine.id, webhook.hook_path) :
                         {success: false, error: 'Webhook Stampa non configurato'}
             else
               {success: false, error: 'Azione Stampa non configurata'}
             end

    if result[:success]
      redirect "/aggregated_jobs/#{@aggregated_job.id}?msg=success&text=#{URI.encode_www_form_component(result[:message])}"
    else
      redirect "/aggregated_jobs/#{@aggregated_job.id}?msg=error&text=#{URI.encode_www_form_component(result[:error])}"
    end
  end

  # POST /aggregated_jobs/:id/send_label - Send aggregated file to Switch for label
  post '/aggregated_jobs/:id/send_label' do
    @aggregated_job = AggregatedJob.find(params[:id])
    
    unless @aggregated_job.status == 'preview_pending'
      return redirect "/aggregated_jobs/#{@aggregated_job.id}?msg=error&text=Job+non+in+anteprima"
    end

    result = case @aggregated_job.print_flow&.label_executor
             when 'automation'
               {success: false, error: 'Per l’etichetta interna seleziona prima una macchina di stampa'}
             when 'webhook'
               webhook = @aggregated_job.print_flow.label_webhook
               webhook ? @aggregated_job.send_to_switch_operation('label', nil, webhook.hook_path) :
                         {success: false, error: 'Webhook Etichetta non configurato'}
             else
               {success: false, error: 'Azione Etichetta non configurata'}
             end
    
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

  # DELETE /aggregated_jobs/:id - Delete aggregated job (allowed for any status)
  delete '/aggregated_jobs/:id' do
    @aggregated_job = AggregatedJob.find(params[:id])
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
