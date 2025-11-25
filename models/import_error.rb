# @feature integration
# @domain data-models
# ImportError model - Tracks FTP import failures

class ImportError < ActiveRecord::Base
  validates :filename, :error_message, presence: true

  scope :recent, -> { order(created_at: :desc) }
  scope :by_date, ->(date_str) { where('DATE(created_at) = ?', date_str) if date_str.present? }
end
