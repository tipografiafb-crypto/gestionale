require 'minitest/autorun'
require 'active_support/core_ext/object/blank'
require 'active_support/core_ext/object/deep_dup'
require 'tmpdir'
require_relative '../services/automation_engine'

# Run the real PDF pipeline without starting the application or writing to its DB.
class AutomationPreset
  def self.active; end
end unless defined?(AutomationPreset)

class AutomationStepRepeatTest < Minitest::Test
  PYTHON = ENV.fetch('AUTOMATION_TEST_PYTHON', 'python3')
  CLI = File.expand_path('../tools/automation_pdf/cli.py', __dir__)
  Artifact = Struct.new(:id, :full_path, :metadata, :media_type) do
    def available?
      File.file?(full_path)
    end
  end

  class Executor < AutomationNodeExecutor
    attr_reader :commands

    def initialize(source, config, context, directory)
      @config = config
      @context = context
      @run = Struct.new(:current_artifact).new(source)
      @step = Struct.new(:node_type, :node_key).new('step_repeat', 'impose')
      @directory = directory
      @commands = []
    end

    private

    def run_output_dir
      @directory
    end

    def run_pdf_tool(*arguments)
      @commands << arguments
      stdout, stderr, status = Open3.capture3(PYTHON, CLI, *arguments)
      raise stderr unless status.success?

      JSON.parse(stdout)
    end
  end

  def setup
    @directory = Dir.mktmpdir('step-repeat-test-')
    @old_pdfx = ENV['PDFX_FINALIZER_ENABLED']
    ENV['PDFX_FINALIZER_ENABLED'] = '0'
    @preset = {
      'layout_mode' => 'grid', 'sheet_width_mm' => 500, 'sheet_height_mm' => 350,
      'rows' => 5, 'columns' => 5, 'gap_x_mm' => 10, 'gap_y_mm' => 10,
      'anchor' => 'bottom_left', 'page_distribution' => 'sequential',
      'fill_last_sheet' => false, 'double_sided_mode' => 'none'
    }
  end

  def teardown
    ENV['PDFX_FINALIZER_ENABLED'] = @old_pdfx
    FileUtils.remove_entry(@directory)
  end

  def source(labels, metadata = {})
    path = File.join(@directory, 'source.pdf')
    script = <<~PY
      import json, sys
      from reportlab.pdfgen import canvas
      c = canvas.Canvas(sys.argv[1], pagesize=(88*72/25.4, 58*72/25.4))
      for label in json.loads(sys.argv[2]):
          c.drawString(10, 10, label)
          c.showPage()
      c.save()
    PY
    _, error, status = Open3.capture3(PYTHON, '-c', script, path, JSON.generate(labels))
    raise error unless status.success?

    Artifact.new(1, path, metadata, 'application/pdf')
  end

  def execute(source, mode: nil, copies: 5)
    config = {'preset_code' => 'TEST'}
    config['copies_mode'] = mode if mode
    context = {'variables' => {'production_copies' => copies}}
    executor = Executor.new(source, config, context, @directory)
    scope = Object.new
    scope.define_singleton_method(:find_by) { |**| Struct.new(:config).new(@preset_config) }
    scope.instance_variable_set(:@preset_config, @preset)
    artifact = nil
    create_artifact = lambda do |**attributes|
      artifact = Artifact.new(2, attributes.fetch(:path), attributes.fetch(:metadata), 'application/pdf')
    end
    with_method(AutomationPreset, :active, -> { scope }) do
      with_method(AutomationEngine, :create_artifact!, create_artifact) { executor.execute }
    end
    [artifact, executor]
  end

  def with_method(target, name, implementation)
    original = target.method(name)
    target.define_singleton_method(name, implementation)
    yield
  ensure
    target.define_singleton_method(name, original)
  end

  def label_counts(artifact)
    script = <<~PY
      import json, sys
      from pypdf import PdfReader
      text = '\\n'.join(page.extract_text() or '' for page in PdfReader(sys.argv[1]).pages)
      print(json.dumps({label: text.count(label) for label in ['ES7882', 'IT10190']}))
    PY
    stdout, error, status = Open3.capture3(PYTHON, '-c', script, artifact.full_path)
    raise error unless status.success?

    JSON.parse(stdout)
  end

  def test_existing_nodes_still_apply_the_received_quantity
    artifact, = execute(source(['IT10190']))
    assert_equal 5, artifact.metadata['placed_pages']
    assert_equal 5, label_counts(artifact)['IT10190']
    assert_equal 'quantity', artifact.metadata['copies_mode']
  end

  def test_explicit_quantity_mode_still_multiplies
    artifact, = execute(source(['IT10190']), mode: 'quantity', copies: 3)
    assert_equal 3, label_counts(artifact)['IT10190']
  end

  def test_once_keeps_all_six_aggregated_elements_despite_coordinator_quantity
    artifact, executor = execute(source(['ES7882'] + ['IT10190'] * 5), mode: 'once')
    assert_equal 6, artifact.metadata['placed_pages']
    assert_equal 1, artifact.metadata['sheets']
    assert_equal({'ES7882' => 1, 'IT10190' => 5}, label_counts(artifact))
    refute executor.commands.any? { |command| command.first == 'duplicate-pages' }
  end

  def test_once_overrides_preset_repetition_without_changing_the_preset
    @preset.merge!('page_distribution' => 'repeat_each', 'repeat_product' => true, 'fill_last_sheet' => true)
    original = @preset.deep_dup
    artifact, = execute(source(['ES7882'] + ['IT10190'] * 5), mode: 'once')
    assert_equal 6, artifact.metadata['placed_pages']
    assert_equal({'ES7882' => 1, 'IT10190' => 5}, label_counts(artifact))
    assert_equal original, @preset
  end

  def test_quantity_keeps_existing_preset_repetition
    @preset.merge!('page_distribution' => 'repeat_each', 'fill_last_sheet' => true)
    artifact, = execute(source(['IT10190']), mode: 'quantity')
    assert_equal 25, artifact.metadata['placed_pages']
  end

  def test_quantity_does_not_duplicate_copies_already_applied
    artifact, executor = execute(source(['IT10190'] * 5, {'copies_applied' => 5}))
    assert_equal 5, label_counts(artifact)['IT10190']
    refute executor.commands.any? { |command| command.first == 'duplicate-pages' }
  end

  def test_invalid_mode_is_rejected_at_validation_and_execution
    graph = {
      'nodes' => [
        {'id' => 'input', 'type' => 'trigger'},
        {'id' => 'impose', 'type' => 'step_repeat', 'config' => {'preset_code' => 'TEST', 'copies_mode' => 'invalid'}}
      ],
      'edges' => [{'source' => 'input', 'target' => 'impose'}]
    }
    assert AutomationGraphValidator.new(graph).errors.any? { |error| error.include?('Gestione copie non valida') }
    assert_raises(ArgumentError) { execute(source(['IT10190']), mode: 'invalid') }
  end
end
