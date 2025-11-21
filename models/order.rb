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
  
  attr_accessor :customer_name, :customer_note

  # Scopes for filtering
  scope :recent, -> { order(created_at: :desc) }
  scope :by_status, ->(status) { where(status: status) if status.present? }

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
end
