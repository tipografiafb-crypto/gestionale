# @feature storage-management
# @domain admin
# Admin cleanup routes - Manage file storage and cleanup

class PrintOrchestrator < Sinatra::Base
  RETENTION_DAYS = (ENV['DAYS_TO_KEEP'] || 30).to_i

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

  def calculate_total_disk_usage
    total = 0
    Dir.glob('storage/**/*').each do |file|
      total += File.size(file) if File.file?(file)
    end
    total
  end

  # GET /admin/cleanup - Cleanup dashboard
  get '/admin/cleanup' do
    @total_assets = Asset.count
    @downloaded_assets = Asset.not_deleted.where.not(local_path: nil).count
    @deleted_assets = Asset.deleted.count
    @disk_usage = format_file_size(calculate_total_disk_usage)
    @retention_days = RETENTION_DAYS
    
    # Get last cleanup time from log or return nil
    @last_cleanup_time = 'N/A'
    
    erb :admin_cleanup
  end

  # GET /admin/cleanup/preview - Preview files for a specific month
  get '/admin/cleanup/preview' do
    year = params[:year].to_i
    month = params[:month].to_i
    
    @total_assets = Asset.count
    @downloaded_assets = Asset.not_deleted.where.not(local_path: nil).count
    @deleted_assets = Asset.deleted.count
    @disk_usage = format_file_size(calculate_total_disk_usage)
    @retention_days = RETENTION_DAYS

    if month > 0 && year > 0
      start_date = Date.new(year, month, 1).beginning_of_month
      end_date = start_date.end_of_month
      
      @preview_assets = Asset.where("created_at >= ? AND created_at <= ?", start_date, end_date).where(deleted_at: nil).includes(:order_item).order(created_at: :desc)
      
      @preview_space = format_file_size(@preview_assets.sum { |a| a.file_size })
    else
      @preview_assets = []
      @preview_space = '0 B'
    end

    erb :admin_cleanup
  end

  # POST /admin/cleanup/auto - Execute automatic cleanup
  post '/admin/cleanup/auto' do
    begin
      cutoff_date = RETENTION_DAYS.days.ago
      deleted_count = 0
      freed_space = 0

      Asset.where("created_at < ?", cutoff_date).where(deleted_at: nil).find_each do |asset|
        if asset.downloaded? && File.exist?(asset.local_path_full)
          file_size = File.size(asset.local_path_full)
          begin
            File.delete(asset.local_path_full)
            freed_space += file_size
            deleted_count += 1
            asset.update(deleted_at: Time.current)
          rescue => e
            puts "Error deleting #{asset.local_path}: #{e.message}"
          end
        end
      end

      redirect "/admin/cleanup?msg=success&text=Pulizia+completata:+#{deleted_count}+file+eliminati,+#{format_file_size(freed_space)}+liberati"
    rescue => e
      redirect "/admin/cleanup?msg=error&text=Errore+durante+la+pulizia:+#{e.message}"
    end
  end

  # POST /admin/cleanup/delete_month - Delete files from specific month
  post '/admin/cleanup/delete_month' do
    begin
      year = params[:year].to_i
      month = params[:month].to_i

      if year == 0 || month == 0
        redirect "/admin/cleanup?msg=error&text=Anno+e+mese+non+validi"
        return
      end

      start_date = Date.new(year, month, 1).beginning_of_month
      end_date = start_date.end_of_month

      deleted_count = 0
      freed_space = 0

      Asset.where("created_at >= ? AND created_at <= ?", start_date, end_date).where(deleted_at: nil).find_each do |asset|
        if asset.downloaded? && File.exist?(asset.local_path_full)
          file_size = File.size(asset.local_path_full)
          begin
            File.delete(asset.local_path_full)
            freed_space += file_size
            deleted_count += 1
            asset.update(deleted_at: Time.current)
          rescue => e
            puts "Error deleting #{asset.local_path}: #{e.message}"
          end
        end
      end

      month_name = Date.new(year, month, 1).strftime('%B %Y')
      redirect "/admin/cleanup?msg=success&text=Eliminati+#{deleted_count}+file+da+#{month_name}+(#{format_file_size(freed_space)}+liberati)"
    rescue => e
      redirect "/admin/cleanup?msg=error&text=Errore+durante+l'eliminazione:+#{e.message}"
    end
  end
end
