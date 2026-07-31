class AutomationPresetFolder < ActiveRecord::Base
  validates :kind, :name, presence: true
  validates :name, uniqueness: {scope: :kind}
  scope :ordered, -> { order(:name) }
end
