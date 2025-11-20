class CreateOrders < ActiveRecord::Migration[7.1]
  def change
    create_table :orders do |t|
      t.string :external_order_code, null: false
      t.references :store, null: false, foreign_key: true
      t.string :status, null: false, default: 'new'
      t.timestamps
    end

    add_index :orders, [:store_id, :external_order_code], unique: true
  end
end
