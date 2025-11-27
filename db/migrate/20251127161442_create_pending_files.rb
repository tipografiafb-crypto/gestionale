class CreatePendingFiles < ActiveRecord::Migration[6.0]
  def change
    create_table :pending_files do |t|
      t.string :external_order_code, null: false
      t.integer :external_id_riga, null: false
      t.string :filename, null: false
      t.string :file_path, null: false
      t.string :kind
      t.string :status, default: 'pending'
      t.references :order_item, foreign_key: true

      t.timestamps
    end

    add_index :pending_files, [:external_order_code, :external_id_riga], unique: true
  end
end
