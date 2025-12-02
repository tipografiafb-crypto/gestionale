# @feature aggregation
# @domain data-models
# AggregatedJob model - Groups multiple line items into a single job for Switch processing
class AggregatedJob < ActiveRecord::Base
  has_many :aggregated_job_items, dependent: :destroy
  has_many :order_items, through: :aggregated_job_items
  belongs_to :print_flow, optional: true
  
  validates :name, presence: true
  
  # Statuses: pending, aggregating, preview_pending, aggregated, printing, completed, failed
  # Flow: pending -> aggregating -> preview_pending (await approval) -> aggregated -> printing -> completed
  STATUSES = %w[pending aggregating preview_pending aggregated printing completed failed].freeze
  
  scope :pending, -> { where(status: 'pending') }
  scope :aggregating, -> { where(status: 'aggregating') }
  scope :preview_pending, -> { where(status: 'preview_pending') }
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
  
  # Auto-send aggregation (used when pending job needs to aggregate)
  def send_aggregation_first
    return unless status == 'pending' && print_flow.present?
    return unless print_flow.preprint_webhook.present?
    
    # Use preprint webhook for aggregation
    webhook = print_flow.preprint_webhook
    send_aggregation_to_switch(webhook.hook_path)
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
  
  # Called by Switch when aggregated file is ready (with URL)
  def receive_aggregated_file(file_url, filename = nil)
    update(
      status: 'preview_pending',
      aggregated_file_url: file_url,
      aggregated_filename: filename || File.basename(file_url),
      aggregated_at: Time.current
    )
  end
  
  # Receive aggregated file from base64 and save locally
  def receive_aggregated_file_from_base64(file_base64, filename = 'aggregated.pdf')
    begin
      # Decode base64
      file_content = Base64.decode64(file_base64)
      
      # Create storage/aggregated directory
      dir = File.join(Dir.pwd, 'storage', 'aggregated')
      FileUtils.mkdir_p(dir) unless Dir.exist?(dir)
      
      # Save file with filename from Switch
      local_filename = filename.present? ? filename : "agg_#{id}.pdf"
      local_path = File.join(dir, local_filename)
      File.write(local_path, file_content)
      
      puts "[AGGREGATED_JOB] Saved file to: #{local_path}"
      
      # Update job with file info - use filename received from Switch
      update(
        status: 'preview_pending',
        aggregated_file_url: "/file/agg_#{id}/#{local_filename}",
        aggregated_filename: filename,
        aggregated_at: Time.current,
        notes: local_filename
      )
      
      { success: true, message: 'File saved locally' }
    rescue => e
      puts "[AGGREGATED_JOB_ERROR] Failed to save base64 file: #{e.message}"
      puts "[AGGREGATED_JOB_ERROR] Backtrace: #{e.backtrace.first(5).join("\n")}"
      { success: false, error: e.message }
    end
  end
  
  # Send aggregated file to Switch for an operation (preprint, print, label)
  def send_to_switch_operation(operation)
    # Se in pending, aggregare prima. Se in preview_pending, procedere direttamente
    if status == 'pending'
      # Auto-aggregate first from pending items
      send_aggregation_first
    end
    
    return { success: false, error: 'Job non in preview_pending' } unless status == 'preview_pending'
    return { success: false, error: 'File aggregato non disponibile' } unless aggregated_file_url.present?
    return { success: false, error: 'Flusso di stampa non assegnato' } unless print_flow.present?
    
    # Get webhook from print_flow based on operation
    webhook = case operation
              when 'preprint'
                print_flow.preprint_webhook
              when 'print'
                print_flow.print_webhook
              when 'label'
                print_flow.label_webhook
              else
                nil
              end
    
    return { success: false, error: "Webhook per #{operation} non configurato nel flusso" } unless webhook.present?
    
    server_url = ENV['SERVER_BASE_URL'] || 'http://localhost:5000'
    
    operation_map = { 'preprint' => 1, 'print' => 2, 'label' => 3 }
    operation_id = operation_map[operation] || 2
    
    payload = {
      aggregated_job_id: id,
      nr_files: 1,
      id_riga: id,
      codice_ordine: "AGG-#{id}",
      product: name,
      operation_id: operation_id,
      job_operation_id: "agg-#{operation}-#{id}",
      url: aggregated_file_url,
      widegest_url: "#{server_url}/api/v1/aggregation_callback",
      filename: aggregated_filename || "aggregated_#{id}.pdf",
      scala: '1:1',
      quantita: order_items.sum(:quantity),
      materiale: order_items.first&.product&.notes || '',
      campi_custom: {},
      taglio: false,
      stampa: true,
      plancia: false,
      larghezza: 0.0,
      altezza: 0.0
    }
    
    result = SwitchClient.send_to_switch(webhook_path: webhook.hook_path, job_data: payload)
    
    if result[:success]
      { success: true, message: "File aggregato inviato per #{operation}" }
    else
      { success: false, error: result[:error] }
    end
  end
  
  # Called when print is completed
  def mark_print_completed
    update(status: 'completed', completed_at: Time.current)
    
    # Update all order items
    order_items.each do |item|
      item.update(print_status: 'completed')
    end
  end
  
  # Reset aggregation to pending state (clear aggregation data)
  def reset_aggregation
    update(
      status: 'pending',
      aggregated_file_url: nil,
      aggregated_filename: nil,
      sent_at: nil,
      aggregated_at: nil,
      completed_at: nil
    )
  end
  
  def status_label
    case status
    when 'pending' then 'In Attesa'
    when 'aggregating' then 'Aggregazione in corso'
    when 'preview_pending' then 'In Anteprima'
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
    when 'preview_pending' then 'warning'
    when 'aggregated' then 'success'
    when 'printing' then 'primary'
    when 'completed' then 'success'
    when 'failed' then 'danger'
    else 'secondary'
    end
  end
end
