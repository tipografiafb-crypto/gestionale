#!/usr/bin/env ruby
# @feature storage-management
# @domain admin
# Manual cleanup script for old graphical files throughout storage
# Usage: ruby scripts/cleanup.rb [--dry-run] [--days N]

ENV['DISABLE_BACKGROUND_POLLERS'] = '1'
require_relative '../app'

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
result = StorageGraphicFileCleanup.new(cutoff: cutoff_date).cleanup(dry_run: dry_run)
result[:entries].each do |entry|
  puts "[#{dry_run ? 'DRY' : 'OK'}] #{dry_run ? 'Would delete' : 'Deleted'} graphic file: #{entry[:path]} (#{format_file_size(entry[:size])})"
end
deleted_count = dry_run ? result[:candidate_count] : result[:deleted_count]
freed_space = dry_run ? result[:candidate_bytes] : result[:freed_bytes]
error_count = result[:errors].length

puts
puts "━" * 60
puts "Results:"
puts "  Files processed: #{deleted_count}"
puts "  Space #{dry_run ? 'would be ' : ''}freed: #{format_file_size(freed_space)}"
puts "  Errors: #{error_count}"
puts "━" * 60
puts "[#{dry_run ? 'DRY RUN' : 'COMPLETED'}] at #{Time.current.strftime('%Y-%m-%d %H:%M:%S')}"
