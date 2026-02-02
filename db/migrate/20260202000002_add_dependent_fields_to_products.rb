class AddDependentFieldsToProducts < ActiveRecord::Migration[7.2]
  def change
    add_column :products, :is_dependent, :boolean, default: false
    add_column :products, :master_product_id, :integer
    add_index :products, :master_product_id
  end
end
