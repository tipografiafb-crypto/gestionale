ENV['DISABLE_BACKGROUND_POLLERS'] = '1'
require_relative '../app'
ActiveRecord::Base.logger = nil
AiImageService.generate!(Integer(ARGV.fetch(0)))
