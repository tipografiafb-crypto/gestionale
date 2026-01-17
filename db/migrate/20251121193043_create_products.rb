class CreateProducts < ActiveRecord::Migration[7.0]
  def change
    create_table :products do |t|
      t.string :sku, null: false
      t.string :name
      t.text :notes
      t.boolean :active, default: true
      t.integer :product_category_id
      t.integer :default_print_flow_id
      t.integer :min_stock_level, default: 0
      t.integer :master_product_id
      t.boolean :is_dependent, default: false

      t.timestamps
    end
    add_index :products, :sku, unique: true
    add_index :products, :product_category_id
    add_index :products, :master_product_id
  end
end
