require 'base64'
require 'time'

module ImageEditService
  PNG_SIGNATURE = "\x89PNG\r\n\x1a\n".b.freeze
  MAX_PIXELS = 120_000_000
  MAX_SCALE = 10.0
  MIN_SCALE = 0.05

  module_function

  def backup_path(asset)
    path = asset&.local_path_full
    return nil if path.to_s.empty?

    dir = File.dirname(path)
    basename = File.basename(path, '.*')
    extension = File.extname(path)
    File.join(dir, "#{basename}_original_backup#{extension}")
  end

  def source_path(asset)
    backup = backup_path(asset)
    return backup if backup && File.file?(backup)

    asset&.local_path_full
  end

  def decode_png_data_url(data_url)
    prefix = 'data:image/png;base64,'
    raise ArgumentError, 'Il file elaborato deve essere un PNG' unless data_url.to_s.start_with?(prefix)

    Base64.strict_decode64(data_url.delete_prefix(prefix))
  rescue ArgumentError => e
    raise e if e.message == 'Il file elaborato deve essere un PNG'

    raise ArgumentError, 'Dati PNG non validi'
  end

  def png_dimensions(content_or_path)
    header = if content_or_path.respond_to?(:read)
               content_or_path.read(24)
             elsif content_or_path.is_a?(String) && content_or_path.b.start_with?(PNG_SIGNATURE)
               content_or_path.b.byteslice(0, 24)
             elsif content_or_path.is_a?(String) && File.file?(content_or_path)
               File.binread(content_or_path, 24)
             else
               content_or_path.to_s.b.byteslice(0, 24)
             end
    return nil unless header&.bytesize.to_i >= 24 && header.start_with?(PNG_SIGNATURE)
    return nil unless header.byteslice(12, 4) == 'IHDR'

    header.byteslice(16, 8).unpack('NN')
  end

  def normalize_recipe(recipe, output_dimensions:, source_dimensions:)
    raw = recipe.is_a?(Hash) ? recipe : {}
    mode = raw['mode'].to_s
    raise ArgumentError, 'Modalità di modifica non valida' unless %w[fixed crop].include?(mode)

    source_width, source_height = source_dimensions.map(&:to_i)
    output_width, output_height = output_dimensions.map(&:to_i)
    validate_dimensions!(source_width, source_height, 'originali')
    validate_dimensions!(output_width, output_height, 'di uscita')

    declared_source_width = integer(raw['source_width'])
    declared_source_height = integer(raw['source_height'])
    unless [declared_source_width, declared_source_height] == [source_width, source_height]
      raise ArgumentError, 'Le dimensioni sorgente non corrispondono al file originale'
    end

    scale = number(raw['scale'])
    unless scale.between?(MIN_SCALE, MAX_SCALE)
      raise ArgumentError, "Lo zoom deve essere compreso tra #{MIN_SCALE}x e #{MAX_SCALE}x"
    end

    dpi = number(raw['dpi'], 300.0)
    raise ArgumentError, 'Il valore DPI non è valido' unless dpi.between?(36, 2400)

    normalized = {
      'mode' => mode,
      'source_width' => source_width,
      'source_height' => source_height,
      'output_width' => output_width,
      'output_height' => output_height,
      'image_left' => number(raw['image_left'], source_width / 2.0),
      'image_top' => number(raw['image_top'], source_height / 2.0),
      'scale' => scale,
      'offset_x' => number(raw['offset_x']),
      'offset_y' => number(raw['offset_y']),
      'dpi' => dpi.round(3),
      'saved_at' => Time.now.utc.iso8601
    }

    if mode == 'fixed'
      unless [output_width, output_height] == [source_width, source_height]
        raise ArgumentError, 'La modalità “Mantieni formato” deve conservare esattamente larghezza e altezza originali'
      end
      normalized['crop'] = nil
    else
      crop = raw['crop'].is_a?(Hash) ? raw['crop'] : {}
      crop_x = integer(crop['x'])
      crop_y = integer(crop['y'])
      crop_width = integer(crop['width'])
      crop_height = integer(crop['height'])
      unless [crop_width, crop_height] == [output_width, output_height]
        raise ArgumentError, 'Le dimensioni del ritaglio non corrispondono al PNG prodotto'
      end
      if crop_x.negative? || crop_y.negative? || crop_x + crop_width > source_width || crop_y + crop_height > source_height
        raise ArgumentError, 'Il rettangolo di ritaglio deve rimanere dentro il formato originale'
      end
      normalized['crop'] = {
        'x' => crop_x,
        'y' => crop_y,
        'width' => crop_width,
        'height' => crop_height
      }
    end

    normalized
  end

  def validate_dimensions!(width, height, label)
    if width <= 0 || height <= 0 || width * height > MAX_PIXELS
      raise ArgumentError, "Dimensioni #{label} non valide"
    end
  end

  def integer(value, fallback = 0)
    Integer(value.nil? || value == '' ? fallback : value)
  rescue ArgumentError, TypeError
    raise ArgumentError, 'Valore numerico non valido'
  end

  def number(value, fallback = 0.0)
    Float(value.nil? || value == '' ? fallback : value)
  rescue ArgumentError, TypeError
    raise ArgumentError, 'Valore numerico non valido'
  end
end
