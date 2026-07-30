class LinkPrintMachinesToDestinations < ActiveRecord::Migration[7.2]
  def change
    add_reference(
      :print_machines,
      :automation_destination,
      foreign_key: true,
      index: true
    )
  end
end
