# @feature switch
# @domain services
# SwitchClient - Handles communication with Enfocus Switch
require 'http'
require 'json'

class SwitchClient
  attr_reader :order, :switch_job

  def initialize(order)
    @order = order
    @switch_job = order.switch_job || order.build_switch_job
  end

  # Send order to Switch
  def send_to_switch
    # Check if order is ready
    unless @order.ready_for_switch?
      return { success: false, error: 'Order not ready (assets not downloaded)' }
    end

    begin
      # Prepare payload
      payload = build_payload

      # Send to Switch webhook
      response = HTTP
        .timeout(30)
        .headers(
          'Content-Type' => 'application/json',
          'X-API-Key' => ENV['SWITCH_API_KEY'] || ''
        )
        .post(switch_webhook_url, json: payload)

      # Process response
      if response.status.success?
        handle_success(response)
      else
        handle_error(response)
      end

    rescue StandardError => e
      handle_exception(e)
    end
  end

  private

  def switch_webhook_url
    ENV['SWITCH_WEBHOOK_URL'] || 'http://localhost:9999/webhook'
  end

  def build_payload
    {
      external_order_code: @order.external_order_code,
      store_code: @order.store.code,
      store_name: @order.store.name,
      items: @order.order_items.map do |item|
        {
          sku: item.sku,
          quantity: item.quantity,
          assets: item.assets.map do |asset|
            {
              type: asset.asset_type,
              url: asset.original_url,
              local_path: asset.local_path_full
            }
          end
        }
      end,
      metadata: {
        order_id: @order.id,
        created_at: @order.created_at.iso8601
      }
    }
  end

  def handle_success(response)
    body = JSON.parse(response.body.to_s) rescue {}
    
    @switch_job.update(
      status: 'sent',
      switch_job_id: body['job_id']
    )
    @switch_job.add_log("Successfully sent to Switch. Job ID: #{body['job_id']}")
    
    @order.update_status('sent_to_switch')

    { success: true, job_id: body['job_id'], message: 'Sent to Switch successfully' }
  end

  def handle_error(response)
    error_message = "Switch returned #{response.status}: #{response.body}"
    @switch_job.update(status: 'failed')
    @switch_job.add_log(error_message)
    @order.update_status('error')

    { success: false, error: error_message }
  end

  def handle_exception(exception)
    error_message = "Exception: #{exception.message}"
    @switch_job.update(status: 'failed')
    @switch_job.add_log(error_message)
    @order.update_status('error')

    { success: false, error: error_message }
  end
end
