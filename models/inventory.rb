# @feature storage
# @domain data-models
# Inventory model - Stock management for products
class Inventory < ActiveRecord::Base
  belongs_to :product

  validates :product_id, presence: true, uniqueness: true
  validates :quantity_in_stock, presence: true, numericality: { only_integer: true }

  scope :by_product, ->(product_id) { where(product_id: product_id) if product_id.present? }

  # Increase stock
  def add_stock(quantity)
    update(quantity_in_stock: quantity_in_stock + quantity)
  end

  # Decrease stock (prevents negative values - checks available stock)
  def remove_stock(quantity)
    if quantity_in_stock >= quantity
      update(quantity_in_stock: quantity_in_stock - quantity)
      true
    else
      false
    end
  end

  # Check if enough stock
  def sufficient_stock?(quantity)
    quantity_in_stock >= quantity
  end
end
