class PrintOrchestrator < Sinatra::Base
  helpers do
    def ai_edit_for_request
      AiImageEdit.where(asset_id: params[:id]).find(params[:edit_id])
    end

    def ai_json
      content_type :json
      yield.to_json
    rescue ActiveRecord::RecordNotFound
      halt 404, {error: 'File o elaborazione non trovati'}.to_json
    rescue ArgumentError => e
      halt 422, {error: e.message}.to_json
    rescue StandardError
      halt 500, {error: 'Operazione non completata. Riprova o controlla lo stato dell’elaborazione.'}.to_json
    end
  end

  before '/assets/:id/ai-edits*' do
    if request.post? && request.env['HTTP_ORIGIN'] && request.env['HTTP_ORIGIN'] != request.base_url
      halt 403, 'Origine della richiesta non valida'
    end
  end

  get '/admin/ai-images' do
    @ai_settings = AiImageSettings.config
    @ai_configured = !AiImageSettings.api_key.empty?
    @ai_edits = AiImageEdit.order(id: :desc).limit(100)
    @ai_total = AiImageEdit.sum(:cost_usd)
    @ai_count = AiImageEdit.where.not(cost_usd: nil).count
    @ai_unknown = AiImageEdit.where(cost_usd: nil).count
    erb :ai_images_settings
  end

  post '/admin/ai-images' do
    halt 403 if request.env['HTTP_ORIGIN'] && request.env['HTTP_ORIGIN'] != request.base_url
    begin
      AiImageSettings.save!(params)
      redirect '/admin/ai-images?msg=success&text=Impostazioni+AI+salvate'
    rescue ArgumentError => e
      redirect "/admin/ai-images?msg=error&text=#{URI.encode_www_form_component(e.message)}"
    end
  end

  get '/assets/:id/ai-edits' do
    ai_json do
      asset = Asset.find(params[:id])
      edits = AiImageEdit.where(asset_id: asset.id).order(id: :desc).limit(20).map { |e| e.expire_if_stale!.public_data }
      {edits: edits, configured: !AiImageSettings.api_key.empty?, model: AiImageSettings.config['model']}
    end
  end

  post '/assets/:id/ai-edits' do
    ai_json do
      asset = Asset.find(params[:id])
      info = png_print_info(asset)
      edit = AiImageService.create!(asset,
        dpi: info && (info[:declared_dpi] || info[:target_dpi]) || 300,
        background: params.fetch('background', 'auto'))
      AiImageService.start!(edit)
      status 202
      edit.public_data
    end
  end

  get '/assets/:id/ai-edits/:edit_id' do
    ai_json { ai_edit_for_request.expire_if_stale!.public_data }
  end

  %w[source result].each do |kind|
    get "/assets/:id/ai-edits/:edit_id/#{kind}" do
      edit = ai_edit_for_request
      path = kind == 'source' ? edit.source_path : edit.result_path
      halt 404 unless File.file?(path)
      content_type 'image/png'
      send_file path, disposition: 'inline'
    end
  end

  post '/assets/:id/ai-edits/:edit_id/accept' do
    ai_json do
      AiImageService.accept!(ai_edit_for_request, allow_aspect_change: params['allow_aspect_change'] == '1').public_data
    end
  end

  post '/assets/:id/ai-edits/:edit_id/discard' do
    ai_json do
      edit = ai_edit_for_request
      edit.with_lock do
        raise ArgumentError, 'Elaborazione non scartabile' unless %w[ready discarded].include?(edit.status)
        edit.update!(status: 'discarded')
      end
      edit.public_data
    end
  end
end
