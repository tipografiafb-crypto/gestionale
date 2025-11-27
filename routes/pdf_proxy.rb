# PDF Proxy - Serve output PDFs to external systems expecting /orders/ path
class PrintOrchestrator < Sinatra::Base
  # GET /orders/:filename
  # Serve print output PDFs for external system access
  get '/orders/:filename' do
    begin
      # Format: eu{codice_ordine}-{id_riga}.pdf
      filename = params[:filename]
      match = filename.to_s.match(/^eu(\d+)-(\d+)\.pdf$/i)
      
      unless match
        status 404
        return "File not found"
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
      
      # Find the print_output asset for this item
      asset = item.assets.find_by(asset_type: 'print_output')
      unless asset && asset.local_path_full && File.exist?(asset.local_path_full)
        status 404
        return "PDF not found"
      end
      
      # Serve the PDF
      content_type 'application/pdf'
      headers['Content-Disposition'] = "inline; filename='#{filename}'"
      headers['Cache-Control'] = 'no-cache, no-store, must-revalidate'
      
      File.read(asset.local_path_full)
      
    rescue => e
      status 500
      "Error: #{e.message}"
    end
  end
end
