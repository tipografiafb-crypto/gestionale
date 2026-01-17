class CreateInventories < ActiveRecord::Migration[7.0]
  def change
    create_table :inventories do |t|
      t.references :product, null: false, foreign_key: true
      t.integer :quantity_in_stock, default: 0, null: false

      t.timestamps
    end
    add_index :inventories, :product_id, unique: true
  end
end
