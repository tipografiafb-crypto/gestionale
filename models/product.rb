# @feature orders
# @domain data-models
# Product model - SKU to print flow routing configuration

class Product < ActiveRecord::Base
  belongs_to :print_flow, optional: true
  belongs_to :product_category, optional: true

  validates :sku, presence: true, uniqueness: true
  validates :name, presence: true
  validates :print_flow_id, presence: true

  scope :active, -> { where(active: true) }
  scope :by_flow, ->(flow_id) { where(print_flow_id: flow_id) if flow_id.present? }
  scope :by_category, ->(category_id) { where(product_category_id: category_id) if category_id.present? }
  scope :ordered, -> { order(name: :asc) }

  def display_name
    "#{sku} - #{name} → #{print_flow&.name}"
  end
end
