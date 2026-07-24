class CreateAutomationEngine < ActiveRecord::Migration[7.2]
  def change
    create_table :automation_flows do |t|
      t.string :name, null: false
      t.text :description
      t.string :status, null: false, default: 'draft'
      t.bigint :active_version_id
      t.timestamps
    end
    add_index :automation_flows, :name, unique: true
    add_index :automation_flows, :active_version_id

    create_table :automation_flow_versions do |t|
      t.references :automation_flow, null: false, foreign_key: true
      t.integer :version_number, null: false
      t.string :status, null: false, default: 'draft'
      t.jsonb :graph, null: false, default: {}
      t.string :checksum
      t.timestamp :published_at
      t.timestamps
    end
    add_index :automation_flow_versions,
              [:automation_flow_id, :version_number],
              unique: true,
              name: 'idx_automation_flow_versions_unique'

    add_foreign_key :automation_flows,
                    :automation_flow_versions,
                    column: :active_version_id

    create_table :automation_runs do |t|
      t.references :automation_flow_version, null: false, foreign_key: true
      t.references :order_item, foreign_key: true
      t.string :status, null: false, default: 'queued'
      t.jsonb :context, null: false, default: {}
      t.string :current_node_key
      t.text :error_message
      t.timestamp :started_at
      t.timestamp :completed_at
      t.timestamps
    end
    add_index :automation_runs, :status

    create_table :automation_step_runs do |t|
      t.references :automation_run, null: false, foreign_key: true
      t.string :node_key, null: false
      t.string :node_type, null: false
      t.string :status, null: false, default: 'queued'
      t.jsonb :input_data, null: false, default: {}
      t.jsonb :output_data, null: false, default: {}
      t.integer :attempts, null: false, default: 0
      t.integer :max_attempts, null: false, default: 3
      t.text :error_message
      t.string :worker_id
      t.timestamp :available_at
      t.timestamp :locked_at
      t.timestamp :started_at
      t.timestamp :finished_at
      t.timestamps
    end
    add_index :automation_step_runs, [:status, :available_at]
    add_index :automation_step_runs,
              [:automation_run_id, :node_key],
              unique: true,
              name: 'idx_automation_steps_run_node'

    create_table :automation_artifacts do |t|
      t.references :automation_run, null: false, foreign_key: true
      t.references :automation_step_run, foreign_key: true
      t.string :kind, null: false
      t.string :filename, null: false
      t.string :media_type
      t.string :local_path, null: false
      t.string :checksum
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end
    add_index :automation_artifacts, [:automation_run_id, :kind]

    create_table :automation_presets do |t|
      t.string :kind, null: false
      t.string :code, null: false
      t.string :name, null: false
      t.jsonb :config, null: false, default: {}
      t.boolean :active, null: false, default: true
      t.timestamps
    end
    add_index :automation_presets, [:kind, :code], unique: true
  end
end
