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
      action = action.to_s
      raise ArgumentError, "Azione interna non supportata: #{action}" unless OPERATIONS.key?(action)
      raise ArgumentError, "L'azione #{action} non usa un flusso interno" unless print_flow.executor_for(action) == 'automation'

      automation_flow = print_flow.automation_flow_for(action)
      raise ArgumentError, "Flusso interno #{action} non configurato" unless automation_flow
      raise ArgumentError, "Pubblica il flusso interno #{automation_flow.name} prima di usarlo" unless automation_flow.active_version

      source_assets = Array(assets).compact
      raise ArgumentError, 'Nessun file disponibile per avviare il flusso' if source_assets.empty?

      unavailable = source_assets.reject(&:downloaded?)
      raise ArgumentError, "File locale non disponibile: #{unavailable.first&.filename_from_url}" if unavailable.any?

      batch_id = SecureRandom.uuid
      runs = source_assets.each_with_index.map do |asset, index|
        AutomationEngine.start_run(
          flow: automation_flow,
          order_item: order_item,
          source_asset: asset,
          operation_type: action,
          print_flow: print_flow,
          action_batch_id: batch_id,
          simulation: simulation,
          extra_context: {
            'operation_id' => OPERATIONS.fetch(action),
            'file_index' => index + 1,
            'file_count' => source_assets.length,
            'machine' => print_machine && {
              'id' => print_machine.id,
              'name' => print_machine.name
            }
          }
        )
      end

      mark_item_started!(order_item, print_flow, action, batch_id, print_machine)
      {
        success: true,
        batch_id: batch_id,
        runs: runs,
        simulation: simulation
      }
    end

    private

    def mark_item_started!(item, print_flow, action, batch_id, print_machine)
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
      return unless managed_action?(run)

      register_preprint_output!(run) if run.operation_type == 'preprint'
      return unless batch_runs(run).all? { |candidate| candidate.status == 'completed' }

      item = run.order_item
      case run.operation_type
      when 'preprint'
        item.update!(
          preprint_status: 'completed',
          preprint_completed_at: Time.current
        )
      when 'print'
        item.update!(print_status: 'ripped')
      end
    end

    def run_failed!(run)
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
      artifact = result_artifact(run)
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
