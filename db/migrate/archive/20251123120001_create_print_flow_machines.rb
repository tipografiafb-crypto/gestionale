class CreatePrintFlowMachines < ActiveRecord::Migration[7.0]
  def change
    create_table :print_flow_machines do |t|
      t.references :print_flow, foreign_key: true, null: false
      t.references :print_machine, foreign_key: true, null: false

      t.timestamps
    end

    add_index :print_flow_machines, [:print_flow_id, :print_machine_id], unique: true
  end
end
