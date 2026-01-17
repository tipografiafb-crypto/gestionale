class AddCategoryToProducts < ActiveRecord::Migration[7.0]
  def change
    unless column_exists?(:products, :product_category_id)
      add_reference :products, :product_category, foreign_key: true, null: true
    end
  end
end
