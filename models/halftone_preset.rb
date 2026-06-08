# @feature halftone
# @domain data-models
# Saved operator presets for DTF halftone processing.
class HalftonePreset < ActiveRecord::Base
  validates :name, presence: true, uniqueness: true
  validates :settings, presence: true

  scope :ordered, -> { order(name: :asc) }

  def settings_hash
    settings || {}
  end
end
