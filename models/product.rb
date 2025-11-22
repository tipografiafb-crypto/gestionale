# @feature orders
# @domain data-models
# Product model - SKU to print flow routing configuration

class Product < ActiveRecord::Base
  has_many :product_print_flows, dependent: :destroy
  has_many :print_flows, through: :product_print_flows
  belongs_to :default_print_flow, class_name: 'PrintFlow', optional: true
  belongs_to :product_category, optional: true

  validates :sku, presence: true, uniqueness: true
  validates :name, presence: true
  validates :default_print_flow_id, presence: true

  scope :active, -> { where(active: true) }
  scope :by_flow, ->(flow_id) { joins(:print_flows).where(print_flows: { id: flow_id }) if flow_id.present? }
  scope :by_category, ->(category_id) { where(product_category_id: category_id) if category_id.present? }
  scope :ordered, -> { order(name: :asc) }

  def display_name
    flow_names = print_flows.map(&:name).join(', ')
    "#{sku} - #{name} → [#{flow_names}]"
  end
end
