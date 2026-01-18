# @feature storage
# @domain data-models
# Asset model - Images and files associated with order items
class Asset < ActiveRecord::Base
  belongs_to :order_item

  validates :original_url, presence: true
  
  scope :not_deleted, -> { where(deleted_at: nil) }
  scope :deleted, -> { where.not(deleted_at: nil) }

  # Check if asset has been downloaded locally
  def downloaded?
    local_path.present? && File.exist?(local_path_full)
  end

  # Get full local path
  def local_path_full
    return nil unless local_path
    File.join(Dir.pwd, local_path)
  end

  # Get filename from URL
  def filename_from_url
    return 'unknown.png' if original_url.blank?
    path = URI.parse(original_url).path
    path.present? ? path.split('/').last : 'unknown.png'
  rescue URI::InvalidURIError
    'unknown.png'
  end

  # Generate local storage path
  def generate_local_path(store_code, order_code, sku)
    filename = filename_from_url
    type_prefix = asset_type.present? ? "#{asset_type}_" : ""
    "storage/#{store_code}/#{order_code}/#{sku}/#{type_prefix}#{filename}"
  end
  
  # Get file size in bytes
  def file_size
    return 0 unless downloaded? && File.exist?(local_path_full)
    File.size(local_path_full)
  end
end
