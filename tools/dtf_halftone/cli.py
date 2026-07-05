import argparse
import json
import math
import tempfile
from contextlib import contextmanager
from dataclasses import replace
from pathlib import Path
from typing import Iterator, Optional

from PIL import Image

from .config import HalftoneConfig, RGBColor
from .engine import process_image, read_image_info, save_mask_preview


def main() -> int:
    parser = argparse.ArgumentParser(description="Create a DTF halftone PNG without resizing pixels.")
    parser.add_argument("input", help="Input PNG path")
    parser.add_argument("output", nargs="?", help="Output PNG path")
    parser.add_argument("--info", action="store_true", help="Only print image size/DPI information")
    parser.add_argument("--mask-preview", action="store_true", help="Export the grayscale pre-halftone mask")
    parser.add_argument("--json", action="store_true", help="Print machine-readable JSON")
    parser.add_argument("--target-dpi", type=int, default=300)
    parser.add_argument("--lpi", type=float, default=35.0)
    parser.add_argument("--angle", type=float, default=22.5)
    parser.add_argument("--dot-shape", choices=["circle", "round", "euclid", "ellipse", "line"], default="circle")
    parser.add_argument("--min-dot-px", type=float, default=0.0)
    parser.add_argument("--min-dot-percent", type=float, default=6.0, help="Minimum printable dot coverage; accepts 6 or 0.06")
    parser.add_argument("--min-hole-percent", type=float, default=4.0, help="Minimum open hole coverage; accepts 4 or 0.04")
    parser.add_argument("--max-coverage", type=float, default=85.0, help="Maximum halftone coverage; accepts 85 or 0.85")
    parser.add_argument("--highlight-mode", choices=["drop", "force"], default="drop")
    parser.add_argument("--tone-mode", choices=["alpha", "luminance", "combined", "photoshop_action", "retino_am"], default="alpha")
    parser.add_argument("--invert", action="store_true", help="Invert tonal coverage before screening")
    parser.add_argument("--saturation", type=float, default=1.0)
    parser.add_argument("--contrast", type=float, default=1.0)
    parser.add_argument("--brightness", type=float, default=0.0)
    parser.add_argument("--shirt-color", type=parse_hex_color)
    parser.add_argument("--knockout-strength", type=float, default=0.0)
    parser.add_argument("--knockout-inner", type=float, default=8.0)
    parser.add_argument("--knockout-outer", type=float, default=45.0)
    parser.add_argument("--antialias-px", type=float, default=0.0)
    parser.add_argument("--mask-black", type=float, default=36.0)
    parser.add_argument("--mask-white", type=float, default=245.0)
    parser.add_argument("--mask-gamma", type=float, default=1.0)
    parser.add_argument("--resize-width-cm", type=float, default=0.0, help="Resize input width before halftone, interpreted at target DPI")
    parser.add_argument("--resize-height-cm", type=float, default=0.0, help="Resize input height before halftone, interpreted at target DPI")
    parser.add_argument("--preview-max-px", type=int, default=0, help="Resize input for fast preview; export remains full size")
    args = parser.parse_args()

    if args.info:
        info = read_image_info(args.input, args.target_dpi)
        _print_result(info, args.json)
        return 0

    if not args.output:
        parser.error("output is required unless --info is used")

    config = HalftoneConfig(
        target_dpi=args.target_dpi,
        lpi=args.lpi,
        angle=args.angle,
        dot_shape=args.dot_shape,
        min_dot_px=args.min_dot_px,
        min_dot_percent=_percent_to_fraction(args.min_dot_percent),
        min_hole_percent=_percent_to_fraction(args.min_hole_percent),
        max_coverage=_percent_to_fraction(args.max_coverage),
        highlight_mode=args.highlight_mode,
        tone_mode=args.tone_mode,
        invert=args.invert,
        saturation=args.saturation,
        contrast=args.contrast,
        brightness=args.brightness,
        shirt_color=args.shirt_color,
        knockout_strength=args.knockout_strength,
        knockout_inner=args.knockout_inner,
        knockout_outer=args.knockout_outer,
        antialias_px=args.antialias_px,
        mask_black=args.mask_black,
        mask_white=args.mask_white,
        mask_gamma=args.mask_gamma,
    )

    output_path = Path(args.output)
    output_path.parent.mkdir(parents=True, exist_ok=True)

    with _prepared_input(args.input, config, args.resize_width_cm, args.resize_height_cm) as prepared_input:
        if args.mask_preview:
            result = save_mask_preview(prepared_input, str(output_path), config)
        elif args.preview_max_px and args.preview_max_px > 0:
            result = _process_preview(prepared_input, str(output_path), config, args.preview_max_px)
        else:
            result = process_image(prepared_input, str(output_path), config)
    _print_result(result, args.json)
    return 0


