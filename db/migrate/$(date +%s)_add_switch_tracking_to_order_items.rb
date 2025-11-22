class AddSwitchTrackingToOrderItems < ActiveRecord::Migration[7.0]
  def change
    add_column :order_items, :preprint_status, :string, default: 'pending'
    add_column :order_items, :preprint_job_id, :string
    add_column :order_items, :preprint_preview_url, :string
    add_column :order_items, :print_status, :string, default: 'pending'
    add_column :order_items, :print_job_id, :string
    
    add_index :order_items, :preprint_status
    add_index :order_items, :print_status
  end
end
