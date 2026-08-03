# @feature automation
# @domain services

require 'digest'
require 'fileutils'
require 'json'
require 'open3'
require 'pathname'
require 'securerandom'
require 'socket'
require 'time'

class AutomationGraphValidator
  attr_reader :graph

  def initialize(graph)
    @graph = graph.is_a?(Hash) ? graph : {}
  end

  def errors
    result = []
    nodes = Array(graph['nodes'])
    edges = Array(graph['edges'])
    ids = nodes.map { |node| node['id'].to_s }

    result << 'Il flusso deve contenere almeno un blocco' if nodes.empty?
    result << 'Gli identificativi dei blocchi devono essere univoci' if ids.uniq.size != ids.size
    result << 'È richiesto esattamente un blocco Ingresso' unless nodes.count { |node| node['type'] == 'trigger' } == 1

    nodes.each do |node|
      result << 'Un blocco non ha identificativo' if node['id'].to_s.strip.empty?
      result << "Tipo mancante per il blocco #{node['id']}" if node['type'].to_s.strip.empty?
    end

    edges.each do |edge|
      result << "Collegamento con origine non valida: #{edge['source']}" unless ids.include?(edge['source'].to_s)
      result << "Collegamento con destinazione non valida: #{edge['target']}" unless ids.include?(edge['target'].to_s)
    end

    nodes.select { |node| node['type'] == 'handoff' }.each do |node|
      if edges.any? { |edge| edge['source'].to_s == node['id'].to_s }
        result << "Il blocco Passa a flusso #{node['id']} deve essere terminale"
      end
    end

    nodes.select { |node| node['type'] == 'fork' }.each do |node|
      label = node['label'].presence || node['id']
      outgoing = edges.count { |edge| edge['source'].to_s == node['id'].to_s }
      result << "Collega almeno due uscite al blocco #{label}" if outgoing < 2
    end

    nodes.select { |node| node['type'] == 'hot_folder' }.each do |node|
      if node.dig('config', 'destination_code').to_s.strip.empty?
        result << "Seleziona la hot folder nel blocco #{node['label'].presence || node['id']}"
      end
    end
    nodes.select { |node| node['type'] == 'label_printer' }.each do |node|
      if node.dig('config', 'destination_code').to_s.strip.empty?
        result << "Seleziona la stampante nel blocco #{node['label'].presence || node['id']}"
      end
    end
    nodes.select { |node| node['type'] == 'insert_blanks' }.each do |node|
      label = node['label'].presence || node['id']
      Array(node.dig('config', 'rules')).each_with_index do |rule, index|
        rule_label = "regola #{index + 1} di #{label}"
        unless %w[start after end].include?(rule['position'].to_s)
          result << "Posizione non valida nella #{rule_label}"
        end
        unless %w[all front back].include?(rule.fetch('target', 'all').to_s)
          result << "Lato non valido nella #{rule_label}"
        end
        result << "Numero di pagine vuote non valido nella #{rule_label}" if rule['count'].to_i.negative?
        if rule['repeat'] == true && rule['interval'].to_i < 1
          result << "Intervallo mancante nella #{rule_label}"
        end
        minimum = rule['min_quantity'].to_i
        maximum = rule['max_quantity'].to_i
        if minimum.positive? && maximum.positive? && minimum > maximum
          result << "Intervallo quantità invertito nella #{rule_label}"
        end
      end
    end
    nodes.select { |node| node['type'] == 'collect_group' }.each do |node|
      label = node['label'].presence || node['id']
      config = node['config'] || {}
      result << "Campo gruppo mancante nel blocco #{label}" if config['group_field'].to_s.strip.empty?
      if config['expected_count'].to_i <= 0 && config['expected_count_field'].to_s.strip.empty?
        result << "Numero atteso mancante nel blocco #{label}"
      end
      result << "Timeout non valido nel blocco #{label}" if config.fetch('timeout_minutes', 15).to_f <= 0
      unless %w[fail process_received].include?(config.fetch('timeout_policy', 'fail').to_s)
        result << "Comportamento timeout non valido nel blocco #{label}"
      end
    end
    nodes.select { |node| node['type'] == 'select_resource' }.each do |node|
      label = node['label'].presence || node['id']
      config = node['config'] || {}
      result << "Tipo risorsa mancante nel blocco #{label}" if config['asset_type'].to_s.strip.empty?
      result << "Indice risorsa non valido nel blocco #{label}" if config.fetch('asset_index', 1).to_i < 1
      unless %w[fail route_missing].include?(config.fetch('missing_policy', 'fail').to_s)
        result << "Comportamento risorsa mancante non valido nel blocco #{label}"
      end
    end
    nodes.select { |node| node['type'] == 'illustrator' }.each do |node|
      label = node['label'].presence || node['id']
      config = node['config'] || {}
      mode = config.fetch('script_mode', 'template').to_s
      result << "Modalità Illustrator non valida nel blocco #{label}" unless %w[template document].include?(mode)
      if mode == 'document' && config['script_name'].to_s.strip.empty?
        result << "Seleziona lo script Illustrator nel blocco #{label}"
      end
    end
    nodes.select { |node| node['type'] == 'step_repeat' }.each do |node|
      label = node['label'].presence || node['id']
      config = node['config'] || {}
      source = config.fetch('preset_source', 'fixed').to_s
      unless %w[fixed variable].include?(source)
        result << "Origine preset non valida nel blocco #{label}"
      end
      if source == 'variable' && config['preset_variable'].to_s.strip.empty?
        result << "Variabile preset mancante nel blocco #{label}"
      elsif source == 'fixed' && config['preset_code'].to_s.strip.empty?
        result << "Preset imposizione mancante nel blocco #{label}"
      end
    end
    nodes.select { |node| node['type'] == 'pdf_label' }.each do |node|
      label = node['label'].presence || node['id']
      config = node['config'] || {}
      result << "Testo mancante nel blocco #{label}" if config['text'].to_s.strip.empty?
      result << "Dimensione testo non valida nel blocco #{label}" unless config.fetch('font_size_pt', 8.5).to_f.positive?
      unless %w[top_left top_center top_right bottom_left bottom_center bottom_right].include?(config.fetch('anchor', 'top_left').to_s)
        result << "Posizione testo non valida nel blocco #{label}"
      end
    end
    nodes.select { |node| node['type'] == 'resize_pdf' }.each do |node|
      label = node['label'].presence || node['id']
      config = node['config'] || {}
      unless config['width_mm'].to_f.positive? && config['height_mm'].to_f.positive?
        result << "Dimensioni finali non valide nel blocco #{label}"
      end
      mode = config.fetch('mode', 'contain').to_s
      unless %w[contain stretch].include?(mode) || mode.match?(/\A\{\{[^}]+\}\}\z/)
        result << "Adattamento non valido nel blocco #{label}"
      end
    end

    result << 'Il flusso contiene un ciclo non consentito' if cyclic?(ids, edges)
    result.uniq
  end

  private

  def cyclic?(ids, edges)
    adjacency = Hash.new { |hash, key| hash[key] = [] }
    edges.each { |edge| adjacency[edge['source'].to_s] << edge['target'].to_s }
    visiting = {}
    visited = {}

    visit = lambda do |id|
      return true if visiting[id]
      return false if visited[id]

      visiting[id] = true
      return true if adjacency[id].any? { |target| visit.call(target) }

      visiting.delete(id)
      visited[id] = true
      false
    end
    ids.any? { |id| visit.call(id) }
  end
end

class AutomationFlowChainValidator
  def initialize(flow, graph)
    @flow = flow
    @graph = graph.is_a?(Hash) ? graph : {}
  end

  def errors
    result = []
    handoff_nodes = Array(@graph['nodes']).select { |node| node['type'] == 'handoff' }
    if handoff_nodes.any? { |node| node.dig('config', 'target_flow_id').to_i.zero? }
      result << 'Seleziona l’automazione successiva nel blocco Passa a un’altra automazione'
    end
    handoff_ids(@graph).each do |target_id|
      target = AutomationFlow.find_by(id: target_id)
      if target.nil?
        result << "Automazione successiva non trovata: #{target_id}"
      elsif target.id == @flow.id
        result << 'Un flusso non può passare a sé stesso'
      elsif target.active_version.nil?
        result << "Pubblica prima l'automazione successiva: #{target.name}"
      end
    end
    result << 'La catena di automazioni contiene un ciclo' if cyclic?
    result.uniq
  end

  private

  def handoff_ids(graph)
    Array(graph['nodes'])
      .select { |node| node['type'] == 'handoff' }
      .map { |node| node.dig('config', 'target_flow_id').to_i }
      .reject(&:zero?)
  end

  def cyclic?
    visiting = {}
    visited = {}
    visit = lambda do |flow_id, graph|
      return true if visiting[flow_id]
      return false if visited[flow_id]

      visiting[flow_id] = true
      cycle = handoff_ids(graph).any? do |target_id|
        target = AutomationFlow.find_by(id: target_id)
        target && visit.call(target.id, target.active_version&.graph || {})
      end
      visiting.delete(flow_id)
      visited[flow_id] = true
      cycle
    end
    visit.call(@flow.id, @graph)
  end
end

