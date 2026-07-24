#!/usr/bin/env python3
"""PDF helpers for the automation engine.

The module intentionally exposes a small CLI contract so the Ruby worker can
invoke it without shell interpolation.
"""

import argparse
import json
import math
from pathlib import Path

from PIL import Image
from pypdf import PdfReader, PdfWriter, Transformation
from pypdf._page import PageObject
from reportlab.graphics.barcode import code128
from reportlab.lib.units import mm
from reportlab.pdfgen import canvas


def image_to_pdf(
    input_path: str,
    output_path: str,
    dpi: float,
    width_mm: float = 0,
    height_mm: float = 0,
) -> dict:
    with Image.open(input_path) as image:
        width_px, height_px = image.size
        resize_applied = width_mm > 0 and height_mm > 0
        if resize_applied:
            width_pt = width_mm * mm
            height_pt = height_mm * mm
        else:
            width_pt = width_px * 72.0 / dpi
            height_pt = height_px * 72.0 / dpi

        pdf = canvas.Canvas(output_path, pagesize=(width_pt, height_pt))
        pdf.drawImage(
            input_path,
            0,
            0,
            width=width_pt,
            height=height_pt,
            preserveAspectRatio=True,
            mask="auto",
        )
        pdf.showPage()
        pdf.save()

    return {
        "page_width_pt": width_pt,
        "page_height_pt": height_pt,
        "source_width_px": width_px,
        "source_height_px": height_px,
        "dpi": dpi,
        "width_mm": width_mm if resize_applied else width_pt / mm,
        "height_mm": height_mm if resize_applied else height_pt / mm,
        "resize_applied": resize_applied,
    }


def duplicate_pages(input_path: str, output_path: str, copies: int) -> dict:
    reader = PdfReader(input_path)
    if not reader.pages:
        raise ValueError("Il PDF sorgente non contiene pagine")

    copies = max(1, int(copies))
    writer = PdfWriter()
    for _copy_index in range(copies):
        for page in reader.pages:
            writer.add_page(page)
        # Force independent page/content objects for the next repetition.
        # Reusing pypdf's translation cache can make later repeated pages blank
        # when they are subsequently merged into an imposed sheet.
        writer.reset_translation(reader)

    Path(output_path).parent.mkdir(parents=True, exist_ok=True)
    with open(output_path, "wb") as output_file:
        writer.write(output_file)

    return {
        "source_pages": len(reader.pages),
        "copies": copies,
        "output_pages": len(reader.pages) * copies,
    }


def merge_pages(input_paths: list[str], output_path: str) -> dict:
    if len(input_paths) < 2:
        raise ValueError("Servono almeno due PDF da unire")

    writer = PdfWriter()
    page_counts = []
    for input_path in input_paths:
        reader = PdfReader(input_path)
        if not reader.pages:
            raise ValueError(f"Il PDF {input_path} non contiene pagine")
        page_counts.append(len(reader.pages))
        for page in reader.pages:
            writer.add_page(page)
        writer.reset_translation(reader)

    Path(output_path).parent.mkdir(parents=True, exist_ok=True)
    with open(output_path, "wb") as output_file:
        writer.write(output_file)

    return {
        "input_files": len(input_paths),
        "input_page_counts": page_counts,
        "output_pages": sum(page_counts),
    }


