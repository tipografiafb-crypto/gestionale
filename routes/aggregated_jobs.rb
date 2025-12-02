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
    return redirect '/aggregated_jobs/new?msg=error&text=Seleziona+almeno+2+line+items' if item_ids.count < 2

    begin
      items = OrderItem.where(id: item_ids, preprint_status: 'completed')
      return redirect '/aggregated_jobs/new?msg=error&text=Alcuni+item+non+hanno+preprint+completato' if items.count != item_ids.count

      job = AggregatedJob.create_from_items(
        items, 
        name: params[:name], 
        print_flow_id: params[:print_flow_id].presence
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
    erb :aggregated_job_detail
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

  # POST /aggregated_jobs/:id/send_print - Send aggregated file to Switch for printing
  post '/aggregated_jobs/:id/send_print' do
    @aggregated_job = AggregatedJob.find(params[:id])
    webhook_path = params[:webhook_path]
    
    unless webhook_path.present?
      return redirect "/aggregated_jobs/#{@aggregated_job.id}?msg=error&text=Seleziona+un+webhook+per+la+stampa"
    end
    
    unless @aggregated_job.status == 'aggregated'
      return redirect "/aggregated_jobs/#{@aggregated_job.id}?msg=error&text=Il+file+aggregato+non+è+ancora+pronto"
    end

    result = @aggregated_job.send_print_to_switch(webhook_path)
    
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
end