class AutomationBootstrap
  class << self
    def blank_graph
      {
        'schema_version' => 1,
        'nodes' => [
          node('input', 'trigger', 'Ingresso', 80, 180),
          node('finish', 'finish', 'Completato', 420, 180)
        ],
        'edges' => [
          edge('edge-input-finish', 'input', 'finish')
        ]
      }
    end

    def seed_plectrum_flow!
      seed_presets!
      flow = AutomationFlow.find_or_initialize_by(name: 'Plettri automatici')
      flow.description = 'PNG web → Photoshop → Illustrator → plancia interna → macchina e barcode'
      flow.status ||= 'draft'
      flow.save!

      draft = flow.versions.where(status: 'draft').order(version_number: :desc).first
      unless draft
        draft = flow.versions.create!(
          version_number: (flow.versions.maximum(:version_number) || 0) + 1,
          status: 'draft',
          graph: plectrum_graph
        )
      end
      draft.update!(graph: plectrum_graph) if draft.graph.blank? || Array(draft.graph['nodes']).size <= 2
      flow
    end

    def seed_scatoline_aggregation_flow!
      seed_presets!
      flow = AutomationFlow.find_or_initialize_by(name: 'SCATOLINE · Aggregazione esempio')
      flow.description =
        'Crea in parallelo la plancia di stampa e la plancia A4 identificativa con i numeri ordine.'
      flow.status ||= 'draft'
      flow.save!

      draft = flow.versions.where(status: 'draft').order(version_number: :desc).first ||
              flow.versions.create!(
                version_number: (flow.versions.maximum(:version_number) || 0) + 1,
                status: 'draft',
                graph: scatoline_aggregation_graph
              )
      active_has_dynamic_imposition = Array(flow.active_version&.graph&.dig('nodes')).any? do |node|
        node['type'] == 'step_repeat' &&
          node.dig('config', 'preset_source') == 'variable'
      end
      if draft.graph.blank? || Array(draft.graph['nodes']).size <= 2 ||
         !active_has_dynamic_imposition
        draft.update!(graph: scatoline_aggregation_graph)
      end
      flow.publish_draft! unless active_has_dynamic_imposition

      flow
    end

    def seed_layered_assets_flow!
      flow = AutomationFlow.find_or_initialize_by(name: 'ADESIVI · Stampa e livello tecnico')
      flow.description =
        'Esempio riutilizzabile: seleziona due risorse della riga, le elabora e le compone in livelli Illustrator.'
      flow.status ||= 'draft'
      flow.save!

      draft = flow.versions.where(status: 'draft').order(version_number: :desc).first ||
              flow.versions.create!(
                version_number: (flow.versions.maximum(:version_number) || 0) + 1,
                status: 'draft',
                graph: layered_assets_graph
              )
      draft.update!(graph: layered_assets_graph)
      flow
    end

    def seed_manual_plectrum_flow!
      illustrator_flow = AutomationFlow.find_by(name: '2 - illustrator')
      raise ArgumentError, 'Manca il modulo “2 - illustrator” richiesto dal flusso manuale' unless illustrator_flow&.active_version

      flow = AutomationFlow.find_or_initialize_by(name: 'PLETTRI · Manuale')
      flow.description = 'Usa l’azione Photoshop scelta dall’operatore e prosegue con il modulo Illustrator comune.'
      flow.status ||= 'draft'
      flow.save!

      graph = manual_plectrum_graph(illustrator_flow.id)
      draft = flow.versions.where(status: 'draft').order(version_number: :desc).first ||
              flow.versions.create!(
                version_number: (flow.versions.maximum(:version_number) || 0) + 1,
                status: 'draft',
                graph: graph
              )
      draft.update!(graph: graph) if draft.graph.blank? || Array(draft.graph['nodes']).size <= 2
      flow.publish_draft! unless flow.active_version

      PrintFlow.find_by(name: 'plettri manuale')&.update!(
        preprint_executor: 'automation',
        preprint_automation_flow: flow
      )
      flow
    end

    def seed_presets!
      upsert_preset(
        'imposition',
        'STANDARD_MONO',
        'Plettri Standard · Quite 15×7',
        {
          'sheet_width_mm' => 498,
          'sheet_height_mm' => 346,
          'anchor' => 'bottom_left',
          'offset_x_mm' => 3.6609867,
          'offset_y_mm' => 8.0000122,
          'gap_x_mm' => 4.1769947,
          'gap_y_mm' => 10.8380036,
          'columns' => 15,
          'rows' => 7,
          'rotate' => false,
          'fill_last_sheet' => false
        }
      )

      [
        ['SCAT_TPH500', 'Scatoline TPH500 · TINPICK 10', 485, 250, 10, 5, 5],
        ['SCAT_TPH501', 'Scatoline TPH501 · TINPICK 20', 500, 350, 7, 5, 10],
        ['SCAT_TPH502', 'Scatoline TPH502 · TINPICK 50', 500, 350, 4, 4, 10],
        ['SCAT_TPH503', 'Scatoline TPH503 · TINPICK 100/500', 500, 350, 4, 4, 10]
      ].each do |code, name, width, height, columns, rows, gap|
        upsert_preset(
          'imposition',
          code,
          name,
          {
            'sheet_width_mm' => width,
            'sheet_height_mm' => height,
            'anchor' => 'bottom_left',
            'offset_x_mm' => 10,
            'offset_y_mm' => 10,
            'gap_x_mm' => gap,
            'gap_y_mm' => gap,
            'columns' => columns,
            'rows' => rows,
            'rotate' => false,
            'fill_last_sheet' => false
          }
        )
      end
    end

    def plectrum_graph
      nodes = [
        node('input', 'trigger', 'PNG ordine', 40, 360),
        node('route_color', 'router', 'Colore prodotto', 250, 360, {
          'cases' => [
            {'port' => 'white', 'label' => 'Bianco (-W)', 'field' => 'product.route_text', 'operator' => 'contains', 'value' => '-W'},
            {'port' => 'black', 'label' => 'Nero (-B)', 'field' => 'product.route_text', 'operator' => 'contains', 'value' => '-B'}
          ],
          'default_port' => 'other'
        }),
        node('white_vars', 'set_variables', 'Azione bianco', 490, 180, {
          'values' => {'adobe_action_set' => 'definitive_0924', 'adobe_action_name' => 'plettri bianchi', 'template' => 'plettri/STANDARD', 'imposition_preset' => 'STANDARD_MONO'}
        }),
        node('black_vars', 'set_variables', 'Azione nero', 490, 360, {
          'values' => {'adobe_action_set' => 'definitive_0924', 'adobe_action_name' => 'plettri neri', 'template' => 'plettri/STANDARD', 'imposition_preset' => 'STANDARD_MONO'}
        }),
        node('other_vars', 'set_variables', 'Azione altri', 490, 540, {
          'values' => {'adobe_action_set' => 'definitive_0924', 'adobe_action_name' => 'altri plettri', 'template' => 'plettri/STANDARD', 'imposition_preset' => 'STANDARD_MONO'}
        }),
        node('route_template', 'router', 'Modello maschera', 740, 360, {
          'cases' => [
            {'port' => 'sharp', 'label' => 'SHARP', 'field' => 'product.route_text', 'operator' => 'contains', 'value' => 'SHARP'},
            {'port' => 'jazz', 'label' => 'JAZZ / JAZIII', 'field' => 'product.route_text', 'operator' => 'contains', 'value' => 'JAZ'},
            {'port' => 'triangle', 'label' => 'TRIANGOLO', 'field' => 'product.route_text', 'operator' => 'contains', 'value' => 'TRIANGOLO'},
            {'port' => 'flow', 'label' => 'FLOW', 'field' => 'product.route_text', 'operator' => 'contains', 'value' => 'FLOW'},
            {'port' => 'tortex', 'label' => 'TORTEX', 'field' => 'product.route_text', 'operator' => 'contains', 'value' => 'TORTEX'},
            {'port' => 'gator', 'label' => 'GATOR', 'field' => 'product.route_text', 'operator' => 'contains', 'value' => 'GATOR'}
          ],
          'default_port' => 'standard'
        }),
        node('template_sharp', 'set_variables', 'Maschera SHARP', 980, 20, {
          'values' => {'template' => 'plettri/SHARP'}
        }),
        node('template_jazz', 'set_variables', 'Maschera JAZZ', 980, 130, {
          'values' => {'template' => 'plettri/JAZZ'}
        }),
        node('template_triangle', 'set_variables', 'Maschera TRIANGOLO', 980, 240, {
          'values' => {'template' => 'plettri/TRIANGOLO'}
        }),
        node('template_flow', 'set_variables', 'Maschera FLOW', 980, 350, {
          'values' => {'template' => 'plettri/FLOW'}
        }),
        node('template_tortex', 'set_variables', 'Maschera TORTEX', 980, 460, {
          'values' => {'template' => 'plettri/TORTEX'}
        }),
        node('template_gator', 'set_variables', 'Maschera GATOR', 980, 570, {
          'values' => {'template' => 'plettri/GATOR'}
        }),
        node('template_standard', 'set_variables', 'Maschera STANDARD', 980, 680, {
          'values' => {'template' => 'plettri/STANDARD'}
        }),
        node('photoshop', 'photoshop', 'Photoshop', 1240, 360, {
          'action_set' => '{{variables.adobe_action_set}}',
          'action_name' => '{{variables.adobe_action_name}}',
          'width_mm' => 0,
          'height_mm' => 0,
          'dpi' => 300,
          'output_kind' => 'photoshop_pdf'
        }),
        node('illustrator', 'illustrator', 'Illustrator + maschera', 1470, 360, {
          'script_name' => 'plettri/plettro2.jsx',
          'template_path' => '{{variables.template}}.ai',
          'pdf_preset' => 'PDF PLANCE',
          'output_kind' => 'unit_pdf'
        }),
        node('copies', 'calculate_copies', 'Calcola quantità', 1700, 360, {
          'quantity_field' => 'item.quantity',
          'output_key' => 'production_copies',
          'range_overrides' => [],
          'exact_overrides' => {'25' => 26, '50' => 52, '100' => 105}
        }),
        node('duplicate', 'duplicate_pages', 'Moltiplica pagine', 1930, 360, {
          'copies_field' => 'variables.production_copies',
          'output_kind' => 'multipage_pdf'
        }),
        node('impose', 'step_repeat', 'Step and repeat', 2160, 360, {
          'preset_code' => '{{variables.imposition_preset}}',
          'output_kind' => 'imposition_pdf'
        }),
        node('print_hotfolder', 'hot_folder', 'Hot folder stampa', 2390, 360, {
          'destination_code' => 'LOCAL_PRINT',
          'artifact_kind' => 'imposition_pdf',
          'filename' => '{{order.code}}-{{item.position}}.pdf',
          'output_kind' => 'delivered_print'
        }),
        node('barcode', 'barcode', 'Barcode ordine', 2620, 360, {
          'data_field' => 'order.code',
          'width_mm' => 70,
          'height_mm' => 35,
          'bar_height_mm' => 18,
          'output_kind' => 'barcode_pdf'
        }),
        node('label_hotfolder', 'hot_folder', 'Hot folder etichetta', 2850, 360, {
          'destination_code' => 'LOCAL_LABELS',
          'artifact_kind' => 'barcode_pdf',
          'filename' => '{{order.code}}-barcode.pdf',
          'output_kind' => 'delivered_label'
        }),
        node('finish', 'finish', 'Completato', 3080, 360, {
          'result_artifact_kind' => 'imposition_pdf'
        })
      ]
      edges = [
        edge('e1', 'input', 'route_color'),
        edge('e2', 'route_color', 'white_vars', 'white'),
        edge('e3', 'route_color', 'black_vars', 'black'),
        edge('e4', 'route_color', 'other_vars', 'other'),
        edge('e5', 'white_vars', 'route_template'),
        edge('e6', 'black_vars', 'route_template'),
        edge('e7', 'other_vars', 'route_template'),
        edge('e8', 'route_template', 'template_sharp', 'sharp'),
        edge('e9', 'route_template', 'template_jazz', 'jazz'),
        edge('e10', 'route_template', 'template_triangle', 'triangle'),
        edge('e11', 'route_template', 'template_flow', 'flow'),
        edge('e12', 'route_template', 'template_tortex', 'tortex'),
        edge('e13', 'route_template', 'template_gator', 'gator'),
        edge('e14', 'route_template', 'template_standard', 'standard'),
        edge('e15', 'template_sharp', 'photoshop'),
        edge('e16', 'template_jazz', 'photoshop'),
        edge('e17', 'template_triangle', 'photoshop'),
        edge('e18', 'template_flow', 'photoshop'),
        edge('e19', 'template_tortex', 'photoshop'),
        edge('e20', 'template_gator', 'photoshop'),
        edge('e21', 'template_standard', 'photoshop'),
        edge('e22', 'photoshop', 'illustrator'),
        edge('e23', 'illustrator', 'copies'),
        edge('e24', 'copies', 'duplicate'),
        edge('e25', 'duplicate', 'impose'),
        edge('e26', 'impose', 'print_hotfolder'),
        edge('e27', 'print_hotfolder', 'barcode'),
        edge('e28', 'barcode', 'label_hotfolder'),
        edge('e29', 'label_hotfolder', 'finish')
      ]
      {'schema_version' => 1, 'nodes' => nodes, 'edges' => edges}
    end

    def scatoline_aggregation_graph
      nodes = [
        node('input', 'trigger', 'Ingresso lavoro aggregato', 80, 260, {
          'operation_type' => 'aggregation',
          'source_type' => 'aggregated_job'
        }),
        node('route_preset', 'router', 'Scegli impose dallo SKU', 320, 260, {
          'cases' => [
            {'port' => 'tph500', 'label' => 'TPH500 · TINPICK 10', 'field' => 'item.sku', 'operator' => 'contains', 'value' => 'TPH500'},
            {'port' => 'tph501', 'label' => 'TPH501 · TINPICK 20', 'field' => 'item.sku', 'operator' => 'contains', 'value' => 'TPH501'},
            {'port' => 'tph502', 'label' => 'TPH502 · TINPICK 50', 'field' => 'item.sku', 'operator' => 'contains', 'value' => 'TPH502'},
            {'port' => 'tph503', 'label' => 'TPH503 · TINPICK 100/500', 'field' => 'item.sku', 'operator' => 'contains', 'value' => 'TPH503'}
          ],
          'default_port' => 'unsupported'
        }),
        node('preset_tph500', 'set_variables', 'Preset TPH500', 580, 40, {
          'values' => {'imposition_preset' => 'SCAT_TPH500', 'label_resize_mode' => 'contain'}
        }),
        node('preset_tph501', 'set_variables', 'Preset TPH501', 580, 180, {
          'values' => {'imposition_preset' => 'SCAT_TPH501', 'label_resize_mode' => 'stretch'}
        }),
        node('preset_tph502', 'set_variables', 'Preset TPH502', 580, 320, {
          'values' => {'imposition_preset' => 'SCAT_TPH502', 'label_resize_mode' => 'contain'}
        }),
        node('preset_tph503', 'set_variables', 'Preset TPH503 (predefinito)', 580, 460, {
          'values' => {'imposition_preset' => 'SCAT_TPH503', 'label_resize_mode' => 'contain'}
        }),
        node('unsupported_sku', 'approval', 'SKU scatolina non configurato', 840, 560),
        node('copies', 'calculate_copies', 'Quantità della riga', 840, 260, {
          'quantity_field' => 'item.quantity',
          'output_key' => 'aggregation_copies',
          'range_overrides' => [],
          'exact_overrides' => {}
        }),
        node('duplicate', 'duplicate_pages', 'Moltiplica pagine', 1090, 260, {
          'copies_field' => 'variables.aggregation_copies',
          'output_kind' => 'aggregation_item_pdf'
        }),
        node('fork_outputs', 'fork', 'Crea entrambe le plance', 1320, 260),
        node('collect_print', 'collect_group', 'Raccogli file per la stampa', 1570, 100, {
          'group_field' => 'aggregation.token',
          'expected_count_field' => 'aggregation.expected_count',
          'order_field' => 'aggregation.position',
          'consistency_field' => 'variables.imposition_preset',
          'timeout_minutes' => 15,
          'timeout_policy' => 'fail',
          'output_kind' => 'aggregated_pdf'
        }),
        node('impose_print', 'step_repeat', 'Componi plancia di stampa', 1820, 100, {
          'preset_source' => 'variable',
          'preset_variable' => 'variables.imposition_preset',
          'preset_code' => '',
          'output_kind' => 'imposition_pdf'
        }),
        node('finish_print', 'finish', 'Plancia di stampa pronta', 2070, 100, {
          'result_artifact_kind' => 'imposition_pdf'
        }),
        node('label_order', 'pdf_label', 'Scrivi numero ordine', 1570, 430, {
          'text' => '{{order.code}}',
          'anchor' => 'top_left',
          'font' => 'Times-Roman',
          'font_size_pt' => 18,
          'background_color' => '#222222',
          'text_color' => '#ffffff',
          'padding_x_mm' => 2,
          'padding_y_mm' => 1.5,
          'offset_x_mm' => 0,
          'offset_y_mm' => 5,
          'output_kind' => 'numbered_item_pdf'
        }),
        node('collect_labels', 'collect_group', 'Raccogli file numerati', 1820, 430, {
          'group_field' => 'aggregation.token',
          'expected_count_field' => 'aggregation.expected_count',
          'order_field' => 'aggregation.position',
          'consistency_field' => 'variables.imposition_preset',
          'timeout_minutes' => 15,
          'timeout_policy' => 'fail',
          'output_kind' => 'numbered_aggregated_pdf'
        }),
        node('impose_labels', 'step_repeat', 'Componi plancia con numeri', 2070, 430, {
          'preset_source' => 'variable',
          'preset_variable' => 'variables.imposition_preset',
          'preset_code' => '',
          'output_kind' => 'label_imposition_pdf'
        }),
        node('resize_labels', 'resize_pdf', 'Adatta la plancia ad A4', 2320, 430, {
          'width_mm' => 297,
          'height_mm' => 210,
          'mode' => '{{variables.label_resize_mode}}',
          'output_kind' => 'identification_sheet_pdf'
        }),
        node('finish_labels', 'finish', 'Plancia identificativa pronta', 2570, 430, {
          'result_artifact_kind' => 'identification_sheet_pdf'
        })
      ]
      edges = [
        edge('e1', 'input', 'route_preset'),
        edge('e2', 'route_preset', 'preset_tph500', 'tph500'),
        edge('e3', 'route_preset', 'preset_tph501', 'tph501'),
        edge('e4', 'route_preset', 'preset_tph502', 'tph502'),
        edge('e5', 'route_preset', 'preset_tph503', 'tph503'),
        edge('e5b', 'route_preset', 'unsupported_sku', 'unsupported'),
        edge('e6', 'preset_tph500', 'copies'),
        edge('e7', 'preset_tph501', 'copies'),
        edge('e8', 'preset_tph502', 'copies'),
        edge('e9', 'preset_tph503', 'copies'),
        edge('e10', 'copies', 'duplicate'),
        edge('e11', 'duplicate', 'fork_outputs'),
        edge('e12', 'fork_outputs', 'collect_print'),
        edge('e13', 'fork_outputs', 'label_order'),
        edge('e14', 'collect_print', 'impose_print'),
        edge('e15', 'impose_print', 'finish_print'),
        edge('e16', 'label_order', 'collect_labels'),
        edge('e17', 'collect_labels', 'impose_labels'),
        edge('e18', 'impose_labels', 'resize_labels'),
        edge('e19', 'resize_labels', 'finish_labels')
      ]
      {'schema_version' => 1, 'nodes' => nodes, 'edges' => edges}
    end

    def layered_assets_graph
      nodes = [
        node('input', 'trigger', 'Ingresso prestampa', 60, 300, {
          'operation_type' => 'preprint;manual',
          'source_type' => 'print_flow;manual'
        }),
        node('has_layers', 'router', 'Il prodotto ha il livello aggiuntivo?', 300, 300, {
          'cases' => [
            {
              'port' => 'yes',
              'label' => 'Sì',
              'field' => 'product.has_cut_file',
              'operator' => 'equals',
              'value' => 'true'
            }
          ],
          'default_port' => 'no'
        }),
        node('missing_setup', 'approval', 'Prodotto senza file aggiuntivo', 560, 520),
        node('fork_resources', 'fork', 'Prepara le risorse', 560, 300),
        node('select_print', 'select_resource', 'Seleziona grafica', 820, 150, {
          'asset_type' => 'print',
          'asset_index' => 1,
          'resource_role' => 'Graphics',
          'resource_position' => 1,
          'missing_policy' => 'fail',
          'output_kind' => 'selected_graphics'
        }),
        node('prepare_print', 'photoshop', 'Prepara grafica a 300 DPI', 1080, 150, {
          'agent_key' => '',
          'action_set' => '',
          'action_name' => '',
          'width_mm' => 0,
          'height_mm' => 0,
          'dpi' => 300,
          'output_kind' => 'graphics_pdf'
        }),
        node('select_cut', 'select_resource', 'Seleziona livello tecnico', 820, 450, {
          'asset_type' => 'cut',
          'asset_index' => 1,
          'resource_role' => 'CutContour',
          'resource_position' => 2,
          'missing_policy' => 'fail',
          'output_kind' => 'selected_technical_layer'
        }),
        node('prepare_cut', 'illustrator', 'Prepara livello CutContour', 1080, 450, {
          'agent_key' => '',
          'script_mode' => 'document',
          'script_name' => 'adesivi/convert_to_cutcontour.jsx',
          'template_path' => '',
          'pdf_preset' => 'PDF_plance_livelli',
          'output_kind' => 'technical_layer_pdf'
        }),
        node('collect_layers', 'collect_group', 'Raccogli i livelli', 1360, 300, {
          'group_field' => 'runtime.root_run_id',
          'expected_count' => 2,
          'expected_count_field' => '',
          'order_field' => 'file.resource_position',
          'consistency_field' => '',
          'timeout_minutes' => 15,
          'timeout_policy' => 'fail',
          'output_kind' => 'layer_source_pdf'
        }),
        node('compose_layers', 'illustrator', 'Componi livelli', 1640, 300, {
          'agent_key' => '',
          'script_mode' => 'document',
          'script_name' => 'adesivi/convert_multipage_pdf.jsx',
          'template_path' => '',
          'pdf_preset' => 'PDF_plance_livelli',
          'output_kind' => 'layered_pdf'
        }),
        node('finish', 'finish', 'PDF a livelli pronto', 1920, 300, {
          'result_artifact_kind' => 'layered_pdf'
        })
      ]
      edges = [
        edge('e1', 'input', 'has_layers'),
        edge('e2', 'has_layers', 'fork_resources', 'yes'),
        edge('e3', 'has_layers', 'missing_setup', 'no'),
        edge('e4', 'fork_resources', 'select_print'),
        edge('e5', 'fork_resources', 'select_cut'),
        edge('e6', 'select_print', 'prepare_print', 'found'),
        edge('e7', 'select_cut', 'prepare_cut', 'found'),
        edge('e8', 'prepare_print', 'collect_layers'),
        edge('e9', 'prepare_cut', 'collect_layers'),
        edge('e10', 'collect_layers', 'compose_layers'),
        edge('e11', 'compose_layers', 'finish')
      ]
      {'schema_version' => 1, 'nodes' => nodes, 'edges' => edges}
    end

    def manual_plectrum_graph(illustrator_flow_id)
      nodes = [
        node('input', 'trigger', 'Ingresso prestampa manuale', 80, 260, {
          'operation_type' => 'preprint;manual',
          'source_type' => 'print_flow;manual'
        }),
        node('photoshop', 'photoshop', 'Photoshop: azione scelta', 420, 260, {
          'agent_key' => 'mac-switch-01',
          'action_set' => '',
          'action_name' => '{{operation.selected_photoshop_action}}',
          'width_mm' => 50,
          'height_mm' => 50,
          'dpi' => 300,
          'output_kind' => 'photoshop_pdf'
        }),
        node('handoff', 'handoff', 'Passa a Illustrator', 760, 260, {
          'target_flow_id' => illustrator_flow_id.to_s
        })
      ]
      edges = [
        edge('e1', 'input', 'photoshop'),
        edge('e2', 'photoshop', 'handoff')
      ]
      {'schema_version' => 1, 'nodes' => nodes, 'edges' => edges}
    end

    private

    def node(id, type, label, x, y, config = {})
      {'id' => id, 'type' => type, 'label' => label, 'position' => {'x' => x, 'y' => y}, 'config' => config}
    end

    def edge(id, source, target, source_port = 'default')
      {'id' => id, 'source' => source, 'target' => target, 'source_port' => source_port}
    end

    def upsert_preset(kind, code, name, config)
      preset = AutomationPreset.find_or_initialize_by(kind: kind, code: code)
      preset.update!(name: name, config: config, active: true)
    end
  end
