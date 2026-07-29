class AddSecurePairingToAutomationAgents < ActiveRecord::Migration[7.1]
  def change
    change_table :automation_agents, bulk: true do |t|
      t.string :token_digest
      t.timestamp :paired_at
      t.timestamp :revoked_at
    end

    add_index :automation_agents, :token_digest, unique: true
    add_index :automation_agents, :revoked_at

    create_table :automation_agent_pairings do |t|
      t.string :code_digest, null: false
      t.string :requested_name
      t.timestamp :expires_at, null: false
      t.timestamp :consumed_at
      t.references :automation_agent, foreign_key: true
      t.timestamps
    end

    add_index :automation_agent_pairings, :code_digest, unique: true
    add_index :automation_agent_pairings, [:consumed_at, :expires_at],
              name: 'index_agent_pairings_on_availability'
  end
end
