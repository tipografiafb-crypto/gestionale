#!/usr/bin/env python3
from __future__ import annotations

"""PDF helpers for the automation engine.

The module intentionally exposes a small CLI contract so the Ruby worker can
invoke it without shell interpolation.
"""

import argparse
import io
import json
import math
from pathlib import Path

from PIL import Image
from pypdf import PdfReader, PdfWriter, Transformation
from pypdf.generic import (
    DecodedStreamObject,
    DictionaryObject,
    NameObject,
    NumberObject,
    RectangleObject,
    StreamObject,
)
from pypdf._page import PageObject
from reportlab.graphics.barcode import code128
from reportlab.lib import colors
from reportlab.pdfbase.pdfmetrics import stringWidth
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


def duplicate_pages(
    input_path: str,
    output_path: str,
    copies: int,
    duplex_order: str = "repeat",
    side_page_counts: list[int] | None = None,
) -> dict:
    reader = PdfReader(input_path)
    if not reader.pages:
        raise ValueError("Il PDF sorgente non contiene pagine")

    copies = max(1, int(copies))
    writer = PdfWriter()
    if duplex_order == "grouped":
        if (
            not isinstance(side_page_counts, list)
            or len(side_page_counts) != 2
            or any(int(value) < 1 for value in side_page_counts)
            or sum(int(value) for value in side_page_counts) != len(reader.pages)
        ):
            raise ValueError("I conteggi fronte/retro non corrispondono alle pagine da duplicare")
        front_pages, back_pages = (int(value) for value in side_page_counts)
        page_groups = (
            list(reader.pages[:front_pages]),
            list(reader.pages[front_pages:front_pages + back_pages]),
        )
        for group in page_groups:
            for _copy_index in range(copies):
                for page in group:
                    writer.add_page(page)
    else:
        for _copy_index in range(copies):
            for page in reader.pages:
                writer.add_page(page)

    Path(output_path).parent.mkdir(parents=True, exist_ok=True)
    with open(output_path, "wb") as output_file:
        writer.write(output_file)

    return {
        "source_pages": len(reader.pages),
        "copies": copies,
        "output_pages": len(reader.pages) * copies,
        "duplex_order": duplex_order,
    }


def _pdf_number(value: float) -> str:
    """Format a PDF number without locale or unnecessary precision."""
    number = float(value)
    if abs(number) < 1e-10:
        return "0"
    return format(number, ".12f").rstrip("0").rstrip(".")


def _page_form_key(page: PageObject) -> tuple:
    # Do not call get_contents() here: it decodes the page stream just to build
    # a cache key and can exceed pypdf's decompression limit on image-heavy PDFs.
    # A page object is stable during one impose operation, so its identity is a
    # sufficient cache key and still reuses the form for repeated placements.
    return (
        id(page),
        round(float(page.mediabox.width), 6),
        round(float(page.mediabox.height), 6),
    )


def _raw_page_contents(page: PageObject) -> StreamObject:
    """Copy a single page stream without inflating its compressed payload."""
    raw_contents = page.get("/Contents")
    if raw_contents is not None:
        contents = raw_contents.get_object() if hasattr(raw_contents, "get_object") else raw_contents
        if isinstance(contents, StreamObject):
            stream = StreamObject()
            stream._data = contents._data
            for key, value in contents.items():
                if key != "/Length":
                    stream[NameObject(key)] = value
            return stream

    # Multi-stream pages are uncommon. Keep the existing decoded fallback for
    # them; the raw single-stream path handles the large image PDFs that caused
    # the decompression failure.
    decoded = page.get_contents()
    stream = StreamObject()
    stream._data = decoded.get_data() if decoded is not None else b""
    return stream


def _imposition_box(page: PageObject) -> tuple[float, float, float, float, str]:
    """Return the box used as the product trim, with a safe PDF fallback."""
    for name in ("TrimBox", "CropBox", "MediaBox"):
        raw_box = page.get(f"/{name}")
        if raw_box is None:
            continue
        left, bottom, right, top = (float(value) for value in raw_box)
        if right > left and top > bottom:
            return left, bottom, right, top, name
    box = page.mediabox
    return float(box.left), float(box.bottom), float(box.right), float(box.top), "MediaBox"


def _existing_bleed_box(
    page: PageObject,
    trim_box: tuple[float, float, float, float],
) -> tuple[float, float, float, float]:
    """Return the PDF BleedBox only when it safely contains the trim."""
    raw_box = page.get("/BleedBox")
    if raw_box is None:
        return trim_box
    left, bottom, right, top = (float(value) for value in raw_box)
    trim_left, trim_bottom, trim_right, trim_top = trim_box
    if (
        right > left
        and top > bottom
        and left <= trim_left
        and bottom <= trim_bottom
        and right >= trim_right
        and top >= trim_top
    ):
        return left, bottom, right, top
    return trim_box


def _bleed_source_box(
    page: PageObject,
    trim_box: tuple[float, float, float, float],
) -> tuple[float, float, float, float]:
    """Return the widest box that may legitimately carry bleed artwork.

    A print-ready PDF declares a BleedBox and that is authoritative. Files that
    only declare a TrimBox still usually paint the bleed inside the CropBox or
    MediaBox, so fall back to those; callers cap the amount they actually use,
    which keeps any crop marks living out there off the form.
    """
    declared = _existing_bleed_box(page, trim_box)
    if declared != trim_box:
        return declared
    trim_left, trim_bottom, trim_right, trim_top = trim_box
    for name in ("CropBox", "MediaBox"):
        raw_box = page.get(f"/{name}")
        if raw_box is None:
            continue
        left, bottom, right, top = (float(value) for value in raw_box)
        if (
            right > left
            and top > bottom
            and left <= trim_left
            and bottom <= trim_bottom
            and right >= trim_right
            and top >= trim_top
        ):
            return left, bottom, right, top
    return trim_box


def _rotated_bounds(
    left: float, bottom: float, right: float, top: float,
    degrees: int, scale: float = 1.0,
) -> tuple[float, float, float, float]:
    """Return the axis-aligned bounds after applying a PDF rotation."""
    if degrees == 0:
        points = ((left, bottom), (right, bottom), (left, top), (right, top))
    elif degrees == 90:
        points = ((-bottom, left), (-bottom, right), (-top, left), (-top, right))
    elif degrees == 180:
        points = ((-left, -bottom), (-right, -bottom), (-left, -top), (-right, -top))
    elif degrees == 270:
        points = ((bottom, -left), (bottom, -right), (top, -left), (top, -right))
    else:
        raise ValueError(f"Rotazione PDF non valida: {degrees}")
    xs = [point[0] * scale for point in points]
    ys = [point[1] * scale for point in points]
    return min(xs), min(ys), max(xs), max(ys)


def _shared_page_form(
    writer: PdfWriter,
    page: PageObject,
    form_cache: dict,
) -> tuple[str, object]:
    """Create one reusable Form XObject for a source page.

    Quite Imposing-style repetition is achieved by referencing this form from
    each placement. The page resources (especially images) are cloned once and
    then shared instead of being copied into every placement.
    """
    key = _page_form_key(page)
    cached = form_cache.get(key)
    if cached is not None:
        return cached

    form = _raw_page_contents(page)
    form[NameObject("/Type")] = NameObject("/XObject")
    form[NameObject("/Subtype")] = NameObject("/Form")
    form[NameObject("/FormType")] = NumberObject(1)
    form[NameObject("/BBox")] = RectangleObject([
        0,
        0,
        float(page.mediabox.width),
        float(page.mediabox.height),
    ])
    resources = page.get("/Resources")
    form[NameObject("/Resources")] = (
        resources.clone(writer) if resources is not None else DictionaryObject()
    )
    if page.get("/Group") is not None:
        form[NameObject("/Group")] = page.get("/Group").clone(writer)

    form_ref = writer._add_object(form)
    name = f"/Fm{len(form_cache)}"
    form_cache[key] = (name, form_ref)
    return name, form_ref


def _place_shared_form(
    output_page: PageObject,
    writer: PdfWriter,
    page: PageObject,
    xobjects: DictionaryObject,
    content_parts: list[str],
    form_cache: dict,
    transform: Transformation,
    clip_rect: tuple[float, float, float, float] | None = None,
) -> None:
    name, form_ref = _shared_page_form(writer, page, form_cache)
    xobjects[NameObject(name)] = form_ref
    matrix = transform.matrix
    values = (
        matrix[0][0], matrix[0][1],
        matrix[1][0], matrix[1][1],
        matrix[2][0], matrix[2][1],
    )
    if clip_rect is not None:
        clip_x, clip_y, clip_width, clip_height = clip_rect
        content_parts.append(
            "q "
            + " ".join(
                _pdf_number(value)
                for value in (clip_x, clip_y, clip_width, clip_height)
            )
            + " re W n "
        )
    content_parts.append(
        "q "
        + " ".join(_pdf_number(value) for value in values)
        + f" cm {name} Do Q"
        + (" Q" if clip_rect is not None else "")
        + "\n"
    )


def _finish_shared_page(
    output_page: PageObject,
    writer: PdfWriter,
    xobjects: DictionaryObject,
    content_parts: list[str],
) -> None:
    resources = DictionaryObject()
    resources[NameObject("/XObject")] = xobjects
    output_page[NameObject("/Resources")] = resources
    content = DecodedStreamObject()
    content.set_data("".join(content_parts).encode("ascii"))
    output_page[NameObject("/Contents")] = writer._add_object(content)


