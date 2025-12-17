# @feature orders
# @domain data-models
# OrderItem model - Individual items within an order
class OrderItem < ActiveRecord::Base
  belongs_to :order
  has_many :assets, dependent: :destroy
  belongs_to :preprint_job, class_name: 'SwitchJob', foreign_key: 'preprint_job_id', optional: true
  belongs_to :print_job, class_name: 'SwitchJob', foreign_key: 'print_job_id', optional: true
  belongs_to :preprint_print_flow, class_name: 'PrintFlow', optional: true
  belongs_to :print_machine, optional: true

  validates :sku, presence: true
  validates :quantity, presence: true, numericality: { greater_than: 0 }
  
  # Switch payload mapping
  # scala: stampa scale (1:1, 2:1, ecc)
  # materiale: material type (Celluloide, Carta, ecc)
  # campi_custom: custom fields from order
  # campi_webhook: webhook metadata (percentuale, stato, ecc)

  # Statuses for two-phase workflow
  PREPRINT_STATUSES = %w[pending processing completed failed].freeze
  PRINT_STATUSES = %w[pending processing ripped completed failed].freeze

  scope :preprint_pending, -> { where(preprint_status: 'pending') }
  scope :preprint_completed, -> { where(preprint_status: 'completed') }
  scope :print_pending, -> { where(print_status: 'pending') }
  scope :print_ripped, -> { where(print_status: 'ripped') }

  # Parse and store JSON data
  def store_json_data(data)
    self.raw_json = data.to_json
  end

  # Retrieve JSON data
  def json_data
    JSON.parse(raw_json) if raw_json.present?
  rescue JSON::ParserError
    {}
  end

  # Check if can send to preprint
  def can_send_to_preprint?
    preprint_status == 'pending' && (assets.empty? || assets.any?(&:downloaded?))
  end

  # Check if can send to print
  def can_send_to_print?
    preprint_status == 'completed' && print_status == 'pending'
  end

  # Get product and print flow for this item
  def product
    @product ||= Product.find_by(sku: sku)
  end

  def print_flow
    # Return selected print flow, or default from product
    preprint_print_flow || product&.default_print_flow
  end
  
  def available_print_flows
    product&.print_flows || []
  end

  # Get print assets for this item (for Switch processing)
  # Includes both 'print' (manual upload) and 'print_file_*' (FTP import) assets
  def switch_print_assets
    assets.where("asset_type LIKE ? OR asset_type = ?", 'print_file%', 'print').order(:id)
  end

  # Get the item number (position in order)
  # Uses position field (set at import time) with fallback to legacy ID-based counting
  def item_number
    # If position field exists and is set, use it
    if respond_to?(:position) && position && position > 0
      position
    else
      # Fallback to legacy behavior: count IDs up to this item (for existing orders)
      order.order_items.where("id <= ?", id).count
    end
  end
  
  # Always order by position for consistent display and numbering
  scope :ordered, -> { order(:position) }

  # Determine workflow status based on preprint and print completion
  # Returns: 'nuovo', 'pre-stampa', 'stampa', 'rippato', 'completato'
  def workflow_status
    if print_status == 'completed'
      'completato'
    elsif print_status == 'ripped'
      'rippato'
    elsif preprint_status == 'completed'
      'stampa'
    elsif preprint_status == 'processing' || preprint_status == 'pending'
      preprint_status == 'processing' ? 'pre-stampa' : 'nuovo'
    else
      'nuovo'
    end
  end

  # Generate Switch filename based on number of print stages
  # Uses external_order_code directly from JSON (e.g., "IT9395" becomes "IT9395-1.png")
  # Single file: {external_order_code}-{item_number}.png (e.g., IT9395-1.png)
  # Two files: {external_order_code}-{item_number}_F.png (stage1) and _R.png (stage2)
  def switch_filename_for_asset(asset)
    print_assets = switch_print_assets
    return nil unless print_assets.include?(asset)
    
    # Use external_order_code directly (e.g., "IT9395" from JSON id field)
    order_code = order.external_order_code.to_s
    
    if print_assets.count == 1
      # Single file: no suffix
      "#{order_code}-#{item_number}.png"
    elsif print_assets.count == 2
      # Two files: add _F or _R based on position
      index = print_assets.find_index(asset)
      suffix = index == 0 ? 'F' : 'R'
      "#{order_code}-#{item_number}_#{suffix}.png"
    end
  end
end
