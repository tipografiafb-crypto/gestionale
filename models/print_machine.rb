# @feature orders
# @domain data-models
# PrintMachine model - Physical printing machines configuration

class PrintMachine < ActiveRecord::Base
  belongs_to :automation_destination, optional: true
  belongs_to :label_automation_destination,
             class_name: 'AutomationDestination',
             optional: true
  has_many :print_flow_machines, dependent: :destroy
  has_many :print_flows, through: :print_flow_machines
  has_many :order_items, dependent: :nullify

  validates :name, presence: true, uniqueness: true
  validate :automation_destination_must_be_network_folder
  validate :label_automation_destination_must_be_printer

  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(name: :asc) }

  def display_name
    "#{name}#{description ? ' - ' + description : ''}"
  end

  private

  def automation_destination_must_be_network_folder
    return unless automation_destination
    return if automation_destination.network_folder?

    errors.add(:automation_destination, 'deve essere una hot folder di rete')
  end

  def label_automation_destination_must_be_printer
    return unless label_automation_destination
    return if label_automation_destination.ipp_printer?

    errors.add(
      :label_automation_destination,
      'deve essere una stampante etichette'
    )
  end
end
