class CreateProductPrintFlows < ActiveRecord::Migration[7.0]
  def change
    create_table :product_print_flows do |t|
      t.references :product, null: false, foreign_key: true
      t.references :print_flow, null: false, foreign_key: true

      t.timestamps
    end

    add_index :product_print_flows, [:product_id, :print_flow_id], unique: true
  end
end
