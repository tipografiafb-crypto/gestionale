# @feature backup
# Backup system for database and files
require 'zip'
require 'shellwords'

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
      unless config.remote_ip.present? && config.remote_path.present? && config.ssh_username.present? && config.ssh_password.present?
        raise "Configurazione SSH incompleta (IP, percorso, username e password richiesti)"
      end
      
      # Transfer via SCP using sshpass for password authentication
      # sshpass allows non-interactive password authentication
      ssh_port = config.ssh_port.presence || 22
      sshpass_cmd = "sshpass -p #{Shellwords.escape(config.ssh_password)} scp -P #{ssh_port} -o ConnectTimeout=10 -o StrictHostKeyChecking=no #{Shellwords.escape(zip_file)} #{Shellwords.escape(config.ssh_username)}@#{config.remote_ip}:#{Shellwords.escape(config.remote_path)}/ 2>&1"
      transfer_output = `#{sshpass_cmd}`
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
          # Ignora file di sistema macOS e directory nascoste
          next if entry.name.include?('__MACOSX') || entry.name.start_with?('.') || entry.name.include?('/.')
          
          # Crea la sottodirectory se necessario
          dest_path = File.join(extract_dir, entry.name)
          FileUtils.mkdir_p(File.dirname(dest_path))
          
          entry.extract(dest_path) unless File.exist?(dest_path)
        end
      end

      # Find database and storage files
      db_file = Dir.glob(File.join(extract_dir, "database_*.sql")).first
      storage_tar = Dir.glob(File.join(extract_dir, "storage_*.tar.gz")).first

      # Restore database
      if db_file && File.exist?(db_file)
        puts "[RESTORE] Database file found: #{db_file}"
        db_url = ENV['DATABASE_URL'] || 'postgresql://localhost/print_orchestrator_development'
        
        # Pulisce il file SQL dai comandi problematici e dai riferimenti all'owner specifico
        clean_db_file = db_file + ".clean"
        # 1. Rimuove \restrict
        # 2. Rimuove OWNER TO (per evitare errori se l'utente è diverso)
        # 3. Rimuove riferimenti specifici a estensioni o commenti di sistema non necessari
        system("grep -vE '^\\\\restrict|^ALTER TABLE .* OWNER TO|^CREATE EXTENSION' #{db_file} > #{clean_db_file}")
        
        # Se il database locale è in uso, dobbiamo assicurarci di avere i permessi per il DROP
        # Usiamo --if-exists per evitare errori se lo schema è già pulito
        # AGGIUNTO: Reindirizzamento dell'errore per capire se il DROP fallisce
        drop_cmd = "psql \"#{db_url}\" -c 'DROP SCHEMA IF EXISTS public CASCADE; CREATE SCHEMA public;' 2>&1"
        drop_output = `#{drop_cmd}`
        puts "[RESTORE] Drop Output: #{drop_output}"
        
        # Importazione con --no-owner e --no-privileges per massima compatibilità
        restore_cmd = "psql \"#{db_url}\" < \"#{clean_db_file}\" 2>&1"
        output = `#{restore_cmd}`
        success = $?.success?
        
        puts "[RESTORE] Output: #{output}"
        
        # Cleanup clean file
        File.delete(clean_db_file) if File.exist?(clean_db_file)
        
        raise "Database restore failed: #{output}" unless success
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
