# @feature orders
# @domain data-models
# Order model - Represents print orders from e-commerce platforms
class Order < ActiveRecord::Base
  STATUSES = %w[new sent_to_switch processing done error].freeze

  belongs_to :store
  has_many :order_items, dependent: :destroy
  has_many :assets, through: :order_items
  has_one :switch_job, dependent: :destroy

  validates :external_order_code, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :external_order_code, uniqueness: { scope: :store_id }

  # Scopes for filtering
  scope :recent, -> { order(created_at: :desc) }
  scope :by_status, ->(status) { where(status: status) if status.present? }
  scope :by_store, ->(store_id) { where(store_id: store_id) if store_id.present? }
  scope :by_order_code, ->(code) { where('external_order_code ILIKE ?', "%#{code}%") if code.present? }
  scope :by_date, ->(date_str) { where('DATE(created_at) = ?', date_str) if date_str.present? }

  # Check if all assets have been downloaded
  def assets_downloaded?
    assets.any? && assets.all? { |asset| asset.local_path.present? }
  end

  # Check if order is ready to send to Switch
  def ready_for_switch?
    assets_downloaded? && %w[new error].include?(status)
  end

  # Update status with validation
  def update_status(new_status)
    update(status: new_status) if STATUSES.include?(new_status)
  end

  # Determine order status based on its items' workflow status
  # Returns: 'nuovo', 'in-lavorazione', 'completato'
  def workflow_status
    items = order_items
    return 'nuovo' if items.empty?
    
    # Check if all items are completed
    all_completed = items.all? { |item| item.print_status == 'completed' }
    return 'completato' if all_completed
    
    # Check if any item has started
    any_started = items.any? { |item| item.preprint_status != 'pending' || item.print_status != 'pending' }
    return 'in-lavorazione' if any_started
    
    'nuovo'
  end

  # Duplicate order for reprinting
  def duplicate
    new_order = dup
    new_order.external_order_code = "#{external_order_code} ristampa"
    new_order.status = 'new'
    new_order.save!
    
    # Duplicate order items and assets
    order_items.each do |item|
      new_item = item.dup
      new_item.order_id = new_order.id
      new_item.preprint_status = 'pending'
      new_item.preprint_job_id = nil
      new_item.preprint_completed_at = nil
      new_item.preprint_preview_url = nil
      new_item.print_status = 'pending'
      new_item.print_job_id = nil
      new_item.print_completed_at = nil
      new_item.print_machine_id = nil
      new_item.campi_webhook = nil
      new_item.save!
      
      # Duplicate only 'print' and 'screenshot' assets, skip results
      item.assets.each do |asset|
        next if %w[print_output print_result label_result].include?(asset.asset_type)
        new_asset = asset.dup
        new_asset.order_item_id = new_item.id
        new_asset.save!
      end
    end
    
    new_order
  end
end
