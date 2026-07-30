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
from pypdf.generic import RectangleObject
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


def insert_blank_pages(input_path: str, output_path: str, config: dict) -> dict:
    reader = PdfReader(input_path)
    if not reader.pages:
        raise ValueError("Il PDF sorgente non contiene pagine")

    rules = config.get("rules", [])
    if not isinstance(rules, list):
        raise ValueError("Le regole delle pagine vuote non sono valide")

    input_pages = len(reader.pages)
    side_page_counts = config.get("side_page_counts")
    if side_page_counts is not None:
        if (
            not isinstance(side_page_counts, list)
            or len(side_page_counts) != 2
        ):
            raise ValueError("I conteggi fronte/retro devono contenere due numeri")
        original_counts = [int(value) for value in side_page_counts]
        if any(value < 1 for value in original_counts):
            raise ValueError("Fronte e retro devono contenere almeno una pagina")
        if sum(original_counts) != input_pages:
            raise ValueError(
                "I conteggi fronte/retro non corrispondono alle pagine del PDF"
            )
        groups = [
            ("front", list(reader.pages[: original_counts[0]])),
            ("back", list(reader.pages[original_counts[0] :])),
        ]
    else:
        original_counts = None
        groups = [("document", list(reader.pages))]

    def blank_like(reference):
        blank = PageObject.create_blank_page(
            width=float(reference.mediabox.width),
            height=float(reference.mediabox.height),
        )
        for box_name in ("cropbox", "trimbox", "bleedbox", "artbox"):
            source_box = getattr(reference, box_name, None)
            if source_box is not None:
                setattr(blank, box_name, RectangleObject(list(source_box)))
        if reference.rotation:
            blank.rotate(reference.rotation)
        return blank

    def rule_applies(rule: dict, side: str) -> bool:
        target = str(rule.get("target", "all"))
        if target not in {"all", "front", "back"}:
            raise ValueError(f"Destinazione regola non valida: {target}")
        if side == "document":
            return target == "all"
        return target == "all" or target == side

    def apply_rule(pages: list, rule: dict) -> tuple[list, int]:
        count = int(rule.get("count", 0) or 0)
        if count < 0:
            raise ValueError("Il numero di pagine vuote non può essere negativo")
        if count == 0:
            return pages, 0

        position = str(rule.get("position", "after"))
        if position not in {"start", "after", "end"}:
            raise ValueError(f"Posizione pagine vuote non valida: {position}")
        if position == "start":
            return [blank_like(pages[0]) for _ in range(count)] + pages, count
        if position == "end":
            return pages + [blank_like(pages[-1]) for _ in range(count)], count

        after_page = int(rule.get("after_page", 0) or 0)
        if after_page < 0:
            raise ValueError("La pagina di inserimento non può essere negativa")
        repeat = bool(rule.get("repeat", False))
        interval = int(rule.get("interval", 0) or 0)
        if repeat and interval < 1:
            raise ValueError(
                "L'intervallo deve essere maggiore di zero quando la ripetizione è attiva"
            )

        positions = []
        if after_page == 0:
            positions.append(0)
        elif after_page <= len(pages):
            positions.append(after_page)
        if repeat:
            next_position = after_page + interval
            while next_position <= len(pages):
                positions.append(next_position)
                next_position += interval
        if not positions:
            return pages, 0

        positions_set = set(positions)
        result = []
        inserted = 0
        if 0 in positions_set:
            result.extend(blank_like(pages[0]) for _ in range(count))
            inserted += count
        for page_number, page in enumerate(pages, start=1):
            result.append(page)
            if page_number in positions_set:
                result.extend(blank_like(page) for _ in range(count))
                inserted += count
        return result, inserted

    quantity = int(config.get("quantity", 0) or 0)
    rule_results = []
    processed_groups = []
    inserted_by_side = {}
    for side, source_pages in groups:
        pages = source_pages
        side_inserted = 0
        for index, raw_rule in enumerate(rules):
            if not isinstance(raw_rule, dict):
                raise ValueError(f"La regola {index + 1} non è valida")
            if raw_rule.get("enabled", True) is False:
                continue
            minimum = int(raw_rule.get("min_quantity", 0) or 0)
            maximum = int(raw_rule.get("max_quantity", 0) or 0)
            if minimum < 0 or maximum < 0:
                raise ValueError("Le condizioni di quantità non possono essere negative")
            if minimum and quantity < minimum:
                continue
            if maximum and quantity > maximum:
                continue
            if not rule_applies(raw_rule, side):
                continue

            pages, inserted = apply_rule(pages, raw_rule)
            side_inserted += inserted
            rule_results.append(
                {
                    "rule": index + 1,
                    "label": str(raw_rule.get("label", "") or ""),
                    "side": side,
                    "inserted": inserted,
                }
            )
        processed_groups.append((side, pages))
        inserted_by_side[side] = side_inserted

    writer = PdfWriter()
    for _side, pages in processed_groups:
        for page in pages:
            writer.add_page(page)
        writer.reset_translation(reader)

    Path(output_path).parent.mkdir(parents=True, exist_ok=True)
    with open(output_path, "wb") as output_file:
        writer.write(output_file)

    output_counts = [len(pages) for _side, pages in processed_groups]
    inserted_total = sum(inserted_by_side.values())
    return {
        "input_pages": input_pages,
        "output_pages": input_pages + inserted_total,
        "inserted_blank_pages": inserted_total,
        "inserted_by_side": inserted_by_side,
        "quantity": quantity,
        "rules_applied": rule_results,
        "original_input_page_counts": original_counts,
        "input_page_counts": output_counts if original_counts else None,
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
    double_sided_mode = str(config.get("double_sided_mode", "none"))
    if double_sided_mode not in {"none", "horizontal", "vertical"}:
        raise ValueError(
            f"Modalità fronte/retro non valida: {double_sided_mode}"
        )
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
    side_page_counts = config.get("side_page_counts")
    duplex_groups = None
    if side_page_counts is not None:
        if double_sided_mode == "none":
            raise ValueError(
                "Le pagine fronte/retro richiedono una modalità fronte/retro"
            )
        if (
            not isinstance(side_page_counts, list)
            or len(side_page_counts) != 2
            or any(
                isinstance(value, bool) or not isinstance(value, (int, float))
                for value in side_page_counts
            )
        ):
            raise ValueError("I conteggi fronte/retro devono contenere due numeri")
        front_pages, back_pages = (int(value) for value in side_page_counts)
        if front_pages < 1 or back_pages < 1:
            raise ValueError("Fronte e retro devono contenere almeno una pagina")
        if front_pages + back_pages != input_pages:
            raise ValueError(
                "I conteggi fronte/retro non corrispondono alle pagine del PDF"
            )
        duplex_groups = (
            (0, front_pages),
            (front_pages, back_pages),
        )
        sheet_pairs = math.ceil(max(front_pages, back_pages) / slots_per_sheet)
        sheets = sheet_pairs * 2
        placements_total = (
            sheets * slots_per_sheet
            if fill_last_sheet
            else front_pages + back_pages
        )
    else:
        sheets = math.ceil(input_pages / slots_per_sheet)
        placements_total = sheets * slots_per_sheet if fill_last_sheet else input_pages
    writer = PdfWriter()

    for sheet_index in range(sheets):
        output_page = PageObject.create_blank_page(
            width=sheet_width, height=sheet_height
        )
        if duplex_groups:
            pair_index = sheet_index // 2
            side_index = sheet_index % 2
            group_start, group_pages = duplex_groups[side_index]
            group_offset = pair_index * slots_per_sheet
            remaining = group_pages - group_offset
            placements_on_sheet = (
                slots_per_sheet
                if fill_last_sheet
                else min(slots_per_sheet, max(0, remaining))
            )
        else:
            group_start = 0
            group_pages = input_pages
            group_offset = sheet_index * slots_per_sheet
            remaining = placements_total - group_offset
            placements_on_sheet = min(slots_per_sheet, remaining)

        for slot_index in range(placements_on_sheet):
            row = slot_index // columns
            column = slot_index % columns
            is_back_sheet = (
                sheet_index % 2 == 1
                if duplex_groups
                else sheet_index % 2 == 1 and double_sided_mode != "none"
            )
            if is_back_sheet and double_sided_mode == "horizontal":
                column = columns - 1 - column
            elif is_back_sheet and double_sided_mode == "vertical":
                row = rows - 1 - row
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

            source_index = group_start + (
                (group_offset + slot_index) % group_pages
            )
            source = reader.pages[source_index]

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
        "double_sided_mode": double_sided_mode,
        "side_page_counts": (
            [duplex_groups[0][1], duplex_groups[1][1]]
            if duplex_groups
            else None
        ),
        "sheet_pairs": sheets // 2 if duplex_groups else None,
        "scale": 1.0,
    }


