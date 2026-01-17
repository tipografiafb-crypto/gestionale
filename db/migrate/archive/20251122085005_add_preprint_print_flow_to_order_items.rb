class AddPreprintPrintFlowToOrderItems < ActiveRecord::Migration[7.0]
  def change
    unless column_exists?(:order_items, :preprint_print_flow_id)
      add_reference :order_items, :preprint_print_flow, foreign_key: { to_table: :print_flows }, null: true
    end
  end
end