def impose(input_path: str, output_path: str, config: dict) -> dict:
    reader = PdfReader(input_path)
    if not reader.pages:
        raise ValueError("Il PDF sorgente non contiene pagine")

    sheet_width = float(config["sheet_width_mm"]) * mm
    sheet_height = float(config["sheet_height_mm"]) * mm
    anchor = str(config.get("anchor", "top_left"))
    if anchor not in {"top_left", "top_right", "bottom_left", "bottom_right"}:
        raise ValueError(f"Punto di ancoraggio non valido: {anchor}")
    offset_x = float(config.get("offset_x_mm", 0)) * mm
    offset_y = float(config.get("offset_y_mm", 0)) * mm
    gap_x = float(config.get("gap_x_mm", 0)) * mm
    gap_y = float(config.get("gap_y_mm", 0)) * mm
    fill_last_sheet = bool(config.get("fill_last_sheet", False))
    rotate = bool(config.get("rotate", False))
    fixed_columns = int(config.get("columns", 0) or 0)
    fixed_rows = int(config.get("rows", 0) or 0)
    if fixed_columns < 0 or fixed_rows < 0:
        raise ValueError("Righe e colonne non possono essere negative")

    first_page = reader.pages[0]
    source_width = float(first_page.mediabox.width)
    source_height = float(first_page.mediabox.height)
    placed_width, placed_height = (
        (source_height, source_width) if rotate else (source_width, source_height)
    )
    for index, page in enumerate(reader.pages[1:], start=2):
        page_width = float(page.mediabox.width)
        page_height = float(page.mediabox.height)
        if abs(page_width - source_width) > 0.01 or abs(page_height - source_height) > 0.01:
            raise ValueError(
                f"La pagina {index} ha dimensioni diverse dalla prima pagina"
            )

    available_width = sheet_width - offset_x
    available_height = sheet_height - offset_y
    if placed_width > available_width or placed_height > available_height:
        raise ValueError(
            "L'oggetto non entra nel foglio con il punto di partenza configurato"
        )
    auto_columns = 1 + math.floor((available_width - placed_width) / (placed_width + gap_x))
    auto_rows = 1 + math.floor((available_height - placed_height) / (placed_height + gap_y))
    columns = fixed_columns or auto_columns
    rows = fixed_rows or auto_rows
    required_width = columns * placed_width + max(0, columns - 1) * gap_x
    required_height = rows * placed_height + max(0, rows - 1) * gap_y
    if required_width > available_width + 0.01 or required_height > available_height + 0.01:
        raise ValueError(
            f"La griglia richiesta {columns}x{rows} non entra nel foglio "
            f"({required_width / mm:.2f}x{required_height / mm:.2f} mm disponibili "
            f"{available_width / mm:.2f}x{available_height / mm:.2f} mm)"
        )
    slots_per_sheet = rows * columns
    input_pages = len(reader.pages)
    sheets = math.ceil(input_pages / slots_per_sheet)
    placements_total = sheets * slots_per_sheet if fill_last_sheet else input_pages
    writer = PdfWriter()

    for sheet_index in range(sheets):
        output_page = PageObject.create_blank_page(
            width=sheet_width, height=sheet_height
        )
        remaining = placements_total - sheet_index * slots_per_sheet
        placements_on_sheet = min(slots_per_sheet, remaining)

        for slot_index in range(placements_on_sheet):
            row = slot_index // columns
            column = slot_index % columns
            grows_left = anchor.endswith("right")
            grows_up = anchor.startswith("bottom")
            if grows_left:
                x = sheet_width - offset_x - placed_width - column * (
                    placed_width + gap_x
                )
            else:
                x = offset_x + column * (placed_width + gap_x)
            if grows_up:
                y = offset_y + row * (placed_height + gap_y)
            else:
                y = sheet_height - offset_y - placed_height - row * (
                    placed_height + gap_y
                )

            source = reader.pages[(sheet_index * slots_per_sheet + slot_index) % input_pages]

            if rotate:
                transform = (
                    Transformation()
                    .rotate(90)
                    .translate(x + placed_width, y)
                )
            else:
                transform = Transformation().translate(x, y)
            output_page.merge_transformed_page(source, transform, over=True)

        writer.add_page(output_page)

    Path(output_path).parent.mkdir(parents=True, exist_ok=True)
    with open(output_path, "wb") as output_file:
        writer.write(output_file)

    return {
        "sheet_width_mm": float(config["sheet_width_mm"]),
        "sheet_height_mm": float(config["sheet_height_mm"]),
        "anchor": anchor,
        "offset_x_mm": float(config.get("offset_x_mm", 0)),
        "offset_y_mm": float(config.get("offset_y_mm", 0)),
        "object_width_mm": round(placed_width / mm, 4),
        "object_height_mm": round(placed_height / mm, 4),
        "rows": rows,
        "columns": columns,
        "rows_mode": "fixed" if fixed_rows else "automatic",
        "columns_mode": "fixed" if fixed_columns else "automatic",
        "slots_per_sheet": slots_per_sheet,
        "input_pages": input_pages,
        "placed_pages": placements_total,
        "sheets": sheets,
        "scale": 1.0,
    }


