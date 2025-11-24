# @feature orders
# @domain data-models
# Product model - SKU to print flow routing configuration

class Product < ActiveRecord::Base
  has_many :product_print_flows, dependent: :destroy
  has_many :print_flows, through: :product_print_flows
  has_one :inventory, dependent: :destroy
  belongs_to :default_print_flow, class_name: 'PrintFlow', optional: true
  belongs_to :product_category, optional: true

  validates :sku, presence: true, uniqueness: true
  validates :name, presence: true
  validates :default_print_flow_id, presence: true
  validates :min_stock_level, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true

  # Create inventory record when product is created
  after_create :create_inventory_record

  scope :active, -> { where(active: true) }
  scope :by_flow, ->(flow_id) { joins(:print_flows).where(print_flows: { id: flow_id }) if flow_id.present? }
  scope :by_category, ->(category_id) { where(product_category_id: category_id) if category_id.present? }
  scope :ordered, -> { order(name: :asc) }

  def display_name
    flow_names = print_flows.map(&:name).join(', ')
    "#{sku} - #{name} → [#{flow_names}]"
  end

  # Duplicate product with all its configurations
  def duplicate
    new_product = self.dup
    # Generate new unique SKU by appending a timestamp
    new_product.sku = "#{sku}_copy_#{Time.now.to_i}"
    new_product.name = "#{name} (Copia)"
    
    if new_product.save
      # Copy print flow associations
      product_print_flows.each do |ppf|
        new_product.product_print_flows.create(print_flow_id: ppf.print_flow_id)
      end
      new_product
    else
      nil
    end
  end

  private

  def create_inventory_record
    Inventory.create!(product_id: id, quantity_in_stock: 0)
  end
end
