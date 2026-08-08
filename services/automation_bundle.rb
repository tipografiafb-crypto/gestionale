# frozen_string_literal: true

require 'json'

# Portable backup of the Automation configuration. Runtime/debug data and
# generated files are deliberately excluded: they belong to individual jobs,
# can be very large, and must not be restored on another machine.
module AutomationBundle
  FORMAT = 'magenta_automation_bundle'
VERSION = 4

  module_function

  def export
    {
      'format' => FORMAT,
      'version' => VERSION,
      'exported_at' => Time.current.iso8601,
      'flows' => AutomationFlow.order(:id).map do |flow|
        {
          'source_id' => flow.id,
          'name' => flow.name,
          'description' => flow.description,
          'status' => flow.status,
          'active_version_number' => flow.active_version&.version_number,
          'versions' => flow.versions.order(:version_number).map do |version|
            {
              'number' => version.version_number,
              'status' => version.status,
              'graph' => deep_copy(version.graph),
              'checksum' => version.checksum,
              'published_at' => version.published_at&.iso8601
            }
          end
        }
      end,
      'folders' => AutomationFolder.order(:id).map do |folder|
        {
          'name' => folder.name,
          'description' => folder.description,
          'root_flow_source_id' => folder.root_flow_id && AutomationFlow.find_by(id: folder.root_flow_id)&.id,
          'flows' => folder.automation_folder_flows.order(:position, :id).map do |membership|
            {'flow_source_id' => membership.automation_flow_id, 'position' => membership.position}
          end
        }
      end,
      'preset_folders' => AutomationPresetFolder.order(:kind, :name).map do |folder|
        {'kind' => folder.kind, 'name' => folder.name}
      end,
      'presets' => AutomationPreset.order(:kind, :code).map do |preset|
        {
          'kind' => preset.kind,
          'code' => preset.code,
          'name' => preset.name,
          'config' => deep_copy(preset.config),
          'active' => preset.active
        }
      end,
      'impositions' => ImpositionTemplate.order(:code).map do |template|
        {
          'code' => template.code,
          'name' => template.name,
          'folder' => template.folder,
          'description' => template.description,
          'status' => template.status,
          'active_version_number' => template.active_version&.version_number,
          'versions' => template.versions.order(:version_number).map do |version|
            {
              'number' => version.version_number,
              'status' => version.status,
              'config' => deep_copy(version.config),
              'published_at' => version.published_at&.iso8601
            }
          end
        }
      end,
      'destinations' => AutomationDestination.order(:code).map do |destination|
        {
          'code' => destination.code,
          'name' => destination.name,
          'kind' => destination.kind,
          'config' => deep_copy(destination.config),
          'active' => destination.active
        }
      end,
      # Resource metadata is useful when moving to another machine. Secrets
      # and live pairing state are intentionally not exported.
      'agents' => AutomationAgent.order(:agent_key).map do |agent|
        {
          'agent_key' => agent.agent_key,
          'name' => agent.name,
          'hostname' => agent.hostname,
          'platform' => agent.platform,
          'capabilities' => deep_copy(agent.capabilities),
          'metadata' => deep_copy(agent.metadata)
        }
      end
    }
  end

  def import!(raw)
    payload = raw.is_a?(String) ? JSON.parse(raw) : raw
    unless payload.is_a?(Hash) && payload['format'].to_s == FORMAT
      raise ArgumentError, 'File non riconosciuto: serve un backup Automation Magenta'
    end
    raise ArgumentError, 'Versione backup non supportata' if payload['version'].to_i > VERSION

    flow_ids = import_flows!(Array(payload['flows']))
    @flow_ids = flow_ids
    import_folders!(Array(payload['folders']), flow_ids)
    import_preset_folders!(Array(payload['preset_folders']))
    import_presets!(Array(payload['presets']))
    import_impositions!(Array(payload['impositions']))
    import_destinations!(Array(payload['destinations']))
    import_agents!(Array(payload['agents']))

    {flows: flow_ids.size, presets: Array(payload['presets']).size,
     impositions: Array(payload['impositions']).size,
     destinations: Array(payload['destinations']).size}
  rescue JSON::ParserError
    raise ArgumentError, 'Il file importato non è un JSON valido'
  end

  def deep_copy(value)
    JSON.parse(JSON.generate(value || {}))
  end
  private_class_method :deep_copy

  def import_flows!(entries)
    flow_ids = {}
    entries.each do |data|
      next unless data.is_a?(Hash) && data['name'].to_s.strip.present?

      flow = AutomationFlow.find_or_initialize_by(name: data['name'].to_s.strip)
      flow.assign_attributes(description: data['description'].to_s, status: data['status'].to_s.presence || 'draft')
      flow.status = 'draft' unless AutomationFlow::STATUSES.include?(flow.status)
      flow.save!
      flow_ids[data['source_id'].to_i] = flow.id
    end

    @flow_ids = flow_ids

    entries.each do |data|
      flow = flow_ids[data['source_id'].to_i] && AutomationFlow.find(flow_ids[data['source_id'].to_i])
      next unless flow

      Array(data['versions']).sort_by { |version| version['number'].to_i }.each do |version_data|
        version = flow.versions.find_or_initialize_by(version_number: version_data['number'].to_i)
        version.assign_attributes(
          status: AutomationFlowVersion::STATUSES.include?(version_data['status'].to_s) ? version_data['status'] : 'draft',
          graph: remap_flow_references(deep_copy(version_data['graph'])),
          checksum: version_data['checksum'],
          published_at: version_data['published_at'].present? ? Time.iso8601(version_data['published_at'].to_s) : nil
        )
        version.save!
      end
      active_number = data['active_version_number'].to_i
      flow.update!(active_version_id: flow.versions.find_by(version_number: active_number)&.id)
    end
    flow_ids
  end
  private_class_method :import_flows!

  def remap_flow_references(value)
    case value
    when Array then value.map { |entry| remap_flow_references(entry) }
    when Hash
      value.each_with_object({}) do |(key, entry), result|
        result[key] = if %w[target_flow_id flow_id].include?(key.to_s) && entry.to_i.positive?
                        @flow_ids[entry.to_i] || entry
                      else
                        remap_flow_references(entry)
                      end
      end
    else value
    end
  end

  def import_folders!(entries, flow_ids)
    entries.each do |data|
      next unless data.is_a?(Hash) && data['name'].to_s.strip.present?

      folder = AutomationFolder.find_or_initialize_by(name: data['name'].to_s.strip)
      folder.update!(description: data['description'].to_s,
                     root_flow_id: flow_ids[data['root_flow_source_id'].to_i])
      Array(data['flows']).each do |membership|
        flow_id = flow_ids[membership['flow_source_id'].to_i]
        next unless flow_id

        link = folder.automation_folder_flows.find_or_initialize_by(automation_flow_id: flow_id)
        link.update!(position: membership['position'].to_i)
      end
    end
  end
  private_class_method :import_folders!

  def import_preset_folders!(entries)
    entries.each do |data|
      next unless data.is_a?(Hash) && data['kind'].present? && data['name'].present?

      AutomationPresetFolder.find_or_create_by!(kind: data['kind'], name: data['name'])
    end
  end
  private_class_method :import_preset_folders!

  def import_presets!(entries)
    entries.each do |data|
      next unless data.is_a?(Hash) && data['kind'].present? && data['code'].present?

      preset = AutomationPreset.find_or_initialize_by(kind: data['kind'], code: data['code'])
      preset.update!(name: data['name'].to_s.presence || data['code'],
                     config: data['config'].is_a?(Hash) ? data['config'] : {},
                     active: data.key?('active') ? data['active'] : true)
    end
  end
  private_class_method :import_presets!

  def import_impositions!(entries)
    entries.each do |data|
      next unless data.is_a?(Hash) && data['code'].present?

      template = ImpositionTemplate.find_or_initialize_by(code: data['code'].to_s)
      template.assign_attributes(
        name: data['name'].to_s.presence || data['code'],
        folder: data['folder'].to_s.presence || 'Principale',
        description: data['description'].to_s,
        status: ImpositionTemplate::STATUSES.include?(data['status'].to_s) ? data['status'] : 'draft'
      )
      template.save!
      Array(data['versions']).each do |version_data|
        number = version_data['number'].to_i
        next unless number.positive?

        version = template.versions.find_or_initialize_by(version_number: number)
        version.update!(
          status: ImpositionTemplateVersion::STATUSES.include?(version_data['status'].to_s) ? version_data['status'] : 'draft',
          config: version_data['config'].is_a?(Hash) ? version_data['config'] : ImpositionConfig.default,
          published_at: version_data['published_at'].present? ? Time.iso8601(version_data['published_at'].to_s) : nil
        )
      end
      active_number = data['active_version_number'].to_i
      template.update!(active_version: template.versions.find_by(version_number: active_number)) if active_number.positive?
    end
  end
  private_class_method :import_impositions!

  def import_destinations!(entries)
    entries.each do |data|
      next unless data.is_a?(Hash) && data['code'].present?

      destination = AutomationDestination.find_or_initialize_by(code: data['code'].to_s)
      destination.update!(name: data['name'].to_s.presence || data['code'],
                          kind: data['kind'].to_s,
                          config: data['config'].is_a?(Hash) ? data['config'] : {},
                          active: data.key?('active') ? data['active'] : true)
    end
  end
  private_class_method :import_destinations!

  def import_agents!(entries)
    entries.each do |data|
      next unless data.is_a?(Hash) && data['agent_key'].present?

      agent = AutomationAgent.find_or_initialize_by(agent_key: data['agent_key'].to_s)
      agent.update!(name: data['name'].to_s.presence || data['agent_key'],
                    hostname: data['hostname'], platform: data['platform'],
                    capabilities: data['capabilities'].is_a?(Array) ? data['capabilities'] : [],
                    metadata: data['metadata'].is_a?(Hash) ? data['metadata'] : {})
    end
  end
  private_class_method :import_agents!

end
