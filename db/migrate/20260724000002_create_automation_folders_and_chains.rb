class CreateAutomationFoldersAndChains < ActiveRecord::Migration[7.2]
  def change
    create_table :automation_folders do |t|
      t.string :name, null: false
      t.text :description
      t.references :root_flow, foreign_key: {to_table: :automation_flows}
      t.timestamps
    end
    add_index :automation_folders, :name, unique: true

    create_table :automation_folder_flows do |t|
      t.references :automation_folder, null: false, foreign_key: true
      t.references :automation_flow, null: false, foreign_key: true
      t.integer :position, null: false, default: 0
      t.timestamps
    end
    add_index :automation_folder_flows,
              [:automation_folder_id, :automation_flow_id],
              unique: true,
              name: 'idx_automation_folder_flows_unique'

    add_reference :automation_runs,
                  :parent_run,
                  foreign_key: {to_table: :automation_runs}
    add_reference :automation_runs,
                  :root_run,
                  foreign_key: {to_table: :automation_runs}
    add_reference :automation_runs,
                  :handoff_step,
                  foreign_key: {to_table: :automation_step_runs}
  end
end
