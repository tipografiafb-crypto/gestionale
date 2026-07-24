# @feature automation
# @domain services

require 'digest'
require 'fileutils'
require 'json'
require 'open3'
require 'pathname'
require 'securerandom'
require 'socket'

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
      upsert_preset(
        'output',
        'LOCAL_TEST',
        'Hot folder locale di test',
        {
          'print_destination' => 'print',
          'label_destination' => 'labels'
        }
      )
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
          'values' => {'adobe_action_set' => 'definitive_0924', 'adobe_action_name' => 'plettri bianchi', 'template' => 'STANDARD', 'imposition_preset' => 'STANDARD_MONO'}
        }),
        node('black_vars', 'set_variables', 'Azione nero', 490, 360, {
          'values' => {'adobe_action_set' => 'definitive_0924', 'adobe_action_name' => 'plettri neri', 'template' => 'STANDARD', 'imposition_preset' => 'STANDARD_MONO'}
        }),
        node('other_vars', 'set_variables', 'Azione altri', 490, 540, {
          'values' => {'adobe_action_set' => 'definitive_0924', 'adobe_action_name' => 'altri plettri', 'template' => 'STANDARD', 'imposition_preset' => 'STANDARD_MONO'}
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
          'values' => {'template' => 'SHARP'}
        }),
        node('template_jazz', 'set_variables', 'Maschera JAZZ', 980, 130, {
          'values' => {'template' => 'JAZZ'}
        }),
        node('template_triangle', 'set_variables', 'Maschera TRIANGOLO', 980, 240, {
          'values' => {'template' => 'TRIANGOLO'}
        }),
        node('template_flow', 'set_variables', 'Maschera FLOW', 980, 350, {
          'values' => {'template' => 'FLOW'}
        }),
        node('template_tortex', 'set_variables', 'Maschera TORTEX', 980, 460, {
          'values' => {'template' => 'TORTEX'}
        }),
        node('template_gator', 'set_variables', 'Maschera GATOR', 980, 570, {
          'values' => {'template' => 'GATOR'}
        }),
        node('template_standard', 'set_variables', 'Maschera STANDARD', 980, 680, {
          'values' => {'template' => 'STANDARD'}
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
          'script_name' => 'plettro2.jsx',
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
          'preset_code' => 'LOCAL_TEST',
          'destination_key' => 'print_destination',
          'artifact_kind' => 'imposition_pdf',
          'filename' => '{{order.code}}-{{item.id}}-plancia.pdf',
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
          'preset_code' => 'LOCAL_TEST',
          'destination_key' => 'label_destination',
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
    def start_run(flow:, order_item:, source_asset: nil, operation_type: 'manual',
                  print_flow: nil, action_batch_id: nil, simulation: false,
                  extra_context: {})
      version = flow.active_version
      raise ArgumentError, 'Pubblica il flusso prima di avviarlo' unless version

      graph_errors = version.graph_errors
      raise ArgumentError, graph_errors.join(', ') if graph_errors.any?

      trigger = Array(version.graph['nodes']).find { |node| node['type'] == 'trigger' }
      accepted_operation = trigger&.dig('config', 'operation_type').to_s
      if accepted_operation.present? && accepted_operation != 'any' &&
         accepted_operation != operation_type.to_s
        raise ArgumentError,
              "Il flusso accetta l'azione #{accepted_operation}, non #{operation_type}"
      end

      asset = source_asset ||
              order_item.switch_print_assets.find(&:downloaded?) ||
              order_item.assets.find(&:downloaded?)
      raise ArgumentError, 'Nessun asset locale disponibile per la riga ordine' unless asset
      raise ArgumentError, 'Il file sorgente non è disponibile localmente' unless asset.downloaded?

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
        schedule_next!(step, result['next_port'] || 'default')
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
        ancestor.update!(
          status: 'completed',
          error_message: nil,
          current_node_key: nil,
          completed_at: Time.current
        )
        ancestor = ancestor.parent_run
      end
    end

    def context_value(context, path)
      path.to_s.split('.').reduce(context) do |value, key|
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
      else 'application/octet-stream'
      end
    end

    private

    def schedule_next!(step, port)
      run = step.automation_run
      graph = run.automation_flow_version.graph
      edge = Array(graph['edges']).find do |candidate|
        candidate['source'] == step.node_key &&
          candidate.fetch('source_port', 'default').to_s == port.to_s
      end
      edge ||= Array(graph['edges']).find do |candidate|
        candidate['source'] == step.node_key &&
          candidate.fetch('source_port', 'default').to_s == 'default'
      end

      unless edge
        run.update!(status: 'completed', current_node_key: nil, completed_at: Time.current)
        complete_chain_ancestors!(run)
        AutomationActionLifecycle.run_completed!(run) if defined?(AutomationActionLifecycle)
        return
      end

      node = Array(graph['nodes']).find { |candidate| candidate['id'] == edge['target'] }
      enqueue_node!(run, node)
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
          'route_text' => route_text
        },
        'operation' => {
          'type' => operation_type,
          'id' => extra_context['operation_id'],
          'print_flow_id' => print_flow&.id,
          'print_flow_name' => print_flow&.name
        },
        'file' => {
          'asset_id' => asset.id,
          'asset_type' => asset.asset_type,
          'filename' => item.switch_filename_for_asset(asset) || asset.filename_from_url,
          'local_path' => asset.local_path,
          'index' => extra_context['file_index'] || 1,
          'count' => extra_context['file_count'] || 1
        },
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
    when 'set_variables' then execute_set_variables
    when 'calculate_copies' then execute_calculate_copies
    when 'duplicate_pages' then execute_duplicate_pages
    when 'pair_sides' then execute_pair_sides
    when 'photoshop', 'illustrator' then execute_adobe
    when 'step_repeat' then execute_step_repeat
    when 'barcode' then execute_barcode
    when 'hot_folder' then execute_hot_folder
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

    counterpart = find_waiting_counterpart(side)
    return combine_with_counterpart!(counterpart, side, source) if counterpart

    waited_since = @step.output_data['waiting_since'].presence
    timeout_minutes = [@config.fetch('timeout_minutes', 15).to_f, 0].max
    deadline = (waited_since ? Time.zone.parse(waited_since) : Time.current) + timeout_minutes.minutes
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
    preset_code = AutomationEngine.resolve(@config['preset_code'], @context)
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
    metadata = run_pdf_tool(
      'impose',
      '--input', input_path,
      '--output', output,
      '--config', JSON.generate(preset.config)
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
    source = if @config['artifact_kind'].present?
               @run.artifact_by_kind(@config['artifact_kind'])
             else
               @run.current_artifact
             end
    raise ArgumentError, "File sorgente non trovato per #{@config['artifact_kind']}" unless source&.available?

    preset_code = AutomationEngine.resolve(@config['preset_code'], @context)
    preset = AutomationPreset.active.find_by(kind: 'output', code: preset_code)
    raise ArgumentError, "Preset di uscita non trovato: #{preset_code}" unless preset

    destination = preset.config[@config['destination_key']]
    root = File.expand_path(ENV.fetch('AUTOMATION_OUTPUT_ROOT', 'storage/automation/hotfolders'), Dir.pwd)
    target_dir = File.expand_path(destination.to_s, root)
    raise ArgumentError, 'Destinazione hot folder non consentita' unless target_dir == root || target_dir.start_with?("#{root}/")

    FileUtils.mkdir_p(target_dir)
    filename = AutomationEngine.resolve(@config['filename'], @context).presence || source.filename
    filename = File.basename(filename)
    target = File.join(target_dir, filename)
    temporary = "#{target}.partial-#{@run.id}-#{@step.id}"
    FileUtils.cp(source.full_path, temporary)
    File.rename(temporary, target)

    artifact = AutomationEngine.create_artifact!(
      run: @run,
      step: @step,
      kind: @config['output_kind'].presence || 'delivered',
      path: target,
      filename: filename,
      media_type: source.media_type,
      metadata: {'source_artifact_id' => source.id, 'preset_code' => preset_code}
    )
    {'artifact_id' => artifact.id, 'delivered_to' => target}
  ensure
    File.delete(temporary) if defined?(temporary) && temporary && File.exist?(temporary)
  end

  def compare(left, operator, right)
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
    ActiveRecord::Base.logger.level = Logger::WARN unless ENV['AUTOMATION_WORKER_SQL_LOG'] == '1'
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
        available_at: Time.zone.parse(result.fetch('wait_until')),
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
