from dataclasses import dataclass
from typing import Optional, Tuple


RGBColor = Tuple[int, int, int]


@dataclass(frozen=True)
class HalftoneConfig:
    target_dpi: int = 300
    lpi: float = 35.0
    angle: float = 22.5
    dot_shape: str = "circle"
    min_dot_px: float = 0.0
    min_dot_percent: float = 0.06
    min_hole_percent: float = 0.04
    max_coverage: float = 1.0
    highlight_mode: str = "drop"
    tone_mode: str = "alpha"
    invert: bool = False
    saturation: float = 1.0
    contrast: float = 1.0
    brightness: float = 0.0
    shirt_color: Optional[RGBColor] = None
    knockout_strength: float = 0.0
    # CIE Lab (Delta E 76) transition: identical garment colours are fully
    # revealed, nearby colours fade in, and distant colours remain printable.
    knockout_inner: float = 3.0
    knockout_outer: float = 30.0
    antialias_px: float = 0.0
    mask_black: float = 36.0
    mask_white: float = 245.0
    mask_gamma: float = 1.0
    output_black: float = 0.0
    output_white: float = 255.0
    alpha_threshold: float = 0.01

    def validate(self) -> None:
        if self.target_dpi <= 0:
            raise ValueError("target_dpi must be greater than 0")
        if self.lpi <= 0:
            raise ValueError("lpi must be greater than 0")
        if self.dot_shape not in {"circle", "round", "euclid", "ellipse", "line"}:
            raise ValueError("dot_shape must be circle, round, euclid, ellipse, or line")
        if self.highlight_mode not in {"drop", "force"}:
            raise ValueError("highlight_mode must be drop or force")
        if self.tone_mode not in {"alpha", "luminance", "combined", "photoshop_action", "retino_am", "dtf_difference"}:
            raise ValueError("tone_mode must be alpha, luminance, combined, photoshop_action, retino_am, or dtf_difference")
        if not 0 <= self.min_dot_percent <= 1:
            raise ValueError("min_dot_percent must be between 0 and 1")
        if not 0 <= self.min_hole_percent <= 1:
            raise ValueError("min_hole_percent must be between 0 and 1")
        if not 0 <= self.max_coverage <= 1:
            raise ValueError("max_coverage must be between 0 and 1")
        if not 0 <= self.knockout_strength <= 1:
            raise ValueError("knockout_strength must be between 0 and 1")
        if self.knockout_inner < 0:
            raise ValueError("knockout_inner must be greater than or equal to 0")
        if self.knockout_outer <= self.knockout_inner:
            raise ValueError("knockout_outer must be greater than knockout_inner")
        if not 0 <= self.mask_black < self.mask_white <= 255:
            raise ValueError("mask_black and mask_white must be between 0 and 255, with black < white")
        if self.mask_gamma <= 0:
            raise ValueError("mask_gamma must be greater than 0")
        if not 0 <= self.output_black <= self.output_white <= 255:
            raise ValueError("output_black and output_white must be between 0 and 255, with black <= white")
