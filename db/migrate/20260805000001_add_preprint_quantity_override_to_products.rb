class AddPreprintQuantityOverrideToProducts < ActiveRecord::Migration[7.2]
  def change
    add_column :products, :allow_preprint_quantity_override, :boolean,
               null: false, default: false
  end
end
