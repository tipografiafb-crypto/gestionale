import math
from pathlib import Path
from typing import Any, Dict, Tuple

import cv2
import numpy as np
from PIL import Image

from .config import HalftoneConfig, RGBColor


def read_image_info(path: str, target_dpi: int = 300) -> Dict[str, Any]:
    image_path = Path(path)
    with Image.open(image_path) as image:
        width, height = image.size
        declared_dpi = image.info.get("dpi")

    return {
        "path": str(image_path),
        "width_px": width,
        "height_px": height,
        "declared_dpi": declared_dpi,
        "target_dpi": target_dpi,
        "print_width_cm": width / target_dpi * 2.54,
        "print_height_cm": height / target_dpi * 2.54,
        "will_resize": False,
    }


def process_image(input_path: str, output_path: str, config: HalftoneConfig) -> Dict[str, Any]:
    config.validate()

    rgb, alpha = _load_rgba_arrays(input_path)

    adjusted_rgb = _adjust_rgb(rgb, config)
    if config.tone_mode == "photoshop_action":
        output_alpha = _photoshop_action_alpha(adjusted_rgb, alpha, config)
        output_alpha = np.clip(output_alpha * _knockout_scale(adjusted_rgb, config), 0.0, 1.0)
    else:
        knockout_scale = _knockout_scale(adjusted_rgb, config)
        effective_alpha = alpha * knockout_scale
        coverage = _coverage(adjusted_rgb, effective_alpha, config)

        dot_mask = _halftone_mask(coverage, config)
        output_alpha = np.clip(effective_alpha * dot_mask, 0.0, 1.0)

    output_alpha = _finalize_output_alpha(output_alpha, config)

    output = np.dstack((adjusted_rgb, output_alpha))
    output_u8 = np.clip(output * 255.0, 0, 255).astype(np.uint8)

    output_image = Image.fromarray(output_u8, mode="RGBA")
    output_image.save(output_path, format="PNG", dpi=(config.target_dpi, config.target_dpi))

    info = read_image_info(input_path, config.target_dpi)
    info.update(
        {
            "output_path": str(output_path),
            "cell_px": config.target_dpi / config.lpi,
            "lpi": config.lpi,
            "angle": config.angle,
            "dot_shape": config.dot_shape,
            "min_dot_px": config.min_dot_px,
        }
    )
    return info


def save_mask_preview(input_path: str, output_path: str, config: HalftoneConfig) -> Dict[str, Any]:
    config.validate()

    rgb, alpha = _load_rgba_arrays(input_path)
    adjusted_rgb = _adjust_rgb(rgb, config)

    if config.tone_mode == "photoshop_action":
        mask = _photoshop_action_reveal_tone(adjusted_rgb, alpha, config)
        mask = np.clip(mask * _knockout_scale(adjusted_rgb, config), 0.0, 1.0)
    else:
        knockout_scale = _knockout_scale(adjusted_rgb, config)
        effective_alpha = alpha * knockout_scale
        mask = np.clip(1.0 - _coverage(adjusted_rgb, effective_alpha, config), 0.0, 1.0)

    mask_u8 = np.clip(mask * 255.0, 0, 255).astype(np.uint8)
    output_image = Image.fromarray(np.dstack((mask_u8, mask_u8, mask_u8)), mode="RGB")
    output_image.save(output_path, format="PNG", dpi=(config.target_dpi, config.target_dpi))

    info = read_image_info(input_path, config.target_dpi)
    info.update({"output_path": str(output_path), "mask_preview": True})
    return info


def _load_rgba_arrays(input_path: str) -> Tuple[np.ndarray, np.ndarray]:
    image = Image.open(input_path).convert("RGBA")
    rgba = np.asarray(image).astype(np.float32) / 255.0
    return rgba[:, :, :3], rgba[:, :, 3]


def _finalize_output_alpha(alpha: np.ndarray, config: HalftoneConfig) -> np.ndarray:
    if config.antialias_px > 0:
        return alpha
    return (alpha >= 0.5).astype(np.float32)


