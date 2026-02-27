# @feature crm
# @domain data-models
# Customer model - Represents customers imported from WooCommerce CRM data
class Customer < ActiveRecord::Base
  belongs_to :store, optional: true
  has_many :sales, dependent: :destroy

  validates :email, presence: true, uniqueness: true

  scope :ordered, -> { order(last_name: :asc, first_name: :asc) }
  scope :by_store, ->(store_id) { where(store_id: store_id) if store_id.present? }
  scope :top_spenders, -> { order(total_spent: :desc) }
  scope :recent, -> { order(last_order_at: :desc) }
  scope :search, ->(q) {
    where('email ILIKE :q OR first_name ILIKE :q OR last_name ILIKE :q OR phone ILIKE :q', q: "%#{q}%") if q.present?
  }

  def full_name
    [first_name, last_name].compact.join(' ').presence || email
  end

  # Create or update customer from CRM JSON data
  def self.upsert_from_crm(data, store)
    customer_data = data['customer']
    return nil unless customer_data && customer_data['email'].present?

    customer = find_or_initialize_by(email: customer_data['email'].downcase.strip)

    customer.assign_attributes(
      first_name: customer_data['first_name'],
      last_name: customer_data['last_name'],
      phone: customer_data['phone'],
      billing_address: customer_data['billing_address'],
      shipping_address: customer_data['shipping_address'],
      store_id: store&.id
    )

    # Update aggregates
    order_date = data['order_date'] ? Time.parse(data['order_date']) : Time.now
    order_total = data.dig('financials', 'total')&.to_f || 0

    if customer.new_record?
      customer.total_spent = order_total
      customer.order_count = 1
      customer.first_order_at = order_date
      customer.last_order_at = order_date
    else
      customer.total_spent = (customer.total_spent || 0) + order_total
      customer.order_count = (customer.order_count || 0) + 1
      customer.first_order_at = order_date if customer.first_order_at.nil? || order_date < customer.first_order_at
      customer.last_order_at = order_date if customer.last_order_at.nil? || order_date > customer.last_order_at
    end

    customer.save!
    customer
  end
end
