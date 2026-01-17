class AddTimestampsToAssets < ActiveRecord::Migration[7.0]
  def change
    unless column_exists?(:assets, :imported_at)
      add_column :assets, :imported_at, :timestamp, null: false, default: -> { 'CURRENT_TIMESTAMP' }
    end
    
    unless column_exists?(:assets, :deleted_at)
      add_column :assets, :deleted_at, :timestamp
    end
    
    unless index_exists?(:assets, :imported_at)
      add_index :assets, :imported_at
    end
    
    unless index_exists?(:assets, :deleted_at)
      add_index :assets, :deleted_at
    end
  end
end
