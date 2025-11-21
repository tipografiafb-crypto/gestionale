class AddCategoryToProducts < ActiveRecord::Migration[7.0]
  def change
    add_reference :products, :product_category, foreign_key: true, null: true
  end
end
