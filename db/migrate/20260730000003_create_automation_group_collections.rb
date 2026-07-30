class CreateAutomationGroupCollections < ActiveRecord::Migration[7.2]
  def change
    create_table :automation_group_collections do |t|
      t.references :automation_flow_version, null: false, foreign_key: true
      t.string :node_key, null: false
      t.string :group_key, null: false
      t.integer :expected_count, null: false
      t.string :status, null: false, default: 'collecting'
      t.references :coordinator_run, foreign_key: {to_table: :automation_runs}
      t.references :output_artifact, foreign_key: {to_table: :automation_artifacts}
      t.timestamp :timeout_at
      t.timestamp :completed_at
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end
    add_index :automation_group_collections,
              [:automation_flow_version_id, :node_key, :group_key],
              unique: true,
              name: 'idx_automation_group_collections_unique'
    add_index :automation_group_collections, :status

    create_table :automation_group_collection_items do |t|
      t.references :automation_group_collection, null: false, foreign_key: true,
                   index: {name: 'idx_automation_group_items_collection'}
      t.references :automation_run, null: false, foreign_key: true
      t.references :automation_artifact, null: false, foreign_key: true
      t.integer :position, null: false, default: 0
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end
    add_index :automation_group_collection_items,
              [:automation_group_collection_id, :automation_run_id],
              unique: true,
              name: 'idx_automation_group_items_unique_run'
  end
end
