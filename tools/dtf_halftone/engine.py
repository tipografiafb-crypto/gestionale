import math
from pathlib import Path
from typing import Any, Dict, Optional, Tuple

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
    if config.tone_mode == "dtf_difference":
        # ActionSeps builds the separation from the untouched artwork. Colour
        # correction affects the printed RGB, not the mask calculation.
        output_alpha = _dtf_difference_alpha(rgb, alpha, config)
    elif config.tone_mode == "retino_am":
        output_alpha = _retino_am_alpha(adjusted_rgb, alpha, config)
    elif config.tone_mode == "photoshop_action":
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
            "min_dot_percent": config.min_dot_percent,
            "min_hole_percent": config.min_hole_percent,
            "max_coverage": config.max_coverage,
            "tone_mode": config.tone_mode,
        }
    )
    return info


def save_mask_preview(input_path: str, output_path: str, config: HalftoneConfig) -> Dict[str, Any]:
    config.validate()

    rgb, alpha = _load_rgba_arrays(input_path)
    adjusted_rgb = _adjust_rgb(rgb, config)

    if config.tone_mode == "dtf_difference":
        mask = _dtf_difference_tone(rgb, alpha, config)
    elif config.tone_mode == "retino_am":
        knockout_scale = _knockout_scale(adjusted_rgb, config)
        mask = _retino_am_coverage(adjusted_rgb, alpha * knockout_scale, config)
    elif config.tone_mode == "photoshop_action":
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
        if config.tone_mode == "retino_am":
            luminance = (
                (0.299 * adjusted[:, :, 0])
                + (0.587 * adjusted[:, :, 1])
                + (0.114 * adjusted[:, :, 2])
            )
            adjusted = luminance[:, :, None] + ((adjusted - luminance[:, :, None]) * config.saturation)
        else:
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


def _dtf_difference_tone(rgb: np.ndarray, alpha: np.ndarray, config: HalftoneConfig) -> np.ndarray:
    """Build the photographic DTF tone from the distance to the shirt colour.

    This mirrors the useful part of the Actionseps workflow: the garment colour
    is removed first, then the remaining colour difference becomes the printable
    tone.  It deliberately keeps RGB untouched; only the mask is transformed.
    """
    shirt_rgb = np.array(config.shirt_color or (0, 0, 0), dtype=np.float32)
    # #151515 is the UI's visible preview for a black garment. Treat very dark
    # garment swatches as technical black for the separation itself; otherwise
    # pure-black jackets look different from the swatch and get printed while
    # nearby chromatic blues are incorrectly removed.
    technical_black = np.max(shirt_rgb) <= 32.0
    if technical_black:
        shirt_rgb[:] = 0.0
    shirt = shirt_rgb / 255.0
    difference = np.abs(rgb - shirt.reshape(1, 1, 3))

    # Keep one authoritative tone curve for every garment.  Selecting a fabric
    # colour changes only the reference colour and its soft similarity guard;
    # it must not replace the proven black-shirt separation with another scale.
    tone = (
        (0.230 * difference[:, :, 0])
        + (0.520 * difference[:, :, 1])
        + (0.250 * difference[:, :, 2])
    )
    if config.invert:
        tone = 1.0 - tone
    tone = _apply_actionseps_levels(tone, config)

    if config.shirt_color is None or technical_black:
        # This is the established black-shirt transition.  Explicit black uses
        # this exact branch as well, guaranteeing parity with fabric disabled.
        colour_distance = np.max(difference, axis=2)
        garment_guard = _smoothstep(5.0 / 255.0, 48.0 / 255.0, colour_distance)
    else:
        # For coloured garments, use perceptual distance only as a broad soft
        # guard.  The weighted RGB difference above still drives the dots, so a
        # sampled shade and nearby shades fade together instead of jumping from
        # transparent to almost fully printed.
        source_lab = cv2.cvtColor((rgb * 255).astype(np.uint8), cv2.COLOR_RGB2LAB).astype(np.float32)
        target_u8 = np.clip(np.rint(shirt * 255.0), 0, 255).astype(np.uint8).reshape(1, 1, 3)
        target_lab = cv2.cvtColor(target_u8, cv2.COLOR_RGB2LAB).astype(np.float32)[0, 0]
        source_lab[:, :, 0] *= 100.0 / 255.0
        source_lab[:, :, 1:] -= 128.0
        target_lab[0] *= 100.0 / 255.0
        target_lab[1:] -= 128.0
        delta_e = np.linalg.norm(source_lab - target_lab.reshape(1, 1, 3), axis=2)
        garment_guard = _smoothstep(config.knockout_inner, config.knockout_outer, delta_e)

    tone = _protect_solid_tones(tone * garment_guard, config)
    return np.where(alpha > config.alpha_threshold, tone * alpha, 0.0).astype(np.float32)


