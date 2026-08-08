# frozen_string_literal: true

require 'json'

# Portable JSON representation for an automation flow. Imports deliberately
# create a draft: publishing is an explicit user action after checking local
# Adobe scripts, masks, destinations and module links.
module AutomationFlowTransfer
  module_function

  def export(flow)
    draft = flow.draft_version
    active = flow.active_version
    graph = draft.graph || AutomationBootstrap.blank_graph
    preset_codes = Array(graph['nodes']).filter_map do |node|
      config = node['config'] || {}
      config['preset_code'].to_s.strip.presence if node['type'] == 'step_repeat' &&
        config.fetch('preset_source', 'fixed').to_s == 'fixed'
    end.uniq

    {
      'format' => 'magenta_automation_flow',
      'exported_at' => Time.current.iso8601,
      'flow' => {
        'name' => flow.name,
        'description' => flow.description,
        'graph' => JSON.parse(JSON.generate(graph)),
        'published_graph' => active && JSON.parse(JSON.generate(active.graph))
      },
      'presets' => AutomationPreset.where(kind: 'imposition', code: preset_codes).map do |preset|
        {
          'kind' => preset.kind,
          'code' => preset.code,
          'name' => preset.name,
          'config' => preset.config,
          'active' => preset.active
        }
      end
    }
  end

  def import!(raw)
    payload = raw.is_a?(String) ? JSON.parse(raw) : raw
    unless payload.is_a?(Hash) && payload['format'].to_s == 'magenta_automation_flow'
      raise ArgumentError, 'File non riconosciuto: serve un export di automazione Magenta'
    end
    data = payload['flow'].is_a?(Hash) ? payload['flow'] : {}
    graph = data['graph']
    unless graph.is_a?(Hash) && graph['nodes'].is_a?(Array) && graph['edges'].is_a?(Array)
      raise ArgumentError, 'Il file non contiene un grafo di automazione valido'
    end

    name = unique_name(data['name'].to_s.strip.presence || 'Automazione importata')
    flow = nil
    warnings = []
    AutomationFlow.transaction do
      flow = AutomationFlow.create!(
        name: name,
        description: data['description'].to_s,
        status: 'draft'
      )
      flow.draft_version.update!(graph: JSON.parse(JSON.generate(graph)))
      import_presets!(payload['presets'], warnings)
      collect_handoff_warnings(graph, warnings)
    end
    {flow: flow, warnings: warnings}
  rescue JSON::ParserError
    raise ArgumentError, 'Il file importato non è un JSON valido'
  end

  def unique_name(base)
    candidate = base
    suffix = 2
    while AutomationFlow.exists?(name: candidate)
      candidate = "#{base} (importato #{suffix})"
      suffix += 1
    end
    candidate
  end
  private_class_method :unique_name

  def import_presets!(presets, warnings)
    Array(presets).each do |data|
      next unless data.is_a?(Hash) && data['kind'].present? && data['code'].present?

      existing = AutomationPreset.find_by(kind: data['kind'], code: data['code'])
      if existing
        warnings << "Preset #{data['code']} già presente: mantenuto quello esistente"
        next
      end
      AutomationPreset.create!(
        kind: data['kind'],
        code: data['code'],
        name: data['name'].to_s.presence || data['code'],
        config: data['config'].is_a?(Hash) ? data['config'] : {},
        active: data.key?('active') ? data['active'] : true
      )
      next unless data['kind'].to_s == 'imposition'

      template = ImpositionTemplate.find_or_initialize_by(code: data['code'])
      template.assign_attributes(
        name: data['name'].to_s.presence || data['code'],
        folder: data.dig('config', 'folder').to_s.presence || 'Importate',
        description: template.description.presence || 'Importata insieme a un flusso di automazione',
        status: 'published'
      )
      template.save!
      next if template.versions.exists?

      published = template.versions.create!(
        version_number: 1,
        status: 'published',
        config: data['config'].is_a?(Hash) ? data['config'] : ImpositionConfig.default,
        published_at: Time.current
      )
      template.update!(active_version: published)
      template.versions.create!(version_number: 2, status: 'draft', config: published.config)
    end
  end
  private_class_method :import_presets!

  def collect_handoff_warnings(graph, warnings)
    Array(graph['nodes']).select { |node| node['type'] == 'handoff' }.each do |node|
      target_id = node.dig('config', 'target_flow_id').to_i
      next if target_id.positive? && AutomationFlow.exists?(target_id)

      warnings << "Il modulo collegato (ID #{target_id}) va riconfigurato nel blocco “#{node['label'] || node['id']}”"
    end
  end
  private_class_method :collect_handoff_warnings
end
