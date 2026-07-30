class LinkPrintMachinesToLabelDestinations < ActiveRecord::Migration[7.2]
  def change
    add_reference(
      :print_machines,
      :label_automation_destination,
      foreign_key: {to_table: :automation_destinations},
      index: true
    )
  end
end
