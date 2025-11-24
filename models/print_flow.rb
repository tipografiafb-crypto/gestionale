# @feature orders
# @domain data-models
# PrintFlow model - Two-step print workflow with pre-print and print webhooks

class PrintFlow < ActiveRecord::Base
  attr_accessor :active, :preprint_webhook_id, :print_webhook_id, :label_webhook_id
  
  belongs_to :preprint_webhook, class_name: 'SwitchWebhook'
  belongs_to :print_webhook, class_name: 'SwitchWebhook'
  belongs_to :label_webhook, class_name: 'SwitchWebhook', optional: true
  has_many :product_print_flows, dependent: :destroy
  has_many :products, through: :product_print_flows
  has_many :print_flow_machines, dependent: :destroy
  has_many :print_machines, through: :print_flow_machines
  
  validates :name, presence: true, uniqueness: true
  validates :preprint_webhook_id, presence: true
  validates :print_webhook_id, presence: true

  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(name: :asc) }

  def display_name
    "#{name} (#{products.count} prodotti)"
  end
end
