class AddCustomerInfoToOrders < ActiveRecord::Migration[7.0]
  def change
    unless column_exists?(:orders, :customer_name)
      add_column :orders, :customer_name, :string
    end
    
    unless column_exists?(:orders, :customer_note)
      add_column :orders, :customer_note, :text
    end
  end
end
