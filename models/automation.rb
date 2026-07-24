# @feature automation
# @domain data-models

require 'digest'
require 'pathname'

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
    (preprint_print_flows.to_a + print_print_flows.to_a + label_print_flows.to_a).uniq
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
      flow.versions.any? do |version|
        %w[draft published].include?(version.status) &&
          flow.handoff_target_ids(version).include?(id)
      end
    end
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
    queued running waiting_external waiting_review completed failed cancelled
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

class AutomationPreset < ActiveRecord::Base
  KINDS = %w[imposition adobe mask output].freeze

  validates :kind, inclusion: { in: KINDS }
  validates :code, :name, presence: true
  validates :code, uniqueness: { scope: :kind }

  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(:kind, :name) }
end

class AutomationAgent < ActiveRecord::Base
  validates :agent_key, :name, presence: true
  validates :agent_key, uniqueness: true

  scope :ordered, -> { order(:name) }

  def online?
    last_seen_at.present? && last_seen_at >= 15.seconds.ago
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
    automation_folder_flows.find_or_create_by!(automation_flow: flow) do |membership|
      membership.position = (automation_folder_flows.maximum(:position) || -1) + 1
    end
  end

  def chain_flows
    return automation_flows.to_a unless root_flow

    found = []
    queue = [root_flow]
    until queue.empty?
      flow = queue.shift
      next if found.include?(flow)

      found << flow
      targets = AutomationFlow.where(id: flow.handoff_target_ids).to_a
      queue.concat(targets)
    end
    found + (automation_flows.to_a - found)
  end
end

class AutomationFolderFlow < ActiveRecord::Base
  belongs_to :automation_folder
  belongs_to :automation_flow

  validates :automation_flow_id, uniqueness: {scope: :automation_folder_id}
end
