class AddCustomerInfoToOrders < ActiveRecord::Migration[7.2]
  def change
    add_column :orders, :customer_name, :string
    add_column :orders, :customer_note, :text
  end
end
