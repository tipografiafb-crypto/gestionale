# @feature backup
# Backup system for database and files
require 'zip'

class BackupManager
  def self.perform_backup(config = nil)
    config ||= BackupConfig.current
    return { success: false, error: 'Configurazione backup non trovata' } unless config&.remote_ip.present?

    begin
      timestamp = Time.current.strftime('%Y%m%d_%H%M%S')
      backup_dir = File.join(Dir.pwd, 'tmp', 'backups')
      FileUtils.mkdir_p(backup_dir)

      # 1. Dump database
      db_file = File.join(backup_dir, "database_#{timestamp}.sql")
      db_url = ENV['DATABASE_URL'] || 'postgresql://localhost/print_orchestrator_development'
      system("pg_dump #{db_url} > #{db_file}") || raise("DB dump failed")

      # 2. Tar storage files
      storage_tar = File.join(backup_dir, "storage_#{timestamp}.tar.gz")
      storage_path = File.join(Dir.pwd, 'storage')
      if Dir.exist?(storage_path)
        system("tar -czf #{storage_tar} -C #{Dir.pwd} storage") || raise("Storage tar failed")
      end

      # 3. Create ZIP with all using rubyzip
      zip_file = File.join(backup_dir, "backup_#{timestamp}.zip")
      Zip::File.open(zip_file, Zip::File::CREATE) do |zipfile|
        zipfile.add("database_#{timestamp}.sql", db_file) if File.exist?(db_file)
        zipfile.add("storage_#{timestamp}.tar.gz", storage_tar) if File.exist?(storage_tar)
      end

      # 4. Copy to remote (required)
      unless config.remote_ip.present? && config.remote_path.present?
        raise "Configurazione server remoto mancante (IP e percorso richiesti)"
      end
      
      # Transfer via SCP to remote
      ssh_cmd = "scp -o ConnectTimeout=10 -o StrictHostKeyChecking=no #{zip_file} root@#{config.remote_ip}:#{config.remote_path}/ 2>&1"
      transfer_output = `#{ssh_cmd}`
      transfer_success = $?.success?
      
      unless transfer_success
        raise "Trasferimento su server remoto fallito: #{transfer_output}"
      end
      
      result = { 
        success: true, 
        file: "backup_#{timestamp}.zip", 
        size: File.size(zip_file), 
        remote_path: "#{config.remote_path}/backup_#{timestamp}.zip",
        message: "✓ Backup trasferito su server remoto (#{config.remote_ip})" 
      }

      # Cleanup temp files AND local backup after successful remote transfer
      File.delete(db_file) if File.exist?(db_file)
      File.delete(storage_tar) if File.exist?(storage_tar)
      File.delete(zip_file) if File.exist?(zip_file)

      result
    rescue => e
      { success: false, error: e.message }
    end
  end

  def self.test_connection(ip, path)
    begin
      # Test SSH connection
      result = `ssh -o ConnectTimeout=5 root@#{ip} "test -d #{path}" 2>&1`
      $?.success? ? { connected: true } : { connected: false, error: "Path not found or SSH failed: #{result}" }
    rescue => e
      { connected: false, error: e.message }
    end
  end

  def self.list_backups
    backup_dir = File.join(Dir.pwd, 'tmp', 'backups')
    return [] unless Dir.exist?(backup_dir)
    
    backup_files = Dir.glob(File.join(backup_dir, "backup_*.zip")).sort.reverse
    backup_files.map do |file|
      filename = File.basename(file)
      size = File.size(file)
      mtime = File.mtime(file)
      { filename: filename, path: file, size: size, created_at: mtime }
    end
  end

  def self.restore_backup(filename)
    backup_dir = File.join(Dir.pwd, 'tmp', 'backups')
    zip_path = File.join(backup_dir, filename)
    
    return { success: false, error: 'File non trovato' } unless File.exist?(zip_path)
    return { success: false, error: 'File non è un backup valido' } unless filename.start_with?('backup_') && filename.end_with?('.zip')

    do_restore(zip_path)
  end

  def self.restore_from_uploaded_file(uploaded_file)
    return { success: false, error: 'File non caricato' } if !uploaded_file || !uploaded_file[:tempfile]
    return { success: false, error: 'Solo file ZIP sono consentiti' } unless uploaded_file[:filename].end_with?('.zip')

    begin
      zip_path = uploaded_file[:tempfile].path
      do_restore(zip_path)
    rescue => e
      { success: false, error: e.message }
    end
  end

  private

  def self.do_restore(zip_path)
    backup_dir = File.join(Dir.pwd, 'tmp', 'backups')
    extract_dir = File.join(backup_dir, 'restore_temp')
    
    begin
      FileUtils.rm_rf(extract_dir)
      FileUtils.mkdir_p(extract_dir)

      # Extract ZIP
      Zip::File.open(zip_path) do |zipfile|
        zipfile.each do |entry|
          entry.extract(File.join(extract_dir, entry.name))
        end
      end

      # Find database and storage files
      db_file = Dir.glob(File.join(extract_dir, "database_*.sql")).first
      storage_tar = Dir.glob(File.join(extract_dir, "storage_*.tar.gz")).first

      # Restore database
      if db_file && File.exist?(db_file)
        db_url = ENV['DATABASE_URL'] || 'postgresql://localhost/print_orchestrator_development'
        system("psql #{db_url} < #{db_file}") || raise("Database restore failed")
      end

      # Restore storage files
      if storage_tar && File.exist?(storage_tar)
        system("cd #{Dir.pwd} && tar -xzf #{storage_tar}") || raise("Storage restore failed")
      end

      # Cleanup
      FileUtils.rm_rf(extract_dir)

      { success: true, message: "Backup ripristinato con successo" }
    rescue => e
      FileUtils.rm_rf(extract_dir) if Dir.exist?(extract_dir)
      { success: false, error: e.message }
    end
  end
end
