# @feature storage
# @domain services
# AssetDownloader - Downloads images from URLs and saves them locally
require 'http'
require 'fileutils'

class AssetDownloader
  attr_reader :order, :results

  def initialize(order)
    @order = order
    @results = { downloaded: 0, errors: 0, skipped: 0, messages: [] }
  end

  # Download all assets for the order
  def download_all
    @order.assets.each do |asset|
      download_asset(asset)
    end
    @results
  end

  private

  def download_asset(asset)
    # Skip if already downloaded
    if asset.downloaded?
      @results[:skipped] += 1
      @results[:messages] << "Skipped #{asset.original_url} (already downloaded)"
      return
    end

    begin
      # Generate local path
      local_path = asset.generate_local_path(
        @order.store.code,
        @order.external_order_code,
        asset.order_item.sku
      )

      # Create directory if it doesn't exist
      FileUtils.mkdir_p(File.dirname(local_path))

      # Download file
      response = HTTP.timeout(30).follow.get(asset.original_url)
      
      if response.status.success?
        File.binwrite(local_path, response.body)
        asset.update(local_path: local_path)
        @results[:downloaded] += 1
        @results[:messages] << "Downloaded #{asset.original_url} to #{local_path}"
      else
        raise "HTTP #{response.status}"
      end

    rescue StandardError => e
      @results[:errors] += 1
      @results[:messages] << "Error downloading #{asset.original_url}: #{e.message}"
    end
  end
end
