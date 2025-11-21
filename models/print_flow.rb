# @feature orders
# @domain data-models
# PrintFlow model - Two-step print workflow with pre-print and print webhooks

class PrintFlow < ActiveRecord::Base
  belongs_to :preprint_webhook, class_name: 'SwitchWebhook'
  belongs_to :print_webhook, class_name: 'SwitchWebhook'
  has_many :products, dependent: :nullify
  
  validates :name, presence: true, uniqueness: true
  validates :preprint_webhook_id, presence: true
  validates :print_webhook_id, presence: true

  scope :active, -> { where(active: true) }

  def display_name
    "#{name} (#{products.count} prodotti)"
  end
end
