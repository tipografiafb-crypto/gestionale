# @feature orders
# @domain data-models
# Product model - SKU to print flow routing configuration

class Product < ActiveRecord::Base
  has_many :product_print_flows, dependent: :destroy
  has_many :print_flows, through: :product_print_flows
  belongs_to :product_category, optional: true

  validates :sku, presence: true, uniqueness: true
  validates :name, presence: true

  scope :active, -> { where(active: true) }
  scope :by_category, ->(category_id) { where(product_category_id: category_id) if category_id.present? }
  scope :ordered, -> { order(name: :asc) }

  def default_print_flow
    product_print_flows.find_by(default_flow: true)&.print_flow || print_flows.first
  end

  def display_name
    "#{sku} - #{name} → #{default_print_flow&.name}"
  end
end
