require 'net/http'
require 'base64'
require 'digest'
require 'rbconfig'
require 'open3'
require_relative 'ai_image_settings'

module AiImageService
  module_function

  def create!(asset, dpi: 300, background: 'auto')
    raise ArgumentError, 'Configura prima la chiave OpenAI in Strumenti → Miglioramento AI' if AiImageSettings.api_key.empty?
    source = asset.local_path_full
    raise ArgumentError, 'Il miglioramento AI è disponibile per file di stampa PNG scaricati' unless asset.asset_type.to_s.start_with?('print_file') && source && File.extname(source).downcase == '.png' && File.file?(source)
    raise ArgumentError, 'Il file supera 45 MB' if File.size(source) > 45 * 1024 * 1024
    dimensions = ImageEditService.png_dimensions(source)
    raise ArgumentError, 'PNG non valido' unless dimensions
    ImageEditService.validate_dimensions!(*dimensions, 'sorgente')
    asset.with_lock do
      AiImageEdit.where(asset_id: asset.id, status: %w[queued processing]).each(&:expire_if_stale!)
      existing = AiImageEdit.find_by(asset_id: asset.id, status: %w[queued processing])
      return existing if existing
      settings = AiImageSettings.config
      detected_transparency = actual_transparency?(source)
      requested_background = background.to_s
      raise ArgumentError, 'Scelta sfondo non valida' unless %w[auto transparent opaque].include?(requested_background)
      transparency = requested_background == 'auto' ? detected_transparency : requested_background == 'transparent'
      settings['background'] = transparency ? 'transparent' : 'opaque'
      settings['transparency_detected'] = transparency
      settings['background_selection'] = requested_background
      settings['prompt'] = prompt_for(settings['prompt'], transparent: transparency)
      edit = AiImageEdit.create!(asset: asset, source_sha256: Digest::SHA256.file(source).hexdigest,
        options: settings.merge('width' => dimensions[0], 'height' => dimensions[1], 'dpi' => dpi))
      FileUtils.mkdir_p(edit.directory)
      FileUtils.cp(source, edit.source_path)
      raise ArgumentError, 'Il file è cambiato durante la preparazione. Riprova.' unless Digest::SHA256.file(edit.source_path).hexdigest == edit.source_sha256
      edit
    end
  end

  def actual_transparency?(path)
    command = ImageEditService.imagemagick_command
    return false unless command
    out, _err, status = Open3.capture3(command, path, '-alpha', 'extract', '-format', '%[fx:min]', 'info:')
    return false unless status.success?
    out.to_f < 1.0
  rescue StandardError
    false
  end

  def prompt_for(base, transparent:)
    background = transparent ?
      'La trasparenza presente nell originale è intenzionale: conservala soltanto dove esiste già.' :
      'Il file originale è completamente opaco: il fondo e ogni pixel nero sono parte della grafica, devono restare opachi e non diventare trasparenti.'
    <<~PROMPT
      #{base}
      #{background}
      Mantieni l intero canvas e tutti i bordi dell immagine. Non ritagliare, non zoomare e non spostare il contenuto.
      Restituisci la stessa composizione e proporzione dell originale, senza aggiungere margini o rimuovere pixel.
    PROMPT
  end

  def start!(edit)
    return unless edit.status == 'queued'
    pid = Process.spawn({'DISABLE_BACKGROUND_POLLERS' => '1'}, RbConfig.ruby,
      File.join(Dir.pwd, 'tools', 'ai_image_worker.rb'), edit.id.to_s,
      chdir: Dir.pwd, out: File::NULL, err: File::NULL)
    Process.detach(pid)
  rescue StandardError
    edit.update!(status: 'failed', error_message: 'Impossibile avviare l’elaborazione AI.')
    raise
  end

  def generate!(id)
    return unless AiImageEdit.where(id: id, status: 'queued').update_all(status: 'processing', updated_at: Time.now) == 1
    edit = AiImageEdit.find(id)
    key = AiImageSettings.api_key
    raise ArgumentError, 'Chiave OpenAI non configurata' if key.empty?
    uri = URI('https://api.openai.com/v1/images/edits')
    request = Net::HTTP::Post.new(uri)
    request['Authorization'] = "Bearer #{key}"
    File.open(edit.source_path, 'rb') do |source|
      request.set_form([
        ['model', edit.options.fetch('model')], ['prompt', edit.options.fetch('prompt')],
        ['quality', edit.options.fetch('quality')], ['size', 'auto'],
        ['output_format', 'png'], ['background', edit.options.fetch('background', 'opaque')], ['n', '1'],
        ['image[]', source, {filename: 'source.png', content_type: 'image/png'}]
      ], 'multipart/form-data')
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.open_timeout = 20
      http.read_timeout = 600
      http.write_timeout = 60
      http.max_retries = 0 # A retry after an ambiguous timeout could bill twice.
      response = http.request(request)
      edit.update!(request_id: response['x-request-id'])
      unless response.is_a?(Net::HTTPSuccess)
        error = JSON.parse(response.body).fetch('error', {}) rescue {}
        code = error['code'].to_s.gsub(/[^a-zA-Z0-9_-]/, '')[0,80]
        raise ArgumentError, "OpenAI HTTP #{response.code}#{code.empty? ? '' : " (#{code})"}. Verifica chiave, credito e accesso al modello nelle impostazioni."
      end
      data = JSON.parse(response.body)
      usage = data.fetch('usage', {})
      edit.update!(usage: usage, cost_usd: AiImageSettings.cost(usage, edit.options))
      binary = Base64.strict_decode64(data.fetch('data').fetch(0).fetch('b64_json'))
      dims = ImageEditService.png_dimensions(binary)
      raise ArgumentError, 'OpenAI non ha restituito un PNG valido' unless dims
      ImageEditService.validate_dimensions!(*dims, 'AI')
      File.binwrite(edit.result_path, binary)
      edit.update!(status: 'ready', options: edit.options.merge('result_width' => dims[0], 'result_height' => dims[1]))
    end
  rescue StandardError => e
    message = e.is_a?(ArgumentError) ? e.message : 'Elaborazione interrotta o risposta non valida. Se il costo non è disponibile, verifica il consumo su OpenAI prima di riprovare.'
    edit&.update!(status: 'failed', error_message: message)
  end

  def accept!(edit, allow_aspect_change: false)
    asset = edit.asset
    raise ArgumentError, 'File eliminato' unless asset
    asset.with_lock do
      edit.reload
      return edit if edit.status == 'accepted'
      raise ArgumentError, 'Risultato non disponibile' unless edit.status == 'ready' && File.file?(edit.result_path)
      path = asset.local_path_full
      raise ArgumentError, 'Il file è stato modificato dopo la richiesta AI. Avvia un nuovo confronto.' unless path && File.file?(path) && Digest::SHA256.file(path).hexdigest == edit.source_sha256
      o = edit.options
      ratio = (o['result_width'].to_f / o['result_height']) / (o['width'].to_f / o['height'])
      raise ArgumentError, 'Le proporzioni sono cambiate. Conferma esplicitamente l’adattamento nel modal.' if (ratio - 1).abs > 0.01 && !allow_aspect_change
      binary = ImageEditService.resize_png_lanczos(File.binread(edit.result_path), width: o['width'], height: o['height'], dpi: o['dpi'])
      raise ArgumentError, 'Dimensioni finali non corrette' unless ImageEditService.png_dimensions(binary) == [o['width'], o['height']]
      raise ArgumentError, 'Il file è stato modificato durante l’adattamento. Riprova.' unless Digest::SHA256.file(path).hexdigest == edit.source_sha256
      ImageEditService.ensure_original_backup!(asset)
      Tempfile.create(['ai-accepted-', '.png'], File.dirname(path)) do |f|
        f.binmode
        f.write(binary)
        f.flush
        f.fsync
        File.rename(f.path, path)
      end
      asset.update!(image_edit_data: {'mode' => 'ai', 'ai_edit_id' => edit.id, 'dpi' => o['dpi'],
        'output_width' => o['width'], 'output_height' => o['height'], 'render_engine' => 'imagemagick_lanczos'})
      edit.update!(status: 'accepted', accepted_at: Time.now)
    end
    edit
  end
end
