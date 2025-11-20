class CreateStores < ActiveRecord::Migration[7.1]
  def change
    create_table :stores do |t|
      t.string :code, null: false, index: { unique: true }
      t.string :name, null: false
      t.timestamps
    end
  end
end
