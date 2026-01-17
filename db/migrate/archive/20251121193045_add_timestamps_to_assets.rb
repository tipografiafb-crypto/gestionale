class AddTimestampsToAssets < ActiveRecord::Migration[7.0]
  def change
    # Check column by column
    unless column_exists?(:assets, :imported_at)
      add_column :assets, :imported_at, :timestamp, null: false, default: -> { 'CURRENT_TIMESTAMP' }
    end
    
    unless column_exists?(:assets, :deleted_at)
      add_column :assets, :deleted_at, :timestamp
    end
    
    # Check index by index
    # We use a rescue block for index creation because index_exists? can be flaky in some environments
    begin
      unless index_exists?(:assets, :imported_at)
        add_index :assets, :imported_at
      end
    rescue => e
      puts "Index on assets(imported_at) might already exist: #{e.message}"
    end

    begin
      unless index_exists?(:assets, :deleted_at)
        add_index :assets, :deleted_at
      end
    rescue => e
      puts "Index on assets(deleted_at) might already exist: #{e.message}"
    end
  end
end
