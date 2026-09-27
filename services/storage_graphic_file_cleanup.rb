require 'set'

class StorageGraphicFileCleanup
  GRAPHIC_EXTENSIONS = %w[
    .pdf .png .jpg .jpeg .tif .tiff .psd .ai .eps .svg .webp .bmp .gif .heic
    .indd .ps .xcf .raw .cr2 .nef .arw .dng
  ].freeze

  def initialize(root: File.join(Dir.pwd, 'storage'), cutoff:)
    @root = File.expand_path(root)
    @cutoff = cutoff
  end

  def candidate_files
    return [] unless Dir.exist?(@root)

    Dir.glob(File.join(@root, '**', '*')).filter_map do |path|
      next if File.symlink?(path)
      next unless File.file?(path)
      next unless GRAPHIC_EXTENSIONS.include?(File.extname(path).downcase)

      expanded_path = File.expand_path(path)
      next unless expanded_path.start_with?("#{@root}#{File::SEPARATOR}")
      next unless File.mtime(expanded_path) < @cutoff

      {path: expanded_path, size: File.size(expanded_path)}
    end
  end

  def cleanup(dry_run: false)
    entries = candidate_files
    result = {
      entries: entries,
      candidate_count: entries.length,
      candidate_bytes: entries.sum { |entry| entry[:size] },
      deleted_count: 0,
      freed_bytes: 0,
      deleted_asset_count: 0,
      deleted_artifact_count: 0,
      errors: []
    }
    return result if dry_run

    deleted_paths = []
    entries.each do |entry|
      File.delete(entry[:path])
      result[:deleted_count] += 1
      result[:freed_bytes] += entry[:size]
      deleted_paths << entry[:path]
    rescue Errno::ENOENT
      next
    rescue StandardError => e
      result[:errors] << {path: entry[:path], message: e.message}
    end

    result[:deleted_asset_count] = mark_assets_deleted(deleted_paths)
    result[:deleted_artifact_count] = delete_artifact_records(deleted_paths)
    result
  end

  private

  def mark_assets_deleted(deleted_paths)
    deleted_paths = deleted_paths.to_set
    asset_ids = Asset.where.not(local_path: nil).pluck(:id, :local_path).filter_map do |id, local_path|
      id if deleted_paths.include?(File.expand_path(local_path.to_s, Dir.pwd))
    end
    Asset.where(id: asset_ids, deleted_at: nil).update_all(deleted_at: Time.current)
  end

  def delete_artifact_records(deleted_paths)
    deleted_paths = deleted_paths.to_set
    artifact_ids = AutomationArtifact.pluck(:id, :local_path).filter_map do |id, local_path|
      id if deleted_paths.include?(File.expand_path(local_path.to_s, Dir.pwd))
    end
    AutomationArtifact.where(id: artifact_ids).destroy_all.length
  end
end
