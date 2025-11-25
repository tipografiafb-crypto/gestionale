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
  PRINT_STATUSES = %w[pending processing completed failed].freeze

  scope :preprint_pending, -> { where(preprint_status: 'pending') }
  scope :preprint_completed, -> { where(preprint_status: 'completed') }
  scope :print_pending, -> { where(print_status: 'pending') }

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
  def item_number
    order.order_items.where("id <= ?", id).count
  end

  # Generate Switch filename based on number of print stages
  # Single file: eu{order_id}-{item_number}.png
  # Two files: eu{order_id}-{item_number}_F.png (stage1) and _R.png (stage2)
  def switch_filename_for_asset(asset)
    print_assets = switch_print_assets
    return nil unless print_assets.include?(asset)
    
    # Extract numeric part from order code, fallback to order id
    code_str = order.external_order_code.to_s.gsub(/[^0-9]/, '')
    order_code = code_str.empty? ? order.id : code_str.to_i
    
    if print_assets.count == 1
      # Single file: no suffix
      "eu#{order_code}-#{item_number}.png"
    elsif print_assets.count == 2
      # Two files: add _F or _R based on position
      index = print_assets.find_index(asset)
      suffix = index == 0 ? 'F' : 'R'
      "eu#{order_code}-#{item_number}_#{suffix}.png"
    end
  end
end
