# @feature aggregation
# @domain data-models
# AggregatedJob model - Groups multiple line items into a single job for Switch processing
class AggregatedJob < ActiveRecord::Base
  has_many :aggregated_job_items, dependent: :destroy
  has_many :order_items, through: :aggregated_job_items
  belongs_to :print_flow, optional: true
  belongs_to :aggregation_job, class_name: 'SwitchJob', foreign_key: 'aggregation_job_id', optional: true
  
  validates :name, presence: true
  
  # Statuses: pending, sent, completed, failed
  scope :pending, -> { where(status: 'pending') }
  scope :sent, -> { where(status: 'sent') }
  scope :completed, -> { where(status: 'completed') }
  
  def self.create_from_items(order_items, name = nil)
    job = create!(
      name: name || "Aggregazione #{Time.current.strftime('%d-%m-%Y %H:%M')}",
      status: 'pending',
      nr_files: order_items.count
    )
    
    order_items.each do |item|
      job.aggregated_job_items.create!(order_item_id: item.id)
    end
    
    job
  end
  
  def send_to_switch
    return { success: false, error: 'Job non pronto per l\'invio' } if status != 'pending'
    
    aggregated_job_id = id
    nr_files = aggregated_job_items.count
    payloads = []
    
    aggregated_job_items.each_with_index do |item, index|
      order_item = item.order_item
      next unless order_item.preprint_status == 'completed'
      
      # Prendi il file dalla pre-stampa
      preprint_asset = order_item.assets.where(asset_type: 'preprint').first
      next unless preprint_asset
      
      payload = build_aggregation_payload(order_item, preprint_asset, aggregated_job_id, nr_files, index + 1)
      payloads << payload
    end
    
    return { success: false, error: 'Nessun file disponibile' } if payloads.empty?
    
    # Invia a Switch
    begin
      payloads.each do |payload|
        SwitchWebhookClient.send_aggregated_job(payload)
      end
      
      update(status: 'sent', sent_at: Time.current)
      { success: true, message: "#{payloads.count} file inviati a Switch" }
    rescue => e
      { success: false, error: e.message }
    end
  end
  
  private
  
  def build_aggregation_payload(order_item, asset, aggregated_job_id, nr_files, index)
    {
      aggregated_job_id: aggregated_job_id,
      nr_files: nr_files,
      file_index: index,
      id_riga: order_item.id,
      codice_ordine: order_item.order.code,
      product: order_item.sku,
      operation_id: 2,
      job_operation_id: order_item.preprint_job&.switch_job_id,
      url: asset.download_url,
      widegest_url: ENV['SWITCH_WEBHOOK_BASE_URL'],
      filename: File.basename(asset.local_path),
      scala: order_item.json_data.dig('scala') || '1:1',
      quantita: order_item.quantity,
      materiale: order_item.json_data.dig('materiale') || '',
      campi_custom: order_item.json_data.dig('campi_custom') || {},
      taglio: order_item.json_data.dig('taglio') == true,
      stampa: true,
      plancia: order_item.json_data.dig('plancia') == true,
      larghezza: order_item.json_data.dig('larghezza').to_f || 0.0,
      altezza: order_item.json_data.dig('altezza').to_f || 0.0
    }
  end
end