def _apply_sheet_marks(
    output_page: PageObject,
    placements: list[dict],
    config: dict,
    fold_x: float | None = None,
    fold_y: float | None = None,
    fold_lines: list[dict] | None = None,
    label: str = "",
    head_direction: str | None = None,
) -> None:
    marks = config.get("marks", {})
    if not isinstance(marks, dict):
        marks = {}
    if not head_direction and not any(
        bool(marks.get(key))
        for key in ("crop", "registration", "fold", "color_bars", "job_info")
    ):
        return

    width = float(output_page.mediabox.width)
    height = float(output_page.mediabox.height)
    overlay_buffer = io.BytesIO()
    overlay = canvas.Canvas(overlay_buffer, pagesize=(width, height))
    overlay.setLineWidth(float(marks.get("line_width_pt", 0.35)))
    overlay.setStrokeColor(colors.black)
    offset = max(0.0, float(marks.get("offset_mm", 2))) * mm
    length = max(0.1, float(marks.get("length_mm", 5))) * mm

    def outer_bounds(placement):
        bleed_x = max(0.0, float(placement.get("bleed_x", placement.get("bleed", 0))))
        bleed_y = max(0.0, float(placement.get("bleed_y", placement.get("bleed", 0))))
        bleed_left = max(0.0, float(placement.get("bleed_left", bleed_x)))
        bleed_right = max(0.0, float(placement.get("bleed_right", bleed_x)))
        bleed_bottom = max(0.0, float(placement.get("bleed_bottom", bleed_y)))
        bleed_top = max(0.0, float(placement.get("bleed_top", bleed_y)))
        x = float(placement["x"])
        y = float(placement["y"])
        return (
            x - bleed_left,
            y - bleed_bottom,
            x + float(placement["width"]) + bleed_right,
            y + float(placement["height"]) + bleed_top,
        )

    def nearest_gap(index, direction):
        left, bottom, right, top = outer_bounds(placements[index])
        gaps = []
        for other_index, other in enumerate(placements):
            if other_index == index:
                continue
            other_left, other_bottom, other_right, other_top = outer_bounds(other)
            if direction in {"left", "right"}:
                if min(top, other_top) - max(bottom, other_bottom) <= 0.01:
                    continue
                if direction == "left" and other_right <= left + 0.01:
                    gaps.append(left - other_right)
                elif direction == "right" and other_left >= right - 0.01:
                    gaps.append(other_left - right)
            else:
                if min(right, other_right) - max(left, other_left) <= 0.01:
                    continue
                if direction == "bottom" and other_top <= bottom + 0.01:
                    gaps.append(bottom - other_top)
                elif direction == "top" and other_bottom >= top - 0.01:
                    gaps.append(other_bottom - top)
        return min(gaps) if gaps else None

    def mark_dimensions(gap):
        if gap is None:
            return offset, length
        if gap + 0.01 >= 2 * (offset + length):
            return offset, length
        # Narrow channels (the head trim of a two-fold section, the gap between
        # repeated forms) still need a trim mark: shorten it instead of hiding
        # it, and drop it only when nothing legible is left.
        available = gap / 2
        local_offset = min(offset, max(0.0, available - 1.0 * mm))
        local_length = available - local_offset
        if local_length < 1.0 * mm:
            return None
        return local_offset, local_length

    def segment_is_clear(index, direction, fixed, start, end):
        """Do not draw a crop mark if its segment enters another product."""
        segment_start, segment_end = sorted((start, end))
        for other_index, other in enumerate(placements):
            if other_index == index:
                continue
            other_left, other_bottom, other_right, other_top = outer_bounds(other)
            if direction in {"left", "right"}:
                crosses_other = (
                    other_bottom - 0.01 <= fixed <= other_top + 0.01
                    and segment_end > other_left + 0.01
                    and segment_start < other_right - 0.01
                )
            else:
                crosses_other = (
                    other_left - 0.01 <= fixed <= other_right + 0.01
                    and segment_end > other_bottom + 0.01
                    and segment_start < other_top - 0.01
                )
            if crosses_other:
                return False
        return True

    if bool(marks.get("crop", False)):
        for index, placement in enumerate(placements):
            left, bottom, right, top = outer_bounds(placement)
            trim_x = float(placement["x"])
            trim_y = float(placement["y"])
            trim_right = trim_x + float(placement["width"])
            trim_top = trim_y + float(placement["height"])
            left_mark = mark_dimensions(nearest_gap(index, "left"))
            right_mark = mark_dimensions(nearest_gap(index, "right"))
            bottom_mark = mark_dimensions(nearest_gap(index, "bottom"))
            top_mark = mark_dimensions(nearest_gap(index, "top"))
            if left_mark:
                local_offset, local_length = left_mark
                start = trim_x - local_offset - local_length
                end = trim_x - local_offset
                if segment_is_clear(index, "left", trim_y, start, end):
                    overlay.line(start, trim_y, end, trim_y)
                if segment_is_clear(index, "left", trim_top, start, end):
                    overlay.line(start, trim_top, end, trim_top)
            if right_mark:
                local_offset, local_length = right_mark
                start = trim_right + local_offset
                end = trim_right + local_offset + local_length
                if segment_is_clear(index, "right", trim_y, start, end):
                    overlay.line(start, trim_y, end, trim_y)
                if segment_is_clear(index, "right", trim_top, start, end):
                    overlay.line(start, trim_top, end, trim_top)
            if bottom_mark:
                local_offset, local_length = bottom_mark
                start = trim_y - local_offset - local_length
                end = trim_y - local_offset
                if segment_is_clear(index, "bottom", trim_x, start, end):
                    overlay.line(trim_x, start, trim_x, end)
                if segment_is_clear(index, "bottom", trim_right, start, end):
                    overlay.line(trim_right, start, trim_right, end)
            if top_mark:
                local_offset, local_length = top_mark
                start = trim_top + local_offset
                end = trim_top + local_offset + local_length
                if segment_is_clear(index, "top", trim_x, start, end):
                    overlay.line(trim_x, start, trim_x, end)
                if segment_is_clear(index, "top", trim_right, start, end):
                    overlay.line(trim_right, start, trim_right, end)

    if bool(marks.get("registration", False)):
        radius = 2.5 * mm
        for x, y in (
            (12 * mm, 12 * mm),
            (width - 12 * mm, 12 * mm),
            (12 * mm, height - 12 * mm),
            (width - 12 * mm, height - 12 * mm),
        ):
            overlay.circle(x, y, radius, stroke=1, fill=0)
            overlay.line(x - radius * 1.5, y, x + radius * 1.5, y)
            overlay.line(x, y - radius * 1.5, x, y + radius * 1.5)

    if bool(marks.get("fold", False)) and fold_x is not None:
        overlay.setStrokeColor(colors.HexColor("#087E8B"))
        overlay.line(fold_x, 0, fold_x, length)
        overlay.line(fold_x, height - length, fold_x, height)
    if bool(marks.get("fold", False)) and fold_y is not None:
        overlay.setStrokeColor(colors.HexColor("#087e8b"))
        overlay.line(0, fold_y, length, fold_y)
        overlay.line(width - length, fold_y, width, fold_y)
        overlay.setStrokeColor(colors.black)
    if bool(marks.get("fold", False)) and fold_lines:
        overlay.setStrokeColor(colors.HexColor("#087E8B"))
        for fold_line in fold_lines:
            direction = str(fold_line.get("direction", "vertical"))
            if direction == "vertical":
                x = float(fold_line["position"])
                start = float(fold_line["start"])
                end = float(fold_line["end"])
                overlay.line(x, max(0, start - length), x, start)
                overlay.line(x, end, x, min(height, end + length))
            else:
                y = float(fold_line["position"])
                start = float(fold_line["start"])
                end = float(fold_line["end"])
                overlay.line(max(0, start - length), y, start, y)
                overlay.line(end, y, min(width, end + length), y)
        overlay.setStrokeColor(colors.black)

    if bool(marks.get("color_bars", False)):
        bar_width = 6 * mm
        bar_height = 4 * mm
        start_x = width / 2 - 2 * bar_width
        for index, color in enumerate((colors.cyan, colors.magenta, colors.yellow, colors.black)):
            overlay.setFillColor(color)
            overlay.rect(start_x + index * bar_width, height - 7 * mm, bar_width, bar_height, stroke=0, fill=1)

    if bool(marks.get("job_info", False)):
        text = str(config.get("job_label") or label or "IMPOSIZIONE")
        overlay.setFillColor(colors.black)
        overlay.setFont("Helvetica", 7)
        overlay.drawString(8 * mm, 4 * mm, text[:180])

    overlay.showPage()
    overlay.save()
    overlay_buffer.seek(0)
    output_page.merge_page(PdfReader(overlay_buffer).pages[0], over=True)


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


def _rect_contains(outer: dict, inner: dict, tolerance: float = 0.01) -> bool:
    return (
        inner["x"] >= outer["x"] - tolerance
        and inner["y"] >= outer["y"] - tolerance
        and inner["x"] + inner["width"] <= outer["x"] + outer["width"] + tolerance
        and inner["y"] + inner["height"] <= outer["y"] + outer["height"] + tolerance
    )


def _prune_free_rectangles(rectangles: list[dict]) -> list[dict]:
    usable = [
        rectangle
        for rectangle in rectangles
        if rectangle["width"] > 0.01 and rectangle["height"] > 0.01
    ]
    pruned = []
    for index, rectangle in enumerate(usable):
        if any(
            index != other_index and _rect_contains(other, rectangle)
            for other_index, other in enumerate(usable)
        ):
            continue
        if not any(
            all(abs(rectangle[key] - current[key]) <= 0.01 for key in ("x", "y", "width", "height"))
            for current in pruned
        ):
            pruned.append(rectangle)
    return pruned


