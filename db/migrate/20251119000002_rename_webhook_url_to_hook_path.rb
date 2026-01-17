class RenameWebhookUrlToHookPath < ActiveRecord::Migration[7.2]
  def change
    rename_column :switch_webhooks, :webhook_url, :hook_path
  end
end
