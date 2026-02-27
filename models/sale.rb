# @feature crm
# @domain data-models
# Sale model - Represents a sale/order from the CRM perspective (financial data)
class Sale < ActiveRecord::Base
  belongs_to :customer
  belongs_to :store, optional: true
  has_many :sale_items, dependent: :destroy

  validates :external_order_code, presence: true
  validates :external_order_code, uniqueness: { scope: :store_id }

  scope :recent, -> { order(order_date: :desc) }
  scope :by_store, ->(store_id) { where(store_id: store_id) if store_id.present? }
  scope :by_customer, ->(customer_id) { where(customer_id: customer_id) if customer_id.present? }
  scope :by_date_range, ->(start_date, end_date) {
    where('order_date >= ? AND order_date <= ?', start_date.beginning_of_day, end_date.end_of_day) if start_date && end_date
  }

  def net_total
    (total || 0) - (tax || 0)
  end
end
