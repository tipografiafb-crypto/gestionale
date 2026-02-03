class AddCutFileFields < ActiveRecord::Migration[7.2]
  def change
    add_column :products, :has_cut_file, :boolean, default: false unless column_exists?(:products, :has_cut_file)
    # Assuming we want to store the local path of the cut file associated with a product
    add_column :products, :cut_file_path, :string unless column_exists?(:products, :cut_file_path)
  end
end
