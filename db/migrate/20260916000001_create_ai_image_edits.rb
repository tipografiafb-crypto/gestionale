class CreateAiImageEdits < ActiveRecord::Migration[7.1]
  def change
    create_table :ai_image_edits do |t|
      t.bigint :asset_id
      t.string :status, null: false, default: 'queued'
      t.string :source_sha256, null: false
      t.jsonb :options, null: false, default: {}
      t.jsonb :usage, null: false, default: {}
      t.decimal :cost_usd, precision: 16, scale: 8
      t.string :request_id
      t.text :error_message
      t.datetime :accepted_at
      t.timestamps
    end
    add_index :ai_image_edits, [:asset_id, :created_at]
    add_index :ai_image_edits, :asset_id, unique: true,
              where: "status IN ('queued', 'processing')", name: 'one_active_ai_edit_per_asset'
    add_foreign_key :ai_image_edits, :assets, on_delete: :nullify
  end
end
