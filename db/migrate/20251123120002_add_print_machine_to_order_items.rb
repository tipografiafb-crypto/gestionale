class AddPrintMachineToOrderItems < ActiveRecord::Migration[7.0]
  def change
    add_column :order_items, :print_machine_id, :bigint
    add_foreign_key :order_items, :print_machines, column: :print_machine_id
  end
end