def _protect_solid_tones(tone: np.ndarray, config: HalftoneConfig) -> np.ndarray:
    """Close only holes too small to survive, without changing intentional caps."""
    protected = np.clip(tone, 0.0, 1.0)
    allows_full_coverage = config.max_coverage >= (1.0 - 1e-6)
    output_can_reach_full = config.output_white >= (255.0 - 1e-6)
    if config.min_hole_percent > 0 and allows_full_coverage and output_can_reach_full:
        printed_area = _spot_area_coverage(protected, config.dot_shape)
        protected = np.where((1.0 - printed_area) < config.min_hole_percent, 1.0, protected)
    return np.minimum(protected, config.max_coverage).astype(np.float32)


def _spot_area_coverage(tone: np.ndarray, dot_shape: str) -> np.ndarray:
    """Return the approximate printed cell area produced by a tonal value."""
    value = np.clip(tone, 0.0, 1.0)
    if dot_shape in {"circle", "round"}:
        radius_squared = 2.0 * value
        inside_circle = (math.pi * radius_squared) / 4.0
        radius = np.sqrt(np.maximum(radius_squared, 1.0))
        corner_segment = (
            radius_squared * np.arccos(np.clip(1.0 / radius, 0.0, 1.0))
            - np.sqrt(np.maximum(radius_squared - 1.0, 0.0))
        )
        outside_circle = ((math.pi * radius_squared) - (4.0 * corner_segment)) / 4.0
        return np.where(value <= 0.5, inside_circle, outside_circle).astype(np.float32)
    # Other spot functions do not currently expose an analytical area mapping.
    # Their near-solid safeguard remains conservative and tone-based.
    return value.astype(np.float32)


def _apply_actionseps_levels(value: np.ndarray, config: HalftoneConfig) -> np.ndarray:
    black = config.mask_black / 255.0
    white = config.mask_white / 255.0
    normalized = np.clip((value - black) / max(white - black, 1e-6), 0.0, 1.0)
    adjusted = np.power(normalized, 1.0 / max(config.mask_gamma, 0.01))
    output_black = config.output_black / 255.0
    output_white = config.output_white / 255.0
    return (output_black + adjusted * (output_white - output_black)).astype(np.float32)


def _dtf_difference_alpha(rgb: np.ndarray, alpha: np.ndarray, config: HalftoneConfig) -> np.ndarray:
    tone = _dtf_difference_tone(rgb, alpha, config)
    # Actionseps-style screening: dot radius follows each pixel's tone instead
    # of averaging a whole cell. This preserves photographic transitions.
    mask = _dtf_radius_screen(tone, config)
    # Photoshop's DTX cleanup is a local Dust & Scratches / median operation.
    # It removes micro-dots without the very expensive full-image component scan.
    printable_mask = alpha > config.alpha_threshold
    return _dtf_cleanup(mask, printable_mask, config)


def _dtf_cleanup(mask: np.ndarray, printable_mask: np.ndarray, config: HalftoneConfig) -> np.ndarray:
    if config.min_dot_px <= 0:
        return ((mask >= 0.5) & printable_mask).astype(np.float32)

    minimum = config.min_dot_px
    kernel = max(3, int(round(minimum)))
    if kernel % 2 == 0:
        kernel += 1
    kernel = min(kernel, 7)
    binary = ((mask >= 0.5).astype(np.uint8) * 255)
    cleaned = cv2.medianBlur(binary, kernel) >= 128
    return (cleaned & printable_mask).astype(np.float32)