def _adjust_rgb(rgb: np.ndarray, config: HalftoneConfig) -> np.ndarray:
    adjusted = np.clip(rgb, 0.0, 1.0)

    if config.saturation != 1.0:
        hsv = cv2.cvtColor((adjusted * 255).astype(np.uint8), cv2.COLOR_RGB2HSV).astype(np.float32)
        hsv[:, :, 1] = np.clip(hsv[:, :, 1] * config.saturation, 0, 255)
        adjusted = cv2.cvtColor(hsv.astype(np.uint8), cv2.COLOR_HSV2RGB).astype(np.float32) / 255.0

    if config.contrast != 1.0 or config.brightness != 0.0:
        adjusted = (adjusted - 0.5) * config.contrast + 0.5 + (config.brightness / 255.0)

    return np.clip(adjusted, 0.0, 1.0)


def _knockout_scale(rgb: np.ndarray, config: HalftoneConfig) -> np.ndarray:
    if config.shirt_color is None or config.knockout_strength <= 0:
        return np.ones(rgb.shape[:2], dtype=np.float32)

    lab = cv2.cvtColor((rgb * 255).astype(np.uint8), cv2.COLOR_RGB2LAB).astype(np.float32)
    target = np.array(config.shirt_color, dtype=np.uint8).reshape(1, 1, 3)
    target_lab = cv2.cvtColor(target, cv2.COLOR_RGB2LAB).astype(np.float32)[0, 0]

    distance = np.linalg.norm(lab - target_lab, axis=2)
    similarity = 1.0 - _smoothstep(config.knockout_inner, config.knockout_outer, distance)
    return np.clip(1.0 - (config.knockout_strength * similarity), 0.0, 1.0).astype(np.float32)


def _coverage(rgb: np.ndarray, alpha: np.ndarray, config: HalftoneConfig) -> np.ndarray:
    if config.tone_mode == "alpha":
        coverage = alpha
    else:
        luminance = (0.2126 * rgb[:, :, 0]) + (0.7152 * rgb[:, :, 1]) + (0.0722 * rgb[:, :, 2])
        ink = 1.0 - luminance
        coverage = ink * alpha if config.tone_mode == "combined" else ink

    coverage = np.where(alpha > config.alpha_threshold, coverage, 0.0)
    return np.clip(coverage, 0.0, 1.0).astype(np.float32)


def _photoshop_action_alpha(rgb: np.ndarray, alpha: np.ndarray, config: HalftoneConfig) -> np.ndarray:
    # Photoshop action reference:
    # Difference against a near-black shirt layer, grayscale, Bitmap > Halftone Screen,
    # then paste that bitmap into a layer mask. Black bitmap pixels hide the original.
    reveal_tone = _photoshop_action_reveal_tone(rgb, alpha, config)
    ink = 1.0 - reveal_tone
    ink = np.where(alpha > config.alpha_threshold, ink * alpha, 0.0).astype(np.float32)

    black_bitmap = _halftone_mask(ink, config)
    if config.antialias_px <= 0:
        black_bitmap = (black_bitmap >= 0.5).astype(np.float32)

    reveal_mask = 1.0 - black_bitmap
    reveal_mask = _apply_highlight_guard_to_reveal_mask(reveal_mask, ink, config)
    return np.clip(alpha * reveal_mask, 0.0, 1.0).astype(np.float32)


def _photoshop_action_reveal_tone(rgb: np.ndarray, alpha: np.ndarray, config: HalftoneConfig) -> np.ndarray:
    shirt = np.array(config.shirt_color or (3, 2, 7), dtype=np.float32) / 255.0
    difference = np.abs(rgb - shirt.reshape(1, 1, 3))
    diff_luminance = (
        (0.2126 * difference[:, :, 0])
        + (0.7152 * difference[:, :, 1])
        + (0.0722 * difference[:, :, 2])
    )
    reveal_tone = _apply_mask_levels(diff_luminance, config)
    return np.where(alpha > config.alpha_threshold, reveal_tone * alpha, 0.0).astype(np.float32)


def _apply_mask_levels(value: np.ndarray, config: HalftoneConfig) -> np.ndarray:
    black = config.mask_black / 255.0
    white = config.mask_white / 255.0
    leveled = np.clip((value - black) / max(white - black, 1e-6), 0.0, 1.0)
    return np.power(leveled, config.mask_gamma).astype(np.float32)


