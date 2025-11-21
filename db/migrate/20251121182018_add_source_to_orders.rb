class AddSourceToOrders < ActiveRecord::Migration[7.2]
  def change
    add_column :orders, :source, :string, default: 'api'
  end
end
