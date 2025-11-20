class CreateAssets < ActiveRecord::Migration[7.1]
  def change
    create_table :assets do |t|
      t.references :order_item, null: false, foreign_key: true
      t.string :original_url, null: false
      t.string :local_path
      t.string :asset_type
      t.timestamps
    end
  end
end
