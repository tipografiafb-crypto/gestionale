import unittest

import numpy as np

from tools.dtf_halftone.config import HalftoneConfig
from tools.dtf_halftone.engine import (
    _dtf_difference_tone,
    _enforce_min_dot_components,
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
        config = HalftoneConfig(
            tone_mode="dtf_difference",
            shirt_color=shirt_color,
            mask_black=0,
            mask_white=255,
            knockout_inner=3,
            knockout_outer=30,
            **overrides,
        )
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

    def test_legacy_mode_ignores_garment_colour(self):
        rgb = np.array([[[0.9, 0.2, 0.1]]], dtype=np.float32)
        alpha = np.ones((1, 1), dtype=np.float32)
        base = HalftoneConfig(tone_mode="retino_am", max_coverage=1.0)
        coloured = HalftoneConfig(tone_mode="retino_am", shirt_color=(220, 30, 20), max_coverage=1.0)
        np.testing.assert_array_equal(
            _retino_am_coverage(rgb, alpha, base),
            _retino_am_coverage(rgb, alpha, coloured),
        )

    def test_round_spot_coverage_matches_requested_printed_area(self):
        axis = np.linspace(-1.0, 1.0, 1200, endpoint=False, dtype=np.float32)
        local_x, local_y = np.meshgrid(axis, axis)
        threshold = _retino_am_spot_threshold(local_x, local_y, "round")
        for requested in (0.15, 0.5, 0.85):
            with self.subTest(requested=requested):
                actual = np.mean(requested > threshold)
                self.assertAlmostEqual(float(actual), requested, delta=0.003)


if __name__ == "__main__":
    unittest.main()
