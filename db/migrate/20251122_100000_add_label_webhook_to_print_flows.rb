class AddLabelWebhookToPrintFlows < ActiveRecord::Migration[7.2]
  def change
    add_column :print_flows, :label_webhook_id, :bigint
    add_index :print_flows, :label_webhook_id
    add_foreign_key :print_flows, :switch_webhooks, column: :label_webhook_id
  end
end
