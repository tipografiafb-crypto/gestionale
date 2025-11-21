class CreateProducts < ActiveRecord::Migration[7.2]
  def change
    create_table :products do |t|
      t.string :sku, null: false
      t.references :switch_webhook, foreign_key: true, null: false
      t.text :notes
      t.boolean :active, default: true
      t.timestamps
    end
    
    add_index :products, :sku, unique: true
  end
end
