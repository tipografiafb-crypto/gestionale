require 'minitest/autorun'

class Time
  def self.current
    now
  end
end unless Time.respond_to?(:current)

module DesignGrouping
  def self.siblings_for(item)
    item.order.order_items
  end
end

module AutomationActionDispatcher
  class << self
    attr_accessor :dispatched_item_ids

    def dispatch!(order_item:, **)
      self.dispatched_item_ids ||= []
      dispatched_item_ids << order_item.id
      { runs: [Object.new] }
    end
  end
end

require_relative '../services/design_group_workflow'

FakeProduct = Struct.new(:allow_preprint_quantity_override)
FakeFlow = Struct.new(:id) do
  def executor_for(_action)
    'automation'
  end
end

class FakeAsset
  def downloaded?
    true
  end
end

class FakeOrderItems < Array
  def reload
    self
  end
end

class FakeOrder
  attr_accessor :status, :order_items

  def initialize
    @status = 'new'
    @order_items = FakeOrderItems.new
  end

  def update!(attributes)
    attributes.each { |key, value| public_send("#{key}=", value) }
  end
end

class FakeItem
  attr_accessor :id, :sku, :order, :preprint_status, :print_status,
                :preprint_completed_at, :print_completed_at, :campi_webhook,
                :preprint_print_flow_id, :preprint_output_ready

  def initialize(id:, order:, preprint_status: 'pending', print_status: 'pending')
    @id = id
    @sku = "SKU-#{id}"
    @order = order
    @preprint_status = preprint_status
    @print_status = print_status
    @preprint_output_ready = true
    @product = FakeProduct.new(false)
  end

  def item_number
    id
  end

  def product
    @product
  end

  def switch_print_assets
    [FakeAsset.new]
  end

  def latest_preprint_asset
    FakeAsset.new if preprint_output_ready
  end

  def update!(attributes)
    attributes.each do |key, value|
      writer = "#{key}="
      public_send(writer, value) if respond_to?(writer)
    end
  end

  alias update update!
end

class DesignGroupWorkflowTest < Minitest::Test
  def setup
    AutomationActionDispatcher.dispatched_item_ids = []
    @order = FakeOrder.new
    @first = FakeItem.new(id: 1, order: @order)
    @second = FakeItem.new(id: 2, order: @order)
    @already_done = FakeItem.new(id: 3, order: @order, preprint_status: 'completed')
    @order.order_items.concat([@first, @second, @already_done])
  end

  def test_preprint_is_dispatched_to_every_pending_row_in_the_design_group
    result = DesignGroupWorkflow.new(@first).send_preprint!(
      print_flow: FakeFlow.new(7),
      percentuale: 0
    )

    assert_equal [1], AutomationActionDispatcher.dispatched_item_ids
    assert_equal 2, result[:rows]
    assert_equal 'processing', @first.preprint_status
    assert_equal 'processing', @second.preprint_status
    assert_equal 'completed', @already_done.preprint_status
  end

  def test_confirmations_advance_all_actionable_rows_and_close_completed_order
    @first.preprint_status = 'processing'
    @second.preprint_status = 'processing'
    result = DesignGroupWorkflow.new(@first).confirm_preprint!

    assert_equal 2, result[:rows]
    assert_equal %w[completed completed completed], @order.order_items.map(&:preprint_status)

    @order.order_items.each { |item| item.print_status = 'ripped' }
    result = DesignGroupWorkflow.new(@first).confirm_print!

    assert_equal 3, result[:rows]
    assert_equal %w[completed completed completed], @order.order_items.map(&:print_status)
    assert_equal 'done', @order.status
  end

  def test_preprint_confirmation_waits_for_every_linked_output
    @first.preprint_status = 'processing'
    @second.preprint_status = 'processing'
    @second.preprint_output_ready = false

    error = assert_raises(DesignGroupWorkflow::Error) do
      DesignGroupWorkflow.new(@first).confirm_preprint!
    end

    assert_match(/Riga 2/, error.message)
    assert_equal %w[processing processing completed], @order.order_items.map(&:preprint_status)
  end
end