def _split_free_rectangles(rectangles: list[dict], used: dict) -> list[dict]:
    result = []
    used_right = used["x"] + used["width"]
    used_bottom = used["y"] + used["height"]
    for free in rectangles:
        free_right = free["x"] + free["width"]
        free_bottom = free["y"] + free["height"]
        intersects = not (
            used_right <= free["x"] + 0.01
            or used["x"] >= free_right - 0.01
            or used_bottom <= free["y"] + 0.01
            or used["y"] >= free_bottom - 0.01
        )
        if not intersects:
            result.append(free)
            continue
        if used["x"] > free["x"] + 0.01:
            result.append({
                "x": free["x"], "y": free["y"],
                "width": used["x"] - free["x"], "height": free["height"],
            })
        if used_right < free_right - 0.01:
            result.append({
                "x": used_right, "y": free["y"],
                "width": free_right - used_right, "height": free["height"],
            })
        if used["y"] > free["y"] + 0.01:
            result.append({
                "x": free["x"], "y": free["y"],
                "width": free["width"], "height": used["y"] - free["y"],
            })
        if used_bottom < free_bottom - 0.01:
            result.append({
                "x": free["x"], "y": used_bottom,
                "width": free["width"], "height": free_bottom - used_bottom,
            })
    return _prune_free_rectangles(result)


def _best_nesting_position(
    free_rectangles: list[dict], width: float, height: float,
    gap_x: float, gap_y: float, allow_rotation: bool,
) -> dict | None:
    candidates = []
    orientations = [(width, height, False)]
    if allow_rotation and abs(width - height) > 0.01:
        orientations.append((height, width, True))
    for free_index, free in enumerate(free_rectangles):
        for placed_width, placed_height, rotated in orientations:
            slot_width = placed_width + gap_x
            slot_height = placed_height + gap_y
            if slot_width > free["width"] + 0.01 or slot_height > free["height"] + 0.01:
                continue
            remaining_width = free["width"] - slot_width
            remaining_height = free["height"] - slot_height
            candidates.append({
                "free_index": free_index,
                "x": free["x"], "y": free["y"],
                "width": placed_width, "height": placed_height,
                "slot_width": slot_width, "slot_height": slot_height,
                "rotated": rotated,
                "score": (
                    min(remaining_width, remaining_height),
                    max(remaining_width, remaining_height),
                    free["y"], free["x"], int(rotated),
                ),
            })
    return min(candidates, key=lambda candidate: candidate["score"]) if candidates else None


def _impose_nesting(reader: PdfReader, output_path: str, config: dict) -> dict:
    sheet_width = float(config["sheet_width_mm"]) * mm
    sheet_height = float(config["sheet_height_mm"]) * mm
    anchor = str(config.get("anchor", "top_left"))
    if anchor not in {"top_left", "top_center", "top_right", "center", "bottom_left", "bottom_center", "bottom_right"}:
        raise ValueError(f"Punto di ancoraggio non valido: {anchor}")
    margin_left = float(config.get("margin_left_mm", config.get("offset_x_mm", 0))) * mm
    margin_right = float(config.get("margin_right_mm", config.get("offset_x_mm", 0))) * mm
    margin_top = float(config.get("margin_top_mm", config.get("offset_y_mm", 0))) * mm
    margin_bottom = float(config.get("margin_bottom_mm", config.get("offset_y_mm", 0))) * mm
    gap_x = float(config.get("gap_x_mm", 0)) * mm
    gap_y = float(config.get("gap_y_mm", 0)) * mm
    allow_rotation = bool(config.get("rotate", False))
    trim_sheet_height = bool(config.get("trim_sheet_height", False))
    if str(config.get("double_sided_mode", "none")) != "none":
        raise ValueError("Il nesting non supporta la modalità fronte/retro")
    if min(margin_left, margin_right, margin_top, margin_bottom, gap_x, gap_y) < 0:
        raise ValueError("Margini e spazi non possono essere negativi")

    content_width = sheet_width - margin_left - margin_right
    content_height = sheet_height - margin_top - margin_bottom
    if content_width <= 0 or content_height <= 0:
        raise ValueError("I margini del nesting non lasciano spazio utile sul foglio")
    bin_width = content_width + gap_x
    bin_height = content_height + gap_y

    items = []
    for page_index, page in enumerate(reader.pages):
        left, bottom, right, top, box_name = _imposition_box(page)
        items.append({
            "page_index": page_index,
            "width": right - left,
            "height": top - bottom,
            "box_left": left,
            "box_bottom": bottom,
            "box_top": top,
            "box_name": box_name,
        })
    items.sort(
        key=lambda item: (
            -max(item["width"], item["height"]),
            -(item["width"] * item["height"]),
            -min(item["width"], item["height"]),
            item["page_index"],
        )
    )

    ordered_equal_size = config.get("ordered_equal_size", True) is not False
    same_size = all(
        abs(item["width"] - items[0]["width"]) <= 0.01 and
        abs(item["height"] - items[0]["height"]) <= 0.01
        for item in items
    )
    sheets = []
    if ordered_equal_size and same_size:
        # Identical pages do not need MaxRects.  Its free-rectangle heuristic
        # can fragment the remaining area and produce unexpected columns.
        # Calculate the grid from the actual page size for this order.
        orientations = [(items[0]["width"], items[0]["height"], False)]
        if allow_rotation and abs(items[0]["width"] - items[0]["height"]) > 0.01:
            orientations.append((items[0]["height"], items[0]["width"], True))

        def grid_capacity(orientation):
            width, height, _ = orientation
            columns = math.floor((bin_width + 0.01) / (width + gap_x))
            rows = math.floor((bin_height + 0.01) / (height + gap_y))
            return max(columns, 0), max(rows, 0)

        orientation = max(
            orientations,
            key=lambda value: math.prod(grid_capacity(value)),
        )
        placed_width, placed_height, rotated = orientation
        columns, rows = grid_capacity(orientation)
        slots_per_sheet = columns * rows
        if slots_per_sheet < 1:
            raise ValueError(
                f"La pagina {items[0]['page_index'] + 1} "
                f"({items[0]['width'] / mm:.2f}x{items[0]['height'] / mm:.2f} mm) "
                "non entra nell'area utile del foglio"
            )
        for index, item in enumerate(items):
            sheet_index, slot_index = divmod(index, slots_per_sheet)
            while len(sheets) <= sheet_index:
                sheets.append({"free": [], "placements": []})
            row, column = divmod(slot_index, columns)
            sheets[sheet_index]["placements"].append({
                "x": column * (placed_width + gap_x),
                "y": row * (placed_height + gap_y),
                "width": placed_width,
                "height": placed_height,
                "rotated": rotated,
                "page_index": item["page_index"],
                "source_width": item["width"],
                "source_height": item["height"],
                "box_left": item["box_left"],
                "box_bottom": item["box_bottom"],
                "box_top": item["box_top"],
            })
        layout_algorithm = "ordered_equal_size_grid"
    else:
        for item in items:
            selected = None
            for sheet_index, sheet in enumerate(sheets):
                candidate = _best_nesting_position(
                    sheet["free"], item["width"], item["height"],
                    gap_x, gap_y, allow_rotation,
                )
                if candidate is not None:
                    candidate["sheet_index"] = sheet_index
                    if selected is None or candidate["score"] < selected["score"]:
                        selected = candidate
            if selected is None:
                sheet = {
                    "free": [{"x": 0.0, "y": 0.0, "width": bin_width, "height": bin_height}],
                    "placements": [],
                }
                sheets.append(sheet)
                selected = _best_nesting_position(
                    sheet["free"], item["width"], item["height"],
                    gap_x, gap_y, allow_rotation,
                )
                if selected is None:
                    raise ValueError(
                        f"La pagina {item['page_index'] + 1} "
                        f"({item['width'] / mm:.2f}x{item['height'] / mm:.2f} mm) "
                        f"non entra nell'area utile del foglio "
                        f"({bin_width / mm:.2f}x{bin_height / mm:.2f} mm, "
                        "dopo i margini configurati)"
                    )
                selected["sheet_index"] = len(sheets) - 1

            sheet = sheets[selected["sheet_index"]]
            placement = {
                **selected,
                "page_index": item["page_index"],
                "source_width": item["width"],
                "source_height": item["height"],
                "box_left": item["box_left"],
                "box_bottom": item["box_bottom"],
                "box_top": item["box_top"],
            }
            placement.pop("free_index", None)
            placement.pop("score", None)
            sheet["placements"].append(placement)
            used = {
                "x": selected["x"], "y": selected["y"],
                "width": selected["slot_width"], "height": selected["slot_height"],
            }
            sheet["free"] = _split_free_rectangles(sheet["free"], used)
        layout_algorithm = "maxrects_best_short_side_fit"

    writer = PdfWriter()
    form_cache = {}
    use_shared_resources = config.get("shared_resources", True) is not False
    metadata_placements = []
    sheet_heights = []
    utilization = []
    for sheet_index, sheet in enumerate(sheets):
        used_content_height = max(
            placement["y"] + placement["height"]
            for placement in sheet["placements"]
        )
        output_height = (
            min(sheet_height, used_content_height + margin_top + margin_bottom)
            if trim_sheet_height else sheet_height
        )
        output_page = PageObject.create_blank_page(width=sheet_width, height=output_height)
        xobjects = DictionaryObject()
        content_parts = []
        rendered_placements = []
        used_area = 0.0
        used_content_width = max(
            placement["x"] + placement["width"]
            for placement in sheet["placements"]
        )
        min_content_x = min(placement["x"] for placement in sheet["placements"])
        min_content_y = min(placement["y"] for placement in sheet["placements"])
        used_content_width -= min_content_x
        used_content_height -= min_content_y
        for placement in sorted(sheet["placements"], key=lambda value: value["page_index"]):
            local_x = placement["x"]
            local_y = placement["y"]
            if anchor.endswith("right"):
                x = output_page.mediabox.width - margin_right - local_x - placement["width"]
            elif anchor == "center" or anchor.endswith("center"):
                x = margin_left + (content_width - used_content_width) / 2 + local_x - min_content_x
            else:
                x = margin_left + local_x
            if anchor == "center":
                y = margin_bottom + (output_height - margin_top - margin_bottom - used_content_height) / 2 + local_y - min_content_y
            elif anchor.startswith("bottom"):
                y = margin_bottom + local_y
            else:
                y = output_height - margin_top - local_y - placement["height"]
            source = reader.pages[placement["page_index"]]
            transform = (
                Transformation().rotate(90).translate(x + placement["box_top"], y - placement["box_left"])
                if placement["rotated"] else Transformation().translate(x, y)
            )
            if not placement["rotated"]:
                transform = Transformation().translate(
                    x - placement["box_left"], y - placement["box_bottom"]
                )
            if use_shared_resources:
                _place_shared_form(
                    output_page, writer, source, xobjects, content_parts,
                    form_cache, transform,
                )
            else:
                output_page.merge_transformed_page(source, transform, over=True)
            used_area += placement["source_width"] * placement["source_height"]
            metadata_placements.append({
                "page": placement["page_index"] + 1,
                "sheet": sheet_index + 1,
                "x_mm": round(float(x) / mm, 4),
                "y_mm": round(float(y) / mm, 4),
                "width_mm": round(placement["width"] / mm, 4),
                "height_mm": round(placement["height"] / mm, 4),
                "rotated": placement["rotated"],
            })
            rendered_placements.append({
                "x": x,
                "y": y,
                "width": placement["width"],
                "height": placement["height"],
            })
        if use_shared_resources:
            _finish_shared_page(output_page, writer, xobjects, content_parts)
        _apply_sheet_marks(
            output_page,
            rendered_placements,
            config,
            label=f"NESTING · FOGLIO {sheet_index + 1}",
        )
        writer.add_page(output_page)
        sheet_heights.append(round(output_height / mm, 4))
        usable_area = content_width * max(output_height - margin_top - margin_bottom, 0.01)
        utilization.append(round(100 * used_area / usable_area, 2))

    Path(output_path).parent.mkdir(parents=True, exist_ok=True)
    with open(output_path, "wb") as output_file:
        writer.write(output_file)

    return {
        "layout_mode": "nesting",
        "algorithm": layout_algorithm,
        "sheet_width_mm": float(config["sheet_width_mm"]),
        "sheet_height_mm": float(config["sheet_height_mm"]),
        "output_sheet_heights_mm": sheet_heights,
        "anchor": anchor,
        "margin_left_mm": float(config.get("margin_left_mm", config.get("offset_x_mm", 0))),
        "margin_right_mm": float(config.get("margin_right_mm", config.get("offset_x_mm", 0))),
        "margin_top_mm": float(config.get("margin_top_mm", config.get("offset_y_mm", 0))),
        "margin_bottom_mm": float(config.get("margin_bottom_mm", config.get("offset_y_mm", 0))),
        "gap_x_mm": float(config.get("gap_x_mm", 0)),
        "gap_y_mm": float(config.get("gap_y_mm", 0)),
        "rotation_allowed": allow_rotation,
        "rotated_pages": sum(1 for placement in metadata_placements if placement["rotated"]),
        "trim_sheet_height": trim_sheet_height,
        "input_pages": len(reader.pages),
        "placed_pages": len(metadata_placements),
        "sheets": len(sheets),
        "utilization_percent": utilization,
        "placements": metadata_placements,
        "scale": 1.0,
        "shared_resources": use_shared_resources,
    }


