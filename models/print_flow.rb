# @feature orders
# @domain data-models
# PrintFlow model - Routes management actions to Switch webhooks or internal automations

class PrintFlow < ActiveRecord::Base
  EXECUTORS = %w[webhook automation].freeze
  LABEL_EXECUTORS = %w[none webhook automation].freeze
  ACTIONS = %w[preprint print label].freeze

  belongs_to :preprint_webhook, class_name: 'SwitchWebhook', optional: true
  belongs_to :print_webhook, class_name: 'SwitchWebhook', optional: true
  belongs_to :label_webhook, class_name: 'SwitchWebhook', optional: true
  belongs_to :preprint_automation_flow, class_name: 'AutomationFlow', optional: true
  belongs_to :print_automation_flow, class_name: 'AutomationFlow', optional: true
  belongs_to :label_automation_flow, class_name: 'AutomationFlow', optional: true
  has_many :product_print_flows, dependent: :destroy
  has_many :products, through: :product_print_flows
  has_many :print_flow_machines, dependent: :destroy
  has_many :print_machines, through: :print_flow_machines
  has_many :event_routes,
           class_name: 'PrintFlowEventRoute',
           dependent: :destroy,
           inverse_of: :print_flow
  
  validates :name, presence: true, uniqueness: true
  validates :preprint_executor, inclusion: {in: EXECUTORS}
  validates :print_executor, inclusion: {in: EXECUTORS}
  validates :label_executor, inclusion: {in: LABEL_EXECUTORS}
  validate :configured_action_destinations

  scope :ordered, -> { order(name: :asc) }

  def display_name
    "#{name} (#{products.count} prodotti)"
  end

  # Parse azione_photoshop options as array
  def azione_photoshop_options_list
    return [] unless azione_photoshop_options.present?
    azione_photoshop_options.split("\n").map(&:strip).reject(&:empty?)
  end

  def executor_for(action)
    return 'automation' if event_route_for(action)

    return nil unless ACTIONS.include?(action.to_s)

    public_send("#{action}_executor")
  end

  def automation_flow_for(action)
    route = event_route_for(action)
    return route.automation_flow if route

    return nil unless ACTIONS.include?(action.to_s)

    public_send("#{action}_automation_flow")
  end

  def webhook_for(action)
    return nil unless ACTIONS.include?(action.to_s)

    public_send("#{action}_webhook")
  end

  def event_route_for(event_key)
    event_routes.active.find_by(event_key: event_key.to_s)
  end

  def destination_label(action)
    executor = executor_for(action)
    return 'Non configurata' if executor == 'none'
    return "Flusso interno: #{automation_flow_for(action)&.name || 'mancante'}" if executor == 'automation'

    webhook = webhook_for(action)
    "Switch: #{webhook&.name || 'webhook mancante'}"
  end

  private

  def configured_action_destinations
    %w[preprint print].each { |action| validate_action_destination(action) }
    validate_action_destination('label') unless label_executor == 'none'
  end

  def validate_action_destination(action)
    executor = executor_for(action)
    if executor == 'automation'
      flow = automation_flow_for(action)
      errors.add("#{action}_automation_flow", 'deve essere selezionato') unless flow
      errors.add("#{action}_automation_flow", 'deve avere una versione pubblicata') if flow && !flow.active_version
    elsif executor == 'webhook'
      errors.add("#{action}_webhook", 'deve essere selezionato') unless webhook_for(action)
    end
  end
end
