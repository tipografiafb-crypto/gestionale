class CreateSwitchWebhooks < ActiveRecord::Migration[7.2]
  def change
    create_table :switch_webhooks unless table_exists?(:switch_webhooks) do |t|
      t.string :name, null: false
      t.string :hook_path, null: false
      t.references :store, foreign_key: true, null: true
      t.boolean :active, default: true
      t.timestamps
    end
    add_index :switch_webhooks, [:name, :store_id], unique: true unless index_exists?(:switch_webhooks, [:name, :store_id])
  end
end
