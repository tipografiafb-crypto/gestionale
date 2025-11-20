class CreateOrderItems < ActiveRecord::Migration[7.1]
  def change
    create_table :order_items do |t|
      t.references :order, null: false, foreign_key: true
      t.string :sku, null: false
      t.integer :quantity, null: false, default: 1
      t.text :raw_json
      t.timestamps
    end
  end
end
