require 'json'
require 'fileutils'
require 'tempfile'
require 'bigdecimal'

module AiImageSettings
  DEFAULT_PROMPT = <<~PROMPT.freeze
    Migliora con estrema fedeltà questa grafica fornita dal cliente per la stampa.
    Riduci gli artefatti di compressione, pulisci la pixelatura e rendi più nitidi i dettagli già presenti.
    Conserva esattamente la composizione, il soggetto, i margini, le proporzioni e la posizione di ogni elemento.
    Non inventare dettagli, non aggiungere elementi, non cambiare stile o colori intenzionali.
    Mantieni tutte le scritte identiche, carattere per carattere, inclusi numeri, punteggiatura e loghi.
    Mantieni lo sfondo e l'eventuale trasparenza. Non aggiungere ombre, bordi, cornici o mockup.
    Se un dettaglio è ambiguo, preservalo senza interpretarlo. Restituisci soltanto la grafica migliorata.
  PROMPT
  DEFAULTS = {
    'model' => 'gpt-image-2.5-sunburst', 'quality' => 'high', 'prompt' => DEFAULT_PROMPT,
    'text_input_rate' => '5', 'image_input_rate' => '8', 'image_output_rate' => '30',
    'cached_text_rate' => '1.25', 'cached_image_rate' => '2'
  }.freeze
  module_function

  def directory
    File.join(Dir.pwd, 'storage', 'ai_configuration')
  end

  def config
    path = File.join(directory, 'settings.json')
    DEFAULTS.merge(File.file?(path) ? JSON.parse(File.read(path)) : {})
  end

  def api_key
    path = File.join(directory, 'api_key')
    File.file?(path) ? File.read(path).strip : ENV.fetch('OPENAI_API_KEY', '').strip
  end

  def atomic_write(name, contents)
    FileUtils.mkdir_p(directory, mode: 0700)
    File.chmod(0700, directory)
    Tempfile.create(['ai-settings', '.tmp'], directory) do |f|
      f.chmod(0600)
      f.write(contents)
      f.flush
      f.fsync
      File.rename(f.path, File.join(directory, name))
    end
  end

  def save!(params)
    values = config
    DEFAULTS.each_key { |key| values[key] = params[key].to_s.strip if params.key?(key) }
    raise ArgumentError, 'Modello non valido' unless values['model'].match?(/\Agpt-image-2\.5-sunburst(?:-\d{4}-\d{2}-\d{2})?\z/)
    raise ArgumentError, 'Qualità non valida' unless %w[low medium high xhigh max auto].include?(values['quality'])
    raise ArgumentError, 'Prompt obbligatorio (massimo 10000 caratteri)' unless values['prompt'].length.between?(1, 10_000)
    DEFAULTS.keys.grep(/rate/).each do |key|
      value = BigDecimal(values[key])
      raise ArgumentError, 'Tariffa non valida' unless value.finite? && value >= 0 && value <= 1000
    end
    key = params['api_key'].to_s.strip
    raise ArgumentError, 'Formato chiave non valido' if !key.empty? && !key.match?(/\Ask-[A-Za-z0-9_-]+\z/)
    atomic_write('settings.json', JSON.pretty_generate(values))
    atomic_write('api_key', key) unless key.empty?
    atomic_write('api_key', '') if params['remove_key'] == '1'
    values
  end

  # No extrapolation from earlier models: calculate only from returned usage.
  def cost(usage, rates)
    details = usage['input_tokens_details'] || {}
    return nil unless details.key?('text_tokens') && details.key?('image_tokens') && usage.key?('output_tokens')
    cached = details['cached_tokens_details'] || {}
    text = details['text_tokens'].to_i
    image = details['image_tokens'].to_i
    ct = cached.fetch('text_tokens', 0).to_i
    ci = cached.fetch('image_tokens', 0).to_i
    # A cache total without modality breakdown cannot be priced exactly.
    return nil if details.fetch('cached_tokens', 0).to_i > ct + ci
    ((text - ct) * BigDecimal(rates['text_input_rate']) +
      (image - ci) * BigDecimal(rates['image_input_rate']) +
      ct * BigDecimal(rates['cached_text_rate']) + ci * BigDecimal(rates['cached_image_rate']) +
      usage['output_tokens'].to_i * BigDecimal(rates['image_output_rate'])) / 1_000_000
  end
end
