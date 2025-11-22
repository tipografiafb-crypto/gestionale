class AddSelectedPrintFlowToOrderItems < ActiveRecord::Migration[7.2]
  def change
    add_column :order_items, :selected_print_flow_id, :bigint
    add_index :order_items, :selected_print_flow_id
    add_foreign_key :order_items, :print_flows, column: :selected_print_flow_id
  end
end
