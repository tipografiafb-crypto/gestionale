class CreatePrintFlowMachines < ActiveRecord::Migration[7.0]
  def change
    create_table :print_flow_machines do |t|
      t.references :print_flow, null: false, foreign_key: true
      t.references :print_machine, null: false, foreign_key: true
      t.timestamps
    end
    
    add_index :print_flow_machines, [:print_flow_id, :print_machine_id], unique: true, name: 'index_print_flow_machines_unique'
  end
end
