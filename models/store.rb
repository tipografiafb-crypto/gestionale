# @feature orders
# @domain data-models
# Store model - Represents e-commerce stores (TPH_IT, TPH_DE, etc.)
class Store < ActiveRecord::Base
  has_many :orders, dependent: :destroy
  has_many :webhooks, class_name: 'SwitchWebhook', dependent: :destroy

  validates :code, presence: true, uniqueness: true
  validates :name, presence: true

  # Find or create store by code
  def self.find_or_create_by_code(code, name = nil)
    find_or_create_by(code: code) do |store|
      store.name = name || code
    end
  end
end