@contextmanager
def _prepared_input(input_path: str, config: HalftoneConfig, width_cm: float, height_cm: float) -> Iterator[str]:
    requested_width = width_cm and width_cm > 0
    requested_height = height_cm and height_cm > 0
    if not requested_width and not requested_height:
        yield input_path
        return

    with Image.open(input_path).convert("RGBA") as image:
        width, height = image.size
        aspect = width / height

        target_width = round(width_cm / 2.54 * config.target_dpi) if requested_width else None
        target_height = round(height_cm / 2.54 * config.target_dpi) if requested_height else None

        if target_width is None and target_height is not None:
            target_width = round(target_height * aspect)
        if target_height is None and target_width is not None:
            target_height = round(target_width / aspect)

        target_width = max(1, int(target_width or width))
        target_height = max(1, int(target_height or height))

        if target_width == width and target_height == height:
            yield input_path
            return

        with tempfile.TemporaryDirectory() as tmpdir:
            resized_input = Path(tmpdir) / "resized_input.png"
            resampling = getattr(Image, "Resampling", Image).LANCZOS
            image.resize((target_width, target_height), resampling).save(
                resized_input,
                format="PNG",
                dpi=(config.target_dpi, config.target_dpi),
            )
            yield str(resized_input)


def _process_preview(input_path: str, output_path: str, config: HalftoneConfig, max_px: int) -> dict:
    with Image.open(input_path).convert("RGBA") as image:
        width, height = image.size
        scale = min(max_px / max(width, height), 1.0)

        with tempfile.TemporaryDirectory() as tmpdir:
            preview_input = Path(tmpdir) / "preview_input.png"
            preview_image = image
            if scale < 1.0:
                resampling = getattr(Image, "Resampling", Image).LANCZOS
                preview_image = image.resize((max(1, round(width * scale)), max(1, round(height * scale))), resampling)

            preview_dpi = max(math.ceil(config.lpi * 2.25), round(config.target_dpi * scale))
            preview_image.save(preview_input, format="PNG", dpi=(preview_dpi, preview_dpi))
            preview_config = replace(
                config,
                target_dpi=preview_dpi,
                min_dot_px=max(0.5, config.min_dot_px * scale),
            )
            result = process_image(str(preview_input), output_path, preview_config)

    result.update(
        {
            "preview": True,
            "preview_scale": scale,
            "source_width_px": width,
            "source_height_px": height,
            "source_target_dpi": config.target_dpi,
        }
    )
    return result


def parse_hex_color(value: Optional[str]) -> Optional[RGBColor]:
    if value is None or value == "":
        return None
    normalized = value.strip().lstrip("#")
    if len(normalized) != 6:
        raise argparse.ArgumentTypeError("color must be in #RRGGBB format")
    try:
        return tuple(int(normalized[i : i + 2], 16) for i in (0, 2, 4))  # type: ignore[return-value]
    except ValueError as exc:
        raise argparse.ArgumentTypeError("color must be in #RRGGBB format") from exc


def _percent_to_fraction(value: float) -> float:
    return value / 100.0 if value >= 1.0 else value


def _print_result(result: dict, as_json: bool) -> None:
    if as_json:
        print(json.dumps(result, indent=2, sort_keys=True))
        return

    print(f"Pixel: {result['width_px']} x {result['height_px']}")
    print(f"DPI dichiarato: {result['declared_dpi']}")
    print(f"DPI produzione: {result['target_dpi']}")
    print(f"Dimensione stampa: {result['print_width_cm']:.2f} x {result['print_height_cm']:.2f} cm")
    print("Ridimensionamento pixel: no")
    if "output_path" in result:
        print(f"Output: {result['output_path']}")


if __name__ == "__main__":
    raise SystemExit(main())
