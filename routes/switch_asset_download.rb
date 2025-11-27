# @feature switch
# @domain api
# Asset Download API - Provides direct file access for Switch
# Endpoint: GET /api/assets/:id/download
# Used by Switch to download the actual asset files

class PrintOrchestrator < Sinatra::Base
  # GET /api/assets/:id/download
  # Download asset file - used by Switch to fetch assets for processing
  get '/api/assets/:id/download' do
    begin
      asset = Asset.find(params[:id])
      
      unless asset.local_path_full && File.exist?(asset.local_path_full)
        status 404
        return "Asset file not found"
      end
      
      # Get Switch filename for this asset
      switch_filename = asset.order_item.switch_filename_for_asset(asset)
      download_filename = switch_filename || asset.filename
      
      # Determine content type based on file extension and asset type
      file_ext = File.extname(download_filename).downcase
      if file_ext == '.pdf' || asset.asset_type == 'print_output'
        content_type 'application/pdf'
        disposition = 'inline'  # Allow browser preview
      else
        content_type 'application/octet-stream'
        disposition = 'attachment'  # Force download
      end
      
      # Set download headers
      headers['Content-Disposition'] = "#{disposition}; filename='#{download_filename}'"
      headers['Cache-Control'] = 'no-cache, no-store, must-revalidate'
      
      # Stream the file
      File.read(asset.local_path_full)
      
    rescue ActiveRecord::RecordNotFound
      status 404
      "Asset not found"
    rescue StandardError => e
      status 500
      "Error retrieving asset: #{e.message}"
    end
  end
end
