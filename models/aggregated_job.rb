# @feature aggregation
# @domain data-models
# AggregatedJob model - Groups multiple line items into a single job for Switch processing
class AggregatedJob < ActiveRecord::Base
  has_many :aggregated_job_items, dependent: :destroy
  has_many :order_items, through: :aggregated_job_items
  belongs_to :print_flow, optional: true
  
  validates :name, presence: true
  
  # Statuses: pending, aggregating, aggregated, printing, completed, failed
  # Flow: pending -> aggregating (sent to Switch) -> aggregated (file received) -> printing -> completed
  STATUSES = %w[pending aggregating aggregated printing completed failed].freeze
  
  scope :pending, -> { where(status: 'pending') }
  scope :aggregating, -> { where(status: 'aggregating') }
  scope :aggregated, -> { where(status: 'aggregated') }
  scope :ready_for_print, -> { where(status: 'aggregated') }
  scope :printing, -> { where(status: 'printing') }
  scope :completed, -> { where(status: 'completed') }
  
  def self.create_from_items(order_items, name: nil, print_flow_id: nil)
    job = create!(
      name: name.presence || "Aggregazione #{Time.current.strftime('%d-%m-%Y %H:%M')}",
      status: 'pending',
      nr_files: order_items.count,
      print_flow_id: print_flow_id
    )
    
    order_items.each do |item|
      job.aggregated_job_items.create!(order_item_id: item.id)
    end
    
    job
  end
  
  # Send aggregation request to Switch (step 1: aggregate files)
  def send_aggregation_to_switch(webhook_path)
    return { success: false, error: 'Job non pronto per l\'invio' } unless status == 'pending'
    return { success: false, error: 'Webhook non specificato' } unless webhook_path.present?
    
    errors = []
    successful_count = 0
    server_url = ENV['SERVER_BASE_URL'] || 'http://localhost:5000'
    
    aggregated_job_items.each_with_index do |aji, index|
      order_item = aji.order_item
      next unless order_item.preprint_status == 'completed'
      
      # Prendi il file dalla pre-stampa (asset type 'preprint' o ultimo asset disponibile)
      preprint_asset = order_item.assets.where(asset_type: 'preprint').first || 
                       order_item.assets.order(created_at: :desc).first
      next unless preprint_asset
      
      product = order_item.product
      
      payload = {
        aggregated_job_id: id,
        nr_files: nr_files,
        file_index: index + 1,
        id_riga: order_item.id,
        codice_ordine: order_item.order.external_order_code,
        product: product ? "#{product.sku} - #{product.name}" : order_item.sku,
        operation_id: 4, # 4 = aggregation
        job_operation_id: "agg-#{id}-item-#{order_item.id}",
        url: "#{server_url}/api/assets/#{preprint_asset.id}/download",
        widegest_url: "#{server_url}/api/v1/aggregation_callback",
        filename: preprint_asset.filename_from_url || "agg_#{id}_#{index + 1}.png",
        scala: order_item.json_data&.dig('scala') || '1:1',
        quantita: order_item.quantity,
        materiale: product&.notes || order_item.json_data&.dig('materiale') || '',
        campi_custom: order_item.json_data&.dig('campi_custom') || {},
        taglio: order_item.json_data&.dig('taglio') == true,
        stampa: true,
        plancia: order_item.json_data&.dig('plancia') == true,
        larghezza: (order_item.json_data&.dig('larghezza') || 0).to_f,
        altezza: (order_item.json_data&.dig('altezza') || 0).to_f
      }
      
      result = SwitchClient.send_to_switch(webhook_path: webhook_path, job_data: payload)
      
      if result[:success]
        successful_count += 1
      else
        errors << "Item #{order_item.id}: #{result[:error]}"
      end
    end
    
    if successful_count > 0
      update(status: 'aggregating', sent_at: Time.current)
      { success: true, message: "#{successful_count}/#{nr_files} file inviati per aggregazione" }
    else
      update(status: 'failed')
      { success: false, error: errors.join(', ').presence || 'Nessun file inviato' }
    end
  end
  
  # Send print request to Switch (step 2: print aggregated file)
  def send_print_to_switch(webhook_path)
    return { success: false, error: 'Job non pronto per la stampa' } unless status == 'aggregated'
    return { success: false, error: 'File aggregato non disponibile' } unless aggregated_file_url.present?
    return { success: false, error: 'Webhook non specificato' } unless webhook_path.present?
    
    server_url = ENV['SERVER_BASE_URL'] || 'http://localhost:5000'
    first_item = order_items.first
    
    payload = {
      aggregated_job_id: id,
      nr_files: 1,
      id_riga: id,
      codice_ordine: "AGG-#{id}",
      product: name,
      operation_id: 2, # 2 = print
      job_operation_id: "agg-print-#{id}",
      url: aggregated_file_url,
      widegest_url: "#{server_url}/api/v1/aggregation_print_callback",
      filename: aggregated_filename || "aggregated_#{id}.pdf",
      scala: '1:1',
      quantita: order_items.sum(:quantity),
      materiale: first_item&.product&.notes || '',
      campi_custom: {},
      taglio: false,
      stampa: true,
      plancia: false,
      larghezza: 0.0,
      altezza: 0.0
    }
    
    result = SwitchClient.send_to_switch(webhook_path: webhook_path, job_data: payload)
    
    if result[:success]
      update(status: 'printing')
      { success: true, message: 'File aggregato inviato a stampa' }
    else
      { success: false, error: result[:error] }
    end
  end
  
  # Called by Switch when aggregated file is ready
  def receive_aggregated_file(file_url, filename = nil)
    update(
      status: 'aggregated',
      aggregated_file_url: file_url,
      aggregated_filename: filename || File.basename(file_url),
      aggregated_at: Time.current
    )
  end
  
  # Called when print is completed
  def mark_print_completed
    update(status: 'completed', completed_at: Time.current)
    
    # Update all order items
    order_items.each do |item|
      item.update(print_status: 'completed')
    end
  end
  
  def status_label
    case status
    when 'pending' then 'In Attesa'
    when 'aggregating' then 'Aggregazione in corso'
    when 'aggregated' then 'Pronto per stampa'
    when 'printing' then 'In stampa'
    when 'completed' then 'Completato'
    when 'failed' then 'Fallito'
    else status.capitalize
    end
  end
  
  def status_color
    case status
    when 'pending' then 'secondary'
    when 'aggregating' then 'info'
    when 'aggregated' then 'warning'
    when 'printing' then 'primary'
    when 'completed' then 'success'
    when 'failed' then 'danger'
    else 'secondary'
    end
  end
end
