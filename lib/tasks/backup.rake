namespace :backup do
  desc "Create local backup of database and storage files"
  task local: :environment do
    result = BackupManager.perform_backup(BackupConfig.current)
    if result[:success]
      puts "✓ Backup completato: #{result[:file]}"
    else
      puts "✗ Errore backup: #{result[:error]}"
      exit 1
    end
  end

  desc "Create backup and send to remote server"
  task send: :environment do
    result = BackupManager.perform_backup(BackupConfig.current)
    if result[:success]
      puts "✓ Backup inviato: #{result[:message]}"
      puts "  File: #{result[:remote_path]}"
    else
      puts "✗ Errore backup: #{result[:error]}"
      exit 1
    end
  end
end
