class CreateImpositionTemplates < ActiveRecord::Migration[7.2]
  class MigrationPreset < ActiveRecord::Base
    self.table_name = 'automation_presets'
  end

  class MigrationTemplate < ActiveRecord::Base
    self.table_name = 'imposition_templates'
  end

  class MigrationVersion < ActiveRecord::Base
    self.table_name = 'imposition_template_versions'
  end

  def up
    create_table :imposition_templates do |t|
      t.string :code, null: false
      t.string :name, null: false
      t.string :folder, null: false, default: 'Principale'
      t.text :description
      t.string :status, null: false, default: 'draft'
      t.bigint :active_version_id
      t.timestamps
    end
    add_index :imposition_templates, :code, unique: true
    add_index :imposition_templates, :active_version_id

    create_table :imposition_template_versions do |t|
      t.references :imposition_template, null: false, foreign_key: true
      t.integer :version_number, null: false
      t.string :status, null: false, default: 'draft'
      t.jsonb :config, null: false, default: {}
      t.timestamp :published_at
      t.timestamps
    end
    add_index :imposition_template_versions,
              [:imposition_template_id, :version_number],
              unique: true,
              name: 'idx_imposition_versions_unique'
    add_foreign_key :imposition_templates,
                    :imposition_template_versions,
                    column: :active_version_id

    MigrationPreset.where(kind: 'imposition').find_each do |preset|
      folder = preset.config.is_a?(Hash) ? preset.config['folder'].to_s : ''
      template = MigrationTemplate.create!(
        code: preset.code,
        name: preset.name,
        folder: folder.empty? ? 'Principale' : folder,
        description: 'Importata dalla libreria preset esistente',
        status: preset.active? ? 'published' : 'archived'
      )
      published = MigrationVersion.create!(
        imposition_template_id: template.id,
        version_number: 1,
        status: 'published',
        config: preset.config,
        published_at: preset.updated_at || Time.current
      )
      template.update_column(:active_version_id, published.id)
      MigrationVersion.create!(
        imposition_template_id: template.id,
        version_number: 2,
        status: 'draft',
        config: preset.config
      )
    end
  end

  def down
    remove_foreign_key :imposition_templates, column: :active_version_id
    drop_table :imposition_template_versions
    drop_table :imposition_templates
  end
end
