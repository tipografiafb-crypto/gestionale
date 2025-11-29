# @feature backup
# Backup system for database and files
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

      # 3. Create ZIP with all
      zip_file = File.join(backup_dir, "backup_#{timestamp}.zip")
      system("cd #{backup_dir} && zip -q #{zip_file} database_#{timestamp}.sql storage_#{timestamp}.tar.gz") || raise("ZIP creation failed")

      # 4. Copy to remote (assumes mount or SSH accessible)
      remote_full_path = "#{config.remote_path}/backup_#{timestamp}.zip"
      
      # Try SSH first, fallback to local copy if mounted
      ssh_cmd = "scp #{zip_file} root@#{config.remote_ip}:#{config.remote_path}/"
      if system(ssh_cmd)
        result = { success: true, file: "backup_#{timestamp}.zip", size: File.size(zip_file), remote_path: remote_full_path }
      else
        # Fallback: try direct copy if path is mounted
        FileUtils.cp(zip_file, remote_full_path)
        result = { success: true, file: "backup_#{timestamp}.zip", size: File.size(zip_file), remote_path: remote_full_path }
      end

      # Cleanup temp files
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
end
