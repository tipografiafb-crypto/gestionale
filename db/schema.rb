# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[7.2].define(version: 2025_11_23_120002) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "assets", force: :cascade do |t|
    t.bigint "order_item_id", null: false
    t.string "original_url", null: false
    t.string "local_path"
    t.string "asset_type"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["order_item_id"], name: "index_assets_on_order_item_id"
  end

  create_table "order_items", force: :cascade do |t|
    t.bigint "order_id", null: false
    t.string "sku", null: false
    t.integer "quantity", default: 1, null: false
    t.text "raw_json"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "preprint_status", default: "pending"
    t.string "preprint_job_id"
    t.string "preprint_preview_url"
    t.string "print_status", default: "pending"
    t.string "print_job_id"
    t.datetime "preprint_completed_at"
    t.datetime "print_completed_at"
    t.bigint "preprint_print_flow_id"
    t.string "scala", default: "1:1"
    t.string "materiale"
    t.json "campi_custom", default: {}
    t.json "campi_webhook", default: {}
    t.bigint "print_machine_id"
    t.index ["order_id"], name: "index_order_items_on_order_id"
    t.index ["preprint_print_flow_id"], name: "index_order_items_on_preprint_print_flow_id"
    t.index ["preprint_status"], name: "index_order_items_on_preprint_status"
    t.index ["print_status"], name: "index_order_items_on_print_status"
  end

  create_table "orders", force: :cascade do |t|
    t.string "external_order_code", null: false
    t.bigint "store_id", null: false
    t.string "status", default: "new", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "source", default: "api"
    t.string "customer_name"
    t.text "customer_note"
    t.index ["store_id", "external_order_code"], name: "index_orders_on_store_id_and_external_order_code", unique: true
    t.index ["store_id"], name: "index_orders_on_store_id"
  end

  create_table "print_flow_machines", force: :cascade do |t|
    t.bigint "print_flow_id", null: false
    t.bigint "print_machine_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["print_flow_id", "print_machine_id"], name: "index_print_flow_machines_on_print_flow_id_and_print_machine_id", unique: true
    t.index ["print_flow_id"], name: "index_print_flow_machines_on_print_flow_id"
    t.index ["print_machine_id"], name: "index_print_flow_machines_on_print_machine_id"
  end

  create_table "print_flows", force: :cascade do |t|
    t.string "name", null: false
    t.text "notes"
    t.boolean "active", default: true
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "preprint_webhook_id"
    t.bigint "print_webhook_id"
    t.bigint "label_webhook_id"
    t.integer "operation_id"
    t.json "opzioni_stampa", default: {}
    t.index ["label_webhook_id"], name: "index_print_flows_on_label_webhook_id"
    t.index ["name"], name: "index_print_flows_on_name", unique: true
    t.index ["preprint_webhook_id"], name: "index_print_flows_on_preprint_webhook_id"
    t.index ["print_webhook_id"], name: "index_print_flows_on_print_webhook_id"
  end

  create_table "print_machines", force: :cascade do |t|
    t.string "name", null: false
    t.text "description"
    t.boolean "active", default: true
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_print_machines_on_name", unique: true
  end

  create_table "product_categories", force: :cascade do |t|
    t.string "name", null: false
    t.text "description"
    t.boolean "active", default: true
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_product_categories_on_name", unique: true
  end

  create_table "product_print_flows", force: :cascade do |t|
    t.bigint "product_id", null: false
    t.bigint "print_flow_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["print_flow_id"], name: "index_product_print_flows_on_print_flow_id"
    t.index ["product_id", "print_flow_id"], name: "index_product_print_flows_on_product_id_and_print_flow_id", unique: true
    t.index ["product_id"], name: "index_product_print_flows_on_product_id"
  end

  create_table "products", force: :cascade do |t|
    t.string "sku", null: false
    t.text "notes"
    t.boolean "active", default: true
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "name", null: false
    t.bigint "product_category_id"
    t.bigint "default_print_flow_id"
    t.index ["default_print_flow_id"], name: "index_products_on_default_print_flow_id"
    t.index ["product_category_id"], name: "index_products_on_product_category_id"
    t.index ["sku"], name: "index_products_on_sku", unique: true
  end

  create_table "stores", force: :cascade do |t|
    t.string "code", null: false
    t.string "name", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "active", default: true
    t.index ["active"], name: "index_stores_on_active"
    t.index ["code"], name: "index_stores_on_code", unique: true
  end

  create_table "switch_jobs", force: :cascade do |t|
    t.bigint "order_id", null: false
    t.string "switch_job_id"
    t.string "status", default: "pending", null: false
    t.string "result_preview_url"
    t.text "log"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "job_operation_id"
    t.index ["order_id"], name: "index_switch_jobs_on_order_id"
  end

  create_table "switch_webhooks", force: :cascade do |t|
    t.string "name", null: false
    t.string "hook_path", null: false
    t.bigint "store_id"
    t.boolean "active", default: true
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["name", "store_id"], name: "index_switch_webhooks_on_name_and_store_id", unique: true
    t.index ["store_id"], name: "index_switch_webhooks_on_store_id"
  end

  add_foreign_key "assets", "order_items"
  add_foreign_key "order_items", "orders"
  add_foreign_key "order_items", "print_flows", column: "preprint_print_flow_id"
  add_foreign_key "order_items", "print_machines"
  add_foreign_key "orders", "stores"
  add_foreign_key "print_flow_machines", "print_flows"
  add_foreign_key "print_flow_machines", "print_machines"
  add_foreign_key "print_flows", "switch_webhooks", column: "label_webhook_id"
  add_foreign_key "print_flows", "switch_webhooks", column: "preprint_webhook_id"
  add_foreign_key "print_flows", "switch_webhooks", column: "print_webhook_id"
  add_foreign_key "product_print_flows", "print_flows"
  add_foreign_key "product_print_flows", "products"
  add_foreign_key "products", "print_flows", column: "default_print_flow_id"
  add_foreign_key "products", "product_categories"
  add_foreign_key "switch_jobs", "orders"
  add_foreign_key "switch_webhooks", "stores"
end
