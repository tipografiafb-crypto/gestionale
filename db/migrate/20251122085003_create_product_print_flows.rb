class CreateProductPrintFlows < ActiveRecord::Migration[7.2]
  def change
    create_table :product_print_flows do |t|
      t.bigint :product_id, null: false
      t.bigint :print_flow_id, null: false
      t.boolean :default_flow, default: false
      t.timestamps
    end

    add_index :product_print_flows, :product_id
    add_index :product_print_flows, :print_flow_id
    add_index :product_print_flows, [:product_id, :print_flow_id], unique: true
    add_foreign_key :product_print_flows, :products
    add_foreign_key :product_print_flows, :print_flows
  end
end
