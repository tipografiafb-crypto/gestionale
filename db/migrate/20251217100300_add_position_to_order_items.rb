class AddPositionToOrderItems < ActiveRecord::Migration[7.0]
  def change
    add_column :order_items, :position, :integer, default: 0
    add_index :order_items, [:order_id, :position]
  end
end
