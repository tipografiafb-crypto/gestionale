class AddCompletionTimestampsToOrderItems < ActiveRecord::Migration[7.2]
  def change
    add_column :order_items, :preprint_completed_at, :datetime
    add_column :order_items, :print_completed_at, :datetime
  end
end
