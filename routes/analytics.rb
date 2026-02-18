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
    
    # Filter by product if specified
    if params[:product_id].present?
      product = Product.find_by(id: params[:product_id])
      if product
        @items = @items.where(sku: product.sku)
      end
    end
    
    # Filter by category if specified
    if params[:category_id].present?
      category = ProductCategory.find_by(id: params[:category_id])
      if category
        product_skus = Product.where(product_category_id: category.id).pluck(:sku)
        @items = @items.where(sku: product_skus)
      end
    end
    
    # Total statistics
    @total_orders = @orders.count
    @total_items = @items.count
    @total_quantity = @items.sum(:quantity)
    
    # For display
    @product_categories = ProductCategory.where(active: true).ordered
    @products = Product.where(active: true).ordered
    @filter_start_date = params[:start_date] || start_date.to_s
    @filter_end_date = params[:end_date] || end_date.to_s
    @filter_product_id = params[:product_id]
    @filter_category_id = params[:category_id]
    
    # Calculate period data for charts
    @period_start = start_date
    @period_end = end_date
    
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
    
    # Get order items with optional product/category filter
    order_ids = orders.pluck(:id)
    items = OrderItem.where(order_id: order_ids)
    
    if params[:product_id].present?
      product = Product.find_by(id: params[:product_id])
      items = items.where(sku: product.sku) if product
    end
    
    if params[:category_id].present?
      category = ProductCategory.find_by(id: params[:category_id])
      if category
        product_skus = Product.where(product_category_id: category.id).pluck(:sku)
        items = items.where(sku: product_skus)
      end
    end
    
    data = {}
    (start_date..end_date).each do |date|
      data[date.to_s] = 0
    end
    
    # Group by date and sum quantities
    items_by_order = items.group_by { |item| item.order_id }
    Order.where(id: items_by_order.keys).each do |order|
      date = order.created_at.to_date.to_s
      quantity = items_by_order[order.id].sum(&:quantity)
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
    
    items = OrderItem.where(order_id: order_ids)
    
    if params[:product_id].present?
      product = Product.find_by(id: params[:product_id])
      items = items.where(sku: product.sku) if product
    end
    
    if params[:category_id].present?
      category = ProductCategory.find_by(id: params[:category_id])
      if category
        product_skus = Product.where(product_category_id: category.id).pluck(:sku)
        items = items.where(sku: product_skus)
      end
    end
    
    # Group by SKU and sum quantities
    product_sales = items
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
    
    if params[:product_id].present?
      product = Product.find_by(id: params[:product_id])
      items = items.where(sku: product.sku) if product
    end
    
    if params[:category_id].present?
      category = ProductCategory.find_by(id: params[:category_id])
      if category
        product_skus = Product.where(product_category_id: category.id).pluck(:sku)
        items = items.where(sku: product_skus)
      end
    end
    
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

  # GET /api/analytics/comparison - Period-over-period comparison
  get '/api/analytics/comparison' do
    content_type :json
    
    end_date = params[:end_date].present? ? Date.parse(params[:end_date]) : Date.today
    start_date = params[:start_date].present? ? Date.parse(params[:start_date]) : (end_date - 7)
    
    duration = (end_date - start_date).to_i + 1
    
    # Current period
    current_start = start_date
    current_end = end_date
    
    # Previous period (same duration)
    prev_end = current_start - 1.day
    prev_start = prev_end - (duration - 1).days
    
    current_orders = Order.where('created_at >= ? AND created_at <= ?',
                                 current_start.beginning_of_day,
                                 current_end.end_of_day)
    prev_orders = Order.where('created_at >= ? AND created_at <= ?',
                              prev_start.beginning_of_day,
                              prev_end.end_of_day)
    
    # Apply filters if specified
    current_items = OrderItem.where(order_id: current_orders.pluck(:id))
    prev_items = OrderItem.where(order_id: prev_orders.pluck(:id))
    
    if params[:product_id].present?
      product = Product.find_by(id: params[:product_id])
      if product
        current_items = current_items.where(sku: product.sku)
        prev_items = prev_items.where(sku: product.sku)
      end
    end
    
    if params[:category_id].present?
      category = ProductCategory.find_by(id: params[:category_id])
      if category
        product_skus = Product.where(product_category_id: category.id).pluck(:sku)
        current_items = current_items.where(sku: product_skus)
        prev_items = prev_items.where(sku: product_skus)
      end
    end
    
    current_qty = current_items.sum(:quantity)
    prev_qty = prev_items.sum(:quantity)
    
    {
      current_period: {
        label: "Periodo selezionato (#{current_start.strftime('%d/%m')} - #{current_end.strftime('%d/%m')})",
        quantity: current_qty,
        orders: current_orders.count
      },
      previous_period: {
        label: "Periodo precedente (#{prev_start.strftime('%d/%m')} - #{prev_end.strftime('%d/%m')})",
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
    
    items = OrderItem.where(order_id: order_ids)
    
    if params[:product_id].present?
      product = Product.find_by(id: params[:product_id])
      items = items.where(sku: product.sku) if product
    end
    
    if params[:category_id].present?
      category = ProductCategory.find_by(id: params[:category_id])
      if category
        product_skus = Product.where(product_category_id: category.id).pluck(:sku)
        items = items.where(sku: product_skus)
      end
    end
    
    top_products = items
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
