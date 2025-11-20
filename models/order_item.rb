# @feature orders
# @domain data-models
# OrderItem model - Individual items within an order
class OrderItem < ActiveRecord::Base
  belongs_to :order
  has_many :assets, dependent: :destroy

  validates :sku, presence: true
  validates :quantity, presence: true, numericality: { greater_than: 0 }

  # Parse and store JSON data
  def store_json_data(data)
    self.raw_json = data.to_json
  end

  # Retrieve JSON data
  def json_data
    JSON.parse(raw_json) if raw_json.present?
  rescue JSON::ParserError
    {}
  end
end
