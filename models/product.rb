# @feature orders
# @domain data-models
# Product model - SKU to webhook routing configuration

class Product < ActiveRecord::Base
  belongs_to :switch_webhook

  validates :sku, presence: true, uniqueness: true
  validates :name, presence: true
  validates :switch_webhook_id, presence: true

  scope :active, -> { where(active: true) }
  scope :by_webhook, ->(webhook_id) { where(switch_webhook_id: webhook_id) if webhook_id.present? }

  def display_name
    "#{sku} - #{name} → #{switch_webhook.name}"
  end
end
