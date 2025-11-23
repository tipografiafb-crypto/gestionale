# @feature orders
# @domain data-models
# PrintFlowMachine model - Junction table for PrintFlow and PrintMachine many-to-many relationship

class PrintFlowMachine < ActiveRecord::Base
  belongs_to :print_flow
  belongs_to :print_machine

  validates :print_flow_id, :print_machine_id, presence: true
end
