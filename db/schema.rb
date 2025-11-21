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

ActiveRecord::Schema[7.2].define(version: 2025_11_21_204148) do
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
    t.index ["order_id"], name: "index_order_items_on_order_id"
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

  create_table "products", force: :cascade do |t|
    t.string "sku", null: false
    t.bigint "switch_webhook_id", null: false
    t.text "notes"
    t.boolean "active", default: true
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "name", null: false
    t.index ["sku"], name: "index_products_on_sku", unique: true
    t.index ["switch_webhook_id"], name: "index_products_on_switch_webhook_id"
  end

  create_table "stores", force: :cascade do |t|
    t.string "code", null: false
    t.string "name", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
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
  add_foreign_key "orders", "stores"
  add_foreign_key "products", "switch_webhooks"
  add_foreign_key "switch_jobs", "orders"
  add_foreign_key "switch_webhooks", "stores"
end
