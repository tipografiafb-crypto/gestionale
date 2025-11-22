# @feature orders
# @domain data-models
# OrderItem model - Individual items within an order
class OrderItem < ActiveRecord::Base
  belongs_to :order
  has_many :assets, dependent: :destroy
  belongs_to :preprint_job, class_name: 'SwitchJob', foreign_key: 'preprint_job_id', optional: true
  belongs_to :print_job, class_name: 'SwitchJob', foreign_key: 'print_job_id', optional: true

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
    # If a specific flow was selected for this item, use it
    # Otherwise use the product's default flow
    if selected_print_flow_id
      PrintFlow.find_by(id: selected_print_flow_id)
    else
      product&.default_print_flow
    end
  end
  
  # Get all available print flows for this item's product
  def available_print_flows
    product&.print_flows || []
  end
end
