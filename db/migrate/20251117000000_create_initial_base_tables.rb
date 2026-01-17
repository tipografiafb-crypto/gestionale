class CreateInitialBaseTables < ActiveRecord::Migration[7.0]
  def change
    # STORES
    create_table :stores unless table_exists?(:stores) do |t|
      t.string :name, null: false
      t.string :api_url
      t.string :consumer_key
      t.string :consumer_secret
      t.boolean :active, default: true
      t.timestamps
    end

    # ORDERS
    create_table :orders unless table_exists?(:orders) do |t|
      t.integer :store_id
      t.string :order_number, null: false
      t.string :status, default: 'pending'
      t.string :source, default: 'api'
      t.string :customer_name
      t.string :customer_email
      t.text :customer_note
      t.timestamps
    end
    add_index :orders, :store_id unless index_exists?(:orders, :store_id)

    # ORDER ITEMS
    create_table :order_items unless table_exists?(:order_items) do |t|
      t.integer :order_id
      t.string :sku
      t.string :name
      t.integer :quantity, default: 1
      t.integer :position
      t.string :scala, default: '1:1'
      t.string :materiale
      t.json :campi_custom, default: {}
      t.json :campi_webhook, default: {}
      t.timestamps
    end
    add_index :order_items, :order_id unless index_exists?(:order_items, :order_id)

    # ASSETS
    create_table :assets unless table_exists?(:assets) do |t|
      t.integer :order_item_id
      t.string :file_path
      t.string :asset_type
      t.timestamp :imported_at, null: false, default: -> { 'CURRENT_TIMESTAMP' }
      t.timestamp :deleted_at
      t.timestamps
    end
    add_index :assets, :order_item_id unless index_exists?(:assets, :order_item_id)

    # SWITCH JOBS
    create_table :switch_jobs unless table_exists?(:switch_jobs) do |t|
      t.integer :order_item_id
      t.string :switch_job_id
      t.string :status
      t.integer :job_operation_id
      t.timestamps
    end
    add_index :switch_jobs, :order_item_id unless index_exists?(:switch_jobs, :order_item_id)
  end
end
