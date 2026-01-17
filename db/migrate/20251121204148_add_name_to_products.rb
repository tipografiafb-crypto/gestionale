class AddNameToProducts < ActiveRecord::Migration[7.0]
  def change
    unless column_exists?(:products, :name)
      add_column :products, :name, :string
    end
  end
end
