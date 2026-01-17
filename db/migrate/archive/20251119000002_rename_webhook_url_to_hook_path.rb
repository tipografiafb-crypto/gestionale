class RenameWebhookUrlToHookPath < ActiveRecord::Migration[7.0]
  def change
    if column_exists?(:switch_webhooks, :webhook_url)
      rename_column :switch_webhooks, :webhook_url, :hook_path
    end
  end
end
