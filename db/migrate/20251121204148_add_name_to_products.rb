class AddNameToProducts < ActiveRecord::Migration[7.2]
  def change
    add_column :products, :name, :string, null: false, default: ""
    change_column_default :products, :name, nil
  end
end
