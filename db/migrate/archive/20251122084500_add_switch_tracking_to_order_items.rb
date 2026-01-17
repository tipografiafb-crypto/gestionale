class AddSwitchTrackingToOrderItems < ActiveRecord::Migration[7.0]
  def change
    unless column_exists?(:order_items, :preprint_preview_url)
      add_column :order_items, :preprint_preview_url, :string
    end
    unless column_exists?(:order_items, :print_status)
      add_column :order_items, :print_status, :string, default: 'pending'
    end
  end
end
