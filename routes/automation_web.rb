# @feature automation
# @domain web-api

require 'fileutils'
require 'json'
require 'securerandom'

class PrintOrchestrator < Sinatra::Base
  AUTOMATION_FIELD_CATALOG = [
    {path: 'item.sku', label: 'SKU prodotto', type: 'text'},
    {path: 'item.quantity', label: 'Quantità ordinata', type: 'number'},
    {path: 'order.code', label: 'Codice ordine', type: 'text'},
    {path: 'order.store', label: 'Negozio', type: 'text'},
    {path: 'item.position', label: 'Posizione riga', type: 'number'},
    {path: 'product.name', label: 'Nome prodotto', type: 'text'},
    {path: 'product.route_text', label: 'SKU + nome prodotto', type: 'text'},
    {path: 'file.filename', label: 'Nome file', type: 'text'},
    {path: 'file.index', label: 'Indice file', type: 'number'},
    {path: 'file.count', label: 'Numero file della riga', type: 'number'},
    {path: 'aggregation.id', label: 'ID lavoro aggregato', type: 'number'},
    {path: 'aggregation.token', label: 'Identificativo univoco del tentativo', type: 'text'},
    {path: 'aggregation.expected_count', label: 'Numero righe attese', type: 'number'},
    {path: 'aggregation.position', label: 'Posizione nel gruppo', type: 'number'},
    {path: 'operation.type', label: 'Codice evento', type: 'text'},
    {path: 'operation.source', label: 'Sorgente evento', type: 'text'},
    {path: 'operation.handoff_from_flow_name', label: 'Automazione precedente', type: 'text'},
    {path: 'machine.name', label: 'Macchina selezionata', type: 'text'},
    {path: 'machine.destination_code', label: 'Hot folder della macchina', type: 'text'},
    {path: 'variables.print_mode', label: 'Tipo stampa (mono/bifa)', type: 'text'},
    {path: 'variables.side_count', label: 'Numero lati', type: 'number'},
    {path: 'payload.campi_webhook.percentuale', label: 'Correzione percentuale', type: 'number'}
  ].freeze

  NODE_CATALOG = [
    {type: 'trigger', label: 'Ingresso', icon: 'fa-play', outputs: ['default']},
    {type: 'router', label: 'Condizione multipla', icon: 'fa-code-branch', outputs: ['configurabili']},
    {type: 'fork', label: 'Dirama lavoro', icon: 'fa-code-fork', outputs: ['default']},
    {type: 'set_variables', label: 'Imposta variabili', icon: 'fa-tags', outputs: ['default']},
    {type: 'calculate_copies', label: 'Calcola quantità', icon: 'fa-calculator', outputs: ['default']},
    {type: 'duplicate_pages', label: 'Moltiplica pagine', icon: 'fa-copy', outputs: ['default']},
    {type: 'pdf_label', label: 'Aggiungi testo al PDF', icon: 'fa-font', outputs: ['default']},
    {type: 'resize_pdf', label: 'Ridimensiona PDF', icon: 'fa-expand', outputs: ['default']},
    {type: 'collect_group', label: 'Raccogli gruppo', icon: 'fa-layer-group', outputs: ['default']},
    {type: 'insert_blanks', label: 'Inserisci pagine vuote', icon: 'fa-file-circle-plus', outputs: ['default']},
    {
      type: 'pair_sides',
      label: 'Abbina fronte e retro',
      icon: 'fa-clone',
      outputs: ['mono', 'bifa', 'incomplete']
    },
    {type: 'photoshop', label: 'Photoshop', icon: 'fa-image', outputs: ['default']},
    {type: 'illustrator', label: 'Illustrator', icon: 'fa-pen-nib', outputs: ['default']},
    {type: 'step_repeat', label: 'Step and repeat', icon: 'fa-grip', outputs: ['default']},
    {type: 'barcode', label: 'Barcode', icon: 'fa-barcode', outputs: ['default']},
    {type: 'hot_folder', label: 'Hot folder', icon: 'fa-folder-open', outputs: ['default']},
    {type: 'label_printer', label: 'Stampa etichetta', icon: 'fa-print', outputs: ['default']},
    {type: 'approval', label: 'Approvazione', icon: 'fa-user-check', outputs: ['default']},
    {type: 'handoff', label: 'Passa a un’altra automazione', icon: 'fa-arrow-right-to-bracket', outputs: []},
    {type: 'finish', label: 'Completato', icon: 'fa-flag-checkered', outputs: []}
  ].freeze

  helpers do
    def automation_json_body
      request.body.rewind
      JSON.parse(request.body.read)
    rescue JSON::ParserError
      halt 400, {success: false, error: 'JSON non valido'}.to_json
    end

    def automation_bearer_token
      request.env['HTTP_AUTHORIZATION'].to_s.sub(/\ABearer\s+/i, '')
    end

    def automation_legacy_agent_authorized?
      expected = ENV['AUTOMATION_AGENT_TOKEN'].to_s
      return true if expected.empty? && settings.development?

      supplied = automation_bearer_token
      return false if supplied.empty? || supplied.bytesize != expected.bytesize

      supplied.bytesize == expected.bytesize &&
        Rack::Utils.secure_compare(supplied, expected)
    end

    def automation_agent_authorized?(agent = nil)
      return false if agent&.revoked_at.present?
      return agent.authenticate_token?(automation_bearer_token) if agent&.token_digest.present?

      automation_legacy_agent_authorized?
    end

    def require_automation_agent!(agent = nil)
      content_type :json
      halt 401, {success: false, error: 'Agente non autorizzato'}.to_json unless
        automation_agent_authorized?(agent)
    end

    def resolve_automation_config(value, context)
      case value
      when Hash
        value.transform_values { |nested| resolve_automation_config(nested, context) }
      when Array
        value.map { |nested| resolve_automation_config(nested, context) }
      else
        AutomationEngine.resolve(value, context)
      end
    end

    def imposition_preset_config
      anchor = params[:anchor].to_s
      allowed_anchors = %w[top_left top_right bottom_left bottom_right]
      raise ArgumentError, 'Punto di ancoraggio non valido' unless allowed_anchors.include?(anchor)
      double_sided_mode = params[:double_sided_mode].presence || 'none'
      unless %w[none horizontal vertical].include?(double_sided_mode)
        raise ArgumentError, 'Modalità fronte/retro non valida'
      end

      config = {
        'folder' => params[:folder].to_s.strip.presence || 'Principale',
        'sheet_width_mm' => Float(params[:sheet_width_mm].to_s.tr(',', '.')),
        'sheet_height_mm' => Float(params[:sheet_height_mm].to_s.tr(',', '.')),
        'anchor' => anchor,
        'offset_x_mm' => Float(params[:offset_x_mm].to_s.tr(',', '.')),
        'offset_y_mm' => Float(params[:offset_y_mm].to_s.tr(',', '.')),
        'gap_x_mm' => Float(params[:gap_x_mm].to_s.tr(',', '.')),
        'gap_y_mm' => Float(params[:gap_y_mm].to_s.tr(',', '.')),
        'columns' => Integer(params[:columns].presence || 0),
        'rows' => Integer(params[:rows].presence || 0),
        'rotate' => params[:rotate] == '1',
        'fill_last_sheet' => params[:fill_last_sheet] == '1',
        'double_sided_mode' => double_sided_mode
      }
      raise ArgumentError, 'Le dimensioni del foglio devono essere maggiori di zero' unless
        config['sheet_width_mm'].positive? && config['sheet_height_mm'].positive?
      raise ArgumentError, 'Partenza e spazi non possono essere negativi' if
        %w[offset_x_mm offset_y_mm gap_x_mm gap_y_mm].any? { |key| config[key].negative? }
      raise ArgumentError, 'Righe e colonne non possono essere negative' if
        config['rows'].negative? || config['columns'].negative?

      config
    end

    def automation_destination_config(kind)
      case kind
      when 'network_folder'
        server_host = params[:server_host].to_s.strip.gsub(%r{\A/+|/+\z}, '')
        share_name = params[:share_name].to_s.strip.gsub(%r{\A/+|/+\z}, '')
        remote_path = params[:remote_path].to_s.strip.gsub(%r{\A/+|/+\z}, '')
        network_uri = params[:network_uri].to_s.strip
        if server_host.present? && share_name.present?
          network_uri = "//#{server_host}/#{share_name}"
          network_uri = "#{network_uri}/#{remote_path}" if remote_path.present?
        end
        application_path = params[:container_path].to_s.strip
        {
          'server_host' => server_host,
          'share_name' => share_name,
          'remote_path' => remote_path,
          'network_uri' => network_uri,
          'host_mount_path' => params[:host_mount_path].presence || application_path,
          'container_path' => application_path,
          'agent_key' => params[:agent_key].to_s.strip,
          'agent_path' => params[:agent_path].to_s.strip
        }
      when 'ipp_printer'
        copies = Integer(params[:copies].presence || 1)
        raise ArgumentError, 'Il numero di copie deve essere compreso tra 1 e 999' unless copies.between?(1, 999)

        {
          'cups_server' => params[:cups_server].to_s.strip,
          'queue' => params[:queue].to_s.strip,
          'media' => params[:media].to_s.strip,
          'fit_to_page' => params[:fit_to_page] == '1',
          'cut_mode' => params[:cut_mode].to_s.strip,
          'copies' => copies
        }
      else
        raise ArgumentError, 'Tipo di destinazione non valido'
      end
    end

    def automation_chain_rows(folder)
      folder.automation_folder_flows.map do |membership|
        {flow: membership.automation_flow, membership: membership}
      end
    end

    def automation_agent_task_config(node, run)
      resolved = resolve_automation_config(node['config'] || {}, run.context)
      return resolved unless node['type'] == 'hot_folder'

      destination = AutomationDestination.active.find_by(
        code: resolved['destination_code'].to_s
      )
      return resolved unless destination

      destination_config = destination.config.is_a?(Hash) ? destination.config : {}
      resolved.merge(
        'agent_key' => destination_config['agent_key'].to_s,
        'agent_path' => destination_config['agent_path'].to_s,
        'destination_code' => destination.code
      )
    end
  end

  get '/automations' do
    @automation_flows = AutomationFlow.includes(
      :active_version,
      :preprint_print_flows,
      :print_print_flows,
      :label_print_flows,
      versions: :automation_runs
    ).ordered
    @automation_runs = AutomationRun.where(parent_run_id: nil)
                                    .includes(automation_flow_version: :automation_flow)
                                    .recent
                                    .limit(30)
    @automation_folders = AutomationFolder.includes(
      :root_flow,
      automation_folder_flows: {automation_flow: :active_version}
    ).ordered
    @organized_flow_ids = @automation_folders.flat_map(&:chain_flows).map(&:id).uniq
    @unorganized_flows = @automation_flows.reject { |flow| @organized_flow_ids.include?(flow.id) }
    @automation_presets = AutomationPreset.ordered
    @automation_destinations = AutomationDestination.ordered
    @automation_agents = AutomationAgent.ordered
    @automation_items = OrderItem.includes(:order).order(created_at: :desc).limit(100)
    erb :automation_flows_list
  end

  get '/automation_presets' do
    @automation_presets = AutomationPreset.ordered
    @automation_preset_folders = AutomationPresetFolder.where(kind: 'imposition').ordered
    @automation_destinations = AutomationDestination.ordered
    @automation_agents = AutomationAgent.active.ordered
    erb :automation_presets
  end

  get '/automation_runs' do
    @automation_flows = AutomationFlow.ordered
    @selected_status = params[:status].to_s
    @selected_flow_id = params[:flow_id].to_s
    @order_query = params[:order].to_s.strip
    @page = [params[:page].to_i, 1].max
    @per_page = 50

    scope = AutomationRun.where(parent_run_id: nil)
                         .includes(:order_item, automation_flow_version: :automation_flow)
                         .recent
    scope = scope.where(status: @selected_status) if AutomationRun::STATUSES.include?(@selected_status)
    if @selected_flow_id.match?(/\A\d+\z/)
      scope = scope.joins(:automation_flow_version)
                   .where(automation_flow_versions: {automation_flow_id: @selected_flow_id.to_i})
    end
    if @order_query.present?
      escaped_query = ActiveRecord::Base.sanitize_sql_like(@order_query)
      scope = scope.where("automation_runs.context -> 'order' ->> 'code' ILIKE ?", "%#{escaped_query}%")
    end

    @automation_runs_count = scope.count
    @automation_runs = scope.offset((@page - 1) * @per_page).limit(@per_page)
    erb :automation_runs_list
  end

  get '/automation_agents' do
    @automation_agents = AutomationAgent.ordered
    @pending_pairings = AutomationAgentPairing.pending.recent
    @pairing_code = params[:pairing_code].to_s.presence
    @pairing_expires_at = Time.iso8601(params[:expires_at].to_s) rescue nil
    erb :automation_agents
  end

  get '/automation_agents/installer' do
    installer_path = File.join(
      Dir.pwd,
      'tools',
      'adobe_agent',
      'dist',
      'Magenta-Adobe-Agent.zip'
    )
    halt 404, 'Installer non ancora generato' unless File.file?(installer_path)

    send_file installer_path,
              filename: 'Magenta-Adobe-Agent.zip',
              disposition: 'attachment',
              type: 'application/zip'
  end

  post '/automation_agents/pairings' do
    pairing, code = AutomationAgentPairing.issue!(requested_name: params[:name])
    query = URI.encode_www_form(
      pairing_code: code,
      expires_at: pairing.expires_at.iso8601,
      msg: 'success',
      text: 'Codice di associazione creato'
    )
    redirect "/automation_agents?#{query}"
  rescue StandardError => e
    redirect "/automation_agents?msg=error&text=#{URI.encode_www_form_component(e.message)}"
  end

  post '/automation_agents/:id/revoke' do
    agent = AutomationAgent.find(params[:id])
    agent.update!(
      revoked_at: Time.current,
      token_digest: nil,
      last_error: 'Associazione revocata dal gestionale'
    )
    redirect '/automation_agents?msg=success&text=Mac+disconnesso'
  rescue StandardError => e
    redirect "/automation_agents?msg=error&text=#{URI.encode_www_form_component(e.message)}"
  end

  post '/automation_agents/:id/sync' do
    agent = AutomationAgent.active.find(params[:id])
    agent_version = agent.metadata.is_a?(Hash) ? agent.metadata['agent_version'].to_i : 0
    raise ArgumentError, 'Aggiorna prima Magenta Adobe Agent su questo Mac' if agent_version < 3

    agent.update!(resource_sync_requested_at: Time.current, last_error: nil)
    redirect '/automation_presets?msg=success&text=Sincronizzazione+Adobe+richiesta'
  rescue StandardError => e
    redirect "/automation_presets?msg=error&text=#{URI.encode_www_form_component(e.message)}"
  end

  post '/automation_folders' do
    folder = AutomationFolder.create!(
      name: params[:name],
      description: params[:description],
      root_flow: nil
    )
    Array(params[:automation_flow_ids]).reject(&:blank?).each do |flow_id|
      folder.include_flow!(AutomationFlow.find(flow_id))
    end
    redirect '/automations?msg=success&text=Cartella+creata'
  rescue StandardError => e
    redirect "/automations?msg=error&text=#{URI.encode_www_form_component(e.message)}"
  end

  post '/automation_folders/:id/flows' do
    folder = AutomationFolder.find(params[:id])
    flow = AutomationFlow.find(params[:automation_flow_id])
    folder.include_flow!(flow)
    redirect '/automations?msg=success&text=Flusso+spostato+nella+cartella'
  rescue StandardError => e
    redirect "/automations?msg=error&text=#{URI.encode_www_form_component(e.message)}"
  end

  post '/automation_folders/:id/flows/:flow_id/delete' do
    folder = AutomationFolder.find(params[:id])
    flow = AutomationFlow.find(params[:flow_id])

    folder.automation_folder_flows.find_by!(automation_flow: flow).destroy!
    redirect '/automations?msg=success&text=Flusso+rimosso+dalla+cartella'
  rescue StandardError => e
    redirect "/automations?msg=error&text=#{URI.encode_www_form_component(e.message)}"
  end

  post '/automation_folders/:id/delete' do
    AutomationFolder.find(params[:id]).destroy!
    redirect '/automations?msg=success&text=Cartella+eliminata,+i+flussi+sono+rimasti+intatti'
  rescue StandardError => e
    redirect "/automations?msg=error&text=#{URI.encode_www_form_component(e.message)}"
  end

  post '/automations' do
    flow = AutomationFlow.create!(
      name: params[:name].presence || "Nuovo flusso #{Time.current.strftime('%d/%m %H:%M')}",
      description: params[:description]
    )
    flow.draft_version
    redirect "/automations/#{flow.id}/edit"
  rescue ActiveRecord::RecordInvalid => e
    redirect "/automations?msg=error&text=#{URI.encode_www_form_component(e.message)}"
  end

  post '/automations/seed_plectrum' do
    flow = AutomationBootstrap.seed_plectrum_flow!
    redirect "/automations/#{flow.id}/edit?msg=success&text=Flusso+plettri+preparato"
  rescue StandardError => e
    redirect "/automations?msg=error&text=#{URI.encode_www_form_component(e.message)}"
  end

  post '/automations/seed_scatoline_aggregation' do
    flow = AutomationBootstrap.seed_scatoline_aggregation_flow!
    text = 'Flusso di esempio creato; puoi selezionarlo quando crei un gruppo di aggregazione'
    redirect "/automations/#{flow.id}/edit?msg=success&text=#{URI.encode_www_form_component(text)}"
  rescue StandardError => e
    redirect "/automations?msg=error&text=#{URI.encode_www_form_component(e.message)}"
  end

  post '/automations/:id/duplicate' do
    source = AutomationFlow.includes(:automation_folders).find(params[:id])
    base_name = "#{source.name} copia"
    duplicate_name = base_name
    suffix = 2
    while AutomationFlow.exists?(name: duplicate_name)
      duplicate_name = "#{base_name} #{suffix}"
      suffix += 1
    end

    duplicate = nil
    AutomationFlow.transaction do
      duplicate = AutomationFlow.create!(
        name: duplicate_name,
        description: source.description
      )
      graph = JSON.parse(JSON.generate(source.draft_version.graph))
      duplicate.draft_version.update!(graph: graph)
      source.automation_folders.each { |folder| folder.include_flow!(duplicate) }
    end

    redirect "/automations/#{duplicate.id}/edit?msg=success&text=Automazione+duplicata"
  rescue StandardError => e
    redirect "/automations?msg=error&text=#{URI.encode_www_form_component(e.message)}"
  end

  post '/automations/:id/delete' do
    flow = AutomationFlow.includes(
      :preprint_print_flows,
      :print_print_flows,
      :label_print_flows,
      versions: {automation_runs: :automation_artifacts}
    ).find(params[:id])

    linked_names = flow.linked_print_flows.map(&:name)
    if linked_names.any?
      raise ArgumentError,
            "Il flusso è ancora collegato a: #{linked_names.join(', ')}. " \
            'Scollegalo dalle azioni di stampa prima di eliminarlo.'
    end
    incoming_names = flow.incoming_handoff_flows.map(&:name)
    if incoming_names.any?
      raise ArgumentError,
            "Il flusso è usato come modulo da: #{incoming_names.join(', ')}. " \
            'Rimuovi prima il blocco Passa a un’altra automazione.'
    end

    removable_paths = flow.versions.flat_map(&:automation_runs)
                           .flat_map(&:automation_artifacts)
                           .reject { |artifact| Asset.where(local_path: artifact.local_path).exists? }
                           .map(&:full_path)
                           .uniq
                           .select do |path|
      automation_root = File.expand_path(File.join(Dir.pwd, 'storage', 'automation', 'runs'))
      expanded = File.expand_path(path)
      expanded.start_with?("#{automation_root}#{File::SEPARATOR}") &&
        !Asset.where(local_path: path).exists?
    end

    flow.transaction do
      flow.update!(active_version: nil)
      flow.versions.each do |version|
        version.automation_runs.each(&:destroy!)
        version.destroy!
      end
      flow.destroy!
    end
    removable_paths.each { |path| FileUtils.rm_f(path) }

    redirect '/automations?msg=success&text=Flusso+eliminato'
  rescue StandardError => e
    redirect "/automations?msg=error&text=#{URI.encode_www_form_component(e.message)}"
  end

  post '/api/automation/events/:event_key/dispatch' do
    content_type :json
    payload = automation_json_body
    print_flow = PrintFlow.find(payload['print_flow_id'])
    order_item = OrderItem.find(payload['order_item_id'])
    requested_asset_ids = Array(payload['asset_ids']).map(&:to_i).reject(&:zero?)
    assets = if requested_asset_ids.any?
               order_item.assets.where(id: requested_asset_ids).to_a
             else
               (
                 order_item.assets.to_a +
                 order_item.switch_print_assets.to_a
               ).uniq.select(&:downloaded?)
             end

    result = AutomationActionDispatcher.dispatch_event!(
      print_flow: print_flow,
      event_key: params[:event_key],
      order_item: order_item,
      assets: assets,
      print_machine: PrintMachine.find_by(id: payload['print_machine_id']),
      simulation: payload.key?('simulation') ? payload['simulation'] == true : AutomationActionDispatcher.simulation_default?,
      trigger_source: 'api'
    )
    status 202
    {
      success: true,
      event_key: params[:event_key],
      batch_id: result[:batch_id],
      run_ids: result[:runs].map(&:id)
    }.to_json
  rescue ActiveRecord::RecordNotFound => e
    status 404
    {success: false, error: e.message}.to_json
  rescue ArgumentError, ActiveRecord::RecordInvalid => e
    status 422
    {success: false, error: e.message}.to_json
  end

  get '/automations/:id/edit' do
    @automation_flow = AutomationFlow.find(params[:id])
    @automation_version = @automation_flow.draft_version
    @node_catalog = NODE_CATALOG
    @automation_presets = AutomationPreset.active.ordered
    @automation_destinations = AutomationDestination.active.ordered
    @automation_agents = AutomationAgent.active.ordered
    @automation_target_flows = AutomationFlow.where.not(id: @automation_flow.id)
                                               .where.not(active_version_id: nil)
                                               .ordered
    @automation_items = OrderItem.includes(:order).order(created_at: :desc).limit(100)
    erb :automation_flow_editor
  end

  get '/api/automations/:id/editor' do
    content_type :json
    flow = AutomationFlow.find(params[:id])
    version = flow.draft_version
    {
      success: true,
      flow: {
        id: flow.id,
        name: flow.name,
        description: flow.description,
        status: flow.status,
        active_version: flow.active_version&.version_number
      },
      version: {
        id: version.id,
        number: version.version_number,
        graph: version.graph
      },
      node_catalog: NODE_CATALOG,
      field_catalog: AUTOMATION_FIELD_CATALOG,
      presets: AutomationPreset.active.ordered.map { |preset|
        {id: preset.id, kind: preset.kind, code: preset.code, name: preset.name}
      },
      destinations: AutomationDestination.active.ordered.map { |destination|
        {
          id: destination.id,
          kind: destination.kind,
          code: destination.code,
          name: destination.name,
          available: destination.available?
        }
      },
      agents: AutomationAgent.active.ordered.map { |agent|
        {
          key: agent.agent_key,
          name: agent.name,
          online: agent.online?,
          capabilities: agent.capabilities,
          metadata: agent.metadata
        }
      },
      flows: AutomationFlow.where.not(id: flow.id)
                           .where.not(active_version_id: nil)
                           .ordered
                           .map { |target| {id: target.id, name: target.name, version: target.active_version.version_number} }
    }.to_json
  end

  put '/api/automations/:id/editor' do
    content_type :json
    flow = AutomationFlow.find(params[:id])
    payload = automation_json_body
    graph = payload['graph']
    errors = AutomationGraphValidator.new(graph).errors +
             AutomationFlowChainValidator.new(flow, graph).errors

    flow.update!(
      name: payload.dig('flow', 'name').presence || flow.name,
      description: payload.dig('flow', 'description')
    )
    version = flow.draft_version
    version.update!(
      graph: graph,
      checksum: Digest::SHA256.hexdigest(JSON.generate(graph))
    )
    {
      success: true,
      valid: errors.empty?,
      errors: errors,
      version: version.version_number,
      saved_at: Time.current.iso8601
    }.to_json
  rescue ActiveRecord::RecordInvalid => e
    status 422
    {success: false, errors: e.record.errors.full_messages}.to_json
  end

  post '/api/automations/:id/validate' do
    content_type :json
    flow = AutomationFlow.find(params[:id])
    graph = if request.media_type == 'application/json'
              automation_json_body['graph']
            else
              flow.draft_version.graph
            end
    errors = AutomationGraphValidator.new(graph).errors +
             AutomationFlowChainValidator.new(flow, graph).errors
    {
      success: errors.empty?,
      errors: errors,
      nodes_count: Array(graph['nodes']).size,
      edges_count: Array(graph['edges']).size
    }.to_json
  end

  post '/automations/:id/publish' do
    flow = AutomationFlow.find(params[:id])
    published = flow.publish_draft!
    redirect "/automations/#{flow.id}/edit?msg=success&text=Versione+#{published.version_number}+pubblicata"
  rescue StandardError => e
    redirect "/automations/#{params[:id]}/edit?msg=error&text=#{URI.encode_www_form_component(e.message)}"
  end

  post '/automations/:id/runs' do
    flow = AutomationFlow.find(params[:id])
    item = OrderItem.find(params[:order_item_id])
    run = AutomationEngine.start_run(
      flow: flow,
      order_item: item,
      simulation: params[:simulation] == '1'
    )
    redirect "/automation_runs/#{run.id}"
  rescue StandardError => e
    redirect "/automations/#{params[:id]}/edit?msg=error&text=#{URI.encode_www_form_component(e.message)}"
  end

  get '/automation_runs/:id' do
    @automation_run = AutomationRun.includes(
      :automation_artifacts,
      automation_step_runs: :automation_artifacts
    ).find(params[:id])
    erb :automation_run_detail
  end

  post '/automation_runs/:id/retry' do
    run = AutomationRun.find(params[:id])
    AutomationEngine.retry_run!(run)
    redirect "/automation_runs/#{run.id}?msg=success&text=Passaggio+rimesso+in+coda"
  rescue StandardError => e
    redirect "/automation_runs/#{params[:id]}?msg=error&text=#{URI.encode_www_form_component(e.message)}"
  end

  post '/automation_steps/:id/approve' do
    step = AutomationStepRun.find(params[:id])
    AutomationEngine.approve_step!(step)
    redirect "/automation_runs/#{step.automation_run_id}?msg=success&text=Passaggio+approvato"
  rescue StandardError => e
    redirect request.referer || "/automations?msg=error&text=#{URI.encode_www_form_component(e.message)}"
  end

  get '/automation_artifacts/:id/download' do
    artifact = AutomationArtifact.find(params[:id])
    halt 404, 'File non disponibile' unless artifact.available?

    send_file artifact.full_path,
              filename: artifact.filename,
              disposition: params[:inline] == '1' ? 'inline' : 'attachment',
              type: artifact.media_type
  end

  post '/automations/presets' do
    config = if params[:kind] == 'imposition' && params[:sheet_width_mm].present?
               imposition_preset_config
             else
               JSON.parse(params[:config].presence || '{}')
             end
    preset = if params[:id].present?
               AutomationPreset.find(params[:id])
             else
               AutomationPreset.new
             end
    preset.update!(
      kind: params[:kind],
      code: params[:code],
      name: params[:name],
      config: config,
      active: params[:active] == '1'
    )
    redirect '/automation_presets?msg=success&text=Preset+salvato'
  rescue StandardError => e
    redirect "/automation_presets?msg=error&text=#{URI.encode_www_form_component(e.message)}"
  end

  post '/automation_preset_folders' do
    AutomationPresetFolder.create!(kind: 'imposition', name: params[:name].to_s.strip)
    redirect '/automation_presets?tab=imposition&msg=success&text=Cartella+creata'
  rescue StandardError => e
    redirect "/automation_presets?tab=imposition&msg=error&text=#{URI.encode_www_form_component(e.message)}"
  end

  post '/automation_destinations' do
    destination = if params[:id].present?
                    AutomationDestination.find(params[:id])
                  else
                    AutomationDestination.new
                  end
    destination.update!(
      code: params[:code].to_s.strip,
      name: params[:name].to_s.strip,
      kind: params[:destination_kind].to_s,
      config: automation_destination_config(params[:destination_kind].to_s),
      active: params[:active] == '1'
    )
    redirect '/automation_presets?tab=output&msg=success&text=Destinazione+salvata'
  rescue StandardError => e
    redirect "/automation_presets?tab=output&msg=error&text=#{URI.encode_www_form_component(e.message)}"
  end

  post '/automation_destinations/:id/check' do
    destination = AutomationDestination.find(params[:id])
    result = AutomationDestinationService.check(destination)
    destination.update!(
      last_checked_at: Time.current,
      last_check_status: result.success? ? 'ok' : 'error',
      last_check_message: result.message
    )
    level = result.success? ? 'success' : 'error'
    redirect "/automation_presets?tab=output&msg=#{level}&text=#{URI.encode_www_form_component(result.message)}"
  rescue StandardError => e
    redirect "/automation_presets?tab=output&msg=error&text=#{URI.encode_www_form_component(e.message)}"
  end

  post '/automation_destinations/:id/delete' do
    destination = AutomationDestination.find(params[:id])
    flows = destination.referenced_by_flows
    raise ArgumentError, "Destinazione usata da: #{flows.map(&:name).join(', ')}" if flows.any?
    if destination.print_machines.any?
      raise ArgumentError,
            "Destinazione associata alle macchine: #{destination.print_machines.pluck(:name).join(', ')}"
    end

    destination.destroy!
    redirect '/automation_presets?tab=output&msg=success&text=Destinazione+eliminata'
  rescue StandardError => e
    redirect "/automation_presets?tab=output&msg=error&text=#{URI.encode_www_form_component(e.message)}"
  end

  get '/api/automation/destinations/printers' do
    content_type :json
    printers = AutomationDestinationService.discover_printers(params[:cups_server])
    {success: true, printers: printers}.to_json
  rescue StandardError => e
    status 422
    {success: false, error: e.message}.to_json
  end

  post '/api/automation/agent/claim' do
    payload = automation_json_body
    worker_id = payload['worker_id'].to_s
    capabilities = Array(payload['capabilities']).map(&:to_s)
    halt 422, {success: false, error: 'worker_id mancante'}.to_json if worker_id.empty?

    existing_agent = AutomationAgent.find_by(agent_key: worker_id)
    require_automation_agent!(existing_agent)

    agent_data = payload['agent'].is_a?(Hash) ? payload['agent'] : {}
    agent = AutomationAgent.find_or_initialize_by(agent_key: worker_id)
    agent.assign_attributes(
      name: agent_data['name'].presence || worker_id,
      hostname: agent_data['hostname'],
      platform: agent_data['platform'],
      capabilities: capabilities,
      metadata: agent_data['metadata'].is_a?(Hash) ? agent_data['metadata'] : {},
      last_seen_at: Time.current,
      last_error: agent_data['last_error']
    )
    agent.save!

    sync_pending = agent.resource_sync_requested_at.present? &&
                   (
                     agent.resource_synced_at.blank? ||
                     agent.resource_synced_at < agent.resource_sync_requested_at
                   )
    if sync_pending && agent.metadata['agent_version'].to_i >= 3
      return {
        success: true,
        task: nil,
        command: {
          type: 'sync_resources',
          requested_at: agent.resource_sync_requested_at.iso8601
        }
      }.to_json
    end

    step = AutomationStepRun.transaction do
      candidates = AutomationStepRun.where(status: 'waiting_external', node_type: capabilities)
                                    .where('worker_id IS NULL OR locked_at < ?', 10.minutes.ago)
                                    .order(:created_at)
                                    .limit(50)
                                    .lock('FOR UPDATE SKIP LOCKED')
      candidate = candidates.find do |queued_step|
        queued_run = queued_step.automation_run
        queued_node = AutomationEngine.node_for(queued_step)
        resolved = automation_agent_task_config(queued_node, queued_run)
        target_agent = resolved['agent_key'].to_s
        target_agent.empty? || target_agent == worker_id
      end
      if candidate
        candidate.update!(worker_id: worker_id, locked_at: Time.current)
      end
      candidate
    end

    return {success: true, task: nil}.to_json unless step

    run = step.automation_run
    node = AutomationEngine.node_for(step)
    task_config = automation_agent_task_config(node, run)
    artifact = if node['type'] == 'hot_folder' && task_config['artifact_kind'].present?
                 run.artifact_by_kind(task_config['artifact_kind'])
               else
                 run.current_artifact
               end
    unless artifact&.available?
      AutomationEngine.fail_external_step!(step, 'File di input non disponibile')
      halt 422, {success: false, error: 'File di input non disponibile'}.to_json
    end

    {
      success: true,
      task: {
        step_id: step.id,
        run_id: run.id,
        node_key: step.node_key,
        node_type: step.node_type,
        config: task_config,
        context: run.context,
        input_filename: artifact.filename,
        input_url: "/automation_artifacts/#{artifact.id}/download"
      }
    }.to_json
  end

  post '/api/automation/agent/pair' do
    content_type :json
    payload = automation_json_body
    pairing = AutomationAgentPairing.find_available(payload['code'])
    halt 422, {
      success: false,
      error: 'Codice non valido, scaduto o già utilizzato'
    }.to_json unless pairing

    agent_data = payload['agent'].is_a?(Hash) ? payload['agent'] : {}
    requested_key = payload['worker_id'].to_s
    agent = if requested_key.present?
              AutomationAgent.find_or_initialize_by(agent_key: requested_key)
            else
              AutomationAgent.new(agent_key: "adobe-#{SecureRandom.uuid}")
            end

    token = nil
    AutomationAgent.transaction do
      agent.assign_attributes(
        name: agent_data['name'].presence || pairing.requested_name.presence ||
              agent_data['hostname'].presence || 'Mac Adobe',
        hostname: agent_data['hostname'],
        platform: agent_data['platform'],
        capabilities: Array(payload['capabilities']).map(&:to_s),
        metadata: agent_data['metadata'].is_a?(Hash) ? agent_data['metadata'] : {},
        last_seen_at: Time.current,
        last_error: nil
      )
      agent.save!
      token = agent.issue_token!
      pairing.consume!(agent)
    end

    {
      success: true,
      agent: {
        key: agent.agent_key,
        name: agent.name,
        token: token,
        paired_at: agent.paired_at.iso8601
      }
    }.to_json
  rescue ActiveRecord::RecordInvalid, ArgumentError => e
    status 422
    {success: false, error: e.message}.to_json
  end

  post '/api/automation/agent/sync_complete' do
    payload = automation_json_body
    worker_id = payload['worker_id'].to_s
    agent = AutomationAgent.find_by(agent_key: worker_id)
    require_automation_agent!(agent)
    halt 404, {success: false, error: 'Mac Adobe non trovato'}.to_json unless agent

    agent_data = payload['agent'].is_a?(Hash) ? payload['agent'] : {}
    sync_error = payload['error'].to_s.presence
    agent.update!(
      capabilities: Array(payload['capabilities']).map(&:to_s).presence || agent.capabilities,
      metadata: agent_data['metadata'].is_a?(Hash) ? agent_data['metadata'] : agent.metadata,
      last_seen_at: Time.current,
      last_error: sync_error,
      resource_synced_at: Time.current
    )
    {success: sync_error.nil?, synced_at: agent.resource_synced_at.iso8601}.to_json
  end

  post '/api/automation/agent/steps/:id/complete' do
    step = AutomationStepRun.find(params[:id])
    require_automation_agent!(AutomationAgent.find_by(agent_key: step.worker_id))
    upload = params[:file]
    tempfile = upload && (upload[:tempfile] || upload['tempfile'])
    uploaded_name = upload && (upload[:filename] || upload['filename'])
    uploaded_type = upload && (upload[:type] || upload['type'])
    halt 422, {success: false, error: 'File risultato mancante'}.to_json unless tempfile

    filename = File.basename(uploaded_name.presence || "step-#{step.id}.pdf")
    directory = File.join(Dir.pwd, 'storage', 'automation', 'runs', step.automation_run_id.to_s, 'external')
    FileUtils.mkdir_p(directory)
    path = File.join(directory, "#{SecureRandom.hex(5)}-#{filename}")
    FileUtils.cp(tempfile.path, path)
    metadata = JSON.parse(params[:metadata].presence || '{}')

    AutomationEngine.complete_external_step!(
      step,
      uploaded_path: path,
      filename: filename,
      media_type: uploaded_type,
      metadata: metadata.merge('worker_id' => params[:worker_id])
    )
    {success: true, step_id: step.id}.to_json
  rescue JSON::ParserError
    halt 422, {success: false, error: 'Metadata JSON non valido'}.to_json
  end

  post '/api/automation/agent/steps/:id/fail' do
    step = AutomationStepRun.find(params[:id])
    require_automation_agent!(AutomationAgent.find_by(agent_key: step.worker_id))
    payload = automation_json_body
    AutomationAgent.find_by(agent_key: step.worker_id)&.update!(
      last_seen_at: Time.current,
      last_error: payload['error']
    )
    AutomationEngine.fail_external_step!(step, payload['error'].presence || 'Errore agente Adobe')
    {success: true, step_id: step.id}.to_json
  end
end
