# @feature invoices
# @domain web

class PrintOrchestrator < Sinatra::Base
  get '/invoices' do
    @filter_query = params[:q].to_s.strip
    @filter_status = InvoiceRequest::STATUSES.include?(params[:status]) ? params[:status] : ''

    scope = InvoiceRequest.includes(order: :store).recent
    scope = scope.matching(@filter_query)
    scope = scope.with_status(@filter_status)

    @per_page = 25
    @total_count = scope.count
    @total_pages = [(@total_count.to_f / @per_page).ceil, 1].max
    @current_page = [[params.fetch(:page, 1).to_i, 1].max, @total_pages].min
    @invoice_requests = scope.offset((@current_page - 1) * @per_page).limit(@per_page)
    @status_counts = InvoiceRequest.group(:status).count

    erb :invoices_list
  end

  get '/invoices/:id' do
    @invoice_request = InvoiceRequest.includes(order: [:store, :order_items]).find(params[:id])
    erb :invoice_detail
  rescue ActiveRecord::RecordNotFound
    status 404
    erb :not_found
  end

  put '/invoices/:id' do
    invoice_request = InvoiceRequest.find(params[:id])
    new_status = params[:status].to_s
    unless InvoiceRequest::STATUSES.include?(new_status)
      redirect "/invoices/#{invoice_request.id}?msg=error&text=Stato+fattura+non+valido"
    end

    invoice_request.update!(
      status: new_status,
      status_changed_at: Time.current,
      issued_at: new_status == 'issued' ? (invoice_request.issued_at || Time.current) : nil,
      notes: params[:notes].to_s.strip.presence
    )
    redirect "/invoices/#{invoice_request.id}?msg=success&text=Stato+aggiornato"
  rescue ActiveRecord::RecordNotFound
    status 404
    erb :not_found
  end

  delete '/invoices/:id' do
    invoice_request = InvoiceRequest.find(params[:id])
    invoice_request.destroy!
    redirect '/invoices?msg=success&text=Richiesta+fattura+cancellata'
  rescue ActiveRecord::RecordNotFound
    status 404
    erb :not_found
  end
end