end

class AutomationEngine
  class << self
    def validate_trigger!(trigger, event_key:, source:)
      accepted_events = trigger_values(trigger, 'operation_type')
      unless trigger_accepts?(accepted_events, event_key)
        raise ArgumentError,
              "Il flusso accetta gli eventi #{accepted_events.join(', ')}, non #{event_key}"
      end

      accepted_sources = trigger_values(trigger, 'source_type')
      unless trigger_accepts?(accepted_sources, source)
        raise ArgumentError,
              "Il flusso accetta le sorgenti #{accepted_sources.join(', ')}, non #{source}"
      end
    end

    def start_run(flow:, order_item:, source_asset: nil, operation_type: 'manual',
                  print_flow: nil, action_batch_id: nil, simulation: false,
                  extra_context: {})
      version = flow.active_version
      raise ArgumentError, 'Pubblica il flusso prima di avviarlo' unless version

      graph_errors = version.graph_errors
      raise ArgumentError, graph_errors.join(', ') if graph_errors.any?

      trigger = Array(version.graph['nodes']).find { |node| node['type'] == 'trigger' }
      trigger_source = extra_context['trigger_source'].presence || 'manual'
      validate_trigger!(trigger, event_key: operation_type.to_s, source: trigger_source)

      asset_optional = operation_type.to_s == 'label'
      asset = source_asset
      unless asset || asset_optional
        asset = order_item.switch_print_assets.find(&:downloaded?) ||
                order_item.assets.find(&:downloaded?)
      end
      unless asset || asset_optional
        raise ArgumentError, 'Nessun asset locale disponibile per la riga ordine'
      end
      if asset && !asset.downloaded?
        raise ArgumentError, 'Il file sorgente non è disponibile localmente'
      end

      run = nil
      AutomationRun.transaction do
        run = AutomationRun.create!(
          automation_flow_version: version,
          order_item: order_item,
          source_asset: asset,
          print_flow: print_flow,
          operation_type: operation_type,
          action_batch_id: action_batch_id,
          status: 'queued',
          context: build_context(
            order_item,
            simulation,
            asset: asset,
            operation_type: operation_type,
            print_flow: print_flow,
            extra_context: extra_context
          )
        )
        if asset
          artifact = create_artifact!(
            run: run,
            step: nil,
            kind: 'source',
            path: asset.local_path_full,
            filename: File.basename(asset.local_path_full),
            media_type: media_type_for(asset.local_path_full),
            metadata: {
              'asset_id' => asset.id,
              'operation_type' => operation_type,
              'action_batch_id' => action_batch_id
            }.compact
          )
          update_runtime!(run, 'current_artifact_id' => artifact.id)
        end
        enqueue_node!(run, trigger)
      end
      run
    end

    def start_chained_run!(parent_run:, handoff_step:, target_flow:)
      version = target_flow.active_version
      raise ArgumentError, "Pubblica prima il flusso #{target_flow.name}" unless version

      source = parent_run.current_artifact
      raise ArgumentError, 'Il flusso precedente non ha prodotto un file' unless source&.available?

      chain_flow_ids = Array(parent_run.context.dig('runtime', 'chain_flow_ids')).map(&:to_i)
      chain_flow_ids = [parent_run.flow.id] if chain_flow_ids.empty?
      if chain_flow_ids.include?(target_flow.id)
        raise ArgumentError, "Ciclo tra automazioni rilevato verso #{target_flow.name}"
      end

      trigger = Array(version.graph['nodes']).find { |node| node['type'] == 'trigger' }
      raise ArgumentError, "Il flusso #{target_flow.name} non contiene un ingresso" unless trigger
      validate_trigger!(trigger, event_key: parent_run.operation_type.to_s, source: 'handoff')

      child = nil
      AutomationRun.transaction do
        context = deep_copy(parent_run.context)
        context['runtime'] ||= {}
        context['runtime']['chain_flow_ids'] = chain_flow_ids + [target_flow.id]
        context['runtime']['parent_run_id'] = parent_run.id
        context['runtime']['root_run_id'] = (parent_run.root_run_id || parent_run.id)
        context['runtime']['handoff_step_id'] = handoff_step.id
        context['runtime']['created_at'] = Time.current.iso8601
        context['operation'] ||= {}
        context['operation']['source'] = 'handoff'
        context['operation']['handoff_from_flow_id'] = parent_run.flow.id
        context['operation']['handoff_from_flow_name'] = parent_run.flow.name

        child = AutomationRun.create!(
          automation_flow_version: version,
          order_item: parent_run.order_item,
          source_asset: parent_run.source_asset,
          print_flow: parent_run.print_flow,
          operation_type: parent_run.operation_type,
          action_batch_id: parent_run.action_batch_id,
          parent_run: parent_run,
          root_run: parent_run.root_run || parent_run,
          handoff_step: handoff_step,
          status: 'queued',
          context: context
        )
        artifact = create_artifact!(
          run: child,
          step: nil,
          kind: 'source',
          path: source.full_path,
          filename: source.filename,
          media_type: source.media_type || media_type_for(source.filename),
          metadata: {
            'parent_run_id' => parent_run.id,
            'parent_artifact_id' => source.id,
            'handoff_step_id' => handoff_step.id
          }
        )
        update_runtime!(child, 'current_artifact_id' => artifact.id)
        enqueue_node!(child, trigger)
      end
      child
    end

    def start_branch_run!(parent_run:, branch_step:, target_node:, branch_index:, branch_count:)
      child = nil
      AutomationRun.transaction do
        context = deep_copy(parent_run.context)
        context['runtime'] ||= {}
        context['runtime'].delete('current_artifact_id')
        context['runtime']['parent_run_id'] = parent_run.id
        context['runtime']['root_run_id'] = parent_run.root_run_id || parent_run.id
        context['runtime']['branch_run'] = true
        context['runtime']['branch_step_id'] = branch_step.id
        context['runtime']['branch_source_node'] = branch_step.node_key
        context['runtime']['branch_target_node'] = target_node['id']
        context['runtime']['branch_index'] = branch_index
        context['runtime']['branch_count'] = branch_count

        child = AutomationRun.create!(
          automation_flow_version: parent_run.automation_flow_version,
          order_item: parent_run.order_item,
          source_asset: parent_run.source_asset,
          print_flow: parent_run.print_flow,
          operation_type: parent_run.operation_type,
          action_batch_id: parent_run.action_batch_id,
          parent_run: parent_run,
          root_run: parent_run.root_run || parent_run,
          status: 'queued',
          context: context
        )

        current_parent_id = parent_run.context.dig('runtime', 'current_artifact_id').to_i
        current_child_id = nil
        parent_run.automation_artifacts.order(:created_at).each do |artifact|
          clone = AutomationArtifact.create!(
            automation_run: child,
            kind: artifact.kind,
            filename: artifact.filename,
            media_type: artifact.media_type,
            local_path: artifact.local_path,
            checksum: artifact.checksum,
            metadata: deep_copy(artifact.metadata).merge(
              'branch_parent_run_id' => parent_run.id,
              'branch_parent_artifact_id' => artifact.id
            )
          )
          current_child_id = clone.id if artifact.id == current_parent_id
        end
        current_child_id ||= child.automation_artifacts.order(:created_at).last&.id
        update_runtime!(child, 'current_artifact_id' => current_child_id) if current_child_id
        enqueue_node!(child, target_node)
      end
      child
    end

    def enqueue_node!(run, node)
      raise ArgumentError, 'Blocco di destinazione non trovato' unless node

      run.automation_step_runs.create!(
        node_key: node['id'],
        node_type: node['type'],
        status: 'queued',
        input_data: {'context_snapshot' => run.context},
        available_at: Time.current
      )
      run.update!(
        status: run.started_at ? 'running' : 'queued',
        current_node_key: node['id'],
        started_at: run.started_at || Time.current
      )
    end

    def complete_step!(step, result = {})
      run = step.automation_run
      AutomationStepRun.transaction do
        apply_context_updates!(run, result['context_updates'] || {})
        step.update!(
          status: result['state'] == 'skipped' ? 'skipped' : 'completed',
          output_data: result,
          error_message: nil,
          finished_at: Time.current
        )
        if result['handoff_child_run_id']
          run.update!(
            status: 'running',
            current_node_key: nil,
            completed_at: nil
          )
          return
        end
        branch_ids = schedule_next!(step, result['next_port'] || 'default')
        if branch_ids.present?
          step.update!(output_data: step.output_data.merge('branch_child_run_ids' => branch_ids))
        end
      end
    end

    def complete_external_step!(step, uploaded_path:, filename:, media_type: nil, metadata: {})
      raise ArgumentError, 'Il passaggio non attende un agente esterno' unless step.status == 'waiting_external'

      node = node_for(step)
      kind = node.dig('config', 'output_kind').presence || "#{step.node_type}_output"
      artifact = create_artifact!(
        run: step.automation_run,
        step: step,
        kind: kind,
        path: uploaded_path,
        filename: filename,
        media_type: media_type || media_type_for(filename),
        metadata: metadata
      )
      complete_step!(
        step,
        'artifact_id' => artifact.id,
        'context_updates' => {'runtime.current_artifact_id' => artifact.id}
      )
    end

    def fail_external_step!(step, message)
      raise ArgumentError, 'Il passaggio non attende un agente esterno' unless step.status == 'waiting_external'

      fail_step!(step, message, retryable: false)
    end

    def approve_step!(step)
      raise ArgumentError, 'Il passaggio non attende approvazione' unless step.status == 'waiting_review'

      complete_step!(step, 'approved_at' => Time.current.iso8601)
    end

    def fail_step!(step, message, retryable: true)
      run = step.automation_run
      if retryable && step.attempts < step.max_attempts
        delay = [step.attempts * 5, 30].min
        step.update!(
          status: 'queued',
          error_message: message,
          worker_id: nil,
          locked_at: nil,
          available_at: Time.current + delay.seconds
        )
        run.update!(status: 'running', error_message: nil)
      else
        step.update!(status: 'failed', error_message: message, finished_at: Time.current)
        run.update!(status: 'failed', error_message: message, completed_at: Time.current)
        propagate_chain_failure!(run, message)
        AutomationActionLifecycle.run_failed!(run) if defined?(AutomationActionLifecycle)
      end
    end

    def retry_run!(run)
      failed = run.automation_step_runs.where(status: 'failed').order(created_at: :desc).first
      raise ArgumentError, 'Il flusso non contiene passaggi falliti' unless failed

      failed.update!(
        status: 'queued',
        attempts: 0,
        error_message: nil,
        worker_id: nil,
        locked_at: nil,
        available_at: Time.current,
        finished_at: nil
      )
      run.update!(status: 'running', error_message: nil, completed_at: nil)
      ancestor = run.parent_run
      while ancestor
        ancestor.update!(status: 'running', error_message: nil, completed_at: nil)
        ancestor = ancestor.parent_run
      end
      failed
    end

    def node_for(step)
      Array(step.automation_run.automation_flow_version.graph['nodes'])
        .find { |node| node['id'] == step.node_key }
    end

    def create_artifact!(run:, step:, kind:, path:, filename:, media_type:, metadata: {})
      AutomationArtifact.create!(
        automation_run: run,
        automation_step_run: step,
        kind: kind,
        filename: filename,
        media_type: media_type,
        local_path: relative_path(path),
        checksum: File.file?(path) ? Digest::SHA256.file(path).hexdigest : nil,
        metadata: metadata
      )
    end

    def update_runtime!(run, values)
      context = deep_copy(run.context)
      context['runtime'] ||= {}
      values.each { |key, value| context['runtime'][key.to_s] = value }
      run.update!(context: context)
    end

    def complete_absorbed_run!(run)
      run.update!(
        status: 'completed',
        current_node_key: nil,
        completed_at: Time.current
      )
      complete_chain_ancestors!(run)
    end

    def propagate_chain_failure!(run, message)
      ancestor = run.parent_run
      while ancestor
        ancestor.update!(
          status: 'failed',
          error_message: "Errore nel sottoflusso #{run.flow.name}: #{message}",
          completed_at: Time.current
        )
        ancestor = ancestor.parent_run
      end
    end

    def complete_chain_ancestors!(run)
      ancestor = run.parent_run
      while ancestor
        completed_now = false
        ancestor.with_lock do
          if ancestor.status != 'failed' && ancestor.status != 'completed' &&
             ancestor.child_runs.where.not(status: 'completed').none?
            ancestor.update!(
              status: 'completed',
              error_message: nil,
              current_node_key: nil,
              completed_at: Time.current
            )
            completed_now = true
          end
        end
        break unless completed_now

        AutomationActionLifecycle.run_completed!(ancestor) if defined?(AutomationActionLifecycle)
        ancestor = ancestor.parent_run
      end
    end

    def context_value(context, path)
      normalized_path = path.to_s.strip
      if (match = normalized_path.match(/\A\{\{\s*([^}]+?)\s*\}\}\z/))
        normalized_path = match[1].strip
      end
      normalized_path.split('.').reduce(context) do |value, key|
        value.is_a?(Hash) ? value[key] : nil
      end
    end

    def resolve(value, context)
      return value unless value.is_a?(String)

      exact = value.match(/\A\{\{([^}]+)\}\}\z/)
      return context_value(context, exact[1].strip) if exact

      value.gsub(/\{\{([^}]+)\}\}/) do
        context_value(context, Regexp.last_match(1).strip).to_s
      end
    end

    def media_type_for(path)
      case File.extname(path.to_s).downcase
      when '.pdf' then 'application/pdf'
      when '.png' then 'image/png'
      when '.jpg', '.jpeg' then 'image/jpeg'
      when '.svg' then 'image/svg+xml'
      else 'application/octet-stream'
      end
    end

    private

    def trigger_values(trigger, key)
      configured = trigger&.dig('config', key).to_s
      values = configured.split(/[;,]/).map(&:strip).reject(&:empty?)
      values.presence || ['any']
    end

    def trigger_accepts?(accepted, value)
      accepted.include?('any') || accepted.include?(value.to_s)
    end

    def schedule_next!(step, port)
      run = step.automation_run
      graph = run.automation_flow_version.graph
      edges = Array(graph['edges']).select do |candidate|
        candidate['source'] == step.node_key &&
          candidate.fetch('source_port', 'default').to_s == port.to_s
      end
      edges = Array(graph['edges']).select do |candidate|
        candidate['source'] == step.node_key &&
          candidate.fetch('source_port', 'default').to_s == 'default'
      end if edges.empty?

      if edges.empty?
        run.update!(status: 'completed', current_node_key: nil, completed_at: Time.current)
        AutomationActionLifecycle.run_completed!(run) if defined?(AutomationActionLifecycle)
        complete_chain_ancestors!(run)
        return nil
      end

      if edges.one?
        node = Array(graph['nodes']).find { |candidate| candidate['id'] == edges.first['target'] }
        enqueue_node!(run, node)
        return nil
      end

      branch_ids = edges.each_with_index.map do |edge, index|
        node = Array(graph['nodes']).find { |candidate| candidate['id'] == edge['target'] }
        raise ArgumentError, "Blocco di destinazione non trovato: #{edge['target']}" unless node

        start_branch_run!(
          parent_run: run,
          branch_step: step,
          target_node: node,
          branch_index: index + 1,
          branch_count: edges.length
        ).id
      end
      update_runtime!(run, 'branch_child_run_ids' => branch_ids)
      run.update!(status: 'running', current_node_key: nil, completed_at: nil)
      branch_ids
    end

    def build_context(item, simulation, asset:, operation_type:, print_flow:, extra_context:)
      product = item.product
      payload = item.json_data || {}
      webhook_fields = if item.respond_to?(:campi_webhook)
                         item.campi_webhook
                       else
                         payload['campi_webhook']
                       end
      payload = payload.merge('campi_webhook' => (webhook_fields || {}))
      route_text = [
        payload['product'],
        payload['product_name'],
        product&.name,
        product&.sku,
        item.sku
      ].compact.join(' ')
      {
        'order' => {
          'id' => item.order.id,
          'code' => item.order.external_order_code,
          'store' => item.order.store&.code
        },
        'item' => {
          'id' => item.id,
          'sku' => item.sku,
          'quantity' => item.quantity,
          'position' => item.item_number
        },
        'product' => {
          'id' => product&.id,
          'sku' => product&.sku || item.sku,
          'name' => product&.name,
          'route_text' => route_text,
          'has_cut_file' => product&.has_cut_file == true,
          'asset_types' => item.assets.where.not(asset_type: nil).distinct.order(:asset_type).pluck(:asset_type)
        },
        'operation' => {
          'type' => operation_type,
          'event_key' => extra_context['event_key'] || operation_type,
          'source' => extra_context['trigger_source'] || 'manual',
          'id' => extra_context['operation_id'],
          'print_flow_id' => print_flow&.id,
          'print_flow_name' => print_flow&.name,
          'selected_photoshop_action' => webhook_fields&.fetch('azione photoshop', nil).presence ||
                                        webhook_fields&.fetch('azione_photoshop', nil).presence
        },
        'file' => {
          'asset_id' => asset&.id,
          'asset_type' => asset&.asset_type,
          'filename' => if asset
                          item.switch_filename_for_asset(asset) ||
                            asset.filename_from_url
                        end,
          'local_path' => asset&.local_path,
          'index' => extra_context['file_index'] || 1,
          'count' => extra_context['file_count'] || 1
        },
        'aggregation' => extra_context['aggregation'],
        'machine' => extra_context['machine'],
        'payload' => payload,
        'variables' => {},
        'runtime' => {
          'simulation' => !!simulation,
          'created_at' => Time.current.iso8601
        }
      }
    end

    def apply_context_updates!(run, updates)
      return if updates.empty?

      context = deep_copy(run.context)
      updates.each do |path, value|
        keys = path.to_s.split('.')
        leaf = keys.pop
        target = keys.reduce(context) { |memo, key| memo[key] ||= {} }
        target[leaf] = value
      end
      run.update!(context: context)
    end

    def relative_path(path)
      full = Pathname.new(path).expand_path
      root = Pathname.new(Dir.pwd).expand_path
      full.to_s.start_with?("#{root}/") ? full.relative_path_from(root).to_s : full.to_s
    end

    def deep_copy(value)
      JSON.parse(JSON.generate(value))
    end
  end
