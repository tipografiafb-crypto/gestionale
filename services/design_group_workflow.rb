# Applies production actions to every order row that shares the same artwork.
require 'fileutils'

# A design group is dispatched once. The resulting preprint output is copied to
# the sibling rows when the workflow reports completion.
class DesignGroupWorkflow
  class Error < StandardError; end

  def initialize(source_item, server_url: nil)
    @source_item = source_item
    @order = source_item.order
    @server_url = server_url || ENV['SERVER_BASE_URL'] || 'http://localhost:5000'
  end

  def send_preprint!(print_flow:, percentuale:, azione_photoshop: nil, quantity_override: nil)
    require_source_status!(:preprint_status, %w[pending], 'Questo item non è in attesa di pre-stampa')
    items = group_items.select { |item| item.preprint_status == 'pending' }
    plan = preprint_plan(@source_item, print_flow)

    @order.update!(status: 'processing') if @order.status == 'new'
    webhook_fields = { 'percentuale' => percentuale.to_i.to_s }
    webhook_fields['azione photoshop'] = azione_photoshop unless azione_photoshop.to_s.empty?
    webhook_fields['preprint_quantity_override'] = quantity_override.to_s if quantity_override
    items.each do |item|
      item.update!(
        preprint_print_flow_id: print_flow.id,
        preprint_status: 'processing',
        campi_webhook: webhook_fields
      )
    end

    begin
      jobs = if plan[:executor] == 'automation'
               result = AutomationActionDispatcher.dispatch!(
                 print_flow: print_flow,
                 action: 'preprint',
                 order_item: @source_item,
                 assets: plan[:assets]
               )
               result[:runs].length
             else
               successful_assets = send_preprint_webhooks!(@source_item, print_flow, plan[:assets], webhook_fields)
               @source_item.update!(preprint_job_id: successful_assets.join(','))
               successful_assets.length
             end
    rescue StandardError => e
      items.each { |item| item.update(preprint_status: 'failed') }
      raise Error, "#{item_label(@source_item)}: #{e.message}"
    end

    { rows: items.length, jobs: jobs }
  end

  # Copies one completed preprint result into the sibling rows. Each sibling
  # receives its own Asset record and storage path, so reset/delete operations
  # on one row cannot invalidate another row's result.
  def self.propagate_preprint_output!(source_item, source_asset)
    source_path = source_asset.local_path_full
    return [] unless source_path && File.file?(source_path)

    siblings = DesignGrouping.siblings_for(source_item).reject { |item| item.id == source_item.id }
    siblings.each do |item|
      previous_outputs = item.assets.where(asset_type: 'print_output')
      AutomationRun.where(source_asset_id: previous_outputs.select(:id)).update_all(source_asset_id: nil)
      previous_outputs.destroy_all

      store_code = item.order.store.code || item.order.store.id.to_s
      filename = "shared-#{source_asset.id}-#{File.basename(source_asset.local_path.to_s)}"
      relative_path = File.join('storage', store_code, item.order.external_order_code.to_s, item.sku.to_s, filename)
      full_path = File.join(Dir.pwd, relative_path)
      FileUtils.mkdir_p(File.dirname(full_path))
      FileUtils.cp(source_path, full_path)

      item.assets.create!(
        original_url: source_asset.original_url,
        local_path: relative_path,
        asset_type: 'print_output'
      )
    end
  end

  def confirm_preprint!
    require_source_status!(:preprint_status, %w[processing], 'Questo item non è in fase di pre-stampa')
    items = group_items.select { |item| item.preprint_status == 'processing' }
    missing_outputs = items.reject { |item| item.latest_preprint_asset&.downloaded? }
    if missing_outputs.any?
      labels = missing_outputs.map { |item| item_label(item) }.join(', ')
      raise Error, "Pre-stampa non ancora pronta per: #{labels}"
    end

    completed_at = Time.current
    items.each { |item| item.update!(preprint_status: 'completed', preprint_completed_at: completed_at) }
    { rows: items.length }
  end

  def send_print!(print_machine:)
    require_source_status!(:preprint_status, %w[completed], 'Pre-stampa non completata per questo item')
    require_source_status!(:print_status, %w[pending], 'Questo item non è in attesa di stampa')
    items = group_items.select do |item|
      item.preprint_status == 'completed' && item.print_status == 'pending'
    end
    plans = items.map { |item| print_plan(item) }

    @order.update!(status: 'processing') if @order.status == 'new'
    jobs = 0

    plans.each do |plan|
      item = plan[:item]
      print_flow = plan[:print_flow]
      item.update!(print_status: 'processing', print_machine_id: print_machine.id)

      if plan[:executor] == 'automation'
        result = AutomationActionDispatcher.dispatch!(
          print_flow: print_flow,
          action: 'print',
          order_item: item,
          assets: plan[:assets],
          print_machine: print_machine
        )
        jobs += result[:runs].length
      else
        send_print_webhook!(item, print_flow, plan[:assets].first, print_machine)
        item.update!(print_status: 'ripped')
        jobs += 1
      end
    rescue StandardError => e
      item.update(print_status: 'failed') if item
      raise Error, "#{item_label(item)}: #{e.message}"
    end

    { rows: items.length, jobs: jobs }
  end

  def confirm_print!
    require_source_status!(:print_status, %w[processing ripped], 'Questo item non è in fase di stampa')
    items = group_items.select { |item| %w[processing ripped].include?(item.print_status) }
    completed_at = Time.current
    items.each { |item| item.update!(print_status: 'completed', print_completed_at: completed_at) }
    @order.update!(status: 'done') if @order.order_items.reload.all? { |item| item.print_status == 'completed' }
    { rows: items.length }
  end

  private

  def group_items
    @group_items ||= DesignGrouping.siblings_for(@source_item).sort_by(&:item_number)
  end

  def require_source_status!(attribute, accepted, message)
    raise Error, message unless accepted.include?(@source_item.public_send(attribute))
  end

  def preprint_plan(item, print_flow)
    assets = item.switch_print_assets.select(&:downloaded?)
    raise Error, "#{item_label(item)}: nessun file grafico disponibile" if assets.empty?

    executor = print_flow.executor_for('preprint')
    webhook_configured = executor == 'webhook' && !print_flow.preprint_webhook&.hook_path.to_s.empty?
    unless executor == 'automation' || webhook_configured
      raise Error, 'Flusso di stampa non configurato per la pre-stampa'
    end

    { item: item, assets: assets, executor: executor }
  end

  def print_plan(item)
    print_flow = item.print_flow
    raise Error, "#{item_label(item)}: flusso di stampa non configurato" unless print_flow

    assets = item.assets.where(asset_type: 'print_output').select(&:downloaded?)
    raise Error, "#{item_label(item)}: file di pre-stampa non trovato" if assets.empty?

    executor = print_flow.executor_for('print')
    webhook_configured = executor == 'webhook' && !print_flow.print_webhook&.hook_path.to_s.empty?
    unless executor == 'automation' || webhook_configured
      raise Error, "#{item_label(item)}: azione di stampa non configurata"
    end

    { item: item, print_flow: print_flow, assets: assets, executor: executor }
  end

  def send_preprint_webhooks!(item, print_flow, assets, webhook_fields)
    product = item.product
    successes = []
    errors = []

    assets.each do |asset|
      payload = {
        id_riga: item.item_number,
        codice_ordine: @order.external_order_code,
        product: "#{product&.sku} - #{product&.name}",
        operation_id: 1,
        job_operation_id: item.id.to_s,
        url: "#{@server_url}/api/assets/#{asset.id}/download",
        widegest_url: "#{@server_url}/api/v1/reports_create",
        filename: item.switch_filename_for_asset(asset) || "#{@order.external_order_code.downcase}-#{item.id}.png",
        quantita: item.workflow_quantity,
        materiale: product&.notes || 'N/A',
        campi_custom: {},
        opzioni_stampa: {},
        campi_webhook: webhook_fields
      }

      cut_asset = item.assets.find { |candidate| candidate.asset_type == 'cut' && candidate.downloaded? }
      if cut_asset
        payload[:cut_url] = "#{@server_url}/api/assets/#{cut_asset.id}/download"
        payload[:cut_filename] = "#{@order.external_order_code}-#{item.item_number}-cut.svg"
      end

      result = SwitchClient.send_to_switch(
        webhook_path: print_flow.preprint_webhook.hook_path,
        job_data: payload
      )
      result[:success] ? successes << asset.id : errors << result[:error].to_s
    end

    raise Error, "errore invio: #{errors.join(', ')}" if errors.any?
    successes
  end

  def send_print_webhook!(item, print_flow, asset, print_machine)
    product = item.product
    payload = {
      id_riga: item.item_number,
      codice_ordine: @order.external_order_code,
      product: "#{product&.sku} - #{product&.name}",
      operation_id: 2,
      job_operation_id: item.id.to_s,
      url: "#{@server_url}/api/assets/#{asset.id}/download",
      widegest_url: "#{@server_url}/api/v1/reports_create",
      filename: asset.original_url || "#{@order.external_order_code.downcase}-#{item.id}-print.pdf",
      nome_macchina: print_machine.name,
      campi_webhook: item.campi_webhook || {}
    }
    result = SwitchClient.send_to_switch(
      webhook_path: print_flow.print_webhook.hook_path,
      job_data: payload
    )
    raise Error, (result[:error] || 'Errore invio a Switch').to_s unless result[:success]
  end

  def item_label(item)
    item ? "Riga #{item.item_number} (#{item.sku})" : 'Riga'
  end
end
