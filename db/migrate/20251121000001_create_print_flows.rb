class CreatePrintFlows < ActiveRecord::Migration[7.0]
  def change
    create_table :print_flows do |t|
      t.string :name, null: false
      t.string :preprint_hook_path, null: false
      t.string :print_hook_path, null: false
      t.text :notes
      t.boolean :active, default: true

      t.timestamps
    end

    add_index :print_flows, :name, unique: true
  end
end
