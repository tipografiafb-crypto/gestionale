# @feature backup
# @domain data-models
# Backup configuration for remote storage on Switch machine
class BackupConfig < ActiveRecord::Base
  validates :remote_ip, presence: true
  validates :remote_path, presence: true
  validates :ssh_username, presence: true
  validates :ssh_password, presence: true
  
  # Get or create singleton configuration
  def self.current
    first || create
  end
end
