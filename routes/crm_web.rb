# @feature crm
# @domain ui
# CRM routes - Dashboard for customer management, sales analysis

class PrintOrchestrator < Sinatra::Base

  # GET /crm - CRM Dashboard
  get '/crm' do
    @store_id = params[:store_id]
    
    # Base queries
    customers = Customer.all
    sales = Sale.all
    
    # Apply store filter if present
    if @store_id.present?
      customers = customers.by_store(@store_id)
      sales = sales.by_store(@store_id)
    end

    @total_customers = customers.count
    @total_sales = sales.count
    @total_revenue = sales.sum(:total)
    @avg_order_value = @total_sales > 0 ? (@total_revenue / @total_sales).round(2) : 0

    # Top 10 customers by spending
    @top_customers = customers.top_spenders.limit(10)

    # Recent sales
    @recent_sales = sales.recent.includes(:customer, :store).limit(10)

    # Revenue metrics
    @revenue_30d = sales.where('order_date >= ?', 30.days.ago).sum(:total)
    @orders_30d = sales.where('order_date >= ?', 30.days.ago).count

    @revenue_7d = sales.where('order_date >= ?', 7.days.ago).sum(:total)
    @orders_7d = sales.where('order_date >= ?', 7.days.ago).count

    @stores = Store.active.ordered

    erb :crm_dashboard
  end

  # GET /crm/customers - Customers list
  get '/crm/customers' do
    @customers = Customer.ordered
    @customers = @customers.search(params[:q]) if params[:q].present?
    @customers = @customers.by_store(params[:store_id]) if params[:store_id].present?

    case params[:sort]
    when 'spent_desc'
      @customers = @customers.reorder(total_spent: :desc)
    when 'spent_asc'
      @customers = @customers.reorder(total_spent: :asc)
    when 'orders_desc'
      @customers = @customers.reorder(order_count: :desc)
    when 'recent'
      @customers = @customers.reorder(last_order_at: :desc)
    end

    @stores = Store.active.ordered
    erb :crm_customers
  end

  # GET /crm/customers/:id - Customer detail
  get '/crm/customers/:id' do
    @customer = Customer.find(params[:id])
    @sales = @customer.sales.recent.includes(:store, :sale_items)
    erb :crm_customer_detail
  rescue ActiveRecord::RecordNotFound
    redirect '/crm/customers'
  end

  # POST /crm/customers/:id/notes - Update customer notes
  post '/crm/customers/:id/notes' do
    customer = Customer.find(params[:id])
    customer.update(notes: params[:notes])
    redirect "/crm/customers/#{customer.id}"
  rescue ActiveRecord::RecordNotFound
    redirect '/crm/customers'
  end

  # GET /crm/sales - Sales list
  get '/crm/sales' do
    @sales = Sale.recent.includes(:customer, :store)
    @sales = @sales.by_store(params[:store_id]) if params[:store_id].present?

    if params[:start_date].present? && params[:end_date].present?
      start_date = Date.parse(params[:start_date])
      end_date = Date.parse(params[:end_date])
      @sales = @sales.by_date_range(start_date, end_date)
    end

    if params[:q].present?
      @sales = @sales.where('external_order_code ILIKE ?', "%#{params[:q]}%")
    end

    @stores = Store.active.ordered
    @filter_start_date = params[:start_date]
    @filter_end_date = params[:end_date]
    erb :crm_sales
  end

  # GET /api/crm/revenue-chart - Revenue chart data
  get '/api/crm/revenue-chart' do
    content_type :json

    start_date = params[:start_date].present? ? Date.parse(params[:start_date]) : (Date.today - 30)
    end_date = params[:end_date].present? ? Date.parse(params[:end_date]) : Date.today

    sales = Sale.by_date_range(start_date, end_date)
    sales = sales.by_store(params[:store_id]) if params[:store_id].present?

    data = {}
    (start_date..end_date).each { |d| data[d.to_s] = 0 }

    sales.each do |sale|
      date = sale.order_date&.to_date&.to_s
      data[date] = (data[date] || 0) + (sale.total || 0).to_f if date && data.key?(date)
    end

    {
      labels: data.keys,
      data: data.values.map { |v| v.round(2) }
    }.to_json
  end
end
