class AddPositionToOrderItems < ActiveRecord::Migration[7.0]
  def change
    unless column_exists?(:order_items, :position)
      add_column :order_items, :position, :integer
    end
    
    # Use explicit SQL to check for column existence before index
    if column_exists?(:order_items, :order_id)
      begin
        unless index_exists?(:order_items, [:order_id, :position])
          add_index :order_items, [:order_id, :position]
        end
      rescue => e
        puts "Skipping index creation: #{e.message}"
      end
    end
  end
end
