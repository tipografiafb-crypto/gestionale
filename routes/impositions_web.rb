require 'open3'
require 'tempfile'

class PrintOrchestrator < Sinatra::Base
  get '/impositions' do
    @imposition_templates = ImpositionTemplate.includes(:active_version, :versions).ordered
    @imposition_folders = @imposition_templates.map(&:folder).uniq.sort
    erb :impositions_list
  end

  post '/impositions' do
    template = ImpositionTemplate.create!(
      code: params[:code].to_s.strip.upcase,
      name: params[:name].to_s.strip,
      folder: params[:folder].to_s.strip.presence || 'Principale',
      description: params[:description].to_s.strip,
      status: 'draft'
    )
    template.versions.create!(
      version_number: 1,
      status: 'draft',
      config: ImpositionConfig.default.merge('layout_mode' => params[:layout_mode].presence || 'grid')
    )
    redirect "/impositions/#{template.id}/edit"
  rescue StandardError => error
    redirect "/impositions?msg=error&text=#{URI.encode_www_form_component(error.message)}"
  end

  get '/impositions/:id/edit' do
    @imposition_template = ImpositionTemplate.find(params[:id])
    @imposition_version = @imposition_template.draft_version
    raw_config = @imposition_version.config.is_a?(Hash) ? @imposition_version.config.deep_stringify_keys : {}
    @imposition_config = ImpositionConfig.normalize(raw_config)
    columns = @imposition_config['columns'].to_i
    rows = @imposition_config['rows'].to_i
    unless raw_config.key?('sample_width_mm')
      available_width = @imposition_config['sheet_width_mm'].to_f -
                        @imposition_config['margin_left_mm'].to_f -
                        @imposition_config['margin_right_mm'].to_f
      @imposition_config['sample_width_mm'] =
        (available_width - [columns - 1, 0].max * @imposition_config['gap_x_mm'].to_f) / columns if columns.positive?
    end
    unless raw_config.key?('sample_height_mm')
      available_height = @imposition_config['sheet_height_mm'].to_f -
                         @imposition_config['margin_top_mm'].to_f -
                         @imposition_config['margin_bottom_mm'].to_f
      @imposition_config['sample_height_mm'] =
        (available_height - [rows - 1, 0].max * @imposition_config['gap_y_mm'].to_f) / rows if rows.positive?
    end
    @imposition_config['sample_pages'] = columns * rows if
      !raw_config.key?('sample_pages') && columns.positive? && rows.positive?
    erb :imposition_studio
  end

  post '/impositions/:id' do
    pass unless params[:id].to_s.match?(/\A\d+\z/)

    content_type :json
    template = ImpositionTemplate.find(params[:id])
    payload = JSON.parse(request.body.read)
    config = ImpositionConfig.normalize(payload['config'])
    template.update!(
      name: payload['name'].to_s.strip,
      folder: payload['folder'].to_s.strip.presence || 'Principale',
      description: payload['description'].to_s.strip
    )
    draft = template.draft_version
    draft.update!(config: config)
    {success: true, version: draft.version_number, saved_at: draft.updated_at.iso8601}.to_json
  rescue ActiveRecord::RecordNotFound
    status 404
    {success: false, error: 'Plancia non trovata'}.to_json
  rescue JSON::ParserError, ArgumentError, ActiveRecord::RecordInvalid => error
    status 422
    {success: false, error: error.message}.to_json
  end

  post '/impositions/:id/publish' do
    template = ImpositionTemplate.find(params[:id])
    template.publish_draft!
    redirect "/impositions/#{template.id}/edit?msg=success&text=Plancia+pubblicata"
  rescue StandardError => error
    redirect "/impositions/#{params[:id]}/edit?msg=error&text=#{URI.encode_www_form_component(error.message)}"
  end

  post '/impositions/:id/duplicate' do
    source = ImpositionTemplate.find(params[:id])
    base_code = "#{source.code}_COPY"
    code = base_code
    suffix = 2
    while ImpositionTemplate.exists?(code: code)
      code = "#{base_code}_#{suffix}"
      suffix += 1
    end
    copy = ImpositionTemplate.create!(
      code: code,
      name: "#{source.name} copia",
      folder: source.folder,
      description: source.description,
      status: 'draft'
    )
    copy.versions.create!(
      version_number: 1,
      status: 'draft',
      config: JSON.parse(JSON.generate(source.draft_version.config))
    )
    redirect "/impositions/#{copy.id}/edit?msg=success&text=Plancia+duplicata"
  rescue StandardError => error
    redirect "/impositions?msg=error&text=#{URI.encode_www_form_component(error.message)}"
  end

  post '/impositions/:id/archive' do
    template = ImpositionTemplate.find(params[:id])
    template.update!(status: 'archived')
    AutomationPreset.where(kind: 'imposition', code: template.code).update_all(active: false)
    redirect '/impositions?msg=success&text=Plancia+archiviata'
  rescue StandardError => error
    redirect "/impositions?msg=error&text=#{URI.encode_www_form_component(error.message)}"
  end

  post '/impositions/:id/delete' do
    template = ImpositionTemplate.find(params[:id])
    unless template.status == 'archived'
      redirect "/impositions?msg=error&text=#{URI.encode_www_form_component('Archivia prima la plancia prima di eliminarla') }"
    end

    references = template.automation_reference_names
    unless references.empty?
      message = "Impossibile eliminare: la plancia è ancora referenziata da #{references.join(', ')}"
      redirect "/impositions?msg=error&text=#{URI.encode_www_form_component(message)}"
    end

    ImpositionTemplate.transaction do
      AutomationPreset.where(kind: 'imposition', code: template.code).delete_all
      template.destroy!
    end
    redirect '/impositions?msg=success&text=Plancia+eliminata+definitivamente'
  rescue StandardError => error
    redirect "/impositions?msg=error&text=#{URI.encode_www_form_component(error.message)}"
  end

  post '/impositions/test' do
    upload = params[:pdf]
    tempfile = upload.is_a?(Hash) ? (upload[:tempfile] || upload['tempfile']) : nil
    halt 422, 'Seleziona un PDF di prova' unless tempfile && File.file?(tempfile.path)
    halt 413, 'Il PDF supera 100 MB' if File.size(tempfile.path) > 100 * 1024 * 1024

    config = ImpositionConfig.normalize(JSON.parse(params[:config].to_s))
    Tempfile.create(['imposition-test-', '.pdf']) do |output|
      output.close
      script = File.join(settings.root, 'tools', 'automation_pdf', 'cli.py')
      stdout, stderr, process = Open3.capture3(
        'python3', script, 'impose',
        '--input', tempfile.path,
        '--output', output.path,
        '--config', JSON.generate(config)
      )
      halt 422, stderr.presence || stdout.presence || 'Imposizione non riuscita' unless process.success?

      content_type 'application/pdf'
      attachment "prova-#{Time.now.strftime('%Y%m%d-%H%M%S')}.pdf"
      body File.binread(output.path)
    end
  rescue JSON::ParserError, ArgumentError => error
    status 422
    error.message
  end
end
