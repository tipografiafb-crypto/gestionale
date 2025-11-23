# @feature orders
# @domain data-models
# PrintMachine model - Physical printing machines configuration

class PrintMachine < ActiveRecord::Base
  has_many :print_flow_machines, dependent: :destroy
  has_many :print_flows, through: :print_flow_machines
  has_many :order_items, dependent: :nullify

  validates :name, presence: true, uniqueness: true

  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(name: :asc) }

  def display_name
    "#{name}#{description ? ' - ' + description : ''}"
  end
end
