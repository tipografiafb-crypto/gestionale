# @feature orders
# @domain data-models
# OrderItem model - Individual items within an order
class OrderItem < ActiveRecord::Base
  belongs_to :order
  has_many :assets, dependent: :destroy
  belongs_to :preprint_job, class_name: 'SwitchJob', foreign_key: 'preprint_job_id', optional: true
  belongs_to :print_job, class_name: 'SwitchJob', foreign_key: 'print_job_id', optional: true
  belongs_to :preprint_print_flow, class_name: 'PrintFlow', optional: true

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
end
