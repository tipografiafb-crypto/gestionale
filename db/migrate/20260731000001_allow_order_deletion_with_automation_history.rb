class AllowOrderDeletionWithAutomationHistory < ActiveRecord::Migration[7.2]
  def change
    remove_foreign_key :automation_runs, column: :order_item_id
    add_foreign_key :automation_runs,
                    :order_items,
                    column: :order_item_id,
                    on_delete: :nullify

    remove_foreign_key :automation_runs, column: :source_asset_id
    add_foreign_key :automation_runs,
                    :assets,
                    column: :source_asset_id,
                    on_delete: :nullify
  end
end
