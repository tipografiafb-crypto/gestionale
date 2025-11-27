# PDF Proxy - Serve output PDFs directly from storage filesystem
class PrintOrchestrator < Sinatra::Base
  # GET /orders/:filename
  # Serve print output PDFs directly from storage for external system access
  get '/orders/:filename' do
    begin
      filename = params[:filename]
      
      puts "[PDF_PROXY] Requested file: #{filename}"
      
      # Search for file in storage directory recursively
      # Pattern: storage/{store_code}/{order_code}/{sku}/{filename}
      storage_dir = File.join(Dir.pwd, 'storage')
      
      unless Dir.exist?(storage_dir)
        status 404
        return "Storage directory not found"
      end
      
      file_found = nil
      
      # Search recursively for the file with exact name (no prefix)
      Dir.glob("#{storage_dir}/**/#{filename}").each do |found_path|
        if File.exist?(found_path)
          puts "[PDF_PROXY] Found file: #{found_path}"
          file_found = found_path
          break
        end
      end
      
      unless file_found
        puts "[PDF_PROXY] File NOT found: #{filename}"
        puts "[PDF_PROXY] Available PDF files in storage:"
        Dir.glob("#{storage_dir}/**/*.pdf").each { |f| puts "[PDF_PROXY]   - #{f}" }
        status 404
        return "File not found in storage"
      end
      
      # Serve the PDF
      puts "[PDF_PROXY] Serving: #{file_found}"
      content_type 'application/pdf'
      headers['Content-Disposition'] = "inline; filename='#{filename}'"
      headers['Cache-Control'] = 'no-cache, no-store, must-revalidate'
      
      File.read(file_found)
      
    rescue => e
      puts "[PDF_PROXY_ERROR] #{e.class}: #{e.message}"
      status 500
      "Error: #{e.message}"
    end
  end
end
