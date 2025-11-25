class AddTimestampsToAssets < ActiveRecord::Migration[6.0]
  def change
    add_column :assets, :imported_at, :datetime, default: -> { 'CURRENT_TIMESTAMP' }, null: false
    add_column :assets, :deleted_at, :datetime
    add_index :assets, :imported_at
    add_index :assets, :deleted_at
  end
end
