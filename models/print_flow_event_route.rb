# @feature automation
# @domain data-models

class PrintFlowEventRoute < ActiveRecord::Base
  RESERVED_EVENT_KEYS = %w[preprint print label].freeze
  EVENT_KEY_FORMAT = /\A[a-z][a-z0-9]*(?:[._-][a-z0-9]+)*\z/

  belongs_to :print_flow
  belongs_to :automation_flow

  validates :event_key,
            presence: true,
            uniqueness: {scope: :print_flow_id},
            format: {
              with: EVENT_KEY_FORMAT,
              message: 'può contenere solo lettere minuscole, numeri, punti, trattini e underscore'
            },
            exclusion: {
              in: RESERVED_EVENT_KEYS,
              message: 'è già gestito nelle azioni standard'
            }
  validate :automation_flow_must_be_published

  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(:event_key) }

  def display_label
    label.presence || event_key
  end

  private

  def automation_flow_must_be_published
    return unless automation_flow
    return if automation_flow.active_version

    errors.add(:automation_flow, 'deve avere una versione pubblicata')
  end
end
