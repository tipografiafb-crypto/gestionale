class AddDefaultPrintFlowToProducts < ActiveRecord::Migration[7.0]
  def change
    add_reference :products, :default_print_flow, foreign_key: { to_table: :print_flows }, optional: true
    remove_column :products, :print_flow_id, :bigint if column_exists?(:products, :print_flow_id)
  end
end