def _impose_booklet(reader: PdfReader, output_path: str, config: dict) -> dict:
    binding_method = str(config.get("binding_method", "saddle_stitch"))
    if binding_method not in {"saddle_stitch", "nested_saddle", "perfect_bound"}:
        raise ValueError("Tipo di legatura non valido")
    configured_signature_pages = int(config.get("signature_pages", 16))
    if configured_signature_pages < 4 or configured_signature_pages > 64 or configured_signature_pages % 4:
        raise ValueError("La segnatura deve essere un multiplo di 4 compreso tra 4 e 64 pagine")
    last_signature_padding = str(config.get("last_signature_padding", "multiple_of_4"))
    if last_signature_padding not in {"multiple_of_4", "full"}:
        raise ValueError("Completamento ultima segnatura non valido")
    binding = str(config.get("binding", "left"))
    if binding not in {"left", "right"}:
        raise ValueError("Lato di rilegatura non valido")

    sheet_width = float(config["sheet_width_mm"]) * mm
    sheet_height = float(config["sheet_height_mm"]) * mm
    margin_left = float(config.get("margin_left_mm", 0)) * mm
    margin_right = float(config.get("margin_right_mm", 0)) * mm
    margin_top = float(config.get("margin_top_mm", 0)) * mm
    margin_bottom = float(config.get("margin_bottom_mm", 0)) * mm
    gutter = float(config.get("gutter_mm", 0)) * mm
    repeat_gap = float(config.get("booklet_repeat_gap_mm", 4)) * mm
    max_creep = float(config.get("creep_mm", 0)) * mm
    booklet_bleed = float(config.get("booklet_bleed_mm", 3)) * mm
    if min(
        margin_left, margin_right, margin_top, margin_bottom,
        gutter, repeat_gap, max_creep, booklet_bleed,
    ) < 0:
        raise ValueError("Margini, canale, creep, distanza forme e abbondanza non possono essere negativi")
    repeat_mode = str(config.get("booklet_repeat_mode", "sequential"))
    repeat_mode = {"single": "sequential", "auto": "repeat"}.get(repeat_mode, repeat_mode)
    if repeat_mode not in {"sequential", "repeat"}:
        raise ValueError("Montaggio booklet non valido")
    requested_up = str(config.get("booklet_up", "2"))
    requested_up = "2" if requested_up == "auto" else requested_up
    if requested_up not in {"2", "4"}:
        raise ValueError("Schema di piega booklet non valido")
    booklet_work_style = str(config.get("booklet_work_style", "sheetwise"))
    if booklet_work_style not in {"sheetwise", "work_and_turn"}:
        raise ValueError("Metodo di stampa booklet non valido")
    if requested_up == "2" and booklet_work_style == "work_and_turn":
        raise ValueError("La volta di lato booklet richiede quattro pagine per lato")

    source_left, source_bottom, source_right, source_top, _ = _imposition_box(reader.pages[0])
    source_width = source_right - source_left
    source_height = source_top - source_bottom
    for index, page in enumerate(reader.pages[1:], start=2):
        page_left, page_bottom, page_right, page_top, _ = _imposition_box(page)
        if (
            abs((page_right - page_left) - source_width) > 0.01
            or abs((page_top - page_bottom) - source_height) > 0.01
        ):
            raise ValueError(f"La pagina {index} ha dimensioni diverse dalla prima pagina")

    available_width = sheet_width - margin_left - margin_right
    available_height = sheet_height - margin_top - margin_bottom
    if available_width <= 0 or available_height <= 0:
        raise ValueError("I margini non lasciano spazio per il libretto")
    # Signatures are built before the press form. Every logical booklet sheet
    # is a normal 2-up half-fold; a 4-up press form simply mounts two of those
    # 2-up forms on the same sheet.
    input_pages = len(reader.pages)
    signature_specs = []
    cursor = 0
    while cursor < input_pages:
        if binding_method == "saddle_stitch":
            source_count = input_pages
            padded_size = max(4, math.ceil(source_count / 4) * 4)
        else:
            source_count = min(configured_signature_pages, input_pages - cursor)
            if source_count < configured_signature_pages and last_signature_padding == "multiple_of_4":
                padded_size = max(4, math.ceil(source_count / 4) * 4)
            else:
                padded_size = configured_signature_pages
        # A sequential 4-up mounts two complete 2-up booklet forms on each
        # press sheet. Complete the signature to the next multiple of eight so
        # the last sheet remains a valid pair of forms instead of failing.
        if requested_up == "4" and repeat_mode == "sequential":
            padded_size = max(8, math.ceil(padded_size / 8) * 8)
        signature_entries = [
            {"page": reader.pages[cursor + index], "number": cursor + index + 1}
            for index in range(source_count)
        ]
        while len(signature_entries) < padded_size:
            signature_entries.append({
                "page": PageObject.create_blank_page(width=source_width, height=source_height),
                "number": None,
            })
        signature_specs.append({"entries": signature_entries, "size": padded_size})
        cursor += source_count
        if binding_method == "saddle_stitch":
            break
    signature_count = len(signature_specs)
    signature_sizes = [int(signature["size"]) for signature in signature_specs]
    padded_pages = sum(signature_sizes)
    signature_pages = signature_sizes[0] if binding_method == "saddle_stitch" else configured_signature_pages

    spine_gap = gutter if binding_method == "perfect_bound" else 0.0
    booklet_up = int(requested_up)
    if booklet_up == 4 and repeat_mode == "sequential" and any(size % 8 for size in signature_sizes):
        raise ValueError("Il 4-up sequenziale richiede segnature multiple di 8 pagine")
    form_rows = 2 if booklet_up == 4 else 1
    form_gap = repeat_gap if booklet_up == 4 else 0.0
    # The page keeps its own orientation: which of its edges carries the spine
    # is the product, not a layout choice. To use a sheet the other way round
    # the whole form turns — spine fold, head fold and pages together — so the
    # only candidates are the form upright and the form turned 90°.
    form_rotations = [0]
    if bool(config.get("auto_rotate", True)):
        form_rotations.append(270)
    layouts = []
    for form_rotation in form_rotations:
        # Sizes below are in the form's own frame, which the rotation maps onto
        # the sheet; span_x/span_y are the sheet room measured in that frame.
        span_x = available_height if form_rotation else available_width
        span_y = available_width if form_rotation else available_height
        scale = min(
            1.0,
            max(0.0, (span_x - spine_gap) / (2 * source_width)),
            max(0.0, (span_y - form_gap) / (form_rows * source_height)),
        )
        if scale <= 0:
            continue
        layouts.append((
            scale,
            form_rotation == 0,
            form_rotation,
        ))
    if not layouts:
        raise ValueError("Il formato pagina non entra nel foglio")
    layouts.sort(key=lambda item: item[:2], reverse=True)
    scale, _, form_rotation = layouts[0]
    placed_width = source_width * scale
    placed_height = source_height * scale
    scaled_spine_gap = spine_gap
    spread_width = 2 * placed_width + scaled_spine_gap
    spread_height = form_rows * placed_height + form_gap
    if placed_width <= 0 or placed_height <= 0:
        raise ValueError("Il formato pagina non entra nel foglio")

    form_width = spread_width
    form_height = spread_height
    footprint_width = form_height if form_rotation else form_width
    footprint_height = form_width if form_rotation else form_height
    form_x = margin_left + (available_width - footprint_width) / 2
    form_y = margin_bottom + (available_height - footprint_height) / 2

    def to_sheet(u: float, v: float, width: float, height: float):
        """Map a rectangle from the form frame onto the sheet."""
        if not form_rotation:
            return form_x + u, form_y + v, width, height
        if form_rotation == 90:
            return form_x + (form_height - v - height), form_y + u, height, width
        return form_x + v, form_y + (form_width - u - width), height, width

    def fold_to_sheet(direction: str, position: float, start: float, end: float) -> dict:
        """Map a fold line from the form frame onto the sheet."""
        if not form_rotation:
            if direction == "vertical":
                return {
                    "direction": "vertical", "position": form_x + position,
                    "start": form_y + start, "end": form_y + end,
                }
            return {
                "direction": "horizontal", "position": form_y + position,
                "start": form_x + start, "end": form_x + end,
            }
        if form_rotation == 90 and direction == "vertical":
            return {
                "direction": "horizontal", "position": form_y + position,
                "start": form_x + form_height - end, "end": form_x + form_height - start,
            }
        if form_rotation == 90:
            return {
                "direction": "vertical", "position": form_x + form_height - position,
                "start": form_y + start, "end": form_y + end,
            }
        if direction == "vertical":
            return {
                "direction": "horizontal", "position": form_y + form_width - position,
                "start": form_x + start, "end": form_x + end,
            }
        return {
            "direction": "vertical", "position": form_x + position,
            "start": form_y + form_width - end, "end": form_y + form_width - start,
        }

    writer = PdfWriter()
    form_cache = {}
    metadata_placements = []
    physical_sheet = 0

    def row_v(row: int) -> float:
        if form_rotation == 270:
            return row * (placed_height + form_gap)
        return (form_rows - 1 - row) * (placed_height + form_gap)

    def booklet_spread(signature_size, sheet_index, side_index):
        """Return one logical 2-up half-fold spread."""
        sequence = (
            (signature_size - 1 - sheet_index * 2, sheet_index * 2),
            (sheet_index * 2 + 1, signature_size - 2 - sheet_index * 2),
        )[side_index]
        return tuple(reversed(sequence)) if binding == "right" else sequence

    def mounted_spread(signature_size, sheet_index, side_index, rotation, reverse=False):
        spread = tuple(
            (page_index, rotation, sheet_index)
            for page_index in booklet_spread(signature_size, sheet_index, side_index)
        )
        return tuple(reversed(spread)) if reverse else spread

    for signature_index, signature_spec in enumerate(signature_specs):
        entries = signature_spec["entries"]
        current_signature_pages = int(signature_spec["size"])
        logical_sheets = current_signature_pages // 4
        if booklet_up == 2 or booklet_work_style == "work_and_turn":
            press_groups = [(sheet_index,) for sheet_index in range(logical_sheets)]
        elif repeat_mode == "repeat":
            press_groups = [(sheet_index, sheet_index) for sheet_index in range(logical_sheets)]
        else:
            press_groups = [
                (sheet_index, sheet_index + 1)
                for sheet_index in range(0, logical_sheets, 2)
            ]

        for group in press_groups:
            if booklet_work_style == "work_and_turn":
                sheet_index = group[0]
                sides = ((
                    "BIANCA E VOLTA",
                    mounted_spread(current_signature_pages, sheet_index, 0, 0)
                    + mounted_spread(
                        current_signature_pages, sheet_index, 1, 180, reverse=True,
                    ),
                ),)
            else:
                front = tuple(
                    item
                    for sheet_index in group
                    for item in mounted_spread(current_signature_pages, sheet_index, 0, 0)
                )
                back_order = tuple(reversed(group)) if booklet_up == 4 else group
                back_rotation = 180 if booklet_up == 4 else 0
                back = tuple(
                    item
                    for sheet_index in back_order
                    for item in mounted_spread(
                        current_signature_pages, sheet_index, 1, back_rotation,
                        reverse=booklet_up == 4,
                    )
                )
                sides = (("FRONTE", front), ("RETRO", back))

            physical_sheet += 1
            for side_name, sequence in sides:
                output_page = PageObject.create_blank_page(width=sheet_width, height=sheet_height)
                xobjects = DictionaryObject()
                content_parts = []
                render_placements = []
                fold_lines = []
                for form_row in range(form_rows):
                    row_y = row_v(form_row)
                    fold_lines.append(fold_to_sheet(
                        "vertical",
                        placed_width + scaled_spine_gap / 2,
                        row_y,
                        row_y + placed_height,
                    ))

                for slot, (local_source_index, relative_rotation, logical_sheet) in enumerate(sequence):
                    row = slot // 2 if booklet_up == 4 else 0
                    column = slot % 2
                    creep = (
                        max_creep * logical_sheet / (logical_sheets - 1)
                        if logical_sheets > 1 else 0
                    )
                    toward_spine = creep / 2 if column == 0 else -creep / 2
                    x, y, width, height = to_sheet(
                        column * (placed_width + scaled_spine_gap) + toward_spine,
                        row_v(row),
                        placed_width,
                        placed_height,
                    )
                    entry = entries[local_source_index]
                    source = entry["page"]
                    page_left, page_bottom, page_right, page_top, _ = _imposition_box(source)
                    placement_rotation = (form_rotation + relative_rotation) % 360
                    rotated_bounds = _rotated_bounds(
                        page_left, page_bottom, page_right, page_top,
                        placement_rotation, scale,
                    )
                    offset_x = x - rotated_bounds[0]
                    offset_y = y - rotated_bounds[1]
                    transform = Transformation().scale(scale).rotate(placement_rotation).translate(
                        offset_x, offset_y,
                    )
                    # Bleed is allowed on the outside of the complete press
                    # form. At every internal boundary it is capped to half
                    # the available gap; when pages touch, that means exactly
                    # zero, so artwork can never enter the neighbouring page.
                    outer_bleed = booklet_bleed
                    spine_bleed = min(booklet_bleed, scaled_spine_gap / 2)
                    row_bleed = min(booklet_bleed, form_gap / 2)
                    toward_left = spine_bleed if column == 1 else outer_bleed
                    toward_right = spine_bleed if column == 0 else outer_bleed
                    if booklet_up == 4 and form_rotation == 270:
                        # row_v() reverses the two forms when the press form is
                        # turned clockwise: row 0 is physically on the left,
                        # so its top edge (not its bottom edge) faces row 1.
                        toward_top = row_bleed if row == 0 else outer_bleed
                        toward_bottom = row_bleed if row == 1 else outer_bleed
                    else:
                        toward_top = row_bleed if booklet_up == 4 and row == 1 else outer_bleed
                        toward_bottom = row_bleed if booklet_up == 4 and row == 0 else outer_bleed
                    if form_rotation == 90:
                        bleed_left, bleed_bottom, bleed_right, bleed_top = (
                            toward_top, toward_left, toward_bottom, toward_right,
                        )
                    elif form_rotation == 270:
                        bleed_left, bleed_bottom, bleed_right, bleed_top = (
                            toward_bottom, toward_right, toward_top, toward_left,
                        )
                    else:
                        bleed_left, bleed_bottom, bleed_right, bleed_top = (
                            toward_left, toward_bottom, toward_right, toward_top,
                        )
                    available = _rotated_bounds(
                        *_bleed_source_box(
                            source, (page_left, page_bottom, page_right, page_top),
                        ),
                        placement_rotation, scale,
                    )
                    clip_left = max(x - bleed_left, available[0] + offset_x)
                    clip_bottom = max(y - bleed_bottom, available[1] + offset_y)
                    clip_right = min(x + width + bleed_right, available[2] + offset_x)
                    clip_top = min(y + height + bleed_top, available[3] + offset_y)
                    _place_shared_form(
                        output_page, writer, source, xobjects, content_parts,
                        form_cache, transform,
                        clip_rect=(
                            clip_left, clip_bottom,
                            clip_right - clip_left, clip_top - clip_bottom,
                        ),
                    )
                    render_placements.append({
                        "x": x, "y": y,
                        "width": width, "height": height,
                        "bleed_left": bleed_left,
                        "bleed_right": bleed_right,
                        "bleed_bottom": bleed_bottom,
                        "bleed_top": bleed_top,
                    })
                    metadata_placements.append({
                        "page": entry["number"],
                        "sheet": physical_sheet,
                        "booklet_sheet": logical_sheet + 1,
                        "side": side_name.lower().replace(" ", "_"),
                        "repeat_booklet": row + 1,
                        "position": f"r{row + 1}c{column + 1}",
                        "row": row + 1,
                        "column": column + 1,
                        "rotation": placement_rotation,
                        "x_mm": round(x / mm, 4),
                        "y_mm": round(y / mm, 4),
                        "width_mm": round(width / mm, 4),
                        "height_mm": round(height / mm, 4),
                        "creep_mm": round(creep / mm, 4),
                    })
                _finish_shared_page(output_page, writer, xobjects, content_parts)
                _apply_sheet_marks(
                    output_page,
                    render_placements,
                    config,
                    fold_lines=fold_lines,
                    label=(
                        f"LIBRETTO · SEGNATURA {signature_index + 1} · "
                        f"FORMA {physical_sheet} · {side_name}"
                    ),
                    head_direction="left" if form_rotation else "top",
                )
                writer.add_page(output_page)

    Path(output_path).parent.mkdir(parents=True, exist_ok=True)
    with open(output_path, "wb") as output_file:
        writer.write(output_file)

    return {
        "layout_mode": "booklet",
        "sheet_width_mm": float(config["sheet_width_mm"]),
        "sheet_height_mm": float(config["sheet_height_mm"]),
        "signature_pages": signature_pages,
        "signatures": signature_count,
        "physical_sheets": physical_sheet,
        "sheets": len(writer.pages),
        "input_pages": input_pages,
        "output_document_pages": padded_pages,
        "inserted_blank_pages": padded_pages - input_pages,
        "scale": round(scale, 6),
        "binding": binding,
        "binding_method": binding_method,
        "pages_per_side": booklet_up,
        "pages_per_sheet": booklet_up * 2,
        "positions_per_side": booklet_up,
        "columns": 2,
        "rows": form_rows,
        # The form turns as one piece; the page never turns on its own, so the
        # spine always stays on the same edge of the product.
        "form_rotation": form_rotation,
        "source_rotation": form_rotation,
        "spine_axis": "horizontal" if form_rotation else "vertical",
        "scheme": "two_2up_forms_4up" if booklet_up == 4 else "JDF_F4-1_half_fold_2up",
        "booklet_up": booklet_up,
        "booklet_work_style": booklet_work_style,
        "booklet_repeat_mode": repeat_mode,
        "booklet_repeats_per_sheet": 2 if booklet_up == 4 else 1,
        "repeat_columns": 1,
        "repeat_rows": form_rows,
        "signature_sizes": signature_sizes,
        "last_signature_padding": last_signature_padding,
        "creep_mm": float(config.get("creep_mm", 0)),
        "head_trim_mm": 0.0,
        "booklet_bleed_mm": round(booklet_bleed / mm, 4),
        "placements": metadata_placements,
    }


