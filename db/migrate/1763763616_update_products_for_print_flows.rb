class UpdateProductsForPrintFlows < ActiveRecord::Migration[7.0]
  def change
    add_reference :products, :print_flow, foreign_key: true, null: true
    remove_foreign_key :products, :switch_webhooks
    remove_reference :products, :switch_webhook, index: true
  end
end
