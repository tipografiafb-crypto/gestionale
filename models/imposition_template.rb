require 'json'

class ImpositionTemplate < ActiveRecord::Base
  STATUSES = %w[draft published archived].freeze

  has_many :versions,
           class_name: 'ImpositionTemplateVersion',
           dependent: :destroy,
           inverse_of: :imposition_template
  belongs_to :active_version,
             class_name: 'ImpositionTemplateVersion',
             optional: true

  validates :code, :name, :folder, presence: true
  validates :code, uniqueness: true, format: {
    with: /\A[A-Za-z0-9_-]+\z/,
    message: 'può contenere solo lettere, numeri, trattino e underscore'
  }
  validates :status, inclusion: {in: STATUSES}

  scope :ordered, -> { order(:folder, :name) }
  before_destroy :clear_active_version_reference, prepend: true

  def draft_version
    versions.where(status: 'draft').order(version_number: :desc).first ||
      versions.create!(
        version_number: versions.maximum(:version_number).to_i + 1,
        status: 'draft',
        config: active_version&.config || ImpositionConfig.default
      )
  end

  def publish_draft!
    draft = draft_version
    normalized = ImpositionConfig.normalize(draft.config)

    transaction do
      versions.where(status: 'published').where.not(id: draft.id)
              .update_all(status: 'archived', updated_at: Time.current)
      draft.update!(status: 'published', config: normalized, published_at: Time.current)
      update!(status: 'published', active_version: draft)
      AutomationPreset.find_or_initialize_by(kind: 'imposition', code: code).update!(
        name: name,
        config: normalized.merge('folder' => folder),
        active: true
      )
      versions.create!(
        version_number: versions.maximum(:version_number).to_i + 1,
        status: 'draft',
        config: JSON.parse(JSON.generate(normalized))
      )
    end
    draft
  end

  private

  def clear_active_version_reference
    update_column(:active_version_id, nil) if active_version_id.present?
  end
end

class ImpositionTemplateVersion < ActiveRecord::Base
  STATUSES = %w[draft published archived].freeze

  belongs_to :imposition_template, inverse_of: :versions
  validates :version_number, numericality: {only_integer: true, greater_than: 0}
  validates :status, inclusion: {in: STATUSES}
end
