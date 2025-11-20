# @feature switch
# @domain data-models
# SwitchJob model - Tracks jobs sent to Enfocus Switch
class SwitchJob < ActiveRecord::Base
  STATUSES = %w[pending sent completed failed].freeze

  belongs_to :order

  validates :status, inclusion: { in: STATUSES }

  # Scopes
  scope :recent, -> { order(created_at: :desc) }
  scope :by_status, ->(status) { where(status: status) if status.present? }

  # Check if job is in progress
  def in_progress?
    %w[pending sent].include?(status)
  end

  # Check if job is complete
  def complete?
    status == 'completed'
  end

  # Check if job failed
  def failed?
    status == 'failed'
  end

  # Add log entry
  def add_log(message)
    timestamp = Time.now.strftime('%Y-%m-%d %H:%M:%S')
    new_log = self.log.to_s + "\n[#{timestamp}] #{message}"
    update(log: new_log.strip)
  end
end