def _dtf_radius_screen(tone: np.ndarray, config: HalftoneConfig) -> np.ndarray:
    height, width = tone.shape
    cell_px = config.target_dpi / config.lpi
    if cell_px < 2:
        raise ValueError("lpi is too high for the selected target DPI")
    yy, xx = np.indices((height, width), dtype=np.float32)
    angle = math.radians(config.angle)
    cos_a, sin_a = math.cos(angle), math.sin(angle)
    xr = (xx * cos_a) - (yy * sin_a)
    yr = (xx * sin_a) + (yy * cos_a)
    local_x = (np.mod(xr, cell_px) / cell_px) * 2.0 - 1.0
    local_y = (np.mod(yr, cell_px) / cell_px) * 2.0 - 1.0
    printable_tone = np.clip(tone, 0.0, 1.0)

    # Photoshop's Round screen grows circular dots and, above the midpoint,
    # leaves shrinking round holes. It reaches full coverage at white.
    if config.dot_shape in {"circle", "round"}:
        # Preserve the established round-dot geometry in both fabric modes.
        threshold = _retino_am_spot_threshold(local_x, local_y, "round")
        return (printable_tone > threshold).astype(np.float32)

    radius = np.sqrt(printable_tone / math.pi) * cell_px
    local_x_px = local_x * (cell_px / 2.0)
    local_y_px = local_y * (cell_px / 2.0)
    if config.dot_shape == "line":
        inside = np.abs(local_y_px) <= (radius / np.sqrt(2.0))
    elif config.dot_shape == "ellipse":
        inside = ((local_x_px / np.maximum(radius * 1.45, 1e-6)) ** 2 +
                  (local_y_px / np.maximum(radius / 1.45, 1e-6)) ** 2) <= 1.0
    else:
        inside = (local_x_px * local_x_px + local_y_px * local_y_px) <= (radius * radius)
    return np.where(tone <= 0, 0.0, inside.astype(np.float32))


def _apply_mask_levels(value: np.ndarray, config: HalftoneConfig) -> np.ndarray:
    black = config.mask_black / 255.0
    white = config.mask_white / 255.0
    leveled = np.clip((value - black) / max(white - black, 1e-6), 0.0, 1.0)
    return np.power(leveled, config.mask_gamma).astype(np.float32)


def _retino_am_alpha(rgb: np.ndarray, alpha: np.ndarray, config: HalftoneConfig) -> np.ndarray:
    knockout_scale = _knockout_scale(rgb, config)
    effective_alpha = alpha * knockout_scale
    coverage = _retino_am_coverage(rgb, effective_alpha, config)
    screen_mask = _retino_am_screen_mask(coverage, config)
    printable_mask = effective_alpha > config.alpha_threshold
    return _enforce_min_dot_components(screen_mask, config, printable_mask)


def _retino_am_coverage(rgb: np.ndarray, alpha: np.ndarray, config: HalftoneConfig) -> np.ndarray:
    tone = _srgb_encoded_luminance(rgb) * alpha
    if config.invert:
        tone = 1.0 - tone

    black = config.mask_black / 255.0
    white = config.mask_white / 255.0
    span = max(white - black, 1e-6)
    leveled = (tone - black) / span
    clipped = np.clip(leveled, 0.0, 1.0)

    gamma = max(config.mask_gamma, 0.01)
    coverage = np.power(clipped, 1.0 / gamma)
    coverage = np.where(leveled <= 0.0, 0.0, coverage)
    coverage = np.where(leveled >= 1.0, 1.0, coverage)
    coverage = np.where(coverage < config.min_dot_percent, 0.0, coverage)
    coverage = np.where(coverage > (1.0 - config.min_hole_percent), 1.0, coverage)
    coverage = np.where((coverage > 0.0) & (coverage < 1.0), coverage * config.max_coverage, coverage)
    coverage = np.where(alpha > config.alpha_threshold, coverage, 0.0)
    return np.clip(coverage, 0.0, 1.0).astype(np.float32)


def _retino_am_screen_mask(coverage: np.ndarray, config: HalftoneConfig) -> np.ndarray:
    height, width = coverage.shape
    cell_px = config.target_dpi / config.lpi
    if cell_px < 2:
        raise ValueError("lpi is too high for the selected target DPI")

    yy, xx = np.indices((height, width), dtype=np.float32)
    angle = math.radians(config.angle)
    cos_a = math.cos(angle)
    sin_a = math.sin(angle)
    xr = (xx * cos_a) + (yy * sin_a)
    yr = (-xx * sin_a) + (yy * cos_a)

    local_x = (np.mod(xr / cell_px, 1.0) * 2.0) - 1.0
    local_y = (np.mod(yr / cell_px, 1.0) * 2.0) - 1.0
    threshold = _retino_am_spot_threshold(local_x, local_y, config.dot_shape)

    mask = coverage > threshold
    mask = np.where(coverage >= 1.0, True, mask)
    mask = np.where(coverage <= 0.0, False, mask)
    return mask.astype(np.float32)


