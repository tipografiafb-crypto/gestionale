class AddPositionToOrderItems < ActiveRecord::Migration[7.0]
  def change
    unless column_exists?(:order_items, :position)
      add_column :order_items, :position, :integer
    end
    
    # Use a rescue block for index creation to prevent stopping on duplicate index errors
    begin
      unless index_exists?(:order_items, [:order_id, :position])
        add_index :order_items, [:order_id, :position]
      end
    rescue => e
      puts "Index on order_items(order_id, position) might already exist: #{e.message}"
    end
  end
end
