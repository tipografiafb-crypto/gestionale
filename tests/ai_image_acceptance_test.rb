# Run against the configured database. All DB changes roll back; fixture files are temporary.
ENV['DISABLE_BACKGROUND_POLLERS'] = '1'
require_relative '../app'
require 'tmpdir'
ActiveRecord::Base.logger = nil

def check(condition, message)
  raise message unless condition
  puts "PASS: #{message}"
end

Dir.mktmpdir('ai-acceptance-') do |dir|
  ActiveRecord::Base.transaction do
    original = Asset.where("local_path LIKE ?", '%.png').detect(&:downloaded?)
    raise 'A PNG fixture is required' unless original
    source = File.join(dir, 'fixture.png')
    command = ImageEditService.imagemagick_command
    system(command, '-size', '2500x2500', 'xc:#579cc4', '-units', 'PixelsPerInch', '-density', '300', source) || raise('fixture failed')
    asset = original.dup
    asset.local_path = Pathname.new(source).relative_path_from(Pathname.new(Dir.pwd)).to_s
    asset.save!
    sha = Digest::SHA256.file(source).hexdigest
    edit = AiImageEdit.create!(asset: asset, status: 'ready', source_sha256: sha,
      options: AiImageSettings::DEFAULTS.merge('width'=>2500,'height'=>2500,'dpi'=>300,'result_width'=>1500,'result_height'=>1500))
    # Keep test-generated artifacts inside the temporary directory.
    edit.define_singleton_method(:directory) { dir }
    system(command, '-size', '1500x1500', 'xc:#58aacc', edit.result_path) || raise('fixture failed')
    AiImageService.accept!(edit)
    check(ImageEditService.png_dimensions(source) == [2500,2500], 'AI resized from 1500 to 2500 pixels')
    check(Digest::SHA256.file(ImageEditService.backup_path(asset)).hexdigest == sha, 'original backup is byte-identical')
    check(edit.status == 'accepted', 'acceptance recorded')
    req = Rack::MockRequest.new(PrintOrchestrator)
    response = req.post("http://localhost/assets/#{asset.id}/restore", params: {order_id: asset.order_item.order_id, item_id: asset.order_item_id})
    check(response.status == 302, "existing reset endpoint succeeds (#{response.status}: #{response.body[0,200]})")
    check(Digest::SHA256.file(source).hexdigest == sha, 'reset restores exact original bytes')
    # Stale proposals must never overwrite newer edits.
    edit.update!(status: 'ready', source_sha256: 'stale')
    begin
      AiImageService.accept!(edit)
      raise 'stale result accepted'
    rescue ArgumentError => e
      check(e.message.include?('modificato'), 'stale source rejected')
    end
    check(Digest::SHA256.file(source).hexdigest == sha, 'rejected proposal leaves source intact')
    edit.update!(status: 'ready', source_sha256: sha, options: edit.options.merge('result_width'=>1000))
    begin
      AiImageService.accept!(edit)
      raise 'aspect mismatch accepted'
    rescue ArgumentError => e
      check(e.message.include?('proporzioni'), 'aspect mismatch requires explicit acceptance')
    end
    raise ActiveRecord::Rollback
  end
end