def _enforce_min_dot_components(
    mask: np.ndarray, config: HalftoneConfig, printable_mask: Optional[np.ndarray] = None
) -> np.ndarray:
    if config.min_dot_px <= 0:
        return mask

    binary = (mask >= 0.5).astype(np.uint8)
    component_count, labels, stats, centroids = cv2.connectedComponentsWithStats(binary, connectivity=4)
    min_area = max(2, round(math.pi * config.min_dot_px * config.min_dot_px / 4.0))
    result = binary.copy()
    radius = config.min_dot_px / 2.0
    radius_int = math.ceil(radius)
    height, width = binary.shape

    for label in range(1, component_count):
        if stats[label, cv2.CC_STAT_AREA] >= min_area:
            continue

        result[labels == label] = 0
        if config.highlight_mode != "force":
            continue

        center_x, center_y = np.rint(centroids[label]).astype(int)
        y0 = max(0, center_y - radius_int)
        y1 = min(height, center_y + radius_int + 1)
        x0 = max(0, center_x - radius_int)
        x1 = min(width, center_x + radius_int + 1)
        yy, xx = np.ogrid[y0:y1, x0:x1]
        disk = ((xx - center_x) ** 2 + (yy - center_y) ** 2) <= radius * radius
        if printable_mask is not None:
            disk &= printable_mask[y0:y1, x0:x1]
        region = result[y0:y1, x0:x1]
        region[disk] = 1

    return result.astype(np.float32)


def _retino_am_spot_threshold(
    local_x: np.ndarray,
    local_y: np.ndarray,
    dot_shape: str,
    normalize_area: bool = False,
) -> np.ndarray:
    if dot_shape in {"circle", "round"}:
        raw = ((local_x * local_x) + (local_y * local_y)) * 0.5
        if normalize_area:
            radius_squared = 2.0 * np.clip(raw, 0.0, 1.0)
            inside_circle = (math.pi * radius_squared) / 4.0
            radius = np.sqrt(np.maximum(radius_squared, 1.0))
            corner_segment = (
                radius_squared * np.arccos(np.clip(1.0 / radius, 0.0, 1.0))
                - np.sqrt(np.maximum(radius_squared - 1.0, 0.0))
            )
            outside_circle = ((math.pi * radius_squared) - (4.0 * corner_segment)) / 4.0
            return np.where(raw <= 0.5, inside_circle, outside_circle).astype(np.float32)
        return np.clip(raw, 0.0, 1.0).astype(np.float32)
    if dot_shape == "ellipse":
        threshold = ((local_x * local_x / 1.55) + (local_y * local_y * 1.55)) * 0.5
        return np.clip(threshold, 0.0, 1.0).astype(np.float32)
    if dot_shape == "line":
        return np.abs(local_y).astype(np.float32)

    ax = np.abs(local_x)
    ay = np.abs(local_y)
    inside_diamond = (ax + ay) <= 1.0
    dot_part = 1.0 - ((local_x * local_x) + (local_y * local_y))
    hole_part = (((ax - 1.0) * (ax - 1.0)) + ((ay - 1.0) * (ay - 1.0))) - 1.0
    spot = np.where(inside_diamond, dot_part, hole_part)
    return ((1.0 - spot) * 0.5).astype(np.float32)


def _srgb_encoded_luminance(rgb: np.ndarray) -> np.ndarray:
    linear = _srgb_to_linear(rgb)
    luminance = (
        (0.2126 * linear[:, :, 0])
        + (0.7152 * linear[:, :, 1])
        + (0.0722 * linear[:, :, 2])
    )
    return _linear_to_srgb(luminance).astype(np.float32)


def _srgb_to_linear(value: np.ndarray) -> np.ndarray:
    return np.where(value <= 0.04045, value / 12.92, np.power((value + 0.055) / 1.055, 2.4))


def _linear_to_srgb(value: np.ndarray) -> np.ndarray:
    return np.where(value <= 0.0031308, value * 12.92, (1.055 * np.power(value, 1.0 / 2.4)) - 0.055)


def _apply_highlight_guard_to_reveal_mask(reveal_mask: np.ndarray, ink: np.ndarray, config: HalftoneConfig) -> np.ndarray:
    if config.min_dot_px <= 0:
        return reveal_mask

    cell_px = config.target_dpi / config.lpi
    expected_diameter = np.sqrt(np.clip(ink, 0.0, 1.0) / math.pi) * cell_px * 2.0
    too_small = (expected_diameter > 0) & (expected_diameter < config.min_dot_px)
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
    radius = _apply_min_dot(radius * 2.0, config) / 2.0

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
