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
    highlight_mode: str = "drop"
    tone_mode: str = "alpha"
    saturation: float = 1.0
    contrast: float = 1.0
    brightness: float = 0.0
    shirt_color: Optional[RGBColor] = None
    knockout_strength: float = 0.0
    knockout_inner: float = 8.0
    knockout_outer: float = 45.0
    antialias_px: float = 0.0
    mask_black: float = 36.0
    mask_white: float = 245.0
    mask_gamma: float = 1.0
    alpha_threshold: float = 0.01

    def validate(self) -> None:
        if self.target_dpi <= 0:
            raise ValueError("target_dpi must be greater than 0")
        if self.lpi <= 0:
            raise ValueError("lpi must be greater than 0")
        if self.dot_shape not in {"circle", "ellipse", "line"}:
            raise ValueError("dot_shape must be circle, ellipse, or line")
        if self.highlight_mode not in {"drop", "force"}:
            raise ValueError("highlight_mode must be drop or force")
        if self.tone_mode not in {"alpha", "luminance", "combined", "photoshop_action"}:
            raise ValueError("tone_mode must be alpha, luminance, combined, or photoshop_action")
        if not 0 <= self.knockout_strength <= 1:
            raise ValueError("knockout_strength must be between 0 and 1")
        if self.knockout_outer <= self.knockout_inner:
            raise ValueError("knockout_outer must be greater than knockout_inner")
        if not 0 <= self.mask_black < self.mask_white <= 255:
            raise ValueError("mask_black and mask_white must be between 0 and 255, with black < white")
        if self.mask_gamma <= 0:
            raise ValueError("mask_gamma must be greater than 0")
