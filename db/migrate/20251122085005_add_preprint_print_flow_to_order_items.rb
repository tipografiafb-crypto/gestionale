class AddPreprintPrintFlowToOrderItems < ActiveRecord::Migration[7.0]
  def change
    add_reference :order_items, :preprint_print_flow, foreign_key: { to_table: :print_flows }, optional: true
  end
end
