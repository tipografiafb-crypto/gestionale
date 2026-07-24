# @feature automation
# @domain integration

require 'fileutils'
require 'http'
require 'http/form_data'
require 'json'
require 'open3'
require 'pathname'
require 'securerandom'
require 'socket'
require 'tempfile'
require 'tmpdir'

class AutomationAdobeAgent
  def initialize(
    base_url: ENV.fetch('AUTOMATION_BASE_URL', 'http://localhost:5010'),
    token: ENV['AUTOMATION_AGENT_TOKEN'],
    worker_id: ENV.fetch('AUTOMATION_AGENT_ID', "adobe-#{Socket.gethostname}"),
    workspace_root: ENV.fetch('AUTOMATION_WORKSPACE_ROOT', Dir.pwd)
  )
    @base_url = base_url.sub(%r{/$}, '')
    @token = token
    @worker_id = worker_id
    @workspace_root = workspace_root
  end

  def run(once: false, poll_seconds: 2)
    puts "[AdobeAgent] #{@worker_id} collegato a #{@base_url}"
    loop do
      task = claim
      if task
        process(task)
        return if once
      elsif once
        puts '[AdobeAgent] Nessun task disponibile'
        return
      else
        sleep(poll_seconds)
      end
    rescue Interrupt
      puts '[AdobeAgent] Arrestato'
      return
    rescue StandardError => e
      warn "[AdobeAgent] #{e.class}: #{e.message}"
      sleep(poll_seconds) unless once
      raise if once
    end
  end

  private

  def claim
    response = request.post(
      "#{@base_url}/api/automation/agent/claim",
      json: {
        worker_id: @worker_id,
        capabilities: %w[photoshop illustrator]
      }
    )
    raise "Claim fallito: HTTP #{response.status} #{response.body}" unless response.status.success?

    payload = JSON.parse(response.body.to_s)
    payload['task']
  end

  def process(task)
    Dir.mktmpdir("automation-adobe-#{task['step_id']}-") do |dir|
      input = download_input(task, dir)
      output = File.join(dir, task['node_type'] == 'illustrator' ? 'illustrator.pdf' : 'photoshop.pdf')
      config = task['config'] || {}

      if task['node_type'] == 'photoshop'
        execute_photoshop(input, output, config, task['context'] || {}, dir)
      elsif task['node_type'] == 'illustrator'
        execute_illustrator(input, output, config, dir)
      else
        raise "Task Adobe non supportato: #{task['node_type']}"
      end

      raise 'Adobe non ha prodotto il PDF atteso' unless File.file?(output) && File.size(output).positive?

      complete(task, output)
    end
  rescue StandardError => e
    fail_task(task, "#{e.class}: #{e.message}")
  end

  def download_input(task, dir)
    extension = File.extname(task['input_filename'].to_s)
    extension = '.bin' if extension.empty?
    path = File.join(dir, "input#{extension}")
    response = request.get("#{@base_url}#{task['input_url']}")
    raise "Download input fallito: HTTP #{response.status}" unless response.status.success?

    File.binwrite(path, response.body.to_s)
    path
  end

  def execute_photoshop(input, output, config, context, dir)
    dpi = config.fetch('dpi', 300).to_f
    width_mm = config['width_mm'].to_f
    height_mm = config['height_mm'].to_f
    raise ArgumentError, 'Larghezza e altezza devono essere entrambe maggiori di zero' if
      width_mm.positive? != height_mm.positive?
    resize_line = if width_mm.positive?
                    width_px = (width_mm / 25.4 * dpi).round
                    height_px = (height_mm / 25.4 * dpi).round
                    "documentRef.resizeImage(UnitValue(#{width_px}, \"px\"), UnitValue(#{height_px}, \"px\"), #{dpi}, ResampleMethod.BICUBIC);"
                  else
                    "documentRef.resizeImage(undefined, undefined, #{dpi}, ResampleMethod.NONE);"
                  end
    jsx = <<~JSX
      #target photoshop
      app.displayDialogs = DialogModes.NO;
      var inputFile = new File(#{JSON.generate(input)});
      var outputFile = new File(#{JSON.generate(output)});
      var documentRef = app.open(inputFile);
      if (#{JSON.generate(config['action_set'].to_s)} !== "" && #{JSON.generate(config['action_name'].to_s)} !== "") {
        app.doAction(#{JSON.generate(config['action_name'].to_s)}, #{JSON.generate(config['action_set'].to_s)});
      }
      documentRef = app.activeDocument;
      #{resize_line}
      var saveOptions = new PDFSaveOptions();
      saveOptions.embedColorProfile = true;
      saveOptions.preserveEditing = false;
      documentRef.saveAs(outputFile, saveOptions, true, Extension.LOWERCASE);
      documentRef.close(SaveOptions.DONOTSAVECHANGES);
    JSX
    execute_jsx(
      app_name: ENV.fetch('ADOBE_PHOTOSHOP_APP', 'Adobe Photoshop 2024'),
      jsx: jsx,
      path: File.join(dir, 'photoshop.jsx')
    )
  end

  def execute_illustrator(input, output, config, dir)
    template = config['template_path'].to_s
    template = File.expand_path(template, @workspace_root) unless Pathname.new(template).absolute?
    raise "Template Illustrator non trovato: #{template}" unless File.file?(template)

    jsx = <<~JSX
      #target illustrator
      app.userInteractionLevel = UserInteractionLevel.DONTDISPLAYALERTS;
      var templateFile = new File(#{JSON.generate(template)});
      var imageFile = new File(#{JSON.generate(input)});
      var outputFile = new File(#{JSON.generate(output)});
      var documentRef = app.open(templateFile);
      var mask = documentRef.pageItems[0];
      var placed = documentRef.placedItems.add();
      placed.file = imageFile;
      var maskBounds = mask.geometricBounds;
      var imageBounds = placed.geometricBounds;
      var maskWidth = maskBounds[2] - maskBounds[0];
      var maskHeight = maskBounds[1] - maskBounds[3];
      var imageWidth = imageBounds[2] - imageBounds[0];
      var imageHeight = imageBounds[1] - imageBounds[3];
      placed.position = [
        maskBounds[0] + (maskWidth - imageWidth) / 2,
        maskBounds[1] - (maskHeight - imageHeight) / 2
      ];
      placed.zOrder(ZOrderMethod.SENDTOBACK);
      var group = documentRef.groupItems.add();
      placed.moveToBeginning(group);
      mask.moveToBeginning(group);
      group.clipped = true;
      group.selected = true;
      app.executeMenuCommand('expandStyle');
      documentRef.artboards[0].artboardRect = maskBounds;
      var pdfOptions = new PDFSaveOptions();
      pdfOptions.pDFPreset = #{JSON.generate(config.fetch('pdf_preset', 'PDF PLANCE'))};
      documentRef.saveAs(outputFile, pdfOptions);
      documentRef.close(SaveOptions.DONOTSAVECHANGES);
    JSX
    execute_jsx(
      app_name: ENV.fetch('ADOBE_ILLUSTRATOR_APP', 'Adobe Illustrator'),
      jsx: jsx,
      path: File.join(dir, 'illustrator.jsx')
    )
  end

  def execute_jsx(app_name:, jsx:, path:)
    File.write(path, jsx)
    apple_script = <<~APPLESCRIPT
      set jsxFile to POSIX file #{JSON.generate(path)}
      tell application #{JSON.generate(app_name)}
        activate
        do javascript jsxFile
      end tell
    APPLESCRIPT
    _stdout, stderr, status = Open3.capture3('osascript', '-e', apple_script)
    raise "Errore #{app_name}: #{stderr}" unless status.success?
  end

  def complete(task, output)
    response = request.post(
      "#{@base_url}/api/automation/agent/steps/#{task['step_id']}/complete",
      form: {
        worker_id: @worker_id,
        file: HTTP::FormData::File.new(output),
        metadata: JSON.generate({'agent' => @worker_id})
      }
    )
    raise "Upload risultato fallito: HTTP #{response.status} #{response.body}" unless response.status.success?

    puts "[AdobeAgent] Completato step #{task['step_id']} (#{task['node_type']})"
  end

  def fail_task(task, message)
    request.post(
      "#{@base_url}/api/automation/agent/steps/#{task['step_id']}/fail",
      json: {worker_id: @worker_id, error: message}
    )
    warn "[AdobeAgent] Step #{task['step_id']} fallito: #{message}"
  end

  def request
    headers = {'Accept' => 'application/json'}
    headers['Authorization'] = "Bearer #{@token}" if @token.present?
    HTTP.headers(headers)
  end

  def context_value(context, path)
    path.to_s.split('.').reduce(context) do |value, key|
      value.is_a?(Hash) ? value[key] : nil
    end
  end
end
