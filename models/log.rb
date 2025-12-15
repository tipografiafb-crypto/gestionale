# @feature logging
# @domain data-models
# Log model - Application event logging
class Log < ActiveRecord::Base
  LEVELS = %w[info warn error debug].freeze
  CATEGORIES = %w[ftp order switch asset import system].freeze

  validates :level, inclusion: { in: LEVELS }
  validates :category, inclusion: { in: CATEGORIES }
  validates :message, presence: true

  scope :recent, -> { order(created_at: :desc) }
  scope :by_level, ->(level) { where(level: level) if level.present? }
  scope :by_category, ->(category) { where(category: category) if category.present? }
  scope :last_24h, -> { where(created_at: 24.hours.ago..Time.now) }

  def self.log(level, category, message, details = nil)
    create(
      level: level,
      category: category,
      message: message,
      details: details
    )
  rescue => e
    puts "[LOG ERROR] Failed to log: #{e.message}"
  end
end
