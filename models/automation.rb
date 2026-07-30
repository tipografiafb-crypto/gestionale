# @feature automation
# @domain data-models

require 'digest'
require 'pathname'
require 'securerandom'
require 'active_support/security_utils'

class AutomationFlow < ActiveRecord::Base
  STATUSES = %w[draft published archived].freeze

  has_many :versions,
           class_name: 'AutomationFlowVersion',
           dependent: :destroy,
           inverse_of: :automation_flow
  belongs_to :active_version,
             class_name: 'AutomationFlowVersion',
             optional: true
  has_many :preprint_print_flows,
           class_name: 'PrintFlow',
           foreign_key: :preprint_automation_flow_id,
           dependent: :restrict_with_error
  has_many :print_print_flows,
           class_name: 'PrintFlow',
           foreign_key: :print_automation_flow_id,
           dependent: :restrict_with_error
  has_many :label_print_flows,
           class_name: 'PrintFlow',
           foreign_key: :label_automation_flow_id,
           dependent: :restrict_with_error
  has_many :print_flow_event_routes, dependent: :restrict_with_error
  has_many :automation_folder_flows, dependent: :destroy
  has_many :automation_folders, through: :automation_folder_flows
  has_many :root_automation_folders,
           class_name: 'AutomationFolder',
           foreign_key: :root_flow_id,
           dependent: :nullify

  validates :name, presence: true, uniqueness: true
  validates :status, inclusion: { in: STATUSES }

  scope :ordered, -> { order(name: :asc) }

  def linked_print_flows
    (
      preprint_print_flows.to_a +
      print_print_flows.to_a +
      label_print_flows.to_a +
      print_flow_event_routes.includes(:print_flow).map(&:print_flow)
    ).uniq
  end

  def runs_count
    versions.sum { |version| version.automation_runs.size }
  end

  def handoff_target_ids(version = active_version)
    return [] unless version

    Array(version.graph['nodes'])
      .select { |node| node['type'] == 'handoff' }
      .filter_map { |node| node.dig('config', 'target_flow_id').to_i.presence }
  end

  def incoming_handoff_flows
    AutomationFlow.where.not(id: id).includes(:versions).select do |flow|
      flow.current_dependency_versions.any? do |version|
        flow.handoff_target_ids(version).include?(id)
      end
    end
  end

  # Historical published versions remain available for old execution records,
  # but they must not keep current modules locked after a handoff is removed.
  def current_dependency_versions
    [
      active_version,
      versions.where(status: 'draft').order(version_number: :desc).first
    ].compact.uniq
  end

  def draft_version
    versions.where(status: 'draft').order(version_number: :desc).first ||
      versions.create!(
        version_number: (versions.maximum(:version_number) || 0) + 1,
        status: 'draft',
        graph: AutomationBootstrap.blank_graph
      )
  end

  def publish_draft!
    draft = draft_version
    errors = draft.graph_errors
    raise ArgumentError, errors.join(', ') if errors.any?

    transaction do
      versions.where(status: 'published').where.not(id: draft.id)
              .update_all(status: 'archived', updated_at: Time.current)
      draft.update!(
        status: 'published',
        published_at: Time.current,
        checksum: Digest::SHA256.hexdigest(JSON.generate(draft.graph))
      )
      update!(status: 'published', active_version: draft)
      versions.create!(
        version_number: draft.version_number + 1,
        status: 'draft',
        graph: JSON.parse(JSON.generate(draft.graph))
      )
    end
    draft
  end
end

class AutomationFlowVersion < ActiveRecord::Base
  STATUSES = %w[draft published archived].freeze

  belongs_to :automation_flow, inverse_of: :versions
  has_many :automation_runs, dependent: :restrict_with_error

  validates :version_number, presence: true,
                             numericality: { only_integer: true, greater_than: 0 }
  validates :status, inclusion: { in: STATUSES }

  def graph_errors
    AutomationGraphValidator.new(graph).errors +
      AutomationFlowChainValidator.new(automation_flow, graph).errors
  end
end

