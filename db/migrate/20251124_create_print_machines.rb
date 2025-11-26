class CreatePrintMachines < ActiveRecord::Migration[7.0]
  def change
    create_table :print_machines do |t|
      t.string :name, null: false
      t.string :description
      t.boolean :active, null: false, default: true
      t.timestamps
    end
    
    add_index :print_machines, :name, unique: true
  end
end
