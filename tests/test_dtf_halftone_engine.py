import unittest

import numpy as np

from tools.dtf_halftone.config import HalftoneConfig
from tools.dtf_halftone.engine import (
    _choke_outer_alpha_fringe,
    _dtf_difference_alpha,
    _dtf_difference_tone,
    _enforce_min_dot_components,
    _protect_solid_tones,
    _retino_am_coverage,
    _retino_am_spot_threshold,
)


class EnforceMinDotComponentsTest(unittest.TestCase):
    def test_disabled_returns_mask_unchanged(self):
        mask = np.zeros((8, 8), dtype=np.float32)
        mask[2, 2] = 1

        result = _enforce_min_dot_components(mask, HalftoneConfig(min_dot_px=0))

        np.testing.assert_array_equal(result, mask)

    def test_drop_removes_only_components_below_minimum_area(self):
        mask = np.zeros((12, 12), dtype=np.float32)
        mask[1, 1] = 1
        mask[6:9, 6:9] = 1
        config = HalftoneConfig(min_dot_px=3, highlight_mode="drop")

        result = _enforce_min_dot_components(mask, config)

        self.assertEqual(result[1, 1], 0)
        self.assertEqual(int(result[6:9, 6:9].sum()), 9)

    def test_force_replaces_small_component_with_minimum_disk(self):
        mask = np.zeros((12, 12), dtype=np.float32)
        mask[5, 5] = 1
        config = HalftoneConfig(min_dot_px=3, highlight_mode="force")

        result = _enforce_min_dot_components(mask, config)

        self.assertEqual(int(result.sum()), 9)
        self.assertEqual(result[5, 5], 1)

    def test_force_does_not_grow_outside_printable_pixels(self):
        mask = np.zeros((12, 12), dtype=np.float32)
        mask[5, 5] = 1
        printable = np.zeros((12, 12), dtype=bool)
        printable[5, 4:7] = True
        config = HalftoneConfig(min_dot_px=3, highlight_mode="force")

        result = _enforce_min_dot_components(mask, config, printable)

        self.assertEqual(int(result.sum()), 3)
        np.testing.assert_array_equal(result[5, 4:7], np.ones(3, dtype=np.float32))


