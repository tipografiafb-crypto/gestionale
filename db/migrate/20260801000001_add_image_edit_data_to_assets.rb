class AddImageEditDataToAssets < ActiveRecord::Migration[7.2]
  def change
    add_column :assets, :image_edit_data, :jsonb, default: {}, null: false unless column_exists?(:assets, :image_edit_data)
  end
end