def barcode_pdf(data: str, output_path: str, config: dict) -> dict:
    width_mm = float(config.get("width_mm", 90))
    height_mm = float(config.get("height_mm", 29))
    bar_height_mm = float(config.get("bar_height_mm", 20))
    quiet_mm = float(config.get("quiet_mm", 4))
    human_readable = bool(config.get("human_readable", True))

    pdf = canvas.Canvas(output_path, pagesize=(width_mm * mm, height_mm * mm))
    barcode = code128.Code128(
        data,
        barHeight=bar_height_mm * mm,
        barWidth=float(config.get("bar_width", 0.75)) * mm,
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

    blanks_parser = subparsers.add_parser("insert-blanks")
    blanks_parser.add_argument("--input", required=True)
    blanks_parser.add_argument("--output", required=True)
    blanks_parser.add_argument("--config", required=True)

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
    elif args.command == "insert-blanks":
        result = insert_blank_pages(
            args.input, args.output, json.loads(args.config)
        )
    elif args.command == "impose":
        result = impose(args.input, args.output, json.loads(args.config))
    elif args.command == "barcode":
        result = barcode_pdf(args.data, args.output, json.loads(args.config))
    else:
        result = inspect_pdf(args.input)
    print(json.dumps(result, ensure_ascii=False))


if __name__ == "__main__":
    main()
