class CreatePrintMachines < ActiveRecord::Migration[7.0]
  def change
    create_table :print_machines do |t|
      t.string :name, null: false
      t.text :description
      t.boolean :active, default: true

      t.timestamps
    end

    add_index :print_machines, :name, unique: true
  end
end
