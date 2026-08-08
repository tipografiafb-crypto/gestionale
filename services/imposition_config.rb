module ImpositionConfig
  LAYOUT_MODES = %w[grid nesting booklet].freeze
  ANCHORS = %w[top_left top_center top_right center bottom_left bottom_center bottom_right].freeze
  DUPLEX_MODES = %w[none horizontal vertical].freeze
  BLEED_MODES = %w[none existing scale].freeze
  SIGNATURE_SIZES = [4, 8, 16, 24, 32].freeze

  module_function

  def default
    {
      'layout_mode' => 'grid',
      'sheet_width_mm' => 320.0,
      'sheet_height_mm' => 450.0,
      'sample_width_mm' => 90.0,
      'sample_height_mm' => 50.0,
      'sample_pages' => 12,
      'anchor' => 'top_left',
      'margin_left_mm' => 10.0,
      'margin_right_mm' => 10.0,
      'margin_top_mm' => 10.0,
      'margin_bottom_mm' => 10.0,
      'offset_x_mm' => 10.0,
      'offset_y_mm' => 10.0,
      'gap_x_mm' => 4.0,
      'gap_y_mm' => 4.0,
      'columns' => 0,
      'rows' => 0,
      'rotate' => false,
      'fill_last_sheet' => false,
      'trim_sheet_height' => false,
      'double_sided_mode' => 'none',
      'bleed_mode' => 'existing',
      'bleed_mm' => 3.0,
      'signature_pages' => 16,
      'binding' => 'left',
      'gutter_mm' => 0.0,
      'creep_mm' => 0.0,
      'marks' => {
        'crop' => true,
        'registration' => false,
        'fold' => true,
        'color_bars' => false,
        'job_info' => true,
        'offset_mm' => 2.0,
        'length_mm' => 5.0,
        'line_width_pt' => 0.35
      }
    }
  end

  def normalize(raw)
    input = raw.is_a?(Hash) ? raw.deep_stringify_keys : {}
    config = default.deep_merge(input)
    mode = config['layout_mode'].to_s
    raise ArgumentError, 'Tipo di imposizione non valido' unless LAYOUT_MODES.include?(mode)

    config['sheet_width_mm'] = positive_number(config['sheet_width_mm'], 'larghezza foglio')
    config['sheet_height_mm'] = positive_number(config['sheet_height_mm'], 'altezza foglio')
    %w[sample_width_mm sample_height_mm].each do |field|
      config[field] = positive_number(config[field], field.tr('_', ' '))
    end
    %w[margin_left_mm margin_right_mm margin_top_mm margin_bottom_mm gap_x_mm gap_y_mm bleed_mm gutter_mm creep_mm].each do |field|
      config[field] = non_negative_number(config[field], field.tr('_', ' '))
    end
    raise ArgumentError, 'I margini occupano tutto il foglio' if
      config['margin_left_mm'] + config['margin_right_mm'] >= config['sheet_width_mm'] ||
      config['margin_top_mm'] + config['margin_bottom_mm'] >= config['sheet_height_mm']

    config['anchor'] = config['anchor'].to_s
    raise ArgumentError, 'Punto di ancoraggio non valido' unless ANCHORS.include?(config['anchor'])
    config['double_sided_mode'] = config['double_sided_mode'].to_s
    raise ArgumentError, 'Modalità fronte/retro non valida' unless DUPLEX_MODES.include?(config['double_sided_mode'])
    config['bleed_mode'] = config['bleed_mode'].to_s
    raise ArgumentError, 'Modalità abbondanza non valida' unless BLEED_MODES.include?(config['bleed_mode'])
    if mode == 'nesting' && config['double_sided_mode'] != 'none'
      raise ArgumentError, 'Il nesting non supporta il fronte/retro'
    end

    config['columns'] = non_negative_integer(config['columns'], 'colonne')
    config['rows'] = non_negative_integer(config['rows'], 'righe')
    config['sample_pages'] = [positive_integer(config['sample_pages'], 'pagine di esempio'), 999].min
    config['signature_pages'] = Integer(config['signature_pages'])
    unless SIGNATURE_SIZES.include?(config['signature_pages'])
      raise ArgumentError, 'La segnatura deve contenere 4, 8, 16, 24 o 32 pagine'
    end
    config['binding'] = %w[left right].include?(config['binding'].to_s) ? config['binding'].to_s : 'left'
    %w[rotate fill_last_sheet trim_sheet_height].each { |field| config[field] = truthy?(config[field]) }

    marks = config['marks'].is_a?(Hash) ? config['marks'].deep_stringify_keys : {}
    %w[crop registration fold color_bars job_info].each { |field| marks[field] = truthy?(marks[field]) }
    marks['offset_mm'] = non_negative_number(marks['offset_mm'], 'distanza segni')
    marks['length_mm'] = positive_number(marks['length_mm'], 'lunghezza segni')
    marks['line_width_pt'] = positive_number(marks['line_width_pt'], 'spessore segni')
    config['marks'] = marks
    config['offset_x_mm'] = config['margin_left_mm']
    config['offset_y_mm'] = config['margin_top_mm']
    config
  rescue TypeError, ArgumentError => error
    raise error if error.is_a?(ArgumentError) && !error.message.start_with?('invalid value')

    raise ArgumentError, 'La configurazione contiene un valore non valido'
  end

  def positive_number(value, label)
    number = Float(value)
    raise ArgumentError, "#{label.capitalize} deve essere maggiore di zero" unless number.positive?
    number
  end

  def non_negative_number(value, label)
    number = Float(value || 0)
    raise ArgumentError, "#{label.capitalize} non può essere negativo" if number.negative?
    number
  end

  def positive_integer(value, label)
    number = Integer(value)
    raise ArgumentError, "#{label.capitalize} deve essere maggiore di zero" unless number.positive?
    number
  end

  def non_negative_integer(value, label)
    number = Integer(value || 0)
    raise ArgumentError, "#{label.capitalize} non può essere negativo" if number.negative?
    number
  end

  def truthy?(value)
    value == true || value.to_s == '1' || value.to_s.casecmp('true').zero?
  end
end
