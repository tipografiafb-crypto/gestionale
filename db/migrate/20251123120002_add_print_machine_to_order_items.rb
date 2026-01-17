class AddPrintMachineToOrderItems < ActiveRecord::Migration[7.0]
  def change
    unless column_exists?(:order_items, :print_machine_id)
      add_reference :order_items, :print_machine, foreign_key: true, null: true
    end
  end
end
