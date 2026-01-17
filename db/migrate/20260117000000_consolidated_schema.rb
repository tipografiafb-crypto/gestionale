class ConsolidatedSchema < ActiveRecord::Migration[7.0]
  def change
    create_table :stores, if_not_exists: true do |t|
      t.string :name, null: false
      t.string :api_url
      t.string :consumer_key
      t.string :consumer_secret
      t.boolean :active, default: true
      t.timestamps
    end

    create_table :orders, if_not_exists: true do |t|
      t.integer :store_id
      t.string :order_number, null: false
      t.string :status, default: 'pending'
      t.string :source, default: 'api'
      t.string :customer_name
      t.string :customer_email
      t.text :customer_note
      t.timestamps
    end

    create_table :order_items, if_not_exists: true do |t|
      t.integer :order_id
      t.string :sku
      t.string :name
      t.integer :quantity, default: 1
      t.string :print_status, default: 'pending'
      t.integer :position
      t.string :scala, default: '1:1'
      t.string :materiale
      t.json :campi_custom, default: {}
      t.json :campi_webhook, default: {}
      t.string :preprint_preview_url
      t.integer :preprint_print_flow_id
      t.integer :print_machine_id
      t.timestamps
    end

    create_table :products, if_not_exists: true do |t|
      t.string :sku, null: false
      t.string :name
      t.text :notes
      t.boolean :active, default: true
      t.integer :product_category_id
      t.integer :default_print_flow_id
      t.integer :min_stock_level, default: 0
      t.integer :master_product_id
      t.boolean :is_dependent, default: false
      t.integer :print_flow_id
      t.timestamps
    end

    create_table :inventories, if_not_exists: true do |t|
      t.integer :product_id, null: false
      t.integer :quantity_in_stock, default: 0, null: false
      t.timestamps
    end

    create_table :assets, if_not_exists: true do |t|
      t.integer :order_item_id
      t.string :file_path
      t.string :asset_type
      t.timestamp :imported_at, null: false, default: -> { 'CURRENT_TIMESTAMP' }
      t.timestamp :deleted_at
      t.timestamps
    end

    create_table :switch_webhooks, if_not_exists: true do |t|
      t.string :name, null: false
      t.string :hook_path, null: false
      t.integer :store_id
      t.boolean :active, default: true
      t.timestamps
    end

    create_table :print_flows, if_not_exists: true do |t|
      t.string :name, null: false
      t.integer :preprint_webhook_id
      t.integer :print_webhook_id
      t.boolean :azione_photoshop_enabled, default: false
      t.text :azione_photoshop_options
      t.string :default_azione_photoshop
      t.integer :operation_id
      t.json :opzioni_stampa, default: {}
      t.timestamps
    end

    create_table :product_categories, if_not_exists: true do |t|
      t.string :name, null: false
      t.text :description
      t.boolean :autopilot_preprint_enabled, default: false
      t.timestamps
    end

    create_table :switch_jobs, if_not_exists: true do |t|
      t.integer :order_item_id
      t.string :switch_job_id
      t.string :status
      t.integer :job_operation_id
      t.timestamps
    end

    create_table :print_machines, if_not_exists: true do |t|
      t.string :name, null: false
      t.text :description
      t.string :ip_address
      t.boolean :active, default: true
      t.timestamps
    end

    create_table :print_flow_machines, if_not_exists: true do |t|
      t.integer :print_flow_id
      t.integer :print_machine_id
      t.timestamps
    end

    create_table :logs, if_not_exists: true do |t|
      t.string :level
      t.string :category
      t.text :message
      t.text :details
      t.timestamps
    end

    create_table :import_errors, if_not_exists: true do |t|
      t.string :order_number
      t.text :error_message
      t.timestamps
    end
  end
end
