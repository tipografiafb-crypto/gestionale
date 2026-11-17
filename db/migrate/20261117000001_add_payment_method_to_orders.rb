class AddPaymentMethodToOrders < ActiveRecord::Migration[7.1]
  def up
    add_column :orders, :payment_method, :string, if_not_exists: true
  end

  def down
    remove_column :orders, :payment_method, if_exists: true
  end
end
