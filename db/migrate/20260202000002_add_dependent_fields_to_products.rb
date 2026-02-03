class AddDependentFieldsToProducts < ActiveRecord::Migration[7.2]
  def change
    add_column :products, :is_dependent, :boolean, default: false unless column_exists?(:products, :is_dependent)
    add_column :products, :master_product_id, :integer unless column_exists?(:products, :master_product_id)
    add_index :products, :master_product_id unless index_exists?(:products, :master_product_id)
  end
end
