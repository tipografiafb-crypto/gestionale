# @feature orders
# @domain data-models
# PrintFlow model - Two-step print workflow with pre-print and print webhooks

class PrintFlow < ActiveRecord::Base
  has_many :products, dependent: :nullify
  
  validates :name, presence: true, uniqueness: true
  validates :preprint_hook_path, presence: true, format: { with: /\A\//, message: "deve iniziare con /" }
  validates :print_hook_path, presence: true, format: { with: /\A\//, message: "deve iniziare con /" }

  scope :active, -> { where(active: true) }

  # Compute full webhook URLs from hook_paths
  def preprint_webhook_url
    base_url = ENV['SWITCH_WEBHOOK_BASE_URL'] || 'http://localhost:9000'
    "#{base_url}#{preprint_hook_path}"
  end

  def print_webhook_url
    base_url = ENV['SWITCH_WEBHOOK_BASE_URL'] || 'http://localhost:9000'
    "#{base_url}#{print_hook_path}"
  end

  def display_name
    "#{name} (#{products.count} prodotti)"
  end
end
