# @feature orders
# @domain data-models
# ProductCategory model - Categories for organizing products

class ProductCategory < ActiveRecord::Base
  has_many :products, dependent: :restrict_with_error

  validates :name, presence: true, uniqueness: true
  validates :name, length: { minimum: 2, maximum: 100 }

  scope :ordered, -> { order(name: :asc) }

  def product_count
    products.count
  end

  # Autopilot for preprint
  def autopilot_preprint_status
    autopilot_preprint_enabled ? "ABILITATO" : "disabilitato"
  end
end
