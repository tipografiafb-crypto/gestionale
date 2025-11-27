# PDF Proxy - Serve output PDFs directly from storage filesystem
class PrintOrchestrator < Sinatra::Base
  # GET /orders/:filename
  # Serve print output PDFs directly from storage for external system access
  get '/orders/:filename' do
    begin
      # Format: eu{codice_ordine}-{id_riga}.pdf
      filename = params[:filename]
      match = filename.to_s.match(/^eu(\d+)-(\d+)\.pdf$/i)
      
      unless match
        status 404
        return "Invalid filename format"
      end
      
      codice_ordine = "EU#{match[1]}".upcase
      id_riga = match[2].to_i
      
      # Search for file in storage directory recursively
      # Pattern: storage/{store_code}/{order_code}/{sku}/print_output_{filename}
      storage_dir = File.join(Dir.pwd, 'storage')
      
      puts "[PDF_PROXY] Looking for: print_output_#{filename}"
      puts "[PDF_PROXY] Storage dir: #{storage_dir}"
      puts "[PDF_PROXY] Storage exists: #{Dir.exist?(storage_dir)}"
      
      unless Dir.exist?(storage_dir)
        status 404
        return "Storage directory not found"
      end
      
      file_found = nil
      
      # Search recursively for the file
      Dir.glob("#{storage_dir}/**/print_output_#{filename}").each do |found_path|
        if File.exist?(found_path)
          puts "[PDF_PROXY] Found file: #{found_path}"
          file_found = found_path
          break
        end
      end
      
      unless file_found
        puts "[PDF_PROXY] File NOT found!"
        puts "[PDF_PROXY] Available files in storage:"
        Dir.glob("#{storage_dir}/**/print_output_*.pdf").each { |f| puts "[PDF_PROXY]   - #{f}" }
        status 404
        return "File not found in storage"
      end
      
      # Serve the PDF
      puts "[PDF_PROXY] Serving PDF: #{file_found}"
      content_type 'application/pdf'
      headers['Content-Disposition'] = "inline; filename='#{filename}'"
      headers['Cache-Control'] = 'no-cache, no-store, must-revalidate'
      
      File.read(file_found)
      
    rescue => e
      puts "[PDF_PROXY_ERROR] #{e.class}: #{e.message}"
      puts "[PDF_PROXY_BACKTRACE] #{e.backtrace.first(5).join("\n")}"
      status 500
      "Error: #{e.message}"
    end
  end
end
