class AiImageEdit < ActiveRecord::Base
  belongs_to :asset, optional: true

  def directory
    File.join(Dir.pwd, 'storage', 'ai_image_edits', id.to_s)
  end

  def source_path
    File.join(directory, 'source.png')
  end

  def result_path
    File.join(directory, 'result.png')
  end

  def expire_if_stale!
    if %w[queued processing].include?(status) && updated_at < 20.minutes.ago
      update!(status: 'failed', error_message: 'Elaborazione interrotta. Il costo non è disponibile: controllare il consumo OpenAI prima di riprovare.')
    end
    self
  end

  def public_data
    {
      id: id, status: status, cost_usd: cost_usd&.to_s('F'), usage: usage,
      error: error_message, model: options['model'], quality: options['quality'],
      width: options['width'], height: options['height'], dpi: options['dpi'],
      result_width: options['result_width'], result_height: options['result_height'],
      source_url: "/assets/#{asset_id}/ai-edits/#{id}/source",
      result_url: "/assets/#{asset_id}/ai-edits/#{id}/result",
      created_at: created_at.iso8601, accepted_at: accepted_at&.iso8601
    }
  end
end
