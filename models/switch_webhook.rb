# @feature switch
# @domain data-models
# SwitchWebhook model - Registered Switch webhook endpoints with names

class SwitchWebhook < ActiveRecord::Base
  belongs_to :store, optional: true
  has_many :switch_jobs

  validates :name, presence: true
  validates :webhook_url, presence: true, format: { with: URI::DEFAULT_PARSER.make_regexp, message: "must be a valid URL" }
  validates :name, uniqueness: { scope: :store_id, allow_nil: true }

  scope :active, -> { where(active: true) }
  scope :by_store, ->(store_id) { where(store_id: store_id) }

  def display_name
    store_id ? "#{name} (#{store&.name})" : name
  end
end
