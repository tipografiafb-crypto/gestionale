class CreateAutomationPresetFolders < ActiveRecord::Migration[7.0]
  def change
    create_table :automation_preset_folders do |t|
      t.string :kind, null: false, default: 'imposition'
      t.string :name, null: false
      t.timestamps
    end
    add_index :automation_preset_folders, [:kind, :name], unique: true
  end
end
