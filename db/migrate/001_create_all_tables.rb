class CreateAllTables < ActiveRecord::Migration[7.2]
  def change
    # ===== CORE TABLES =====
    create_table :stores do |t|
      t.string :code, null: false, index: { unique: true }
      t.string :name, null: false
      t.boolean :active, default: true
      t.timestamps
    end

    create_table :orders do |t|
      t.string :external_order_code, null: false
      t.references :store, null: false, foreign_key: true
      t.string :status, null: false, default: 'new'
      t.string :source, default: 'api'
      t.string :customer_name
      t.text :customer_note
      t.timestamps
    end
    add_index :orders, [:store_id, :external_order_code], unique: true

    create_table :import_errors do |t|
      t.string :filename, null: false
      t.string :external_order_code
      t.text :error_message, null: false
      t.timestamps
    end
    add_index :import_errors, :created_at

    create_table :order_items do |t|
      t.references :order, null: false, foreign_key: true
      t.string :sku, null: false
      t.integer :quantity, null: false, default: 1
      t.text :raw_json
      
      # Switch payload fields
      t.string :scala, default: "1:1"
      t.string :materiale
      t.json :campi_custom, default: {}
      t.json :campi_webhook, default: {}
      
      # Tracking fields
      t.string :preprint_status, default: 'pending'
      t.string :preprint_job_id
      t.string :preprint_preview_url
      t.datetime :preprint_started_at
      t.datetime :preprint_completed_at
      
      t.string :print_status, default: 'pending'
      t.string :print_job_id
      t.datetime :print_started_at
      t.datetime :print_completed_at
      
      t.references :preprint_print_flow, foreign_key: { to_table: :print_flows }, optional: true
      t.bigint :print_machine_id
      
      t.timestamps
    end
    add_index :order_items, :preprint_status
    add_index :order_items, :print_status

    create_table :assets do |t|
      t.references :order_item, null: false, foreign_key: true
      t.string :original_url, null: false
      t.string :local_path
      t.string :asset_type
      t.timestamps
    end

    create_table :switch_jobs do |t|
      t.references :order, null: false, foreign_key: true
      t.string :switch_job_id
      t.string :status, null: false, default: 'pending'
      t.string :result_preview_url
      t.text :log
      t.integer :job_operation_id
      t.timestamps
    end

    # ===== WEBHOOKS & WORKFLOWS =====
    create_table :switch_webhooks do |t|
      t.string :name, null: false
      t.string :hook_path, null: false
      t.references :store, foreign_key: true, null: true
      t.boolean :active, default: true
      t.timestamps
    end
    add_index :switch_webhooks, [:name, :store_id], unique: true

    create_table :print_flows do |t|
      t.string :name, null: false
      t.text :notes
      t.references :preprint_webhook, foreign_key: { to_table: :switch_webhooks }, optional: true
      t.references :print_webhook, foreign_key: { to_table: :switch_webhooks }, optional: true
      t.references :label_webhook, foreign_key: { to_table: :switch_webhooks }, optional: true
      t.integer :operation_id
      t.json :opzioni_stampa, default: {}
      t.timestamps
    end
    add_index :print_flows, :name, unique: true

    # ===== PRODUCTS & ROUTING =====
    create_table :products do |t|
      t.string :sku, null: false
      t.string :name, null: false
      t.text :notes
      t.integer :min_stock_level, default: 0
      t.references :product_category, foreign_key: true, null: true
      t.references :default_print_flow, foreign_key: { to_table: :print_flows }, optional: true
      t.timestamps
    end
    add_index :products, :sku, unique: true

    create_table :product_print_flows do |t|
      t.references :product, null: false, foreign_key: true
      t.references :print_flow, null: false, foreign_key: true
      t.timestamps
    end
    add_index :product_print_flows, [:product_id, :print_flow_id], unique: true

    create_table :product_categories do |t|
      t.string :name, null: false
      t.text :description
      t.timestamps
    end
    add_index :product_categories, :name, unique: true

    # ===== PRINTING MACHINES =====
    create_table :print_machines do |t|
      t.string :name, null: false
      t.string :description
      t.boolean :active, null: false, default: true
      t.timestamps
    end
    add_index :print_machines, :name, unique: true

    create_table :print_flow_machines do |t|
      t.references :print_flow, null: false, foreign_key: true
      t.references :print_machine, null: false, foreign_key: true
      t.timestamps
    end
    add_index :print_flow_machines, [:print_flow_id, :print_machine_id], unique: true

    # ===== INVENTORY =====
    create_table :inventories do |t|
      t.references :product, null: false, foreign_key: true
      t.integer :quantity_in_stock, null: false, default: 0
      t.timestamps
    end
    add_index :inventories, :product_id, unique: true

    # Add foreign key for print_machine_id in order_items
    add_foreign_key :order_items, :print_machines, column: :print_machine_id
  end
end
