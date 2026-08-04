# @feature automation
# @domain services

require 'securerandom'

class AutomationActionDispatcher
  OPERATIONS = {
    'preprint' => 1,
    'print' => 2,
    'label' => 3
  }.freeze

  class << self
    def simulation_default?
      configured = ENV['AUTOMATION_ACTION_SIMULATION']
      return configured == 'true' unless configured.nil?

      ENV.fetch('RACK_ENV', 'development') != 'production'
    end

    def dispatch!(print_flow:, action:, order_item:, assets:, print_machine: nil, simulation: simulation_default?)
      dispatch_event!(
        print_flow: print_flow,
        event_key: action,
        order_item: order_item,
        assets: assets,
        print_machine: print_machine,
        simulation: simulation
      )
    end

    def dispatch_event!(print_flow:, event_key:, order_item:, assets:, print_machine: nil,
                        simulation: simulation_default?, trigger_source: 'print_flow')
      event_key = event_key.to_s.strip
      raise ArgumentError, 'Evento mancante' if event_key.empty?
      unless event_key.match?(PrintFlowEventRoute::EVENT_KEY_FORMAT)
        raise ArgumentError, "Codice evento non valido: #{event_key}"
      end
      unless print_flow.executor_for(event_key) == 'automation'
        raise ArgumentError, "L'evento #{event_key} non usa un flusso interno"
      end

      automation_flow = print_flow.automation_flow_for(event_key)
      raise ArgumentError, "Flusso interno #{event_key} non configurato" unless automation_flow
      raise ArgumentError, "Pubblica il flusso interno #{automation_flow.name} prima di usarlo" unless automation_flow.active_version

      source_assets = Array(assets).compact
      if source_assets.empty? && event_key != 'label'
        raise ArgumentError, 'Nessun file disponibile per avviare il flusso'
      end

      if %w[print label].include?(event_key)
        raise ArgumentError, 'Seleziona una macchina di stampa' unless print_machine
        unless print_machine.active? && print_flow.print_machines.active.exists?(id: print_machine.id)
          raise ArgumentError, "La macchina #{print_machine.name} non è disponibile per questo flusso"
        end
      end
      if event_key == 'label'
        label_destination = print_machine.label_automation_destination
        unless label_destination&.active? && label_destination.ipp_printer?
          raise ArgumentError,
                "La macchina #{print_machine.name} non ha una stampante etichette configurata"
        end
      end

      unavailable = source_assets.reject(&:downloaded?)
      raise ArgumentError, "File locale non disponibile: #{unavailable.first&.filename_from_url}" if unavailable.any?

      batch_id = SecureRandom.uuid
      run_sources = source_assets.empty? ? [nil] : source_assets
      runs = run_sources.each_with_index.map do |asset, index|
        AutomationEngine.start_run(
          flow: automation_flow,
          order_item: order_item,
          source_asset: asset,
          operation_type: event_key,
          print_flow: print_flow,
          action_batch_id: batch_id,
          simulation: simulation,
          extra_context: {
            'operation_id' => OPERATIONS[event_key],
            'event_key' => event_key,
            'trigger_source' => trigger_source,
            'file_index' => index + 1,
            'file_count' => source_assets.length,
            'machine' => print_machine && {
              'id' => print_machine.id,
              'name' => print_machine.name,
              'destination_code' => print_machine.automation_destination&.code,
              'destination_name' => print_machine.automation_destination&.name,
              'label_destination_code' =>
                print_machine.label_automation_destination&.code,
              'label_destination_name' =>
                print_machine.label_automation_destination&.name
            }
          }
        )
      end

      mark_item_started!(order_item, print_flow, event_key, batch_id, print_machine)
      {
        success: true,
        batch_id: batch_id,
        runs: runs,
        simulation: simulation
      }
    end

    private

    def mark_item_started!(item, print_flow, action, batch_id, print_machine)
      return unless OPERATIONS.key?(action)

      item.order.update!(status: 'processing') if item.order.status == 'new'
      case action
      when 'preprint'
        item.update!(
          preprint_print_flow_id: print_flow.id,
          preprint_status: 'processing',
          preprint_job_id: "automation:#{batch_id}"
        )
      when 'print'
        item.update!(
          print_status: 'processing',
          print_job_id: "automation:#{batch_id}",
          print_machine_id: print_machine&.id
        )
      end
    end
  end