def barcode_pdf(data: str, output_path: str, config: dict) -> dict:
    width_mm = float(config.get("width_mm", 70))
    height_mm = float(config.get("height_mm", 35))
    bar_height_mm = float(config.get("bar_height_mm", 18))
    quiet_mm = float(config.get("quiet_mm", 4))
    human_readable = bool(config.get("human_readable", True))

    pdf = canvas.Canvas(output_path, pagesize=(width_mm * mm, height_mm * mm))
    barcode = code128.Code128(
        data,
        barHeight=bar_height_mm * mm,
        barWidth=float(config.get("bar_width", 0.38)) * mm,
        humanReadable=human_readable,
        quiet=True,
    )
    x = max(quiet_mm * mm, (width_mm * mm - barcode.width) / 2)
    y = max(quiet_mm * mm, (height_mm * mm - barcode.height) / 2)
    barcode.drawOn(pdf, x, y)
    pdf.showPage()
    pdf.save()

    return {
        "data": data,
        "symbology": "Code 128",
        "width_mm": width_mm,
        "height_mm": height_mm,
    }


def inspect_pdf(input_path: str) -> dict:
    reader = PdfReader(input_path)
    pages = []
    for page in reader.pages:
        pages.append(
            {
                "width_pt": float(page.mediabox.width),
                "height_pt": float(page.mediabox.height),
            }
        )
    return {"page_count": len(pages), "pages": pages}


def parse_args():
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="command", required=True)

    image_parser = subparsers.add_parser("image-to-pdf")
    image_parser.add_argument("--input", required=True)
    image_parser.add_argument("--output", required=True)
    image_parser.add_argument("--dpi", type=float, default=300)
    image_parser.add_argument("--width-mm", type=float, default=0)
    image_parser.add_argument("--height-mm", type=float, default=0)

    impose_parser = subparsers.add_parser("impose")
    impose_parser.add_argument("--input", required=True)
    impose_parser.add_argument("--output", required=True)
    impose_parser.add_argument("--config", required=True)

    duplicate_parser = subparsers.add_parser("duplicate-pages")
    duplicate_parser.add_argument("--input", required=True)
    duplicate_parser.add_argument("--output", required=True)
    duplicate_parser.add_argument("--copies", required=True, type=int)

    merge_parser = subparsers.add_parser("merge-pages")
    merge_parser.add_argument("--input", required=True, action="append")
    merge_parser.add_argument("--output", required=True)

    barcode_parser = subparsers.add_parser("barcode")
    barcode_parser.add_argument("--data", required=True)
    barcode_parser.add_argument("--output", required=True)
    barcode_parser.add_argument("--config", default="{}")

    inspect_parser = subparsers.add_parser("inspect")
    inspect_parser.add_argument("--input", required=True)
    return parser.parse_args()


def main():
    args = parse_args()
    if args.command == "image-to-pdf":
        result = image_to_pdf(
            args.input,
            args.output,
            args.dpi,
            args.width_mm,
            args.height_mm,
        )
    elif args.command == "duplicate-pages":
        result = duplicate_pages(args.input, args.output, args.copies)
    elif args.command == "merge-pages":
        result = merge_pages(args.input, args.output)
    elif args.command == "impose":
        result = impose(args.input, args.output, json.loads(args.config))
    elif args.command == "barcode":
        result = barcode_pdf(args.data, args.output, json.loads(args.config))
    else:
        result = inspect_pdf(args.input)
    print(json.dumps(result, ensure_ascii=False))


if __name__ == "__main__":
    main()
