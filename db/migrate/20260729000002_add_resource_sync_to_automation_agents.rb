class AddResourceSyncToAutomationAgents < ActiveRecord::Migration[7.1]
  def change
    change_table :automation_agents, bulk: true do |t|
      t.timestamp :resource_sync_requested_at
      t.timestamp :resource_synced_at
    end
  end
end
