# @feature orders
# @domain data-models
# ProductPrintFlow model - Junction table for product-to-multiple-print-flows relationship

class ProductPrintFlow < ActiveRecord::Base
  belongs_to :product
  belongs_to :print_flow

  validates :product_id, presence: true, uniqueness: { scope: :print_flow_id }
  validates :print_flow_id, presence: true

  # Ensure only one default flow per product
  before_save :reset_other_defaults
  
  scope :by_product, ->(product_id) { where(product_id: product_id) }
  scope :default, -> { where(default_flow: true) }

  private

  def reset_other_defaults
    return unless default_flow && default_flow_changed?
    ProductPrintFlow.where(product_id: product_id).where.not(id: id).update_all(default_flow: false)
  end
end
