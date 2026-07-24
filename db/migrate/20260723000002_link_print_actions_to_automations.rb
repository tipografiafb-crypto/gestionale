class LinkPrintActionsToAutomations < ActiveRecord::Migration[7.2]
  def change
    add_column :print_flows, :preprint_executor, :string, null: false, default: 'webhook'
    add_column :print_flows, :print_executor, :string, null: false, default: 'webhook'
    add_column :print_flows, :label_executor, :string, null: false, default: 'none'

    add_reference :print_flows,
                  :preprint_automation_flow,
                  foreign_key: {to_table: :automation_flows}
    add_reference :print_flows,
                  :print_automation_flow,
                  foreign_key: {to_table: :automation_flows}
    add_reference :print_flows,
                  :label_automation_flow,
                  foreign_key: {to_table: :automation_flows}

    add_reference :automation_runs, :source_asset, foreign_key: {to_table: :assets}
    add_reference :automation_runs, :print_flow, foreign_key: true
    add_column :automation_runs, :operation_type, :string
    add_column :automation_runs, :action_batch_id, :string
    add_index :automation_runs, :operation_type
    add_index :automation_runs, :action_batch_id
  end
end
