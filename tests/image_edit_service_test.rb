require 'minitest/autorun'
require_relative '../services/image_edit_service'

class ImageEditServiceTest < Minitest::Test
  def png(width, height)
    ImageEditService::PNG_SIGNATURE + [13].pack('N') + 'IHDR' + [width, height].pack('NN') + "\x08\x06\x00\x00\x00".b
  end

  def base_recipe(mode: 'fixed')
    {
      'mode' => mode,
      'source_width' => 1000,
      'source_height' => 1000,
      'image_left' => 540,
      'image_top' => 480,
      'scale' => 1.25,
      'offset_x' => 40,
      'offset_y' => -20,
      'dpi' => 300
    }
  end

  def test_reads_png_dimensions_from_binary
    assert_equal [1000, 800], ImageEditService.png_dimensions(png(1000, 800))
  end

  def test_fixed_mode_requires_original_output_dimensions
    recipe = ImageEditService.normalize_recipe(
      base_recipe,
      output_dimensions: [1000, 1000],
      source_dimensions: [1000, 1000]
    )

    assert_equal 'fixed', recipe['mode']
    assert_equal [1000, 1000], [recipe['output_width'], recipe['output_height']]

    error = assert_raises(ArgumentError) do
      ImageEditService.normalize_recipe(
        base_recipe,
        output_dimensions: [900, 1000],
        source_dimensions: [1000, 1000]
      )
    end
    assert_match(/conservare esattamente/, error.message)
  end

  def test_crop_mode_accepts_a_smaller_canvas
    raw = base_recipe(mode: 'crop').merge(
      'crop' => {'x' => 100, 'y' => 200, 'width' => 400, 'height' => 300}
    )
    recipe = ImageEditService.normalize_recipe(
      raw,
      output_dimensions: [400, 300],
      source_dimensions: [1000, 1000]
    )

    assert_equal 'crop', recipe['mode']
    assert_equal({'x' => 100, 'y' => 200, 'width' => 400, 'height' => 300}, recipe['crop'])
  end

  def test_crop_must_stay_inside_original_canvas
    raw = base_recipe(mode: 'crop').merge(
      'crop' => {'x' => 800, 'y' => 0, 'width' => 400, 'height' => 300}
    )

    error = assert_raises(ArgumentError) do
      ImageEditService.normalize_recipe(
        raw,
        output_dimensions: [400, 300],
        source_dimensions: [1000, 1000]
      )
    end
    assert_match(/dentro il formato originale/, error.message)
  end
end