def _apply_highlight_guard_to_reveal_mask(reveal_mask: np.ndarray, ink: np.ndarray, config: HalftoneConfig) -> np.ndarray:
    if config.min_dot_px <= 0:
        return reveal_mask

    cell_px = config.target_dpi / config.lpi
    expected_radius = np.sqrt(np.clip(ink, 0.0, 1.0) / math.pi) * cell_px
    too_small = (expected_radius > 0) & (expected_radius < config.min_dot_px)
    if config.highlight_mode == "drop":
        return np.where(too_small, 1.0, reveal_mask)
    return reveal_mask


def _halftone_mask(coverage: np.ndarray, config: HalftoneConfig) -> np.ndarray:
    height, width = coverage.shape
    cell_px = config.target_dpi / config.lpi
    if cell_px < 2:
        raise ValueError("lpi is too high for the selected target DPI")

    xx, yy = np.meshgrid(np.arange(width, dtype=np.float32), np.arange(height, dtype=np.float32))
    xx -= width / 2.0
    yy -= height / 2.0

    angle = math.radians(config.angle)
    cos_a = math.cos(angle)
    sin_a = math.sin(angle)
    xr = (xx * cos_a) + (yy * sin_a)
    yr = (-xx * sin_a) + (yy * cos_a)

    cell_x = np.floor(xr / cell_px).astype(np.int32)
    cell_y = np.floor(yr / cell_px).astype(np.int32)
    min_x = int(cell_x.min())
    min_y = int(cell_y.min())
    nx = int(cell_x.max() - min_x + 1)

    cell_ids = ((cell_y - min_y) * nx + (cell_x - min_x)).ravel()
    flat_coverage = coverage.ravel()
    sums = np.bincount(cell_ids, weights=flat_coverage)
    counts = np.bincount(cell_ids)
    means = sums / np.maximum(counts, 1)
    cell_coverage = means[cell_ids].reshape(height, width).astype(np.float32)

    local_x = ((xr / cell_px) - np.floor(xr / cell_px) - 0.5) * cell_px
    local_y = ((yr / cell_px) - np.floor(yr / cell_px) - 0.5) * cell_px

    if config.dot_shape == "line":
        return _line_mask(local_y, cell_coverage, cell_px, config)

    radius = np.sqrt(cell_coverage / math.pi) * cell_px
    radius = _apply_min_dot(radius, config)

    if config.dot_shape == "ellipse":
        aspect = 1.8
        a = radius * math.sqrt(aspect)
        b = radius / math.sqrt(aspect)
        signed_distance = 1.0 - np.sqrt(((local_x / np.maximum(a, 1e-6)) ** 2) + ((local_y / np.maximum(b, 1e-6)) ** 2))
        edge_px = np.minimum(a, b) * signed_distance
    else:
        distance = np.sqrt((local_x * local_x) + (local_y * local_y))
        edge_px = radius - distance

    return _edge_to_alpha(edge_px, config.antialias_px)


def _line_mask(local_y: np.ndarray, coverage: np.ndarray, cell_px: float, config: HalftoneConfig) -> np.ndarray:
    line_width = coverage * cell_px
    line_width = _apply_min_dot(line_width, config)
    edge_px = (line_width / 2.0) - np.abs(local_y)
    return _edge_to_alpha(edge_px, config.antialias_px)


def _apply_min_dot(size_px: np.ndarray, config: HalftoneConfig) -> np.ndarray:
    active = size_px > 0
    too_small = active & (size_px < config.min_dot_px)
    if config.highlight_mode == "drop":
        return np.where(too_small, 0.0, size_px)
    return np.where(too_small, config.min_dot_px, size_px)


def _edge_to_alpha(edge_px: np.ndarray, antialias_px: float) -> np.ndarray:
    if antialias_px <= 0:
        return (edge_px >= 0).astype(np.float32)
    return np.clip((edge_px + antialias_px) / (2.0 * antialias_px), 0.0, 1.0).astype(np.float32)


def _smoothstep(edge0: float, edge1: float, value: np.ndarray) -> np.ndarray:
    t = np.clip((value - edge0) / (edge1 - edge0), 0.0, 1.0)
    return t * t * (3.0 - (2.0 * t))
