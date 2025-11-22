class MigrateProductPrintFlowData < ActiveRecord::Migration[7.2]
  def up
    # Migrate existing print_flow_id to product_print_flows table
    execute <<-SQL
      INSERT INTO product_print_flows (product_id, print_flow_id, default_flow, created_at, updated_at)
      SELECT id, print_flow_id, true, NOW(), NOW()
      FROM products
      WHERE print_flow_id IS NOT NULL
      ON CONFLICT DO NOTHING
    SQL
    
    # Remove old print_flow_id column
    remove_column :products, :print_flow_id
  end
  
  def down
    # Add back the column
    add_column :products, :print_flow_id, :bigint
    
    # Restore data from product_print_flows
    execute <<-SQL
      UPDATE products
      SET print_flow_id = ppf.print_flow_id
      FROM product_print_flows ppf
      WHERE products.id = ppf.product_id
      AND ppf.default_flow = true
    SQL
    
    add_index :products, :print_flow_id
    add_foreign_key :products, :print_flows, column: :print_flow_id
  end
end