end

class AutomationNodeExecutor
  def initialize(step)
    @step = step
    @run = step.automation_run
    @node = AutomationEngine.node_for(step)
    @config = @node.fetch('config', {})
    @context = @run.context
  end

  def execute
    case @step.node_type
    when 'trigger' then {}
    when 'router' then execute_router
    when 'fork' then {}
    when 'set_variables' then execute_set_variables
    when 'select_resource' then execute_select_resource
    when 'calculate_copies' then execute_calculate_copies
    when 'duplicate_pages' then execute_duplicate_pages
    when 'pdf_label' then execute_pdf_label
    when 'resize_pdf' then execute_resize_pdf
    when 'collect_group' then execute_collect_group
    when 'insert_blanks' then execute_insert_blanks
    when 'pair_sides' then execute_pair_sides
    when 'photoshop', 'illustrator' then execute_adobe
    when 'step_repeat' then execute_step_repeat
    when 'barcode' then execute_barcode
    when 'hot_folder' then execute_hot_folder
    when 'label_printer' then execute_label_printer
    when 'approval' then {'state' => 'waiting_review'}
    when 'handoff' then execute_handoff
    when 'finish' then {}
    else
      raise ArgumentError, "Tipo di blocco non supportato: #{@step.node_type}"
    end
  end

  private

  def execute_handoff
    target_id = @config['target_flow_id'].to_i
    target = AutomationFlow.find_by(id: target_id)
    raise ArgumentError, 'Seleziona l’automazione successiva' unless target

    child = AutomationEngine.start_chained_run!(
      parent_run: @run,
      handoff_step: @step,
      target_flow: target
    )
    {
      'handoff_child_run_id' => child.id,
      'handoff_target_flow_id' => target.id,
      'handoff_target_flow_name' => target.name,
      'context_updates' => {'runtime.handoff_child_run_id' => child.id}
    }
  end

  def execute_router
    selected = Array(@config['cases']).find do |rule|
      compare(
        AutomationEngine.context_value(@context, rule['field']),
        rule['operator'],
        AutomationEngine.resolve(rule['value'], @context)
      )
    end
    {'next_port' => selected&.dig('port') || @config['default_port'] || 'default'}
  end

  def execute_set_variables
    updates = {}
    @config.fetch('values', {}).each do |key, value|
      updates["variables.#{key}"] = AutomationEngine.resolve(value, @context)
    end
    {'context_updates' => updates}
  end

  def execute_select_resource
    requested_type = AutomationEngine.resolve(@config['asset_type'], @context).to_s.strip
    requested_index = [@config.fetch('asset_index', 1).to_i, 1].max
    candidates = @run.order_item.assets.order(:id).select(&:downloaded?)
    candidates.select! do |asset|
      if requested_type == 'print'
        asset.asset_type == 'print' || asset.asset_type.to_s.start_with?('print_file')
      else
        asset.asset_type.to_s == requested_type
      end
    end
    selected = candidates[requested_index - 1]
    unless selected
      if @config.fetch('missing_policy', 'fail').to_s == 'route_missing'
        return {
          'next_port' => 'missing',
          'requested_asset_type' => requested_type,
          'requested_asset_index' => requested_index
        }
      end
      raise ArgumentError,
            "Risorsa #{requested_type} numero #{requested_index} non disponibile per la riga ordine"
    end

    role = AutomationEngine.resolve(@config['resource_role'], @context).to_s.strip.presence || requested_type
    position = @config.fetch('resource_position', requested_index).to_i
    filename = @run.order_item.switch_filename_for_asset(selected) ||
               selected.filename_from_url || File.basename(selected.local_path_full)
    artifact = AutomationEngine.create_artifact!(
      run: @run,
      step: @step,
      kind: @config['output_kind'].to_s.strip.presence || "selected_#{role}",
      path: selected.local_path_full,
      filename: filename,
      media_type: AutomationEngine.media_type_for(selected.local_path_full),
      metadata: {
        'asset_id' => selected.id,
        'asset_type' => selected.asset_type,
        'resource_role' => role,
        'resource_position' => position
      }
    )
    {
      'next_port' => 'found',
      'artifact_id' => artifact.id,
      'selected_asset_id' => selected.id,
      'context_updates' => {
        'runtime.current_artifact_id' => artifact.id,
        'file.asset_id' => selected.id,
        'file.asset_type' => selected.asset_type,
        'file.filename' => filename,
        'file.local_path' => selected.local_path,
        'file.resource_role' => role,
        'file.resource_position' => position,
        'variables.resource_role' => role,
        'variables.resource_position' => position
      }
    }
  end

  def execute_calculate_copies
    quantity = AutomationEngine.context_value(@context, @config['quantity_field']).to_i
    override = @config.fetch('exact_overrides', {})[quantity.to_s]
    range = Array(@config['range_overrides']).find do |rule|
      quantity >= rule['from'].to_i && quantity <= rule['to'].to_i
    end
    override ||= range&.dig('copies')
    copies = (override || quantity).to_i
    copies = 1 if copies < 1
    output_key = @config['output_key'].presence || 'production_copies'
    {
      'copies' => copies,
      'ordered_quantity' => quantity,
      'matched_rule' => if @config.fetch('exact_overrides', {}).key?(quantity.to_s)
                          'exact'
                        elsif range
                          'range'
                        end,
      'context_updates' => {"variables.#{output_key}" => copies}
    }
  end

  def execute_adobe
    return {'state' => 'waiting_external'} unless @context.dig('runtime', 'simulation')

    source = require_artifact!
    output_dir = run_output_dir
    output = File.join(output_dir, "#{@step.node_key}-#{SecureRandom.hex(4)}.pdf")

    metadata = if source.media_type == 'application/pdf'
                 FileUtils.cp(source.full_path, output)
                 {'simulation' => true, 'copied_pdf' => true}
               else
                 image_arguments = [
                   'image-to-pdf',
                   '--input', source.full_path,
                   '--output', output,
                   '--dpi', (@config['dpi'] || 300).to_s
                 ]
                 if @config['width_mm'].to_f.positive? && @config['height_mm'].to_f.positive?
                   image_arguments.concat([
                     '--width-mm', @config['width_mm'].to_s,
                     '--height-mm', @config['height_mm'].to_s
                   ])
                 end
                 run_pdf_tool(
                   *image_arguments
                 ).merge('simulation' => true)
               end
    artifact = AutomationEngine.create_artifact!(
      run: @run,
      step: @step,
      kind: @config['output_kind'].presence || "#{@step.node_type}_output",
      path: output,
      filename: File.basename(output),
      media_type: 'application/pdf',
      metadata: metadata
    )
    {
      'artifact_id' => artifact.id,
      'simulation' => true,
      'context_updates' => {'runtime.current_artifact_id' => artifact.id}
    }
  end

  def execute_duplicate_pages
    source = require_artifact!
    copies = AutomationEngine.context_value(@context, @config['copies_field']).to_i
    copies = 1 if copies < 1
    output = File.join(run_output_dir, "#{@step.node_key}-#{SecureRandom.hex(4)}.pdf")
    metadata = run_pdf_tool(
      'duplicate-pages',
      '--input', source.full_path,
      '--output', output,
      '--copies', copies.to_s
    )
    artifact = AutomationEngine.create_artifact!(
      run: @run,
      step: @step,
      kind: @config['output_kind'].presence || 'multipage_pdf',
      path: output,
      filename: File.basename(output),
      media_type: 'application/pdf',
      metadata: metadata
    )
    {
      'artifact_id' => artifact.id,
      'context_updates' => {'runtime.current_artifact_id' => artifact.id}
    }
  end

  def execute_pdf_label
    source = require_artifact!
    text = AutomationEngine.resolve(@config['text'].presence || '{{order.code}}', @context).to_s
    raise ArgumentError, 'Il testo da inserire nel PDF è vuoto' if text.strip.empty?

    output = File.join(run_output_dir, "#{@step.node_key}-#{SecureRandom.hex(4)}.pdf")
    label_config = {
      'anchor' => @config.fetch('anchor', 'top_left'),
      'font' => @config.fetch('font', 'Times-Roman'),
      'font_size_pt' => @config.fetch('font_size_pt', 18).to_f,
      'background_color' => @config.fetch('background_color', '#222222'),
      'text_color' => @config.fetch('text_color', '#ffffff'),
      'padding_x_mm' => @config.fetch('padding_x_mm', 2).to_f,
      'padding_y_mm' => @config.fetch('padding_y_mm', 1.5).to_f,
      'offset_x_mm' => @config.fetch('offset_x_mm', 0).to_f,
      'offset_y_mm' => @config.fetch('offset_y_mm', 5).to_f
    }
    metadata = run_pdf_tool(
      'add-text-label',
      '--input', source.full_path,
      '--output', output,
      '--text', text,
      '--config', JSON.generate(label_config)
    )
    artifact = AutomationEngine.create_artifact!(
      run: @run,
      step: @step,
      kind: @config['output_kind'].presence || 'labeled_pdf',
      path: output,
      filename: File.basename(output),
      media_type: 'application/pdf',
      metadata: metadata.merge('source_artifact_id' => source.id)
    )
    {
      'artifact_id' => artifact.id,
      'context_updates' => {'runtime.current_artifact_id' => artifact.id}
    }
  end

  def execute_resize_pdf
    source = require_artifact!
    output = File.join(run_output_dir, "#{@step.node_key}-#{SecureRandom.hex(4)}.pdf")
    resize_config = {
      'width_mm' => @config.fetch('width_mm', 297).to_f,
      'height_mm' => @config.fetch('height_mm', 210).to_f,
      'mode' => AutomationEngine.resolve(@config.fetch('mode', 'contain'), @context).to_s
    }
    metadata = run_pdf_tool(
      'resize-pages',
      '--input', source.full_path,
      '--output', output,
      '--config', JSON.generate(resize_config)
    )
    artifact = AutomationEngine.create_artifact!(
      run: @run,
      step: @step,
      kind: @config['output_kind'].presence || 'resized_pdf',
      path: output,
      filename: File.basename(output),
      media_type: 'application/pdf',
      metadata: metadata.merge('source_artifact_id' => source.id)
    )
    {
      'artifact_id' => artifact.id,
      'context_updates' => {'runtime.current_artifact_id' => artifact.id}
    }
  end

  def execute_collect_group
    source = require_artifact!
    group_field = @config['group_field'].presence || 'aggregation.token'
    expected_field = @config['expected_count_field'].presence || 'aggregation.expected_count'
    order_field = @config['order_field'].presence || 'aggregation.position'
    group_key = AutomationEngine.context_value(@context, group_field).to_s.strip
    expected_count = @config['expected_count'].to_i
    expected_count = AutomationEngine.context_value(@context, expected_field).to_i unless expected_count.positive?
    position = AutomationEngine.context_value(@context, order_field).to_i
    consistency_field = @config['consistency_field'].to_s.strip.presence
    consistency_value = if consistency_field
                          AutomationEngine.context_value(@context, consistency_field).to_s.strip
                        end

    raise ArgumentError, "Il valore di #{group_field} è vuoto" if group_key.empty?
    raise ArgumentError, "Il valore di #{expected_field} deve essere maggiore di zero" unless expected_count.positive?
    if consistency_field && consistency_value.empty?
      raise ArgumentError, "Il valore di #{consistency_field} è vuoto"
    end

    timeout_minutes = [@config.fetch('timeout_minutes', 15).to_f, 0.1].max
    timeout_at = Time.current + timeout_minutes.minutes
    result = nil

    AutomationGroupCollection.transaction do
      lock_key = [
        @run.automation_flow_version_id,
        @step.node_key,
        group_key
      ].join(':')
      ActiveRecord::Base.connection.execute(
        "SELECT pg_advisory_xact_lock(hashtext(#{ActiveRecord::Base.connection.quote(lock_key)}))"
      )

      collection = AutomationGroupCollection.find_or_create_by!(
        automation_flow_version: @run.automation_flow_version,
        node_key: @step.node_key,
        group_key: group_key
      ) do |record|
        record.expected_count = expected_count
        record.timeout_at = timeout_at
        record.metadata = {
          'group_field' => group_field,
          'expected_count_field' => expected_field,
          'aggregation_id' => @context.dig('aggregation', 'id'),
          'aggregation_name' => @context.dig('aggregation', 'name'),
          'consistency_field' => consistency_field,
          'consistency_value' => consistency_value
        }
      end
      collection.lock!
      if collection.expected_count != expected_count
        raise ArgumentError,
              "Il gruppo #{group_key} attende #{collection.expected_count} file, " \
              "ma questa esecuzione ne dichiara #{expected_count}"
      end
      stored_consistency_field = collection.metadata['consistency_field'].to_s.presence
      stored_consistency_value = collection.metadata['consistency_value'].to_s
      if stored_consistency_field != consistency_field ||
         (consistency_field && stored_consistency_value != consistency_value)
        raise ArgumentError,
              "Gruppo incompatibile: #{consistency_field || stored_consistency_field} " \
              "vale “#{stored_consistency_value}” nel gruppo e “#{consistency_value}” in questa riga"
      end
      if collection.status == 'completed'
        if collection.coordinator_run_id == @run.id && collection.output_artifact&.available?
          artifact = collection.output_artifact
          result = {
            'artifact_id' => artifact.id,
            'collection_id' => collection.id,
            'group_key' => group_key,
            'received_count' => collection.items.count,
            'expected_count' => collection.expected_count,
            'recovered_completed_collection' => true,
            'context_updates' => {'runtime.current_artifact_id' => artifact.id}
          }
          next
        end
        raise ArgumentError, "Il gruppo #{group_key} è già stato completato"
      end

      collection.items.find_or_create_by!(automation_run: @run) do |member|
        member.automation_artifact = source
        member.position = position
        member.metadata = {
          'filename' => source.filename,
          'order_code' => @context.dig('order', 'code'),
          'order_item_id' => @run.order_item_id,
          'consistency_value' => consistency_value
        }
      end

      received_count = collection.items.count
      complete = received_count >= expected_count
      if !complete && Time.current >= collection.timeout_at
        if @config.fetch('timeout_policy', 'fail') == 'process_received'
          complete = received_count.positive?
        else
          raise ArgumentError,
                "Gruppo incompleto: ricevuti #{received_count}/#{expected_count} file"
        end
      end

      unless complete
        result = {
          'state' => 'waiting_group',
          'wait_until' => collection.timeout_at.iso8601,
          'collection_id' => collection.id,
          'group_key' => group_key,
          'received_count' => received_count,
          'expected_count' => expected_count
        }
        next
      end

      members = collection.items.includes(:automation_artifact, :automation_run)
                          .order(:position, :id).to_a
      unavailable = members.find { |member| !member.automation_artifact.available? }
      raise ArgumentError, "File del gruppo non disponibile: #{unavailable&.automation_artifact&.filename}" if unavailable

      output = File.join(run_output_dir, "#{@step.node_key}-#{SecureRandom.hex(4)}.pdf")
      metadata = if members.one?
                   FileUtils.cp(members.first.automation_artifact.full_path, output)
                   {
                     'input_files' => 1,
                     'single_file_passthrough' => true
                   }
                 else
                   run_pdf_tool(
                     'merge-pages',
                     *members.flat_map { |member| ['--input', member.automation_artifact.full_path] },
                     '--output', output
                   )
                 end
      artifact = AutomationEngine.create_artifact!(
        run: @run,
        step: @step,
        kind: @config['output_kind'].presence || 'aggregated_pdf',
        path: output,
        filename: File.basename(output),
        media_type: 'application/pdf',
        metadata: metadata.merge(
          'collection_id' => collection.id,
          'group_key' => group_key,
          'expected_count' => expected_count,
          'received_count' => members.length,
          'member_run_ids' => members.map(&:automation_run_id)
        )
      )

      absorbed_run_ids = []
      members.each do |member|
        next if member.automation_run_id == @run.id

        waiting_step = member.automation_run.automation_step_runs.find_by(node_key: @step.node_key)
        next unless waiting_step && waiting_step.status == 'queued' &&
                    waiting_step.output_data['state'] == 'waiting_group'

        waiting_step.update!(
          status: 'completed',
          output_data: waiting_step.output_data.merge(
            'absorbed_into_run_id' => @run.id,
            'collection_id' => collection.id,
            'output_artifact_id' => artifact.id
          ),
          available_at: nil,
          finished_at: Time.current
        )
        AutomationEngine.complete_absorbed_run!(member.automation_run)
        absorbed_run_ids << member.automation_run_id
      end

      collection.update!(
        status: 'completed',
        coordinator_run: @run,
        output_artifact: artifact,
        completed_at: Time.current
      )
      result = {
        'artifact_id' => artifact.id,
        'collection_id' => collection.id,
        'group_key' => group_key,
        'received_count' => members.length,
        'expected_count' => expected_count,
        'absorbed_run_ids' => absorbed_run_ids,
        'context_updates' => {
          'runtime.current_artifact_id' => artifact.id,
          'aggregation.received_count' => members.length
        }
      }
    end
    result
  end

  def execute_insert_blanks
    source = require_artifact!
    quantity_field = @config['quantity_field'].presence || 'item.quantity'
    quantity = AutomationEngine.context_value(@context, quantity_field).to_i
    pdf_config = {
      'quantity' => quantity,
      'rules' => resolve_nested_config(Array(@config['rules']))
    }
    side_page_counts = Array(source.metadata.to_h['side_page_counts']).map(&:to_i)
    if side_page_counts.length == 2 && side_page_counts.all?(&:positive?)
      pdf_config['side_page_counts'] = side_page_counts
    end

    output = File.join(run_output_dir, "#{@step.node_key}-#{SecureRandom.hex(4)}.pdf")
    metadata = run_pdf_tool(
      'insert-blanks',
      '--input', source.full_path,
      '--output', output,
      '--config', JSON.generate(pdf_config)
    )
    artifact = AutomationEngine.create_artifact!(
      run: @run,
      step: @step,
      kind: @config['output_kind'].presence || 'blank_padded_pdf',
      path: output,
      filename: File.basename(output),
      media_type: 'application/pdf',
      metadata: metadata.merge(
        'side_page_counts' => (
          metadata['input_page_counts'] if side_page_counts.length == 2
        ),
        'source_artifact_id' => source.id,
        'quantity_field' => quantity_field
      )
    )
    {
      'artifact_id' => artifact.id,
      'context_updates' => {'runtime.current_artifact_id' => artifact.id}
    }
  end

  def execute_pair_sides
    source = require_artifact!
    filename = @context.dig('file', 'filename').presence || source.filename
    side = side_for_filename(filename)

    unless side
      return {
        'next_port' => 'mono',
        'print_mode' => 'mono',
        'context_updates' => {
          'variables.print_mode' => 'mono',
          'variables.side_count' => 1
        }
      }
    end

    # A front-suffixed file is also used for products that are genuinely
    # monofacial. Only wait for a back side when the order line actually has
    # a corresponding _R asset; otherwise route the _F file as mono.
    if side == 'front' && !back_asset_expected?
      return {
        'next_port' => 'mono',
        'print_mode' => 'mono',
        'context_updates' => {
          'variables.print_mode' => 'mono',
          'variables.side_count' => 1
        }
      }
    end

    counterpart = find_waiting_counterpart(side)
    return combine_with_counterpart!(counterpart, side, source) if counterpart

    waited_since = @step.output_data['waiting_since'].presence
    timeout_minutes = [@config.fetch('timeout_minutes', 15).to_f, 0].max
    deadline = (waited_since ? Time.iso8601(waited_since) : Time.current) + timeout_minutes.minutes
    return missing_side_result(side) if Time.current >= deadline

    {
      'state' => 'waiting_group',
      'waiting_since' => waited_since || Time.current.iso8601,
      'wait_until' => deadline.iso8601,
      'detected_side' => side,
      'group_value' => pairing_group_value,
      'filename' => filename
    }
  end

  def side_for_filename(filename)
    stem = File.basename(filename.to_s, File.extname(filename.to_s))
    front = @config.fetch('front_suffix', '_F').to_s
    back = @config.fetch('back_suffix', '_R').to_s
    raise ArgumentError, 'I suffissi fronte e retro devono essere diversi' if front.casecmp?(back)
    raise ArgumentError, 'Configura entrambi i suffissi fronte e retro' if front.empty? || back.empty?

    return 'front' if stem.downcase.end_with?(front.downcase)
    return 'back' if stem.downcase.end_with?(back.downcase)
  end

  def pairing_group_value
    field = @config['group_field'].presence || 'item.id'
    AutomationEngine.context_value(@context, field).to_s
  end

  def back_asset_expected?
    return false unless @run.order_item

    print_assets = @run.order_item.assets.where(deleted_at: nil).select do |asset|
      asset.asset_type.to_s == 'print' || asset.asset_type.to_s.start_with?('print_file')
    end
    # Imported two-sided products are represented by multiple print_file_*
    # assets. Their physical paths may not contain _R, so the asset count is
    # the primary signal; retain the suffix check as a fallback.
    return true if print_assets.size > 1

    print_assets.any? do |asset|
      source = [asset.original_url, asset.local_path].compact.join(' ')
      stem = File.basename(source.to_s, File.extname(source.to_s))
      stem.downcase.end_with?(@config.fetch('back_suffix', '_R').to_s.downcase)
    end
  end

  def find_waiting_counterpart(side)
    return nil if @run.action_batch_id.blank?

    candidates = AutomationRun.where(
      automation_flow_version_id: @run.automation_flow_version_id,
      order_item_id: @run.order_item_id,
      action_batch_id: @run.action_batch_id
    ).where.not(id: @run.id)

    candidates.each do |candidate_run|
      next false unless AutomationEngine.context_value(
        candidate_run.context,
        @config['group_field'].presence || 'item.id'
      ).to_s == pairing_group_value

      candidate_step = candidate_run.automation_step_runs.find_by(
        node_key: @step.node_key,
        status: 'queued'
      )
      next false unless candidate_step&.output_data&.dig('state') == 'waiting_group'

      candidate_filename = candidate_run.context.dig('file', 'filename')
      candidate_side = side_for_filename(candidate_filename)
      return candidate_step if candidate_side && candidate_side != side
    end
    nil
  end

  def combine_with_counterpart!(counterpart_step, side, source)
    counterpart_run = counterpart_step.automation_run
    counterpart_source = counterpart_run.current_artifact
    raise ArgumentError, 'Il file dell’altro lato non è più disponibile' unless counterpart_source&.available?

    front = side == 'front' ? source : counterpart_source
    back = side == 'back' ? source : counterpart_source
    output = File.join(run_output_dir, "#{@step.node_key}-#{SecureRandom.hex(4)}.pdf")
    metadata = run_pdf_tool(
      'merge-pages',
      '--input', front.full_path,
      '--input', back.full_path,
      '--output', output
    )
    artifact = AutomationEngine.create_artifact!(
      run: @run,
      step: @step,
      kind: @config['output_kind'].presence || 'paired_pdf',
      path: output,
      filename: File.basename(output),
      media_type: 'application/pdf',
      metadata: metadata.merge(
        'side_page_counts' => metadata['input_page_counts'],
        'front_artifact_id' => front.id,
        'back_artifact_id' => back.id,
        'paired_run_id' => counterpart_run.id
      )
    )

    counterpart_step.update!(
      status: 'completed',
      output_data: counterpart_step.output_data.merge(
        'paired_into_run_id' => @run.id,
        'paired_artifact_id' => artifact.id
      ),
      available_at: nil,
      finished_at: Time.current
    )
    counterpart_run.update!(
      status: 'completed',
      current_node_key: nil,
      completed_at: Time.current
    )

    {
      'artifact_id' => artifact.id,
      'next_port' => 'bifa',
      'print_mode' => 'bifa',
      'paired_run_id' => counterpart_run.id,
      'context_updates' => {
        'runtime.current_artifact_id' => artifact.id,
        'variables.print_mode' => 'bifa',
        'variables.side_count' => 2
      }
    }
  end

  def missing_side_result(side)
    case @config.fetch('missing_policy', 'route_incomplete')
    when 'treat_as_mono'
      {
        'next_port' => 'mono',
        'print_mode' => 'mono',
        'missing_side' => side == 'front' ? 'back' : 'front',
        'context_updates' => {
          'variables.print_mode' => 'mono',
          'variables.side_count' => 1
        }
      }
    when 'fail'
      raise ArgumentError, "Lato #{side == 'front' ? 'retro' : 'fronte'} non ricevuto entro il tempo configurato"
    else
      {
        'next_port' => 'incomplete',
        'print_mode' => 'incomplete',
        'missing_side' => side == 'front' ? 'back' : 'front',
        'context_updates' => {
          'variables.print_mode' => 'incomplete',
          'variables.side_count' => 1
        }
      }
    end
  end

  def execute_step_repeat
    source = require_artifact!
    preset_code = if @config.fetch('preset_source', 'fixed') == 'variable'
                    variable = @config['preset_variable'].presence || 'variables.imposition_preset'
                    AutomationEngine.context_value(@context, variable)
                  else
                    AutomationEngine.resolve(@config['preset_code'], @context)
                  end
    preset_code = preset_code.to_s.strip
    raise ArgumentError, 'Il preset di imposizione risolto è vuoto' if preset_code.empty?
    preset = AutomationPreset.active.find_by(kind: 'imposition', code: preset_code)
    raise ArgumentError, "Preset di imposizione non trovato: #{preset_code}" unless preset

    input_path = source.full_path
    compatibility_metadata = {}
    if @config['copies_field'].present?
      copies = AutomationEngine.context_value(@context, @config['copies_field']).to_i
      copies = 1 if copies < 1
      input_path = File.join(run_output_dir, "#{@step.node_key}-legacy-pages-#{SecureRandom.hex(4)}.pdf")
      compatibility_metadata = run_pdf_tool(
        'duplicate-pages',
        '--input', source.full_path,
        '--output', input_path,
        '--copies', copies.to_s
      ).merge('legacy_inline_duplication' => true)
    end

    output = File.join(run_output_dir, "#{@step.node_key}-#{SecureRandom.hex(4)}.pdf")
    impose_config = preset.config.deep_dup
    side_page_counts = Array(source.metadata.to_h['side_page_counts']).map(&:to_i)
    if side_page_counts.length == 2 &&
       side_page_counts.all?(&:positive?) &&
       %w[horizontal vertical].include?(impose_config['double_sided_mode'].to_s)
      impose_config['side_page_counts'] = side_page_counts
    end

    metadata = run_pdf_tool(
      'impose',
      '--input', input_path,
      '--output', output,
      '--config', JSON.generate(impose_config)
    ).merge(compatibility_metadata)
    artifact = AutomationEngine.create_artifact!(
      run: @run,
      step: @step,
      kind: @config['output_kind'].presence || 'imposition_pdf',
      path: output,
      filename: File.basename(output),
      media_type: 'application/pdf',
      metadata: metadata.merge('preset_code' => preset_code)
    )
    {
      'artifact_id' => artifact.id,
      'context_updates' => {'runtime.current_artifact_id' => artifact.id}
    }
  end

  def execute_barcode
    data = AutomationEngine.context_value(@context, @config['data_field']).to_s
    raise ArgumentError, 'Il valore del barcode è vuoto' if data.empty?

    output = File.join(run_output_dir, "#{@step.node_key}-#{SecureRandom.hex(4)}.pdf")
    metadata = run_pdf_tool(
      'barcode',
      '--data', data,
      '--output', output,
      '--config', JSON.generate(@config)
    )
    artifact = AutomationEngine.create_artifact!(
      run: @run,
      step: @step,
      kind: @config['output_kind'].presence || 'barcode_pdf',
      path: output,
      filename: File.basename(output),
      media_type: 'application/pdf',
      metadata: metadata
    )
    {
      'artifact_id' => artifact.id,
      'context_updates' => {'runtime.current_artifact_id' => artifact.id}
    }
  end

  def execute_hot_folder
    source = delivery_source
    raise ArgumentError, "File sorgente non trovato per #{@config['artifact_kind']}" unless source&.available?

    filename = AutomationEngine.resolve(@config['filename'], @context).presence || source.filename
    filename = File.basename(filename)
    destination_code = AutomationEngine.resolve(@config['destination_code'], @context).to_s

    raise ArgumentError, 'Seleziona una hot folder' if destination_code.blank?

    destination = AutomationDestination.active.find_by(code: destination_code)
    raise ArgumentError, "Destinazione non trovata: #{destination_code}" unless destination

    if destination.config['agent_key'].present? && !simulation?
      raise ArgumentError, 'Percorso hot folder sul Mac non configurato' if
        destination.config['agent_path'].to_s.strip.empty?

      return {'state' => 'waiting_external'}
    end

    delivery = AutomationDestinationService.deliver(
      destination: destination,
      source_path: source.full_path,
      filename: filename,
      simulation: simulation?
    )
    target = delivery[:simulated] ? source.full_path : delivery[:target]
    metadata = {
      'source_artifact_id' => source.id,
      'destination_code' => destination.code,
      'delivered_to' => delivery[:target],
      'simulated' => delivery[:simulated]
    }

    artifact = AutomationEngine.create_artifact!(
      run: @run,
      step: @step,
      kind: @config['output_kind'].presence || 'delivered',
      path: target,
      filename: filename,
      media_type: source.media_type,
      metadata: metadata
    )
    {
      'artifact_id' => artifact.id,
      'delivered_to' => metadata['delivered_to'] || target,
      'simulated' => metadata['simulated'] == true
    }
  end

  def execute_label_printer
    source = delivery_source
    raise ArgumentError, "PDF etichetta non trovato per #{@config['artifact_kind']}" unless source&.available?

    destination_code = AutomationEngine.resolve(@config['destination_code'], @context).to_s
    destination = AutomationDestination.active.find_by(code: destination_code)
    raise ArgumentError, "Stampante etichette non trovata: #{destination_code}" unless destination

    result = AutomationDestinationService.print_label(
      destination: destination,
      source_path: source.full_path,
      simulation: simulation?
    )
    artifact = AutomationEngine.create_artifact!(
      run: @run,
      step: @step,
      kind: @config['output_kind'].presence || 'printed_label',
      path: source.full_path,
      filename: source.filename,
      media_type: source.media_type,
      metadata: {
        'source_artifact_id' => source.id,
        'destination_code' => destination.code,
        'cups_job_id' => result[:job_id],
        'cups_output' => result[:output],
        'simulated' => result[:simulated]
      }
    )
    {
      'artifact_id' => artifact.id,
      'destination_code' => destination.code,
      'cups_job_id' => result[:job_id],
      'simulated' => result[:simulated]
    }
  end

  def delivery_source
    if @config['artifact_kind'].present?
      @run.artifact_by_kind(@config['artifact_kind'])
    else
      @run.current_artifact
    end
  end

  def simulation?
    @context.dig('runtime', 'simulation') == true
  end

  def resolve_nested_config(value)
    case value
    when Hash
      value.transform_values { |nested| resolve_nested_config(nested) }
    when Array
      value.map { |nested| resolve_nested_config(nested) }
    else
      AutomationEngine.resolve(value, @context)
    end
  end

  def compare(left, operator, right)
    alternatives = right.to_s.split(';').map(&:strip).reject(&:empty?)
    if alternatives.length > 1 && operator.to_s != 'matches'
      return alternatives.any? { |value| compare(left, operator, value) }
    end

    case operator.to_s
    when 'equals' then left.to_s.casecmp?(right.to_s)
    when 'contains' then left.to_s.downcase.include?(right.to_s.downcase)
    when 'starts_with' then left.to_s.downcase.start_with?(right.to_s.downcase)
    when 'greater_than' then left.to_f > right.to_f
    when 'greater_or_equal' then left.to_f >= right.to_f
    when 'less_than' then left.to_f < right.to_f
    when 'less_or_equal' then left.to_f <= right.to_f
    when 'matches' then Regexp.new(right.to_s, Regexp::IGNORECASE).match?(left.to_s)
    else false
    end
  rescue RegexpError
    false
  end

  def require_artifact!
    artifact = @run.current_artifact
    raise ArgumentError, 'Il passaggio non ha un file sorgente disponibile' unless artifact&.available?

    artifact
  end

  def run_output_dir
    dir = File.join(Dir.pwd, 'storage', 'automation', 'runs', @run.id.to_s)
    FileUtils.mkdir_p(dir)
    dir
  end

  def run_pdf_tool(*arguments)
    script = File.join(Dir.pwd, 'tools', 'automation_pdf', 'cli.py')
    stdout, stderr, status = Open3.capture3('python3', script, *arguments)
    raise "Elaborazione PDF fallita: #{stderr.presence || stdout}" unless status.success?

    JSON.parse(stdout)
  end