class AutomationRun < ActiveRecord::Base
  STATUSES = %w[
    queued running waiting_external waiting_review waiting_group completed failed cancelled
  ].freeze

  belongs_to :automation_flow_version
  belongs_to :order_item, optional: true
  belongs_to :source_asset, class_name: 'Asset', optional: true
  belongs_to :print_flow, optional: true
  belongs_to :parent_run, class_name: 'AutomationRun', optional: true
  belongs_to :root_run, class_name: 'AutomationRun', optional: true
  belongs_to :handoff_step, class_name: 'AutomationStepRun', optional: true
  has_many :child_runs,
           class_name: 'AutomationRun',
           foreign_key: :parent_run_id,
           dependent: :restrict_with_error
  has_many :automation_step_runs, dependent: :destroy
  has_many :automation_artifacts, dependent: :destroy

  validates :status, inclusion: { in: STATUSES }

  scope :recent, -> { order(created_at: :desc) }

  def flow
    automation_flow_version.automation_flow
  end

  def current_artifact
    artifact_id = context.dig('runtime', 'current_artifact_id')
    automation_artifacts.find_by(id: artifact_id) ||
      automation_artifacts.order(created_at: :desc).first
  end

  def artifact_by_kind(kind)
    automation_artifacts.where(kind: kind).order(created_at: :desc).first
  end

  def chain_root
    root_run || self
  end

  def chain_runs
    ids = [chain_root.id]
    index = 0
    while index < ids.length
      ids.concat(AutomationRun.where(parent_run_id: ids[index]).pluck(:id))
      index += 1
    end
    AutomationRun.where(id: ids).order(:created_at)
  end
end

class AutomationStepRun < ActiveRecord::Base
  STATUSES = %w[
    queued running waiting_external waiting_review completed failed skipped
  ].freeze

  belongs_to :automation_run
  has_many :automation_artifacts, dependent: :nullify

  validates :node_key, :node_type, presence: true
  validates :status, inclusion: { in: STATUSES }

  scope :ready, lambda {
    where(status: 'queued')
      .where('available_at IS NULL OR available_at <= ?', Time.current)
      .order(:created_at)
  }
end

class AutomationArtifact < ActiveRecord::Base
  belongs_to :automation_run
  belongs_to :automation_step_run, optional: true

  validates :kind, :filename, :local_path, presence: true

  def full_path
    Pathname.new(local_path).absolute? ? local_path : File.join(Dir.pwd, local_path)
  end

  def available?
    File.file?(full_path)
  end
end

class AutomationGroupCollection < ActiveRecord::Base
  STATUSES = %w[collecting completed failed].freeze

  belongs_to :automation_flow_version
  belongs_to :coordinator_run, class_name: 'AutomationRun', optional: true
  belongs_to :output_artifact, class_name: 'AutomationArtifact', optional: true
  has_many :items,
           class_name: 'AutomationGroupCollectionItem',
           dependent: :destroy,
           inverse_of: :automation_group_collection

  validates :node_key, :group_key, presence: true
  validates :expected_count, numericality: {only_integer: true, greater_than: 0}
  validates :status, inclusion: {in: STATUSES}
end

class AutomationGroupCollectionItem < ActiveRecord::Base
  belongs_to :automation_group_collection, inverse_of: :items
  belongs_to :automation_run
  belongs_to :automation_artifact

  validates :automation_run_id,
            uniqueness: {scope: :automation_group_collection_id}
end

class AutomationPreset < ActiveRecord::Base
  KINDS = %w[imposition adobe mask].freeze

  validates :kind, inclusion: { in: KINDS }
  validates :code, :name, presence: true
  validates :code, uniqueness: { scope: :kind }

  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(:kind, :name) }
end

class AutomationDestination < ActiveRecord::Base
  KINDS = %w[network_folder ipp_printer].freeze
  CODE_FORMAT = /\A[A-Za-z0-9_-]+\z/

  has_many :print_machines,
           foreign_key: :automation_destination_id,
           dependent: :restrict_with_error
  has_many :label_print_machines,
           class_name: 'PrintMachine',
           foreign_key: :label_automation_destination_id,
           dependent: :restrict_with_error

  validates :kind, inclusion: {in: KINDS}
  validates :code, :name, presence: true
  validates :code, uniqueness: true, format: {
    with: CODE_FORMAT,
    message: 'può contenere solo lettere, numeri, trattino e underscore'
  }
  validate :validate_configuration

  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(:kind, :name) }

  def network_folder?
    kind == 'network_folder'
  end

  def ipp_printer?
    kind == 'ipp_printer'
  end

  def checked?
    last_checked_at.present?
  end

  def available?
    last_check_status == 'ok'
  end

  def referenced_by_flows
    AutomationFlowVersion.includes(:automation_flow).select do |version|
      Array(version.graph['nodes']).any? do |node|
        node.dig('config', 'destination_code').to_s == code
      end
    end.map(&:automation_flow).uniq
  end

  private

  def validate_configuration
    values = config.is_a?(Hash) ? config : {}
    if network_folder?
      container_path = values['container_path'].to_s.strip
      root = ENV.fetch('AUTOMATION_DESTINATIONS_ROOT', '/destinations')
      errors.add(:config, 'deve indicare il percorso operativo sul server') if container_path.empty?
      errors.add(:config, "deve trovarsi sotto #{root}") unless
        container_path == root || container_path.start_with?("#{root}/")
    elsif ipp_printer?
      errors.add(:config, 'deve indicare il nome della coda di stampa') if
        values['queue'].to_s.strip.empty?
      copies = values['copies'].to_i
      errors.add(:config, 'deve avere un numero di copie compreso tra 1 e 999') unless
        copies.between?(1, 999)
    end
  end
