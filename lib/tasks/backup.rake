namespace :backup do
  desc "Create local backup of database and storage files"
  task local: :environment do
    system("bash scripts/backup.sh")
  end

  desc "Create backup and send to remote server"
  task send: :environment do
    system("bash scripts/backup.sh send")
  end
end
