# Keeps root executions and their entire chains together.
class AutomationRunRetention
  LIMIT = 50
  ACTIVE_STATUSES = %w[queued running waiting_external waiting_review waiting_group].freeze

  def self.prune!(limit: LIMIT)
    # Select only IDs so a large history never gets loaded into memory.
    cutoff = AutomationRun.where(parent_run_id: nil).order(created_at: :desc, id: :desc)
                          .offset(limit - 1).pick(:created_at, :id)
    return 0 unless cutoff

    removed = 0
    AutomationRun.where(parent_run_id: nil)
                 .where('created_at < ? OR (created_at = ? AND id < ?)', cutoff[0], cutoff[0], cutoff[1])
                 .find_each(batch_size: 100) do |root|
      removed += 1 if delete_finished_chain!(root)
    end
    removed
  end

  def self.delete_finished_chain!(root)
    paths = []
    deleted = false
    AutomationRun.transaction do
      root.lock!
      runs = root.chain_runs.to_a
      ids = runs.map(&:id)
      next if runs.any? { |run| ACTIVE_STATUSES.include?(run.status) }
      next if AutomationGroupCollection.where(status: 'collecting').where(coordinator_run_id: ids).exists?
      next if AutomationGroupCollectionItem.joins(:automation_group_collection)
             .where(automation_run_id: ids, automation_group_collections: {status: 'collecting'}).exists?

      artifacts = AutomationArtifact.where(automation_run_id: ids).to_a
      artifact_ids = artifacts.map(&:id)
      storage_root = File.expand_path('storage/automation/runs', Dir.pwd) + File::SEPARATOR
      paths = artifacts.map(&:full_path).select { |path| File.expand_path(path).start_with?(storage_root) }.uniq
      paths.reject! do |path|
        relative = path.sub(/^#{Regexp.escape(Dir.pwd)}\//, '')
        Asset.where(local_path: [path, relative]).exists? ||
          AutomationArtifact.where(local_path: [path, relative]).where.not(id: artifact_ids).exists?
      end
      AutomationGroupCollection.where(coordinator_run_id: ids).update_all(coordinator_run_id: nil)
      AutomationGroupCollection.where(output_artifact_id: artifact_ids).update_all(output_artifact_id: nil)
      AutomationGroupCollectionItem.where(automation_run_id: ids).or(
        AutomationGroupCollectionItem.where(automation_artifact_id: artifact_ids)
      ).delete_all
      # Handoff references point back to steps in the same chain.
      AutomationRun.where(id: ids).update_all(handoff_step_id: nil, root_run_id: nil)
      runs.sort_by(&:id).reverse_each(&:destroy!)
      deleted = true
    end
    paths.each { |path| FileUtils.rm_f(path) } if deleted
    deleted
  end
end
