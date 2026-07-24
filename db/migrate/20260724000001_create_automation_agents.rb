class CreateAutomationAgents < ActiveRecord::Migration[7.2]
  def change
    create_table :automation_agents do |t|
      t.string :agent_key, null: false
      t.string :name, null: false
      t.string :hostname
      t.string :platform
      t.jsonb :capabilities, null: false, default: []
      t.jsonb :metadata, null: false, default: {}
      t.timestamp :last_seen_at
      t.text :last_error
      t.timestamps
    end

    add_index :automation_agents, :agent_key, unique: true
    add_index :automation_agents, :last_seen_at
  end
end
