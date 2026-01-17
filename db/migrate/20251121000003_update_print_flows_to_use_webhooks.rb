class UpdatePrintFlowsToUseWebhooks < ActiveRecord::Migration[7.0]
  def change
    add_reference :print_flows, :preprint_webhook, foreign_key: { to_table: :switch_webhooks }, null: true
    add_reference :print_flows, :print_webhook, foreign_key: { to_table: :switch_webhooks }, null: true
    remove_column :print_flows, :preprint_hook_path, :string
    remove_column :print_flows, :print_hook_path, :string
  end
end