end

class AutomationAgent < ActiveRecord::Base
  has_many :pairings,
           class_name: 'AutomationAgentPairing',
           dependent: :nullify

  validates :agent_key, :name, presence: true
  validates :agent_key, uniqueness: true

  scope :ordered, -> {
    order(Arel.sql('CASE WHEN revoked_at IS NULL THEN 0 ELSE 1 END'), name: :asc)
  }
  scope :active, -> { where(revoked_at: nil) }

  def online?
    active? && last_seen_at.present? && last_seen_at >= 15.seconds.ago
  end

  def active?
    revoked_at.nil?
  end

  def authenticate_token?(token)
    return false if token_digest.blank? || token.blank? || !active?

    candidate = Digest::SHA256.hexdigest(token.to_s)
    candidate.bytesize == token_digest.bytesize &&
      ActiveSupport::SecurityUtils.secure_compare(candidate, token_digest)
  end

  def issue_token!
    token = SecureRandom.urlsafe_base64(36)
    update!(
      token_digest: Digest::SHA256.hexdigest(token),
      paired_at: Time.current,
      revoked_at: nil
    )
    token
  end
end

class AutomationAgentPairing < ActiveRecord::Base
  LIFETIME = 10.minutes

  belongs_to :automation_agent, optional: true

  validates :code_digest, :expires_at, presence: true
  validates :code_digest, uniqueness: true

  scope :recent, -> { order(created_at: :desc) }
  scope :pending, -> {
    where(consumed_at: nil)
      .where('expires_at > ?', Time.current)
  }

  def self.issue!(requested_name: nil)
    20.times do
      code = format('%06d', SecureRandom.random_number(1_000_000))
      pairing = create!(
        code_digest: digest_code(code),
        requested_name: requested_name.to_s.strip.presence,
        expires_at: LIFETIME.from_now
      )
      return [pairing, "#{code[0, 3]}-#{code[3, 3]}"]
    rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
      next
    end
    raise 'Impossibile generare un codice di associazione univoco'
  end

  def self.find_available(code)
    normalized = code.to_s.gsub(/\D/, '')
    return nil unless normalized.match?(/\A\d{6}\z/)

    pending.find_by(code_digest: digest_code(normalized))
  end

  def self.digest_code(code)
    Digest::SHA256.hexdigest(code.to_s.gsub(/\D/, ''))
  end

  def consume!(agent)
    with_lock do
      raise ArgumentError, 'Codice di associazione già utilizzato' if consumed_at.present?
      raise ArgumentError, 'Codice di associazione scaduto' if expires_at <= Time.current

      update!(automation_agent: agent, consumed_at: Time.current)
    end
  end
end

class AutomationFolder < ActiveRecord::Base
  belongs_to :root_flow, class_name: 'AutomationFlow', optional: true
  has_many :automation_folder_flows,
           -> { order(:position, :id) },
           dependent: :destroy
  has_many :automation_flows, through: :automation_folder_flows

  validates :name, presence: true, uniqueness: true

  scope :ordered, -> { order(:name) }

  def include_flow!(flow)
    transaction do
      AutomationFolderFlow.where(automation_flow: flow)
                          .where.not(automation_folder_id: id)
                          .destroy_all
      automation_folder_flows.find_or_create_by!(automation_flow: flow) do |membership|
        membership.position = (automation_folder_flows.maximum(:position) || -1) + 1
      end
    end
  end

  def chain_flows
    automation_flows.to_a
  end
end

class AutomationFolderFlow < ActiveRecord::Base
  belongs_to :automation_folder
  belongs_to :automation_flow

  validates :automation_flow_id, uniqueness: {scope: :automation_folder_id}
end
