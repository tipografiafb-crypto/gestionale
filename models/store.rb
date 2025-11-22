# @feature orders
# @domain data-models
# Store model - Represents e-commerce stores (TPH_IT, TPH_DE, etc.)
class Store < ActiveRecord::Base
  has_many :orders, dependent: :destroy
  has_many :webhooks, class_name: 'SwitchWebhook', dependent: :destroy

  validates :code, presence: true, uniqueness: true
  validates :name, presence: true

  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(name: :asc) }

  def self.find_by_code(code)
    find_by(code: code, active: true)
  end
end
