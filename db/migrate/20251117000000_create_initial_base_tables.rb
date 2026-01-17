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
      t.references :store, foreign_key: true
      t.string :order_number, null: false
      t.string :status, default: 'pending'
      t.string :source
      t.string :customer_name
      t.string :customer_email
      t.timestamps
    end

    # ORDER ITEMS
    create_table :order_items unless table_exists?(:order_items) do |t|
      t.references :order, foreign_key: true
      t.string :sku
      t.string :name
      t.integer :quantity, default: 1
      t.string :print_status, default: 'pending'
      t.integer :position
      t.timestamps
    end

    # ASSETS
    create_table :assets unless table_exists?(:assets) do |t|
      t.references :order_item, foreign_key: true
      t.string :file_path
      t.string :asset_type
      t.timestamps
    end
  end
end
