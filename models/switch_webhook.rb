# @feature switch
# @domain data-models
# SwitchWebhook model - Registered Switch webhook endpoints with names

class SwitchWebhook < ActiveRecord::Base
  attr_accessor :store_id, :active
  
  belongs_to :store, optional: true
  has_many :switch_jobs
  has_many :print_flows_as_preprint, class_name: 'PrintFlow', foreign_key: 'preprint_webhook_id', dependent: :nullify
  has_many :print_flows_as_print, class_name: 'PrintFlow', foreign_key: 'print_webhook_id', dependent: :nullify

  validates :name, presence: true
  validates :hook_path, presence: true, format: { with: /\A\//, message: "deve iniziare con /" }
  validates :name, uniqueness: { scope: :store_id, allow_nil: true }

  scope :active, -> { where(active: true) }
  scope :by_store, ->(store_id) { where(store_id: store_id) }

  # Compute full webhook URL from hook_path
  def webhook_url
    base_url = ENV['SWITCH_WEBHOOK_BASE_URL'] || 'http://localhost:9000'
    "#{base_url}#{hook_path}"
  end

  def display_name
    store_id ? "#{name} (#{store&.name})" : name
  end
end
