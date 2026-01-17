class AddSourceToOrders < ActiveRecord::Migration[7.0]
  def change
    unless column_exists?(:orders, :source)
      add_column :orders, :source, :string, default: "api"
    end
  end
end
