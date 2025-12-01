# @feature backup
# @domain data-models
# Backup configuration for remote storage on Switch machine
class BackupConfig < ActiveRecord::Base
  validates :remote_ip, presence: true
  validates :remote_path, presence: true
  validates :ssh_username, presence: true
  validates :ssh_password, presence: true
  validates :ssh_port, presence: true, numericality: { only_integer: true, greater_than: 0, less_than: 65536 }
  
  # Set default port to 22 on initialization
  after_initialize :set_default_port
  
  def set_default_port
    self.ssh_port ||= 22
  end
  
  # Get or create singleton configuration
  def self.current
    first || create
  end
end
