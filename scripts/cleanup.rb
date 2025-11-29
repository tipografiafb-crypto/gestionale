#!/usr/bin/env ruby
# @feature storage-management
# @domain admin
# Automated cleanup script - Run via cron to clean old assets
# Usage: ruby scripts/cleanup.rb [--dry-run] [--days N]

require_relative '../config/environment'

# Parse arguments
dry_run = ARGV.include?('--dry-run')
days_arg = ARGV.find { |arg| arg.start_with?('--days=') }
retention_days = days_arg ? days_arg.split('=')[1].to_i : (ENV['DAYS_TO_KEEP'] || 30).to_i

def format_file_size(bytes)
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

puts "━" * 60
puts "Storage Cleanup #{dry_run ? '[DRY RUN]' : '[EXECUTE]'}"
puts "━" * 60
puts "Retention: #{retention_days} days"
puts "Date cutoff: #{retention_days.days.ago.strftime('%Y-%m-%d %H:%M:%S')}"
puts

cutoff_date = retention_days.days.ago
deleted_count = 0
freed_space = 0
error_count = 0

Asset.where("created_at < ?", cutoff_date).where(deleted_at: nil).find_each do |asset|
  if asset.downloaded? && File.exist?(asset.local_path_full)
    file_size = File.size(asset.local_path_full)
    
    begin
      if dry_run
        puts "[DRY] Would delete: #{asset.local_path} (#{format_file_size(file_size)})"
      else
        File.delete(asset.local_path_full)
        asset.update(deleted_at: Time.current)
        puts "[OK] Deleted: #{asset.local_path} (#{format_file_size(file_size)})"
      end
      
      freed_space += file_size
      deleted_count += 1
    rescue => e
      puts "[ERROR] Failed: #{asset.local_path} - #{e.message}"
      error_count += 1
    end
  end
end

puts
puts "━" * 60
puts "Results:"
puts "  Files processed: #{deleted_count}"
puts "  Space #{dry_run ? 'would be ' : ''}freed: #{format_file_size(freed_space)}"
puts "  Errors: #{error_count}"
puts "━" * 60
puts "[#{dry_run ? 'DRY RUN' : 'COMPLETED'}] at #{Time.current.strftime('%Y-%m-%d %H:%M:%S')}"
