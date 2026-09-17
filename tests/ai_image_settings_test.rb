require 'minitest/autorun'
require_relative '../services/ai_image_settings'

class AiImageSettingsTest < Minitest::Test
  def test_cost_uses_each_modality_rate
    usage = {'input_tokens_details' => {'text_tokens' => 200, 'image_tokens' => 1000}, 'output_tokens' => 4000}
    assert_equal BigDecimal('0.129'), AiImageSettings.cost(usage, AiImageSettings::DEFAULTS)
  end

  def test_cache_discount_is_applied_per_modality
    usage = {'input_tokens_details' => {'text_tokens' => 200, 'image_tokens' => 1000,
      'cached_tokens' => 600, 'cached_tokens_details' => {'text_tokens' => 100, 'image_tokens' => 500}}, 'output_tokens' => 4000}
    assert_equal BigDecimal('0.125625'), AiImageSettings.cost(usage, AiImageSettings::DEFAULTS)
  end

  def test_missing_usage_is_not_reported_as_free
    assert_nil AiImageSettings.cost({}, AiImageSettings::DEFAULTS)
    assert_nil AiImageSettings.cost({'input_tokens_details' => {'text_tokens'=>1, 'image_tokens'=>10, 'cached_tokens'=>5}, 'output_tokens'=>1}, AiImageSettings::DEFAULTS)
  end

  def test_configuration_and_secret_are_separate_and_private
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        AiImageSettings.save!('api_key' => 'sk-test-only', 'quality' => 'medium')
        assert_equal 'sk-test-only', AiImageSettings.api_key
        refute File.read(File.join(AiImageSettings.directory, 'settings.json')).include?('sk-test-only')
        assert_equal 0600, File.stat(File.join(AiImageSettings.directory, 'api_key')).mode & 0777
        AiImageSettings.save!('api_key' => '')
        assert_equal 'sk-test-only', AiImageSettings.api_key
        AiImageSettings.save!('remove_key' => '1')
        assert_equal '', AiImageSettings.api_key
      end
    end
  end
end