end

class AutomationWorker
  DEFAULT_POLL_SECONDS = 1.0

  def self.run(poll_seconds: DEFAULT_POLL_SECONDS)
    logger = ActiveRecord::Base.logger
    logger.level = Logger::WARN if logger && ENV['AUTOMATION_WORKER_SQL_LOG'] != '1'
    worker = new
    puts "[AutomationWorker] Avviato #{worker.worker_id}"
    loop do
      processed = worker.run_once
      sleep(poll_seconds) unless processed
    rescue Interrupt
      puts '[AutomationWorker] Arrestato'
      break
    rescue StandardError => e
      warn "[AutomationWorker] #{e.class}: #{e.message}"
      sleep(poll_seconds)
    end
  end

  attr_reader :worker_id

  def initialize(worker_id: "worker-#{Socket.gethostname}-#{Process.pid}")
    @worker_id = worker_id
  end

  def run_once
    step = claim_step
    return false unless step

    result = AutomationNodeExecutor.new(step).execute
    case result['state']
    when 'waiting_external'
      step.update!(status: 'waiting_external', worker_id: nil, locked_at: nil)
      step.automation_run.update!(status: 'waiting_external')
    when 'waiting_review'
      step.update!(status: 'waiting_review', worker_id: nil, locked_at: nil)
      step.automation_run.update!(status: 'waiting_review')
    when 'waiting_group'
      step.update!(
        status: 'queued',
        output_data: result,
        available_at: Time.iso8601(result.fetch('wait_until')),
        worker_id: nil,
        locked_at: nil
      )
      step.automation_run.update!(status: 'waiting_group')
    else
      AutomationEngine.complete_step!(step, result)
    end
    true
  rescue StandardError => e
    AutomationEngine.fail_step!(step, "#{e.class}: #{e.message}") if step
    true
  end

  private

  def claim_step
    AutomationStepRun.transaction do
      stale_before = 15.minutes.ago
      AutomationStepRun.where(status: 'running')
                       .where('locked_at < ?', stale_before)
                       .update_all(status: 'queued', worker_id: nil, locked_at: nil)

      step = AutomationStepRun.ready.lock('FOR UPDATE SKIP LOCKED').first
      next unless step

      step.update!(
        status: 'running',
        attempts: step.attempts + 1,
        worker_id: worker_id,
        locked_at: Time.current,
        started_at: step.started_at || Time.current
      )
      step.automation_run.update!(status: 'running')
      step
    end
  end
end
