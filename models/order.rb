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

  # Duplicate order for reprinting
  def duplicate
    new_order = dup
    new_order.external_order_code = "#{external_order_code}-COPY-#{Time.now.to_i}"
    new_order.status = 'new'
    new_order.save!
    
    # Duplicate order items and assets
    order_items.each do |item|
      new_item = item.dup
      new_item.order_id = new_order.id
      new_item.preprint_status = 'pending'
      new_item.preprint_job_id = nil
      new_item.print_status = 'pending'
      new_item.print_job_id = nil
      new_item.save!
      
      # Duplicate assets
      item.assets.each do |asset|
        new_asset = asset.dup
        new_asset.order_item_id = new_item.id
        new_asset.save!
      end
    end
    
    new_order
  end
end
