module ImpositionConfig
  LAYOUT_MODES = %w[grid nesting booklet].freeze
  ANCHORS = %w[top_left top_center top_right center bottom_left bottom_center bottom_right].freeze
  WORK_STYLES = %w[single_sided sheetwise work_and_turn work_and_tumble perfecting].freeze
  PLATE_MODES = %w[single_sided duplex_separate duplex_same_set].freeze
  DUPLEX_ORIENTATIONS = %w[head_to_head foot_to_foot].freeze
  DUPLEX_MODES = %w[none horizontal vertical].freeze
  BLEED_MODES = %w[none existing scale].freeze
  BINDING_METHODS = %w[saddle_stitch nested_saddle perfect_bound].freeze
  SIGNATURE_SIZES = (4..64).step(4).to_a.freeze
  BOOKLET_REPEAT_MODES = %w[sequential repeat].freeze
  BOOKLET_UPS = %w[2 4].freeze
  BOOKLET_WORK_STYLES = %w[sheetwise work_and_turn].freeze
  LAST_SIGNATURE_PADDING = %w[multiple_of_4 full].freeze
  PAGE_DISTRIBUTIONS = %w[sequential repeat_each].freeze

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
      'auto_rotate' => true,
      'repeat_product' => true,
      'page_distribution' => 'sequential',
      'fill_last_sheet' => false,
      'trim_sheet_height' => false,
      'plate_mode' => 'single_sided',
      'work_style' => 'single_sided',
      'duplex_orientation' => 'head_to_head',
      'double_sided_mode' => 'none',
      'bleed_mode' => 'existing',
      'bleed_mm' => 3.0,
      'signature_pages' => 16,
      'binding_method' => 'saddle_stitch',
      'binding' => 'left',
      'booklet_repeat_mode' => 'sequential',
      'booklet_repeat_gap_mm' => 4.0,
      'booklet_up' => '2',
      'booklet_work_style' => 'sheetwise',
      'last_signature_padding' => 'multiple_of_4',
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
    # Legacy imposes used offset_x_mm/offset_y_mm as the starting point and
    # had no independent right/bottom margins. Preserve those layouts instead
    # of filling missing legacy fields with the new 10mm defaults.
    config['margin_left_mm'] = input['offset_x_mm'] if !input.key?('margin_left_mm') && input.key?('offset_x_mm')
    config['margin_top_mm'] = input['offset_y_mm'] if !input.key?('margin_top_mm') && input.key?('offset_y_mm')
    config['margin_right_mm'] = 0.0 unless input.key?('margin_right_mm')
    config['margin_bottom_mm'] = 0.0 unless input.key?('margin_bottom_mm')
    mode = config['layout_mode'].to_s
    raise ArgumentError, 'Tipo di imposizione non valido' unless LAYOUT_MODES.include?(mode)

    config['sheet_width_mm'] = positive_number(config['sheet_width_mm'], 'larghezza foglio')
    config['sheet_height_mm'] = positive_number(config['sheet_height_mm'], 'altezza foglio')
    %w[sample_width_mm sample_height_mm].each do |field|
      config[field] = positive_number(config[field], field.tr('_', ' '))
    end
    %w[margin_left_mm margin_right_mm margin_top_mm margin_bottom_mm gap_x_mm gap_y_mm bleed_mm gutter_mm creep_mm booklet_repeat_gap_mm].each do |field|
      config[field] = non_negative_number(config[field], field.tr('_', ' '))
    end
    raise ArgumentError, 'I margini occupano tutto il foglio' if
      config['margin_left_mm'] + config['margin_right_mm'] >= config['sheet_width_mm'] ||
      config['margin_top_mm'] + config['margin_bottom_mm'] >= config['sheet_height_mm']

    config['anchor'] = config['anchor'].to_s
    raise ArgumentError, 'Punto di ancoraggio non valido' unless ANCHORS.include?(config['anchor'])
    legacy_duplex = config['double_sided_mode'].to_s
    unless input.key?('work_style')
      config['work_style'] = case input['plate_mode'].to_s
                             when 'duplex_separate' then 'sheetwise'
                             when 'duplex_same_set'
                               input['duplex_orientation'].to_s == 'foot_to_foot' ? 'work_and_tumble' : 'work_and_turn'
                             else
                               case legacy_duplex
                               when 'horizontal' then 'work_and_turn'
                               when 'vertical' then 'work_and_tumble'
                               else 'single_sided'
                               end
                             end
    end
    config['work_style'] = config['work_style'].to_s
    raise ArgumentError, 'Metodo di stampa non valido' unless WORK_STYLES.include?(config['work_style'])
    unless input.key?('plate_mode')
      config['plate_mode'] = case config['work_style']
                             when 'sheetwise', 'perfecting' then 'duplex_separate'
                             when 'work_and_turn', 'work_and_tumble' then 'duplex_same_set'
                             else 'single_sided'
                             end
    end
    config['plate_mode'] = config['plate_mode'].to_s
    raise ArgumentError, 'Tipo di set lastre non valido' unless PLATE_MODES.include?(config['plate_mode'])
    config['duplex_orientation'] = config['duplex_orientation'].to_s
    if input.key?('double_sided_mode') && !input.key?('duplex_orientation')
      config['duplex_orientation'] = legacy_duplex == 'vertical' ? 'foot_to_foot' : 'head_to_head'
    end
    raise ArgumentError, 'Orientamento fronte/retro non valido' unless DUPLEX_ORIENTATIONS.include?(config['duplex_orientation'])
    config['duplex_orientation'] = 'foot_to_foot' if config['work_style'] == 'work_and_tumble'
    config['duplex_orientation'] = 'head_to_head' if config['work_style'] == 'work_and_turn'
    config['plate_mode'] = case config['work_style']
                           when 'sheetwise', 'perfecting' then 'duplex_separate'
                           when 'work_and_turn', 'work_and_tumble' then 'duplex_same_set'
                           else 'single_sided'
                           end
    config['double_sided_mode'] = case config['work_style']
                                  when 'work_and_turn' then 'horizontal'
                                  when 'work_and_tumble' then 'vertical'
                                  else 'none'
                                  end
    config['bleed_mode'] = config['bleed_mode'].to_s
    raise ArgumentError, 'Modalità abbondanza non valida' unless BLEED_MODES.include?(config['bleed_mode'])
    config['page_distribution'] = config['page_distribution'].to_s
    unless PAGE_DISTRIBUTIONS.include?(config['page_distribution'])
      raise ArgumentError, 'Distribuzione pagine non valida'
    end
    if mode == 'nesting' && config['work_style'] != 'single_sided'
      raise ArgumentError, 'Il nesting non supporta il fronte/retro'
    end
    config['page_distribution'] = 'sequential' unless mode == 'grid'

    config['columns'] = non_negative_integer(config['columns'], 'colonne')
    config['rows'] = non_negative_integer(config['rows'], 'righe')
    config['sample_pages'] = [positive_integer(config['sample_pages'], 'pagine di esempio'), 999].min
    config['signature_pages'] = Integer(config['signature_pages'])
    unless SIGNATURE_SIZES.include?(config['signature_pages'])
      raise ArgumentError, 'La segnatura deve contenere un multiplo di 4 compreso tra 4 e 64 pagine'
    end
    config['binding_method'] = config['binding_method'].to_s
    raise ArgumentError, 'Tipo di legatura non valido' unless BINDING_METHODS.include?(config['binding_method'])
    config['booklet_repeat_mode'] = case config['booklet_repeat_mode'].to_s
                                    when 'single' then 'sequential'
                                    when 'auto' then 'repeat'
                                    else config['booklet_repeat_mode'].to_s
                                    end
    unless BOOKLET_REPEAT_MODES.include?(config['booklet_repeat_mode'])
      raise ArgumentError, 'Modalità Repeat Booklet non valida'
    end
    config['booklet_up'] = config['booklet_up'].to_s
    config['booklet_up'] = '2' if config['booklet_up'].empty? || config['booklet_up'] == 'auto'
    raise ArgumentError, 'Schema di piega booklet non valido' unless BOOKLET_UPS.include?(config['booklet_up'])
    config['booklet_work_style'] = config['booklet_work_style'].to_s
    config['booklet_work_style'] = 'sheetwise' if config['booklet_work_style'].empty?
    unless BOOKLET_WORK_STYLES.include?(config['booklet_work_style'])
      raise ArgumentError, 'Metodo di stampa booklet non valido'
    end
    if config['booklet_up'] == '2' && config['booklet_work_style'] == 'work_and_turn'
      raise ArgumentError, 'La volta di lato booklet richiede quattro pagine per lato'
    end
    config['last_signature_padding'] = config['last_signature_padding'].to_s
    unless LAST_SIGNATURE_PADDING.include?(config['last_signature_padding'])
      raise ArgumentError, 'Completamento ultima segnatura non valido'
    end
    config['binding'] = %w[left right].include?(config['binding'].to_s) ? config['binding'].to_s : 'left'
    # Legacy pages_per_side/booklet_scheme values mixed sheet capacity with
    # folding. Booklet is now always a 2-up half-fold; extra capacity is
    # represented explicitly by Repeat Booklet.
    config.delete('pages_per_side')
    config.delete('booklet_scheme')
    %w[rotate auto_rotate repeat_product fill_last_sheet trim_sheet_height].each { |field| config[field] = truthy?(config[field]) }

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
