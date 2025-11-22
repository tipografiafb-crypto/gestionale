# @feature orders
# @domain data-models
# OrderItem model - Individual items within an order
class OrderItem < ActiveRecord::Base
  belongs_to :order
  has_many :assets, dependent: :destroy

  validates :sku, presence: true
  validates :quantity, presence: true, numericality: { greater_than: 0 }

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
    preprint_status == 'pending' && assets.any?(&:downloaded?)
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
    product&.print_flow
  end
end
