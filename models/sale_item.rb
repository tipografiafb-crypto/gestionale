# @feature crm
# @domain data-models
# SaleItem model - Individual product line within a sale
class SaleItem < ActiveRecord::Base
  belongs_to :sale

  # sku can be blank for some CRM products
  validates :quantity, numericality: { greater_than: 0 }
end
