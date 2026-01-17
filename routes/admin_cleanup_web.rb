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

  # POST /admin/cleanup/test - DRY RUN (no delete)
  post '/admin/cleanup/test' do
    begin
      cutoff_date = RETENTION_DAYS.days.ago
      test_count = 0
      test_space = 0
      candidates = 0

      # Find all assets older than retention period
      old_assets = Asset.where("created_at < ?", cutoff_date).where(deleted_at: nil)
      candidates = old_assets.count

      old_assets.find_each do |asset|
        if asset.downloaded? && File.exist?(asset.local_path_full)
          file_size = File.size(asset.local_path_full)
          test_space += file_size
          test_count += 1
        end
      end

      if test_count > 0
        msg = "TEST PULIZIA (NO DELETE): #{test_count} file trovati (#{candidates} candidati), #{format_file_size(test_space)} da liberare"
      else
        msg = "TEST PULIZIA: Nessun file da eliminare. Candidati per età: #{candidates}, con local_path: #{Asset.where("created_at < ?", cutoff_date).where(deleted_at: nil).where.not(local_path: nil).count}"
      end
      redirect "/admin/cleanup?msg=info&text=#{URI.encode_www_form_component(msg)}"
    rescue => e
      redirect "/admin/cleanup?msg=error&text=#{URI.encode_www_form_component("Errore durante test: #{e.message}")}"
    end
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

  # GET /admin/backup - Show backup configuration page
  get '/admin/backup' do
    @backup_config = BackupConfig.current
    @backups = BackupManager.list_backups
    erb :admin_backup
  end

  # POST /admin/backup/config - Save backup configuration
  post '/admin/backup/config' do
    begin
      config = BackupConfig.current
      config.update(
        remote_ip: params[:remote_ip],
        remote_path: params[:remote_path],
        ssh_username: params[:ssh_username],
        ssh_password: params[:ssh_password],
        ssh_port: (params[:ssh_port].presence || 22).to_i
      )
      redirect "/admin/backup?msg=success&text=Configurazione+salvata"
    rescue => e
      redirect "/admin/backup?msg=error&text=Errore+nel+salvataggio:+#{e.message}"
    end
  end

  # POST /admin/backup/test - Test connection
  post '/admin/backup/test' do
    begin
      result = BackupManager.test_connection(params[:remote_ip], params[:remote_path])
      if result[:connected]
        redirect "/admin/backup?msg=success&text=Connessione+OK:+SSH+raggiungibile"
      else
        redirect "/admin/backup?msg=error&text=Errore+connessione:+#{result[:error]}"
      end
    rescue => e
      redirect "/admin/backup?msg=error&text=Errore+test:+#{e.message}"
    end
  end

  # POST /admin/backup/now - Execute backup immediately
  post '/admin/backup/now' do
    begin
      result = BackupManager.perform_backup
      if result[:success]
        msg = "Backup OK: #{result[:file]} (#{format_file_size(result[:size])}) salvato in #{result[:remote_path]}"
        redirect "/admin/backup?msg=success&text=#{URI.encode_www_form_component(msg)}"
      else
        redirect "/admin/backup?msg=error&text=#{URI.encode_www_form_component("Backup fallito: #{result[:error]}")}"
      end
    rescue => e
      redirect "/admin/backup?msg=error&text=#{URI.encode_www_form_component("Errore backup: #{e.message}")}"
    end
  end

  # POST /admin/backup/restore - Restore from backup
  post '/admin/backup/restore' do
    begin
      filename = params[:filename]
      result = BackupManager.restore_backup(filename)
      
      if result[:success]
        redirect "/admin/backup?msg=success&text=#{URI.encode_www_form_component("✓ #{result[:message]} - Database e file ripristinati")}"
      else
        redirect "/admin/backup?msg=error&text=#{URI.encode_www_form_component("Ripristino fallito: #{result[:error]}")}"
      end
    rescue => e
      redirect "/admin/backup?msg=error&text=#{URI.encode_www_form_component("Errore ripristino: #{e.message}")}"
    end
  end

  # POST /admin/backup/delete - Delete local backup file
  post '/admin/backup/delete' do
    begin
      filename = params[:filename]
      backup_dir = File.join(Dir.pwd, 'tmp', 'backups')
      file_path = File.join(backup_dir, filename)

      if File.exist?(file_path) && filename.start_with?('backup_') && filename.end_with?('.zip')
        File.delete(file_path)
        redirect "/admin/backup?msg=success&text=Backup+eliminato+correttamente"
      else
        redirect "/admin/backup?msg=error&text=File+non+trovato+o+non+valido"
      end
    rescue => e
      redirect "/admin/backup?msg=error&text=Errore+durante+l'eliminazione:+#{e.message}"
    end
  end

  # POST /admin/backup/restore_upload - Restore from uploaded file (disaster recovery)
  post '/admin/backup/restore_upload' do
    begin
      # Debug logging
      puts "[RESTORE_UPLOAD] === INIZIO RICHIESTA ==="
      puts "[RESTORE_UPLOAD] params.keys: #{params.keys.inspect}"
      puts "[RESTORE_UPLOAD] backup_file present?: #{params[:backup_file].present?}"
      
      if params[:backup_file]
        puts "[RESTORE_UPLOAD] backup_file class: #{params[:backup_file].class}"
        puts "[RESTORE_UPLOAD] backup_file keys: #{params[:backup_file].keys.inspect rescue 'N/A'}"
        puts "[RESTORE_UPLOAD] filename: #{params[:backup_file][:filename] rescue 'N/A'}"
        puts "[RESTORE_UPLOAD] tempfile: #{params[:backup_file][:tempfile] rescue 'N/A'}"
        puts "[RESTORE_UPLOAD] tempfile.path: #{params[:backup_file][:tempfile]&.path rescue 'N/A'}"
        puts "[RESTORE_UPLOAD] tempfile.size: #{params[:backup_file][:tempfile]&.size rescue 'N/A'}"
      else
        puts "[RESTORE_UPLOAD] ⚠️ params[:backup_file] is nil/false!"
      end
      
      return redirect("/admin/backup?msg=error&text=Nessun+file+caricato") unless params[:backup_file]

      result = BackupManager.restore_from_uploaded_file(params[:backup_file])
      
      if result[:success]
        redirect "/admin/backup?msg=success&text=#{URI.encode_www_form_component("✓ #{result[:message]} - Caricato e ripristinato")}"
      else
        redirect "/admin/backup?msg=error&text=#{URI.encode_www_form_component("Ripristino fallito: #{result[:error]}")}"
      end
    rescue => e
      puts "[RESTORE_UPLOAD] ❌ ERRORE: #{e.message}"
      puts "[RESTORE_UPLOAD] Backtrace: #{e.backtrace.first(5).join("\n")}"
      redirect "/admin/backup?msg=error&text=#{URI.encode_www_form_component("Errore ripristino: #{e.message}")}"
    end
  end
end
