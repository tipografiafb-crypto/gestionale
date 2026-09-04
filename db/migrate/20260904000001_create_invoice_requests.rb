class CreateInvoiceRequests < ActiveRecord::Migration[7.2]
  def change
    create_table :invoice_requests do |t|
      t.references :order, null: false, foreign_key: true, index: { unique: true }
      t.string :status, null: false, default: 'not_issued'
      t.integer :schema_version, null: false, default: 1
      t.datetime :order_placed_at
      t.datetime :status_changed_at
      t.datetime :issued_at

      t.string :customer_type
      t.string :company_name
      t.string :first_name
      t.string :last_name
      t.string :tax_country
      t.string :vat_number
      t.string :tax_code
      t.string :recipient_code
      t.string :pec
      t.string :email
      t.string :phone

      t.string :address_1
      t.string :address_2
      t.string :postcode
      t.string :city
      t.string :province
      t.string :country

      t.decimal :subtotal, precision: 14, scale: 2
      t.decimal :discount, precision: 14, scale: 2
      t.decimal :shipping, precision: 14, scale: 2
      t.decimal :shipping_tax, precision: 14, scale: 2
      t.decimal :tax, precision: 14, scale: 2
      t.decimal :total, precision: 14, scale: 2
      t.string :currency, limit: 3

      t.jsonb :line_items, null: false, default: []
      t.jsonb :raw_payload, null: false, default: {}
      t.text :notes
      t.timestamps
    end

    add_index :invoice_requests, :status
    add_index :invoice_requests, :order_placed_at
    add_index :invoice_requests, :vat_number
    add_index :invoice_requests, :tax_code
  end
end
