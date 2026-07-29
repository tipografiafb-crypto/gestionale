class CreateAutomationDestinations < ActiveRecord::Migration[7.2]
  def up
    create_table :automation_destinations do |t|
      t.string :code, null: false
      t.string :name, null: false
      t.string :kind, null: false
      t.jsonb :config, null: false, default: {}
      t.boolean :active, null: false, default: true
      t.datetime :last_checked_at
      t.string :last_check_status
      t.text :last_check_message
      t.timestamps
    end
    add_index :automation_destinations, :code, unique: true
    add_index :automation_destinations, [:kind, :active]

    execute "DELETE FROM automation_presets WHERE kind = 'output'"

    execute <<~SQL
      INSERT INTO automation_destinations
        (code, name, kind, config, active, created_at, updated_at)
      VALUES
        (
          'LOCAL_PRINT',
          'Hot folder locale stampa',
          'network_folder',
          '{"container_path":"/destinations/print","host_mount_path":"./storage/automation/destinations/print","network_uri":""}'::jsonb,
          TRUE,
          CURRENT_TIMESTAMP,
          CURRENT_TIMESTAMP
        ),
        (
          'LOCAL_LABELS',
          'Hot folder locale etichette',
          'network_folder',
          '{"container_path":"/destinations/labels","host_mount_path":"./storage/automation/destinations/labels","network_uri":""}'::jsonb,
          TRUE,
          CURRENT_TIMESTAMP,
          CURRENT_TIMESTAMP
        )
    SQL
  end

  def down
    drop_table :automation_destinations
  end
end
