class CreateHalftonePresets < ActiveRecord::Migration[7.2]
  def change
    create_table :halftone_presets, if_not_exists: true do |t|
      t.string :name, null: false
      t.json :settings, default: {}, null: false
      t.timestamps
    end

    add_index :halftone_presets, :name, unique: true unless index_exists?(:halftone_presets, :name)
  end
end