def impose(input_path: str, output_path: str, config: dict) -> dict:
    reader = PdfReader(input_path)
    if not reader.pages:
        raise ValueError("Il PDF sorgente non contiene pagine")

    layout_mode = str(config.get("layout_mode", "grid"))
    if layout_mode == "nesting":
        return _impose_nesting(reader, output_path, config)
    if layout_mode == "booklet":
        return _impose_booklet(reader, output_path, config)
    if layout_mode != "grid":
        raise ValueError(f"Tipo di disposizione non valido: {layout_mode}")

    sheet_width = float(config["sheet_width_mm"]) * mm
    sheet_height = float(config["sheet_height_mm"]) * mm
    anchor = str(config.get("anchor", "top_left"))
    if anchor not in {"top_left", "top_center", "top_right", "center", "bottom_left", "bottom_center", "bottom_right"}:
        raise ValueError(f"Punto di ancoraggio non valido: {anchor}")
    offset_x = float(config.get("offset_x_mm", 0)) * mm
    offset_y = float(config.get("offset_y_mm", 0)) * mm
    margin_left = float(config.get("margin_left_mm", offset_x / mm)) * mm
    margin_right = float(config.get("margin_right_mm", 0)) * mm
    margin_top = float(config.get("margin_top_mm", offset_y / mm)) * mm
    margin_bottom = float(config.get("margin_bottom_mm", 0)) * mm
    gap_x = float(config.get("gap_x_mm", 0)) * mm
    gap_y = float(config.get("gap_y_mm", 0)) * mm
    fill_last_sheet = bool(config.get("fill_last_sheet", False))
    trim_sheet_height = bool(config.get("trim_sheet_height", False))
    repeat_product = bool(config.get("repeat_product", False))
    page_distribution = str(config.get("page_distribution", "sequential"))
    if page_distribution not in {"sequential", "repeat_each"}:
        raise ValueError("Distribuzione pagine non valida")
    repeat_each_element = page_distribution == "repeat_each"
    fixed_columns = int(config.get("columns", 0) or 0)
    fixed_rows = int(config.get("rows", 0) or 0)
    if fixed_columns < 0 or fixed_rows < 0:
        raise ValueError("Righe e colonne non possono essere negative")

    work_style = str(config.get("work_style", ""))
    if work_style not in {"single_sided", "sheetwise", "work_and_turn", "work_and_tumble", "perfecting"}:
        plate_mode = str(config.get("plate_mode", ""))
        legacy_mode = str(config.get("double_sided_mode", "none"))
        if plate_mode == "duplex_separate":
            work_style = "sheetwise"
        elif plate_mode == "duplex_same_set" or legacy_mode in {"horizontal", "vertical"}:
            orientation = str(config.get("duplex_orientation", ""))
            work_style = "work_and_tumble" if orientation == "foot_to_foot" or legacy_mode == "vertical" else "work_and_turn"
        else:
            work_style = "single_sided"
    duplex_enabled = work_style != "single_sided"
    if repeat_each_element and duplex_enabled and len(reader.pages) % 2:
        raise ValueError(
            "Una plancia per elemento richiede coppie complete fronte/retro"
        )
    plate_mode = (
        "duplex_separate" if work_style in {"sheetwise", "perfecting"}
        else "duplex_same_set" if work_style in {"work_and_turn", "work_and_tumble"}
        else "single_sided"
    )
    duplex_orientation = "foot_to_foot" if work_style == "work_and_tumble" else "head_to_head"
    double_sided_mode = (
        "horizontal" if work_style == "work_and_turn" else
        "vertical" if work_style == "work_and_tumble" else
        "none"
    )

    first_page = reader.pages[0]
    source_left, source_bottom, source_right, source_top, source_box_name = _imposition_box(first_page)
    source_width = source_right - source_left
    source_height = source_top - source_bottom
    bleed_mode = str(config.get("bleed_mode", "existing"))
    bleed = (
        max(0.0, float(config.get("bleed_mm", 0))) * mm
        if bleed_mode == "scale" else 0.0
    )
    available_width = sheet_width - margin_left - margin_right
    available_height = sheet_height - margin_top - margin_bottom

    def orientation_capacity(rotation):
        width, height = (
            (source_height, source_width)
            if rotation in {90, 270} else (source_width, source_height)
        )
        if bleed_mode == "scale":
            width += 2 * bleed
            height += 2 * bleed
        columns_for_rotation = fixed_columns or max(
            0, 1 + math.floor((available_width - width) / (width + gap_x))
        )
        rows_for_rotation = fixed_rows or max(
            0, 1 + math.floor((available_height - height) / (height + gap_y))
        )
        required_width_for_rotation = columns_for_rotation * width + max(0, columns_for_rotation - 1) * gap_x
        required_height_for_rotation = rows_for_rotation * height + max(0, rows_for_rotation - 1) * gap_y
        if required_width_for_rotation > available_width + 0.01 or required_height_for_rotation > available_height + 0.01:
            return -1
        return columns_for_rotation * rows_for_rotation

    legacy_source_direction = str(config.get("source_direction", ""))
    if "auto_rotate" not in config and legacy_source_direction in {"top", "right", "bottom", "left"}:
        source_rotation = {"top": 0, "right": 270, "bottom": 180, "left": 90}[legacy_source_direction]
    elif bool(config.get("auto_rotate", False)) and orientation_capacity(270) > orientation_capacity(0):
        source_rotation = 270
    else:
        source_rotation = 0
    source_direction = {0: "top", 90: "left", 180: "bottom", 270: "right"}[source_rotation]
    visible_left, visible_bottom, visible_right, visible_top = (
        _existing_bleed_box(
            first_page,
            (source_left, source_bottom, source_right, source_top),
        )
        if bleed_mode == "existing"
        else (source_left, source_bottom, source_right, source_top)
    )
    trim_width, trim_height = (
        (source_height, source_width)
        if source_rotation in {90, 270}
        else (source_width, source_height)
    )
    if bleed_mode == "existing":
        content_scale = 1.0
        placed_width = trim_width
        placed_height = trim_height
        trim_inset_x = 0.0
        trim_inset_y = 0.0
        trim_bounds = _rotated_bounds(
            source_left, source_bottom, source_right, source_top, source_rotation
        )
        visible_bounds = _rotated_bounds(
            visible_left, visible_bottom, visible_right, visible_top, source_rotation
        )
        clip_left = trim_bounds[0] - visible_bounds[0]
        clip_bottom = trim_bounds[1] - visible_bounds[1]
        clip_right = visible_bounds[2] - trim_bounds[2]
        clip_top = visible_bounds[3] - trim_bounds[3]
    else:
        target_width = trim_width + 2 * bleed
        target_height = trim_height + 2 * bleed
        content_scale = min(
            target_width / trim_width,
            target_height / trim_height,
        )
        placed_width = target_width
        placed_height = target_height
        trim_inset_x = (placed_width - trim_width * content_scale) / 2
        trim_inset_y = (placed_height - trim_height * content_scale) / 2
        clip_left = clip_bottom = clip_right = clip_top = 0.0
    for index, page in enumerate(reader.pages[1:], start=2):
        page_left, page_bottom, page_right, page_top, _ = _imposition_box(page)
        page_width = page_right - page_left
        page_height = page_top - page_bottom
        if abs(page_width - source_width) > 0.01 or abs(page_height - source_height) > 0.01:
            raise ValueError(
                f"La pagina {index} ha dimensioni diverse dalla prima pagina"
            )

    if placed_width > available_width or placed_height > available_height:
        raise ValueError(
            "L'oggetto non entra nel foglio con il punto di partenza configurato"
        )
    auto_columns = 1 + math.floor((available_width - placed_width) / (placed_width + gap_x))
    auto_rows = 1 + math.floor((available_height - placed_height) / (placed_height + gap_y))
    columns = fixed_columns or auto_columns
    rows = fixed_rows or auto_rows
    explicit_same_form_style = work_style in {"work_and_turn", "work_and_tumble"} and config.get("work_style") in {
        "work_and_turn", "work_and_tumble"
    }
    paired_input_hint = (
        explicit_same_form_style
        and
        isinstance(config.get("side_page_counts"), list)
        and len(config.get("side_page_counts")) == 2
    )
    if (repeat_product or repeat_each_element) and work_style == "work_and_turn" and (
        len(reader.pages) == 2 or paired_input_hint or repeat_each_element
    ) and columns % 2:
        columns -= 1
    if (repeat_product or repeat_each_element) and work_style == "work_and_tumble" and (
        len(reader.pages) == 2 or paired_input_hint or repeat_each_element
    ) and rows % 2:
        rows -= 1
    if columns < 1 or rows < 1:
        raise ValueError("Il metodo di stampa selezionato non entra nel foglio")
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
    same_form_product = False
    same_form_product_capacity = 0
    same_form_product_count = 0
    repeat_each_separate = False
    repeat_each_same_form = False
    same_form_paired_input = (
        not repeat_each_element
        and
        explicit_same_form_style
        and
        side_page_counts is not None
        and work_style in {"work_and_turn", "work_and_tumble"}
        and input_pages > 2
        and input_pages % 2 == 0
    )
    repeated_duplex_product = repeat_product and input_pages == 2 and duplex_enabled
    if repeat_each_element:
        if work_style in {"work_and_turn", "work_and_tumble"}:
            repeat_each_same_form = True
            same_form_product = True
            sheets = input_pages // 2
        else:
            repeat_each_separate = True
            sheets = input_pages
        placements_total = sheets * slots_per_sheet
    elif side_page_counts is not None and not same_form_paired_input:
        if not duplex_enabled:
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
    elif repeated_duplex_product and work_style in {"sheetwise", "perfecting"}:
        duplex_groups = ((0, 1), (1, 1))
        sheets = 2
        placements_total = slots_per_sheet * 2
    elif repeated_duplex_product:
        same_form_product = True
        sheets = 1
        placements_total = slots_per_sheet
    elif same_form_paired_input:
        same_form_product = True
        same_form_product_capacity = (
            (columns // 2) * rows
            if work_style == "work_and_turn"
            else columns * (rows // 2)
        )
        same_form_product_count = input_pages // 2
        sheets = math.ceil(same_form_product_count / same_form_product_capacity)
        placements_total = (
            sheets * same_form_product_capacity * 2
            if fill_last_sheet
            else input_pages
        )
    else:
        sheets = math.ceil(input_pages / slots_per_sheet)
        placements_total = sheets * slots_per_sheet if fill_last_sheet else input_pages
    writer = PdfWriter()
    form_cache = {}
    use_shared_resources = config.get("shared_resources", True) is not False
    metadata_placements = []

    def flipped_rotation(rotation, axis):
        if axis == "horizontal":
            return {0: 0, 90: 270, 180: 180, 270: 90}[rotation]
        return {0: 180, 90: 90, 180: 0, 270: 270}[rotation]

    for sheet_index in range(sheets):
        if trim_sheet_height:
            if duplex_groups:
                pair_index = sheet_index // 2
                side_index = sheet_index % 2
                side_total = duplex_groups[side_index][1]
                group_offset = pair_index * slots_per_sheet
                placements_on_sheet = (
                    slots_per_sheet if fill_last_sheet or repeated_duplex_product else
                    min(slots_per_sheet, max(0, side_total - group_offset))
                )
            else:
                remaining = placements_total - sheet_index * slots_per_sheet
                placements_on_sheet = min(slots_per_sheet, max(0, remaining))
            used_rows = max(1, math.ceil(placements_on_sheet / columns))
            used_height = (
                used_rows * placed_height +
                max(0, used_rows - 1) * gap_y
            )
            output_height = min(sheet_height, margin_top + used_height + margin_bottom)
        else:
            output_height = sheet_height
        output_page = PageObject.create_blank_page(
            width=sheet_width, height=output_height
        )
        xobjects = DictionaryObject()
        content_parts = []
        rendered_placements = []
        sheet_head_rotation = source_rotation
        if repeat_each_separate:
            group_start = sheet_index
            group_pages = 1
            group_offset = 0
            remaining = slots_per_sheet
            placements_on_sheet = slots_per_sheet
        elif same_form_paired_input:
            remaining_products = same_form_product_count - sheet_index * same_form_product_capacity
            products_on_sheet = (
                same_form_product_capacity
                if fill_last_sheet
                else min(same_form_product_capacity, max(0, remaining_products))
            )
            placements_on_sheet = products_on_sheet * 2
            group_start = sheet_index * same_form_product_capacity
            group_pages = products_on_sheet
            group_offset = 0
            remaining = placements_on_sheet
        elif duplex_groups:
            pair_index = sheet_index // 2
            side_index = sheet_index % 2
            group_start, group_pages = duplex_groups[side_index]
            group_offset = pair_index * slots_per_sheet
            remaining = group_pages - group_offset
            placements_on_sheet = (
                slots_per_sheet
                if fill_last_sheet or repeated_duplex_product
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
            source_index = None
            placement_rotation = source_rotation
            if same_form_paired_input and work_style == "work_and_turn":
                half_columns = columns // 2
                product_on_sheet = slot_index // 2
                side_index = slot_index % 2
                product_index = sheet_index * same_form_product_capacity + product_on_sheet
                row = product_on_sheet // half_columns
                base_column = product_on_sheet % half_columns
                column = base_column + (half_columns if side_index else 0)
                source_index = product_index * 2 + side_index
                if side_index:
                    placement_rotation = (source_rotation + 180) % 360
            elif same_form_paired_input and work_style == "work_and_tumble":
                half_rows = rows // 2
                product_on_sheet = slot_index // 2
                side_index = slot_index % 2
                product_index = sheet_index * same_form_product_capacity + product_on_sheet
                base_row = product_on_sheet // columns
                column = product_on_sheet % columns
                row = base_row + (half_rows if side_index else 0)
                source_index = product_index * 2 + side_index
                if side_index:
                    placement_rotation = (source_rotation + 180) % 360
            elif same_form_product and work_style == "work_and_turn":
                side_index = 0 if column < columns / 2 else 1
                source_index = (sheet_index * 2 if repeat_each_same_form else 0) + side_index
                if side_index == 1:
                    placement_rotation = (source_rotation + 180) % 360
            elif same_form_product and work_style == "work_and_tumble":
                side_index = 0 if row < rows / 2 else 1
                source_index = (sheet_index * 2 if repeat_each_same_form else 0) + side_index
                if side_index == 1:
                    placement_rotation = (source_rotation + 180) % 360
            if same_form_paired_input and source_index is not None and source_index >= input_pages:
                source_index %= input_pages
            is_back_sheet = False if same_form_paired_input else (
                sheet_index % 2 == 1
                if duplex_groups
                else sheet_index % 2 == 1 and duplex_enabled
            )
            mirror_sheetwise_back = is_back_sheet and work_style == "sheetwise"
            if mirror_sheetwise_back:
                placement_rotation = flipped_rotation(source_rotation, "horizontal")
            elif is_back_sheet and work_style == "perfecting":
                row = rows - 1 - row
                placement_rotation = flipped_rotation(source_rotation, "vertical")
            grows_left = anchor.endswith("right")
            grows_up = anchor.startswith("bottom")
            if anchor == "center" or anchor.endswith("center"):
                centered_x = margin_left + (available_width - required_width) / 2
                x = centered_x + column * (placed_width + gap_x)
            elif grows_left:
                x = sheet_width - margin_right - placed_width - column * (
                    placed_width + gap_x
                )
            else:
                x = margin_left + column * (placed_width + gap_x)
            if anchor == "center":
                y = margin_bottom + (available_height - required_height) / 2 + row * (placed_height + gap_y)
            elif grows_up:
                y = margin_bottom + row * (placed_height + gap_y)
            else:
                y = output_height - margin_top - placed_height - row * (
                    placed_height + gap_y
                )
            if mirror_sheetwise_back:
                # The back is printed after turning the sheet on its vertical
                # axis. Mirror the final position, not merely the cell order:
                # a front anchored top-left must therefore have its back
                # anchored top-right, including the unused area and margins.
                x = sheet_width - x - placed_width
                column = columns - 1 - column

            if source_index is None:
                if repeat_each_separate:
                    source_index = group_start
                elif repeat_product and (input_pages == 1 or repeated_duplex_product):
                    source_index = group_start
                else:
                    source_index = group_start + ((group_offset + slot_index) % group_pages)
            source = reader.pages[source_index]
            source_left, source_bottom, source_right, source_top, _ = _imposition_box(source)
            trim_x = x + trim_inset_x
            trim_y = y + trim_inset_y

            trim_bounds = _rotated_bounds(
                source_left,
                source_bottom,
                source_right,
                source_top,
                placement_rotation,
                content_scale,
            )
            transform = Transformation().scale(content_scale).rotate(placement_rotation).translate(
                trim_x - trim_bounds[0],
                trim_y - trim_bounds[1],
            )
            _place_shared_form(
                output_page, writer, source, xobjects, content_parts,
                form_cache, transform,
                clip_rect=(
                    x - clip_left,
                    y - clip_bottom,
                    placed_width + clip_left + clip_right,
                    placed_height + clip_bottom + clip_top,
                ),
            )
            rendered_placements.append({
                "x": x + trim_inset_x,
                "y": y + trim_inset_y,
                "width": trim_width,
                "height": trim_height,
                "bleed_x": trim_inset_x,
                "bleed_y": trim_inset_y,
            })
            metadata_placements.append({
                "sheet": sheet_index + 1,
                "side": "back" if is_back_sheet else "front",
                "page": source_index + 1,
                "row": row + 1,
                "column": column + 1,
                "rotation": placement_rotation,
                "x_mm": x / mm,
                "y_mm": y / mm,
            })
            if slot_index == 0:
                sheet_head_rotation = placement_rotation

        _finish_shared_page(output_page, writer, xobjects, content_parts)
        _apply_sheet_marks(
            output_page,
            rendered_placements,
            config,
            label=f"RIPETIZIONE · FOGLIO {sheet_index + 1}",
            head_direction={0: "top", 90: "left", 180: "bottom", 270: "right"}[sheet_head_rotation],
        )
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
        "object_width_mm": round(trim_width / mm, 4),
        "object_height_mm": round(trim_height / mm, 4),
        "bleed_mode": str(config.get("bleed_mode", "existing")),
        "bleed_mm": float(config.get("bleed_mm", 0)),
        "rows": rows,
        "columns": columns,
        "rows_mode": "fixed" if fixed_rows else "automatic",
        "columns_mode": "fixed" if fixed_columns else "automatic",
        "slots_per_sheet": slots_per_sheet,
        "input_pages": input_pages,
        "placed_pages": placements_total,
        "sheets": sheets,
        "double_sided_mode": double_sided_mode,
        "plate_mode": plate_mode,
        "duplex_orientation": duplex_orientation,
        "work_style": work_style,
        "page_distribution": page_distribution,
        "source_direction": source_direction,
        "source_rotation": source_rotation,
        "trim_sheet_height": trim_sheet_height,
        "side_page_counts": (
            [duplex_groups[0][1], duplex_groups[1][1]]
            if duplex_groups
            else None
        ),
        "sheet_pairs": (
            sheets // 2
            if duplex_groups or (repeat_each_separate and duplex_enabled)
            else None
        ),
        "scale": 1.0,
        "shared_resources": use_shared_resources,
        "placements": metadata_placements,
    }


def add_text_label(
    input_path: str, output_path: str, text: str, config: dict
) -> dict:
    reader = PdfReader(input_path)
    if not reader.pages:
        raise ValueError("Il PDF sorgente non contiene pagine")

    anchor = str(config.get("anchor", "top_left"))
    allowed_anchors = {
        "top_left", "top_center", "top_right", "center",
        "bottom_left", "bottom_center", "bottom_right",
    }
    if anchor not in allowed_anchors:
        raise ValueError(f"Posizione testo non valida: {anchor}")

    font = str(config.get("font", "Times-Roman"))
    font_size = float(config.get("font_size_pt", 18))
    if font_size <= 0:
        raise ValueError("La dimensione del testo deve essere maggiore di zero")
    offset_x = float(config.get("offset_x_mm", 0)) * mm
    offset_y = float(config.get("offset_y_mm", 5)) * mm
    padding_x = float(config.get("padding_x_mm", 2)) * mm
    padding_y = float(config.get("padding_y_mm", 1.5)) * mm
    try:
        background_color = colors.HexColor(str(config.get("background_color", "#222222")))
        text_color = colors.HexColor(str(config.get("text_color", "#ffffff")))
    except ValueError as exc:
        raise ValueError("Colore testo o sfondo non valido") from exc

    writer = PdfWriter()
    for page in reader.pages:
        width = float(page.mediabox.width)
        height = float(page.mediabox.height)
        overlay_buffer = io.BytesIO()
        overlay = canvas.Canvas(overlay_buffer, pagesize=(width, height))
        try:
            overlay.setFont(font, font_size)
        except KeyError as exc:
            raise ValueError(f"Font PDF non disponibile: {font}") from exc

        text_width = stringWidth(text, font, font_size)
        box_width = text_width + (2 * padding_x)
        box_height = font_size + (2 * padding_y)
        if anchor.endswith("left"):
            box_x = offset_x
        elif anchor.endswith("right"):
            box_x = width - offset_x - box_width
        else:
            box_x = (width - box_width) / 2 + offset_x
        if anchor == "center":
            box_y = (height - box_height) / 2 + offset_y
        elif anchor.startswith("top"):
            box_y = height - offset_y - box_height
        else:
            box_y = offset_y

        overlay.setFillColor(background_color)
        overlay.roundRect(box_x, box_y, box_width, box_height, 1.5 * mm, fill=1, stroke=0)
        overlay.setFillColor(text_color)
        overlay.drawString(box_x + padding_x, box_y + padding_y, text)
        overlay.showPage()
        overlay.save()
        overlay_buffer.seek(0)
        page.merge_page(PdfReader(overlay_buffer).pages[0], over=True)
        writer.add_page(page)
        writer.reset_translation(reader)

    Path(output_path).parent.mkdir(parents=True, exist_ok=True)
    with open(output_path, "wb") as output_file:
        writer.write(output_file)

    return {
        "text": text,
        "pages_labeled": len(reader.pages),
        "anchor": anchor,
        "font": font,
        "font_size_pt": font_size,
        "background_color": str(config.get("background_color", "#222222")),
        "text_color": str(config.get("text_color", "#ffffff")),
        "padding_x_mm": float(config.get("padding_x_mm", 2)),
        "padding_y_mm": float(config.get("padding_y_mm", 1.5)),
        "offset_x_mm": float(config.get("offset_x_mm", 0)),
        "offset_y_mm": float(config.get("offset_y_mm", 5)),
    }


def resize_pdf_pages(input_path: str, output_path: str, config: dict) -> dict:
    reader = PdfReader(input_path)
    if not reader.pages:
        raise ValueError("Il PDF sorgente non contiene pagine")

    target_width = float(config.get("width_mm", 0)) * mm
    target_height = float(config.get("height_mm", 0)) * mm
    if target_width <= 0 or target_height <= 0:
        raise ValueError("Le dimensioni finali devono essere maggiori di zero")
    mode = str(config.get("mode", "contain"))
    if mode not in {"contain", "stretch"}:
        raise ValueError(f"Modalità ridimensionamento non valida: {mode}")

    writer = PdfWriter()
    scales = []
    for source in reader.pages:
        source_width = float(source.mediabox.width)
        source_height = float(source.mediabox.height)
        output_page = PageObject.create_blank_page(
            width=target_width, height=target_height
        )
        if mode == "stretch":
            scale_x = target_width / source_width
            scale_y = target_height / source_height
            translate_x = 0
            translate_y = 0
        else:
            scale_x = scale_y = min(
                target_width / source_width,
                target_height / source_height,
            )
            translate_x = (target_width - source_width * scale_x) / 2
            translate_y = (target_height - source_height * scale_y) / 2
        transformation = (
            Transformation()
            .scale(scale_x, scale_y)
            .translate(translate_x, translate_y)
        )
        output_page.merge_transformed_page(source, transformation, over=True)
        writer.add_page(output_page)
        writer.reset_translation(reader)
        scales.append([scale_x, scale_y])

    Path(output_path).parent.mkdir(parents=True, exist_ok=True)
    with open(output_path, "wb") as output_file:
        writer.write(output_file)

    return {
        "input_pages": len(reader.pages),
        "output_pages": len(reader.pages),
        "width_mm": float(config.get("width_mm", 0)),
        "height_mm": float(config.get("height_mm", 0)),
        "mode": mode,
        "scales": scales,
    }


def barcode_pdf(data: str, output_path: str, config: dict) -> dict:
    width_mm = float(config.get("width_mm", 90))
    height_mm = float(config.get("height_mm", 29))
    bar_height_mm = float(config.get("bar_height_mm", 20))
    font_size_pt = float(config.get("font_size_pt", 18))
    text_distance_pt = float(config.get("text_distance_pt", 6))
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
    # ReportLab keeps the human-readable text size as a mutable attribute.
    # Set it explicitly so the label can use shorter bars and a more legible
    # order number below them.
    barcode.fontSize = font_size_pt
    barcode.textDistance = text_distance_pt
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
        "font_size_pt": font_size_pt,
        "text_distance_pt": text_distance_pt,
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
    duplicate_parser.add_argument("--duplex-order", choices=("repeat", "grouped"), default="repeat")
    duplicate_parser.add_argument("--side-page-counts", default="")

    merge_parser = subparsers.add_parser("merge-pages")
    merge_parser.add_argument("--input", required=True, action="append")
    merge_parser.add_argument("--output", required=True)

    blanks_parser = subparsers.add_parser("insert-blanks")
    blanks_parser.add_argument("--input", required=True)
    blanks_parser.add_argument("--output", required=True)
    blanks_parser.add_argument("--config", required=True)

    label_parser = subparsers.add_parser("add-text-label")
    label_parser.add_argument("--input", required=True)
    label_parser.add_argument("--output", required=True)
    label_parser.add_argument("--text", required=True)
    label_parser.add_argument("--config", default="{}")

    resize_parser = subparsers.add_parser("resize-pages")
    resize_parser.add_argument("--input", required=True)
    resize_parser.add_argument("--output", required=True)
    resize_parser.add_argument("--config", required=True)

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
        result = duplicate_pages(
            args.input,
            args.output,
            args.copies,
            args.duplex_order,
            json.loads(args.side_page_counts) if args.side_page_counts else None,
        )
    elif args.command == "merge-pages":
        result = merge_pages(args.input, args.output)
    elif args.command == "insert-blanks":
        result = insert_blank_pages(
            args.input, args.output, json.loads(args.config)
        )
    elif args.command == "add-text-label":
        result = add_text_label(
            args.input, args.output, args.text, json.loads(args.config)
        )
    elif args.command == "resize-pages":
        result = resize_pdf_pages(
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
