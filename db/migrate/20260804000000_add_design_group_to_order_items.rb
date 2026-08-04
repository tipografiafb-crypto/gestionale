class AddDesignGroupToOrderItems < ActiveRecord::Migration[7.2]
  def change
    add_column :order_items, :design_group_key, :string unless column_exists?(:order_items, :design_group_key)
    add_index :order_items, [:order_id, :design_group_key], name: 'idx_order_items_design_group' unless index_exists?(:order_items, [:order_id, :design_group_key], name: 'idx_order_items_design_group')
  end
end
