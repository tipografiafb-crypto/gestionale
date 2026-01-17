class ConsolidatedSchema < ActiveRecord::Migration[7.2]
  def change
    # stores
    create_table :stores, if_not_exists: true do |t|
      t.string :code, null: false
      t.string :name, null: false
      t.boolean :active, default: true
      t.timestamps
    end
    add_index :stores, :code, unique: true if index_name_exists?(:stores, :code).nil?

    # orders
    create_table :orders, if_not_exists: true do |t|
      t.string :external_order_code, null: false
      t.bigint :store_id, null: false
      t.string :status, default: 'new', null: false
      t.string :source, default: 'api'
      t.string :customer_name
      t.text :customer_note
      t.text :notes
      t.timestamps
    end
    add_index :orders, :store_id if index_name_exists?(:orders, :store_id).nil?
    add_index :orders, [:store_id, :external_order_code], unique: true if index_name_exists?(:orders, [:store_id, :external_order_code]).nil?

    # order_items
    create_table :order_items, if_not_exists: true do |t|
      t.bigint :order_id, null: false
      t.string :sku, null: false
      t.integer :quantity, default: 1, null: false
      t.text :raw_json
      t.string :preprint_status, default: 'pending'
      t.string :preprint_job_id
      t.string :preprint_preview_url
      t.string :print_status, default: 'pending'
      t.string :print_job_id
      t.timestamp :preprint_completed_at
      t.timestamp :print_completed_at
      t.bigint :preprint_print_flow_id
      t.string :scala, default: '1:1'
      t.string :materiale
      t.json :campi_custom, default: {}
      t.json :campi_webhook, default: {}
      t.bigint :print_machine_id
      t.integer :position, default: 0
      t.timestamps
    end

    # assets
    create_table :assets, if_not_exists: true do |t|
      t.bigint :order_item_id, null: false
      t.string :original_url, null: false
      t.string :local_path
      t.string :asset_type
      t.timestamp :deleted_at
      t.timestamps
    end

    # products
    create_table :products, if_not_exists: true do |t|
      t.string :sku, null: false
      t.string :name, null: false
      t.text :notes
      t.boolean :active, default: true
      t.bigint :product_category_id
      t.bigint :default_print_flow_id
      t.integer :min_stock_level, default: 0
      t.timestamps
    end

    # inventories
    create_table :inventories, if_not_exists: true do |t|
      t.integer :product_id, null: false
      t.integer :quantity_in_stock, default: 0
      t.timestamps
    end

    # product_categories
    create_table :product_categories, if_not_exists: true do |t|
      t.string :name, null: false
      t.text :description
      t.boolean :active, default: true
      t.boolean :autopilot_preprint_enabled, default: false
      t.timestamps
    end

    # print_flows
    create_table :print_flows, if_not_exists: true do |t|
      t.string :name, null: false
      t.text :notes
      t.boolean :active, default: true
      t.bigint :preprint_webhook_id
      t.bigint :print_webhook_id
      t.bigint :label_webhook_id
      t.integer :operation_id
      t.json :opzioni_stampa, default: {}
      t.boolean :azione_photoshop_enabled, default: false
      t.text :azione_photoshop_options
      t.string :default_azione_photoshop
      t.timestamps
    end

    # switch_webhooks
    create_table :switch_webhooks, if_not_exists: true do |t|
      t.string :name, null: false
      t.string :hook_path, null: false
      t.bigint :store_id
      t.boolean :active, default: true
      t.timestamps
    end

    # switch_jobs
    create_table :switch_jobs, if_not_exists: true do |t|
      t.bigint :order_id, null: false
      t.string :switch_job_id
      t.string :status, default: 'pending', null: false
      t.string :result_preview_url
      t.text :log
      t.integer :job_operation_id
      t.timestamps
    end

    # print_machines
    create_table :print_machines, if_not_exists: true do |t|
      t.string :name, null: false
      t.text :description
      t.boolean :active, default: true
      t.timestamps
    end

    # print_flow_machines
    create_table :print_flow_machines, if_not_exists: true do |t|
      t.bigint :print_flow_id, null: false
      t.bigint :print_machine_id, null: false
      t.timestamps
    end

    # product_print_flows
    create_table :product_print_flows, if_not_exists: true do |t|
      t.bigint :product_id, null: false
      t.bigint :print_flow_id, null: false
      t.timestamps
    end

    # aggregated_jobs
    create_table :aggregated_jobs, if_not_exists: true do |t|
      t.string :name, null: false
      t.string :status, default: 'pending'
      t.integer :nr_files, default: 0
      t.integer :print_flow_id
      t.text :aggregated_file_url
      t.string :aggregated_filename
      t.timestamp :sent_at
      t.timestamp :aggregated_at
      t.timestamp :completed_at
      t.text :notes
      t.timestamp :preprint_sent_at
      t.timestamps
    end

    # aggregated_job_items
    create_table :aggregated_job_items, if_not_exists: true do |t|
      t.integer :aggregated_job_id, null: false
      t.integer :order_item_id, null: false
      t.timestamps
    end

    # backup_configs
    create_table :backup_configs, if_not_exists: true do |t|
      t.string :remote_ip
      t.string :remote_path
      t.string :ssh_username
      t.string :ssh_password
      t.integer :ssh_port, default: 22
      t.timestamps
    end

    # logs
    create_table :logs, if_not_exists: true do |t|
      t.string :level
      t.string :category
      t.text :message
      t.text :details
      t.timestamps
    end

    # import_errors
    create_table :import_errors, if_not_exists: true do |t|
      t.bigint :store_id
      t.string :filename
      t.string :external_order_code
      t.text :error_message
      t.timestamp :import_date
      t.timestamps
    end
  end

  private

  def index_name_exists?(table_name, column_name)
    indexes(table_name).find { |i| i.columns == Array(column_name).map(&:to_s) }
  end
end
