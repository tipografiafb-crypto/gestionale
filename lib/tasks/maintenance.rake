namespace :maintenance do
  desc "Clean up old asset files (older than DAYS_TO_KEEP environment variable, default 30)"
  task cleanup_old_files: :environment do
    days_to_keep = (ENV['DAYS_TO_KEEP'] || 30).to_i
    cutoff_date = days_to_keep.days.ago
    
    puts "🧹 Starting cleanup of files older than #{days_to_keep} days (before #{cutoff_date.strftime('%Y-%m-%d')})"
    
    deleted_count = 0
    freed_space = 0
    
    Asset.where("imported_at < ?", cutoff_date).where(deleted_at: nil).find_each do |asset|
      if asset.downloaded? && File.exist?(asset.local_path_full)
        file_size = File.size(asset.local_path_full)
        begin
          File.delete(asset.local_path_full)
          freed_space += file_size
          deleted_count += 1
          asset.update(deleted_at: Time.current)
          puts "  ✓ Deleted: #{asset.local_path}"
        rescue => e
          puts "  ✗ Error deleting #{asset.local_path}: #{e.message}"
        end
      end
    end
    
    puts "\n📊 Cleanup Summary:"
    puts "   Files deleted: #{deleted_count}"
    puts "   Space freed: #{format_bytes(freed_space)}"
    puts "✅ Cleanup completed!"
  end

  desc "Clean up files from specific month (YEAR=2025 MONTH=5)"
  task cleanup_by_month: :environment do
    year = ENV['YEAR'].to_i
    month = ENV['MONTH'].to_i
    
    if year == 0 || month == 0
      puts "❌ Error: Please provide YEAR and MONTH"
      puts "   Usage: rake maintenance:cleanup_by_month YEAR=2025 MONTH=5"
      exit 1
    end
    
    start_date = Date.new(year, month, 1).beginning_of_month
    end_date = start_date.end_of_month
    
    puts "🧹 Cleaning up files from #{start_date.strftime('%B %Y')}"
    puts "   Date range: #{start_date} to #{end_date}"
    
    deleted_count = 0
    freed_space = 0
    
    Asset.where("imported_at >= ? AND imported_at <= ?", start_date, end_date).where(deleted_at: nil).find_each do |asset|
      if asset.downloaded? && File.exist?(asset.local_path_full)
        file_size = File.size(asset.local_path_full)
        begin
          File.delete(asset.local_path_full)
          freed_space += file_size
          deleted_count += 1
          asset.update(deleted_at: Time.current)
          puts "  ✓ Deleted: #{asset.local_path}"
        rescue => e
          puts "  ✗ Error deleting #{asset.local_path}: #{e.message}"
        end
      end
    end
    
    puts "\n📊 Cleanup Summary:"
    puts "   Files deleted: #{deleted_count}"
    puts "   Space freed: #{format_bytes(freed_space)}"
    puts "✅ Cleanup completed!"
  end

  private

  def format_bytes(bytes)
    return '0 B' if bytes == 0
    units = ['B', 'KB', 'MB', 'GB']
    size = bytes.to_f
    unit_index = 0
    while size >= 1024.0 && unit_index < units.length - 1
      size /= 1024.0
      unit_index += 1
    end
    "#{size.round(2)} #{units[unit_index]}"
  end
end
