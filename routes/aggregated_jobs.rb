# @feature aggregation
# @domain web-ui
# Routes for managing aggregated jobs

class PrintOrchestrator < Sinatra::Base
  # GET /aggregated_jobs - List all aggregated jobs
  get '/aggregated_jobs' do
    @aggregated_jobs = AggregatedJob.order(created_at: :desc)
    @statuses = ['pending', 'sent', 'completed', 'failed']
    erb :aggregated_jobs_list
  end

  # GET /aggregated_jobs/new - Form to create aggregated job
  get '/aggregated_jobs/new' do
    # Mostra solo order items con preprint completato
    @available_items = OrderItem.where(preprint_status: 'completed', print_status: 'pending').includes(:order).order(created_at: :desc)
    @print_flows = PrintFlow.ordered
    erb :aggregated_jobs_new
  end

  # POST /aggregated_jobs - Create aggregated job from selected items
  post '/aggregated_jobs' do
    item_ids = params[:item_ids] || []
    return redirect '/aggregated_jobs/new?msg=error&text=Seleziona+almeno+2+line+items' if item_ids.count < 2

    begin
      items = OrderItem.where(id: item_ids, preprint_status: 'completed')
      return redirect '/aggregated_jobs/new?msg=error&text=Alcuni+item+non+hanno+preprint+completato' if items.count != item_ids.count

      job = AggregatedJob.create_from_items(items, params[:name])
      redirect "/aggregated_jobs?msg=success&text=Aggregazione+creata+con+#{items.count}+file"
    rescue => e
      redirect "/aggregated_jobs/new?msg=error&text=Errore:+#{e.message}"
    end
  end

  # GET /aggregated_jobs/:id - View aggregated job details
  get '/aggregated_jobs/:id' do
    @aggregated_job = AggregatedJob.find(params[:id])
    @order_items = @aggregated_job.order_items.includes(:order)
    erb :aggregated_job_detail
  end

  # POST /aggregated_jobs/:id/send - Send aggregated job to Switch
  post '/aggregated_jobs/:id/send' do
    @aggregated_job = AggregatedJob.find(params[:id])
    
    if @aggregated_job.status != 'pending'
      redirect "/aggregated_jobs/#{@aggregated_job.id}?msg=error&text=Job+già+inviato"
    end

    result = @aggregated_job.send_to_switch
    
    if result[:success]
      redirect "/aggregated_jobs/#{@aggregated_job.id}?msg=success&text=#{result[:message]}"
    else
      redirect "/aggregated_jobs/#{@aggregated_job.id}?msg=error&text=#{result[:error]}"
    end
  end

  # DELETE /aggregated_jobs/:id - Delete aggregated job
  delete '/aggregated_jobs/:id' do
    @aggregated_job = AggregatedJob.find(params[:id])
    
    if @aggregated_job.status != 'pending'
      return redirect "/aggregated_jobs?msg=error&text=Non+puoi+eliminare+un+job+già+inviato"
    end

    @aggregated_job.destroy
    redirect '/aggregated_jobs?msg=success&text=Aggregazione+eliminata'
  end
end
