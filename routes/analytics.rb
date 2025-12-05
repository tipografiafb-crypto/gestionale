# @feature analytics
# @domain ui
# Analytics routes - Dashboard for sales analysis and inventory insights

class PrintOrchestrator < Sinatra::Base

  # GET /analytics - Main dashboard
  get '/analytics' do
    # Default date range: last 30 days
    end_date = Date.today
    start_date = params[:start_date].present? ? Date.parse(params[:start_date]) : (end_date - 30)
    
    # Build query for orders in date range
    @orders = Order.where('created_at >= ? AND created_at <= ?', 
                          start_date.beginning_of_day, 
                          end_date.end_of_day)
    
    # Get all order items for this period
    order_ids = @orders.pluck(:id)
    @items = OrderItem.where(order_id: order_ids)
    
    # Total statistics
    @total_orders = @orders.count
    @total_items = @items.count
    @total_quantity = @items.sum(:quantity)
    
    # Calculate period data for charts
    @period_start = start_date
    @period_end = end_date
    @filter_start_date = params[:start_date] || start_date.to_s
    @filter_end_date = params[:end_date] || end_date.to_s
    
    erb :analytics
  end

  # GET /api/analytics/daily - Daily sales data
  get '/api/analytics/daily' do
    content_type :json
    
    start_date = params[:start_date].present? ? Date.parse(params[:start_date]) : (Date.today - 30)
    end_date = params[:end_date].present? ? Date.parse(params[:end_date]) : Date.today
    
    # Get orders grouped by date
    orders = Order.where('created_at >= ? AND created_at <= ?', 
                         start_date.beginning_of_day, 
                         end_date.end_of_day)
    
    data = {}
    (start_date..end_date).each do |date|
      data[date.to_s] = 0
    end
    
    # Group by date and sum quantities
    orders.includes(:order_items).each do |order|
      date = order.created_at.to_date.to_s
      quantity = order.order_items.sum(:quantity)
      data[date] = (data[date] || 0) + quantity
    end
    
    {
      labels: data.keys,
      data: data.values
    }.to_json
  end

  # GET /api/analytics/by-product - Sales by product type
  get '/api/analytics/by-product' do
    content_type :json
    
    start_date = params[:start_date].present? ? Date.parse(params[:start_date]) : (Date.today - 30)
    end_date = params[:end_date].present? ? Date.parse(params[:end_date]) : Date.today
    
    order_ids = Order.where('created_at >= ? AND created_at <= ?',
                            start_date.beginning_of_day,
                            end_date.end_of_day).pluck(:id)
    
    # Group by SKU and sum quantities
    product_sales = OrderItem
      .where(order_id: order_ids)
      .group(:sku)
      .select('sku, SUM(quantity) as total_quantity, COUNT(*) as order_count')
      .order('total_quantity DESC')
      .limit(15)
    
    labels = []
    quantities = []
    order_counts = []
    
    product_sales.each do |sale|
      product = Product.find_by(sku: sale.sku)
      labels << "#{product&.name || sale.sku} (#{sale.sku})"
      quantities << sale.total_quantity.to_i
      order_counts << sale.order_count
    end
    
    {
      labels: labels,
      quantities: quantities,
      orders: order_counts
    }.to_json
  end

  # GET /api/analytics/by-category - Sales by product category
  get '/api/analytics/by-category' do
    content_type :json
    
    start_date = params[:start_date].present? ? Date.parse(params[:start_date]) : (Date.today - 30)
    end_date = params[:end_date].present? ? Date.parse(params[:end_date]) : Date.today
    
    order_ids = Order.where('created_at >= ? AND created_at <= ?',
                            start_date.beginning_of_day,
                            end_date.end_of_day).pluck(:id)
    
    # Get items and group by product category
    items = OrderItem.where(order_id: order_ids).includes(:order)
    
    category_data = {}
    
    items.each do |item|
      product = Product.find_by(sku: item.sku)
      category = product&.product_category&.name || 'Non categorizzato'
      
      category_data[category] ||= 0
      category_data[category] += item.quantity
    end
    
    # Sort by quantity descending
    sorted = category_data.sort_by { |_, v| v }.reverse.to_h
    
    {
      labels: sorted.keys,
      data: sorted.values
    }.to_json
  end

  # GET /api/analytics/comparison - Week-over-week comparison
  get '/api/analytics/comparison' do
    content_type :json
    
    end_date = Date.today
    
    # Current week
    current_week_start = end_date.beginning_of_week
    current_week_end = end_date.end_of_week
    
    # Previous week
    prev_week_end = current_week_start - 1.day
    prev_week_start = prev_week_end.beginning_of_week
    
    current_orders = Order.where('created_at >= ? AND created_at <= ?',
                                 current_week_start.beginning_of_day,
                                 current_week_end.end_of_day)
    prev_orders = Order.where('created_at >= ? AND created_at <= ?',
                              prev_week_start.beginning_of_day,
                              prev_week_end.end_of_day)
    
    current_qty = current_orders.includes(:order_items).sum { |o| o.order_items.sum(:quantity) }
    prev_qty = prev_orders.includes(:order_items).sum { |o| o.order_items.sum(:quantity) }
    
    {
      current_week: {
        label: "Questa settimana (#{current_week_start.strftime('%d/%m')} - #{current_week_end.strftime('%d/%m')})",
        quantity: current_qty,
        orders: current_orders.count
      },
      previous_week: {
        label: "Settimana precedente (#{prev_week_start.strftime('%d/%m')} - #{prev_week_end.strftime('%d/%m')})",
        quantity: prev_qty,
        orders: prev_orders.count
      },
      change_percent: prev_qty.zero? ? 0 : ((current_qty - prev_qty).to_f / prev_qty * 100).round(1)
    }.to_json
  end

  # GET /api/analytics/top-products - Top 10 products by quantity
  get '/api/analytics/top-products' do
    content_type :json
    
    start_date = params[:start_date].present? ? Date.parse(params[:start_date]) : (Date.today - 30)
    end_date = params[:end_date].present? ? Date.parse(params[:end_date]) : Date.today
    
    order_ids = Order.where('created_at >= ? AND created_at <= ?',
                            start_date.beginning_of_day,
                            end_date.end_of_day).pluck(:id)
    
    top_products = OrderItem
      .where(order_id: order_ids)
      .group(:sku)
      .select('sku, SUM(quantity) as total_quantity')
      .order('total_quantity DESC')
      .limit(10)
    
    products_data = top_products.map do |item|
      product = Product.find_by(sku: item.sku)
      {
        sku: item.sku,
        name: product&.name || item.sku,
        quantity: item.total_quantity
      }
    end
    
    {
      products: products_data
    }.to_json
  end
end
