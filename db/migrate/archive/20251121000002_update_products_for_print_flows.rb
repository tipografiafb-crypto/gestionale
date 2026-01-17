class UpdateProductsForPrintFlows < ActiveRecord::Migration[7.0]
  def change
    unless column_exists?(:products, :print_flow_id)
      add_reference :products, :print_flow, foreign_key: true, null: true
    end
    
    # These removals are only for legacy installations
    if foreign_key_exists?(:products, :switch_webhooks)
      remove_foreign_key :products, :switch_webhooks
    end
    
    if column_exists?(:products, :switch_webhook_id)
      remove_reference :products, :switch_webhook, index: true
    end
  end
end
