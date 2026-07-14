import unittest

import numpy as np

from tools.dtf_halftone.config import HalftoneConfig
from tools.dtf_halftone.engine import _enforce_min_dot_components


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


if __name__ == "__main__":
    unittest.main()