class DtfGarmentTransitionTest(unittest.TestCase):
    @staticmethod
    def tone_for(colors, shirt_color, **overrides):
        rgb = np.asarray(colors, dtype=np.float32).reshape(1, -1, 3) / 255.0
        alpha = np.ones((1, len(colors)), dtype=np.float32)
        settings = dict(
            tone_mode="dtf_difference",
            shirt_color=shirt_color,
            mask_black=0,
            mask_white=255,
            knockout_inner=3,
            knockout_outer=30,
        )
        settings.update(overrides)
        config = HalftoneConfig(**settings)
        return _dtf_difference_tone(rgb, alpha, config)[0]

    def test_exact_garment_colour_is_transparent_for_common_bases(self):
        for shirt_color in ((0, 0, 0), (255, 255, 255), (190, 30, 35), (20, 140, 70)):
            with self.subTest(shirt_color=shirt_color):
                tone = self.tone_for([shirt_color], shirt_color)
                self.assertAlmostEqual(float(tone[0]), 0.0, places=6)

    def test_similar_colours_fade_in_instead_of_using_a_binary_cut(self):
        shirt = (20, 140, 70)
        exact, near, medium, far = self.tone_for(
            [shirt, (28, 148, 78), (40, 160, 90), (220, 40, 180)], shirt
        )
        self.assertEqual(float(exact), 0.0)
        self.assertGreater(float(near), 0.0)
        self.assertLess(float(near), float(medium))
        self.assertLess(float(medium), float(far))

    def test_sampled_green_also_removes_a_nearby_background_shade(self):
        sampled = (13, 115, 51)
        nearby_background = (4, 120, 44)
        near, far = self.tone_for(
            [nearby_background, (235, 35, 30)],
            sampled,
            mask_black=5,
            mask_white=100,
        )

        self.assertLess(float(near), 0.05)
        self.assertGreater(float(far), 0.95)

    def test_explicit_black_matches_fabric_disabled(self):
        rng = np.random.default_rng(42)
        rgb = rng.random((48, 64, 3), dtype=np.float32)
        alpha = np.ones((48, 64), dtype=np.float32)
        common = dict(
            tone_mode="dtf_difference",
            target_dpi=300,
            lpi=30,
            angle=22.5,
            dot_shape="round",
            mask_black=5,
            mask_white=100,
            mask_gamma=1.0,
        )
        disabled = HalftoneConfig(**common)
        black = HalftoneConfig(**common, shirt_color=(21, 21, 21))

        np.testing.assert_array_equal(
            _dtf_difference_tone(rgb, alpha, disabled),
            _dtf_difference_tone(rgb, alpha, black),
        )
        np.testing.assert_array_equal(
            _dtf_difference_alpha(rgb, alpha, disabled),
            _dtf_difference_alpha(rgb, alpha, black),
        )

    def test_difference_uses_photoshop_grayscale_weights(self):
        tone = self.tone_for(
            [(255, 0, 0), (0, 255, 0), (0, 0, 255)],
            (0, 0, 0),
            min_hole_percent=0,
        )

        np.testing.assert_allclose(tone, [0.299, 0.587, 0.114], atol=1e-6)

    def test_source_alpha_is_flattened_before_levels(self):
        rgb = np.ones((5, 5, 3), dtype=np.float32)
        alpha = np.ones((5, 5), dtype=np.float32)
        alpha[2, 2] = 0.10
        alpha[2, 3] = 0.02
        config = HalftoneConfig(
            tone_mode="dtf_difference",
            shirt_color=(0, 0, 0),
            mask_black=9,
            mask_white=28,
            min_hole_percent=0,
        )

        tone = _dtf_difference_tone(rgb, alpha, config)

        expected_middle = ((0.10 - (9.0 / 255.0)) / ((28.0 - 9.0) / 255.0))
        np.testing.assert_allclose(
            [tone[0, 0], tone[2, 2], tone[2, 3]],
            [1.0, expected_middle, 0.0],
            atol=1e-6,
        )

    def test_final_dtf_mask_is_strictly_binary(self):
        rgb = np.full((32, 64, 3), (184, 115, 51), dtype=np.float32) / 255.0
        alpha = np.tile(np.linspace(0.0, 1.0, 64, dtype=np.float32), (32, 1))
        config = HalftoneConfig(
            tone_mode="dtf_difference",
            shirt_color=(0, 0, 0),
            target_dpi=300,
            lpi=30,
            angle=22,
            dot_shape="round",
            mask_black=9,
            mask_white=28,
            min_hole_percent=0,
        )

        result = _dtf_difference_alpha(rgb, alpha, config)

        self.assertTrue(set(np.unique(result)).issubset({0.0, 1.0}))

    def test_outer_alpha_choke_removes_only_the_faint_external_fringe(self):
        alpha = np.zeros((7, 7), dtype=np.float32)
        alpha[1:6, 1:6] = 0.8
        alpha[1, 1:6] = 0.3
        alpha[5, 1:6] = 0.3
        alpha[1:6, 1] = 0.3
        alpha[1:6, 5] = 0.3
        alpha[3, 3] = 0.3

        result = _choke_outer_alpha_fringe(alpha, 0.01)

        self.assertTrue(np.all(result[1, 1:6] == 0.0))
        self.assertTrue(np.all(result[5, 1:6] == 0.0))
        self.assertAlmostEqual(float(result[3, 3]), 0.3, places=6)
        self.assertAlmostEqual(float(result[2, 2]), 0.8, places=6)

    def test_outer_alpha_choke_never_changes_opaque_image_pixels(self):
        alpha = np.ones((12, 18), dtype=np.float32)

        result = _choke_outer_alpha_fringe(alpha, 0.01)

        np.testing.assert_array_equal(result, alpha)

    def test_maximum_coverage_caps_every_garment_colour(self):
        cap = 0.72
        for shirt_color, artwork in (
            ((0, 0, 0), (255, 255, 255)),
            ((255, 255, 255), (0, 0, 0)),
            ((20, 140, 70), (220, 40, 180)),
        ):
            with self.subTest(shirt_color=shirt_color):
                tone = self.tone_for([artwork], shirt_color, max_coverage=cap)
                self.assertLessEqual(float(tone[0]), cap + 1e-6)

    def test_default_global_coverage_keeps_distant_solids_full(self):
        tone = self.tone_for([(255, 255, 255)], (0, 0, 0), max_coverage=1.0)
        self.assertAlmostEqual(float(tone[0]), 1.0, places=6)

    def test_unprintable_holes_are_closed_only_near_full_coverage(self):
        tone = np.array([0.50, 0.70, 0.75, 0.90, 1.0], dtype=np.float32)
        config = HalftoneConfig(
            min_hole_percent=0.04,
            max_coverage=1.0,
            output_white=255,
            dot_shape="round",
        )

        result = _protect_solid_tones(tone, config)

        np.testing.assert_allclose(result, [0.50, 0.70, 1.0, 1.0, 1.0], atol=1e-6)

    def test_solid_protection_respects_intentional_coverage_cap(self):
        tone = np.array([0.97, 1.0], dtype=np.float32)
        config = HalftoneConfig(min_hole_percent=0.04, max_coverage=0.91, output_white=255)

        result = _protect_solid_tones(tone, config)

        np.testing.assert_allclose(result, [0.91, 0.91], atol=1e-6)

    def test_solid_protection_respects_output_white(self):
        tone = np.array([0.97, 0.99], dtype=np.float32)
        config = HalftoneConfig(min_hole_percent=0.04, max_coverage=1.0, output_white=250)

        result = _protect_solid_tones(tone, config)

        np.testing.assert_allclose(result, tone, atol=1e-6)

    def test_legacy_mode_ignores_garment_colour(self):
        rgb = np.array([[[0.9, 0.2, 0.1]]], dtype=np.float32)
        alpha = np.ones((1, 1), dtype=np.float32)
        base = HalftoneConfig(tone_mode="retino_am", max_coverage=1.0)
        coloured = HalftoneConfig(tone_mode="retino_am", shirt_color=(220, 30, 20), max_coverage=1.0)
        np.testing.assert_array_equal(
            _retino_am_coverage(rgb, alpha, base),
            _retino_am_coverage(rgb, alpha, coloured),
        )

    def test_normalized_round_spot_coverage_matches_requested_printed_area(self):
        axis = np.linspace(-1.0, 1.0, 1200, endpoint=False, dtype=np.float32)
        local_x, local_y = np.meshgrid(axis, axis)
        threshold = _retino_am_spot_threshold(local_x, local_y, "round", normalize_area=True)
        for requested in (0.15, 0.5, 0.85):
            with self.subTest(requested=requested):
                actual = np.mean(requested > threshold)
                self.assertAlmostEqual(float(actual), requested, delta=0.003)


if __name__ == "__main__":
    unittest.main()
