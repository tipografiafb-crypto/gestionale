# PDF Proxy - Serve output PDFs from storage directly
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
      
      # Find the order and item
      order = Order.find_by(external_order_code: codice_ordine)
      unless order
        status 404
        return "Order not found"
      end
      
      item = order.order_items.find_by(id: id_riga)
      unless item
        status 404
        return "Item not found"
      end
      
      # Look for print_output asset
      asset = item.assets.find_by(asset_type: 'print_output')
      unless asset
        puts "[PDF_PROXY] No print_output asset found for order #{codice_ordine}, item #{id_riga}"
        puts "[PDF_PROXY] Available assets: #{item.assets.map { |a| "#{a.asset_type}: #{a.local_path}" }.join(', ')}"
        status 404
        return "Print output not ready"
      end
      
      # Check if file exists
      file_path = asset.local_path_full
      unless file_path && File.exist?(file_path)
        puts "[PDF_PROXY] File not found at: #{file_path}"
        status 404
        return "File not found on disk"
      end
      
      # Serve the PDF
      puts "[PDF_PROXY] Serving PDF: #{file_path}"
      content_type 'application/pdf'
      headers['Content-Disposition'] = "inline; filename='#{filename}'"
      headers['Cache-Control'] = 'no-cache, no-store, must-revalidate'
      
      File.read(file_path)
      
    rescue => e
      puts "[PDF_PROXY_ERROR] #{e.class}: #{e.message}"
      puts "[PDF_PROXY_BACKTRACE] #{e.backtrace.first(5).join("\n")}"
      status 500
      "Error: #{e.message}"
    end
  end
end