end

class AutomationActionLifecycle
  class << self
    def run_completed!(run)
      aggregation_run_completed!(run)
      return unless managed_action?(run)

      register_preprint_output!(run) if run.operation_type == 'preprint'
      return unless batch_runs(run).all? { |candidate| candidate.status == 'completed' }

      item = run.order_item
      case run.operation_type
      when 'preprint'
        # Producing the PDF is not the operator's approval. Keep the item in
        # processing so the UI exposes the manual "Conferma pre-stampa"
        # action; the confirm_preprint route is the only transition to
        # completed.
        item.update!(preprint_status: 'processing')
      when 'print'
        item.update!(print_status: 'ripped')
      end
    end

    def aggregation_run_completed!(run)
      return unless run.operation_type == 'aggregation'

      aggregation_id = run.context.dig('aggregation', 'id').to_i
      return unless aggregation_id.positive?

      job = AggregatedJob.find_by(id: aggregation_id)
      return unless job

      destination_dir = File.join(Dir.pwd, 'storage', 'aggregated')
      FileUtils.mkdir_p(destination_dir)

      identification_artifact = run.artifact_by_kind('identification_sheet_pdf')
      if identification_artifact&.available?
        identification_filename = "#{job.aggregation_code}-scheda-ordini.pdf"
        identification_destination = File.join(destination_dir, identification_filename)
        FileUtils.cp(identification_artifact.full_path, identification_destination)
        job.update!(
          identification_sheet_file_url: "/file/agg_#{job.id}/#{identification_filename}",
          identification_sheet_filename: identification_filename,
          identification_sheet_at: Time.current
        )
      end

      artifact = result_artifact(run)
      return unless artifact&.available? && artifact.kind != 'source'
      return if artifact.kind == 'identification_sheet_pdf'

      filename = "#{job.aggregation_code}.pdf"
      destination = File.join(destination_dir, filename)
      FileUtils.cp(artifact.full_path, destination)
      job.update!(
        status: 'preview_pending',
        aggregated_file_url: "/file/agg_#{job.id}/#{filename}",
        aggregated_filename: filename,
        aggregated_at: Time.current,
        notes: filename
      )
    end

    def run_failed!(run)
      aggregation_id = run.context.dig('aggregation', 'id').to_i
      if aggregation_id.positive?
        AggregatedJob.where(id: aggregation_id).update_all(status: 'failed')
      end
      return unless managed_action?(run)

      case run.operation_type
      when 'preprint' then run.order_item.update!(preprint_status: 'failed')
      when 'print' then run.order_item.update!(print_status: 'failed')
      end
    end

    private

    def managed_action?(run)
      run.order_item && run.action_batch_id.present? &&
        AutomationActionDispatcher::OPERATIONS.key?(run.operation_type.to_s)
    end

    def batch_runs(run)
      AutomationRun.where(
        order_item_id: run.order_item_id,
        operation_type: run.operation_type,
        action_batch_id: run.action_batch_id
      )
    end

    def register_preprint_output!(run)
      # A handoff chain registers the root and child completions separately.
      # Resolve the terminal run so an intermediate Photoshop PDF cannot
      # overwrite the final Illustrator output on the order item.
      terminal_run = run.chain_runs.max_by(&:created_at) || run
      artifact = result_artifact(terminal_run)
      return unless artifact&.available?
      return if artifact.kind == 'source'

      asset = run.order_item.assets.find_or_initialize_by(
        asset_type: 'print_output',
        local_path: artifact.local_path
      )
      asset.original_url = artifact.filename
      asset.save!
    end

    def result_artifact(run)
      graph = run.automation_flow_version.graph
      finish = Array(graph['nodes']).find { |node| node['type'] == 'finish' }
      requested_kind = finish&.dig('config', 'result_artifact_kind').presence
      requested_kind ? run.artifact_by_kind(requested_kind) : run.current_artifact
    end
  end
end
