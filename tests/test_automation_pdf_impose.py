import re
import tempfile
import unittest
from pathlib import Path

from pypdf import PdfReader, PdfWriter
from pypdf.generic import RectangleObject

from tools.automation_pdf.cli import barcode_pdf, impose, insert_blank_pages


class DuplexImpositionTest(unittest.TestCase):
    def make_pdf(self, path: Path, pages: int) -> None:
        writer = PdfWriter()
        for _ in range(pages):
            writer.add_blank_page(width=10, height=10)
        with path.open("wb") as output:
            writer.write(output)

    def config(self, **overrides) -> dict:
        config = {
            "sheet_width_mm": 100,
            "sheet_height_mm": 100,
            "rows": 7,
            "columns": 15,
            "anchor": "bottom_left",
            "offset_x_mm": 0,
            "offset_y_mm": 0,
            "gap_x_mm": 0,
            "gap_y_mm": 0,
            "fill_last_sheet": False,
            "double_sided_mode": "horizontal",
        }
        config.update(overrides)
        return config

    def test_52_front_and_52_back_produce_one_sheet_pair(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "paired.pdf"
            output = Path(directory) / "imposed.pdf"
            self.make_pdf(source, 104)

            metadata = impose(
                str(source),
                str(output),
                self.config(side_page_counts=[52, 52]),
            )

            self.assertEqual(2, len(PdfReader(output).pages))
            self.assertEqual(2, metadata["sheets"])
            self.assertEqual(1, metadata["sheet_pairs"])
            self.assertEqual([52, 52], metadata["side_page_counts"])
            self.assertEqual(104, metadata["placed_pages"])

    def test_105_front_and_105_back_produce_one_sheet_pair(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "paired.pdf"
            output = Path(directory) / "imposed.pdf"
            self.make_pdf(source, 210)

            metadata = impose(
                str(source),
                str(output),
                self.config(side_page_counts=[105, 105]),
            )

            self.assertEqual(2, len(PdfReader(output).pages))
            self.assertEqual(1, metadata["sheet_pairs"])
            self.assertEqual(210, metadata["placed_pages"])

    def test_mono_sequence_keeps_existing_packing_behavior(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "mono.pdf"
            output = Path(directory) / "imposed.pdf"
            self.make_pdf(source, 104)

            metadata = impose(
                str(source),
                str(output),
                self.config(double_sided_mode="none"),
            )

            self.assertEqual(1, len(PdfReader(output).pages))
            self.assertEqual(1, metadata["sheets"])
            self.assertIsNone(metadata["side_page_counts"])

    def test_duplex_counts_must_match_the_input_pdf(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "paired.pdf"
            output = Path(directory) / "imposed.pdf"
            self.make_pdf(source, 104)

            with self.assertRaisesRegex(
                ValueError, "non corrispondono alle pagine"
            ):
                impose(
                    str(source),
                    str(output),
                    self.config(side_page_counts=[50, 50]),
                )

    def test_center_anchor_centers_single_page_on_both_axes(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "center.pdf"
            output = Path(directory) / "centered.pdf"
            self.make_pdf(source, 1)

            metadata = impose(
                str(source),
                str(output),
                self.config(rows=1, columns=1, anchor="center", double_sided_mode="none"),
            )

            self.assertEqual("center", metadata["anchor"])
            self.assertEqual(1, len(PdfReader(output).pages))

    def test_plate_modes_distinguish_separate_and_same_set_duplex(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "duplex.pdf"
            self.make_pdf(source, 2)
            for plate_mode, orientation, expected_legacy in (
                ("duplex_separate", "head_to_head", "none"),
                ("duplex_same_set", "head_to_head", "horizontal"),
                ("duplex_same_set", "foot_to_foot", "vertical"),
            ):
                output = Path(directory) / f"{plate_mode}-{orientation}.pdf"
                metadata = impose(
                    str(source),
                    str(output),
                    self.config(
                        rows=1,
                        columns=1,
                        double_sided_mode="none",
                        plate_mode=plate_mode,
                        duplex_orientation=orientation,
                    ),
                )
                self.assertEqual(2, metadata["sheets"])
                self.assertEqual(plate_mode, metadata["plate_mode"])
                self.assertEqual(orientation, metadata["duplex_orientation"])
                self.assertEqual(expected_legacy, metadata["double_sided_mode"])

    def test_grid_rotates_source_by_selected_direction(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "direction.pdf"
            writer = PdfWriter()
            writer.add_blank_page(width=80, height=50)
            with source.open("wb") as stream:
                writer.write(stream)
            for direction, expected_size in (
                ("top", (80, 50)),
                ("right", (50, 80)),
                ("bottom", (80, 50)),
                ("left", (50, 80)),
            ):
                output = Path(directory) / f"{direction}.pdf"
                metadata = impose(
                    str(source),
                    str(output),
                    self.config(
                        rows=1,
                        columns=1,
                        double_sided_mode="none",
                        source_direction=direction,
                    ),
                )
                self.assertEqual(direction, metadata["source_direction"])
                self.assertAlmostEqual(expected_size[0] * 25.4 / 72, metadata["object_width_mm"], places=3)
                self.assertAlmostEqual(expected_size[1] * 25.4 / 72, metadata["object_height_mm"], places=3)

    def test_a5_sheetwise_repeats_front_and_back_with_opposite_heads(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "a5-duplex.pdf"
            output = Path(directory) / "a5-sheetwise.pdf"
            writer = PdfWriter()
            for _ in range(2):
                writer.add_blank_page(
                    width=148 * 72 / 25.4,
                    height=210 * 72 / 25.4,
                )
            with source.open("wb") as stream:
                writer.write(stream)

            metadata = impose(
                str(source), str(output),
                self.config(
                    sheet_width_mm=450,
                    sheet_height_mm=320,
                    margin_left_mm=5,
                    margin_right_mm=5,
                    margin_top_mm=5,
                    margin_bottom_mm=5,
                    rows=0,
                    columns=0,
                    auto_rotate=True,
                    repeat_product=True,
                    work_style="sheetwise",
                    double_sided_mode="none",
                ),
            )

            self.assertEqual((2, 2), (metadata["columns"], metadata["rows"]))
            self.assertEqual(2, len(PdfReader(output).pages))
            self.assertEqual([1] * 4, [item["page"] for item in metadata["placements"][:4]])
            self.assertEqual([2] * 4, [item["page"] for item in metadata["placements"][4:]])
            self.assertEqual({270}, {item["rotation"] for item in metadata["placements"][:4]})
            self.assertEqual({90}, {item["rotation"] for item in metadata["placements"][4:]})

    def test_work_and_turn_places_both_sides_on_one_form(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "a5-duplex.pdf"
            output = Path(directory) / "a5-work-and-turn.pdf"
            writer = PdfWriter()
            for _ in range(2):
                writer.add_blank_page(width=148 * 72 / 25.4, height=210 * 72 / 25.4)
            with source.open("wb") as stream:
                writer.write(stream)

            metadata = impose(
                str(source), str(output),
                self.config(
                    sheet_width_mm=450,
                    sheet_height_mm=320,
                    margin_left_mm=5,
                    margin_right_mm=5,
                    margin_top_mm=5,
                    margin_bottom_mm=5,
                    rows=0,
                    columns=0,
                    auto_rotate=True,
                    repeat_product=True,
                    work_style="work_and_turn",
                    double_sided_mode="none",
                ),
            )

            self.assertEqual(1, len(PdfReader(output).pages))
            self.assertEqual([1, 2, 1, 2], [item["page"] for item in metadata["placements"]])
            self.assertEqual([270, 90, 270, 90], [item["rotation"] for item in metadata["placements"]])

    def test_work_and_turn_reverses_heads_for_landscape_source(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "a5-landscape-duplex.pdf"
            output = Path(directory) / "a5-landscape-work-and-turn.pdf"
            writer = PdfWriter()
            for _ in range(2):
                writer.add_blank_page(width=210 * 72 / 25.4, height=148 * 72 / 25.4)
            with source.open("wb") as stream:
                writer.write(stream)

            metadata = impose(
                str(source), str(output),
                self.config(
                    sheet_width_mm=450,
                    sheet_height_mm=320,
                    margin_left_mm=5,
                    margin_right_mm=5,
                    margin_top_mm=5,
                    margin_bottom_mm=5,
                    rows=0,
                    columns=0,
                    auto_rotate=True,
                    repeat_product=True,
                    work_style="work_and_turn",
                    double_sided_mode="none",
                ),
            )

            self.assertEqual([0, 180, 0, 180], [item["rotation"] for item in metadata["placements"]])

    def test_work_and_tumble_rotates_second_side_by_180_degrees(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "tumble-duplex.pdf"
            output = Path(directory) / "tumble.pdf"
            self.make_pdf(source, 2)

            metadata = impose(
                str(source), str(output),
                self.config(
                    rows=2,
                    columns=1,
                    repeat_product=True,
                    work_style="work_and_tumble",
                    double_sided_mode="none",
                ),
            )

            self.assertEqual([0, 180], [item["rotation"] for item in metadata["placements"]])

    def test_work_and_turn_keeps_duplicated_duplex_pairs_on_one_form(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "duplicated-duplex.pdf"
            output = Path(directory) / "duplicated-duplex-imposed.pdf"
            self.make_pdf(source, 20)

            metadata = impose(
                str(source), str(output),
                self.config(
                    rows=2,
                    columns=15,
                    repeat_product=True,
                    work_style="work_and_turn",
                    side_page_counts=[10, 10],
                    double_sided_mode="none",
                ),
            )

            self.assertEqual(1, len(PdfReader(output).pages))
            self.assertEqual(20, metadata["placed_pages"])
            self.assertEqual(1, metadata["sheets"])
            self.assertEqual(14, metadata["columns"])
            self.assertEqual({0, 180}, {item["rotation"] for item in metadata["placements"]})

    def test_single_sided_does_not_fill_empty_positions(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "single-sided.pdf"
            output = Path(directory) / "single-sided-imposed.pdf"
            self.make_pdf(source, 1)

            metadata = impose(
                str(source), str(output),
                self.config(
                    rows=2,
                    columns=2,
                    repeat_product=True,
                    work_style="single_sided",
                    double_sided_mode="none",
                ),
            )

            self.assertEqual(1, len(PdfReader(output).pages))
            self.assertEqual(1, metadata["placed_pages"])
            self.assertEqual(1, len(metadata["placements"]))

    def test_single_sided_keeps_multiple_pages_on_the_same_side(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "single-sided-pages.pdf"
            output = Path(directory) / "single-sided-pages-imposed.pdf"
            self.make_pdf(source, 4)

            metadata = impose(
                str(source), str(output),
                self.config(
                    rows=2,
                    columns=2,
                    repeat_product=True,
                    work_style="single_sided",
                    double_sided_mode="none",
                ),
            )

            self.assertEqual(1, len(PdfReader(output).pages))
            self.assertEqual([1, 2, 3, 4], [item["page"] for item in metadata["placements"]])

    def test_grid_uses_trimbox_instead_of_media_box(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "trimmed.pdf"
            output = Path(directory) / "trimmed-imposed.pdf"
            writer = PdfWriter()
            page = writer.add_blank_page(width=120, height=90)
            page.trimbox = RectangleObject([20, 15, 100, 65])
            with source.open("wb") as stream:
                writer.write(stream)

            metadata = impose(
                str(source),
                str(output),
                self.config(
                    rows=1,
                    columns=1,
                    double_sided_mode="none",
                    bleed_mode="scale",
                    bleed_mm=3,
                ),
            )

            self.assertAlmostEqual(80 * 25.4 / 72, metadata["object_width_mm"], places=3)
            self.assertAlmostEqual(50 * 25.4 / 72, metadata["object_height_mm"], places=3)
            contents = PdfReader(output).pages[0].get_contents().get_data()
            self.assertIn(b"re W n", contents)
            self.assertIn(b"0 0 97.007874015748 67.007874015748 re W n", contents)

    def test_grid_keeps_existing_bleedbox_and_clips_outside_it(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "with-bleed.pdf"
            output = Path(directory) / "with-bleed-imposed.pdf"
            writer = PdfWriter()
            page = writer.add_blank_page(width=120, height=90)
            page.trimbox = RectangleObject([20, 15, 100, 65])
            page.bleedbox = RectangleObject([11.496063, 6.496063, 108.503937, 73.503937])
            with source.open("wb") as stream:
                writer.write(stream)

            metadata = impose(
                str(source),
                str(output),
                self.config(rows=1, columns=1, double_sided_mode="none", bleed_mode="existing"),
            )

            self.assertAlmostEqual(80 * 25.4 / 72, metadata["object_width_mm"], places=3)
            self.assertAlmostEqual(50 * 25.4 / 72, metadata["object_height_mm"], places=3)
            contents = PdfReader(output).pages[0].get_contents().get_data()
            self.assertIn(
                b"-8.503937 -8.503937 97.007874 67.007874 re W n",
                contents,
            )

    def test_existing_bleed_does_not_increase_grid_pitch(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "business-card.pdf"
            output = Path(directory) / "business-card-imposed.pdf"
            mm = 72 / 25.4
            writer = PdfWriter()
            page = writer.add_blank_page(width=91 * mm, height=61 * mm)
            page.trimbox = RectangleObject([3 * mm, 3 * mm, 88 * mm, 58 * mm])
            page.bleedbox = RectangleObject([0, 0, 91 * mm, 61 * mm])
            with source.open("wb") as stream:
                writer.write(stream)

            metadata = impose(
                str(source),
                str(output),
                self.config(
                    sheet_width_mm=485,
                    sheet_height_mm=330,
                    margin_left_mm=10,
                    margin_right_mm=10,
                    margin_top_mm=10,
                    margin_bottom_mm=10,
                    rows=5,
                    columns=5,
                    gap_x_mm=4,
                    gap_y_mm=4,
                    fill_last_sheet=True,
                    double_sided_mode="none",
                    bleed_mode="existing",
                ),
            )

            self.assertEqual(25, metadata["placed_pages"])
            self.assertAlmostEqual(85, metadata["object_width_mm"], places=3)
            self.assertAlmostEqual(55, metadata["object_height_mm"], places=3)


class NestingImpositionTest(unittest.TestCase):
    POINTS_PER_MM = 72 / 25.4

    def make_pdf(self, path: Path, sizes_mm: list[tuple[float, float]]) -> None:
        writer = PdfWriter()
        for width, height in sizes_mm:
            writer.add_blank_page(
                width=width * self.POINTS_PER_MM,
                height=height * self.POINTS_PER_MM,
            )
        with path.open("wb") as output:
            writer.write(output)

    def config(self, **overrides) -> dict:
        config = {
            "layout_mode": "nesting",
            "sheet_width_mm": 100,
            "sheet_height_mm": 100,
            "anchor": "top_left",
            "offset_x_mm": 5,
            "offset_y_mm": 5,
            "gap_x_mm": 2,
            "gap_y_mm": 2,
            "rotate": False,
            "double_sided_mode": "none",
        }
        config.update(overrides)
        return config

    def test_mixed_page_sizes_are_packed_without_resizing(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "mixed.pdf"
            output = Path(directory) / "nested.pdf"
            self.make_pdf(source, [(50, 35), (30, 30), (20, 40)])

            metadata = impose(str(source), str(output), self.config())

            self.assertEqual(1, len(PdfReader(output).pages))
            self.assertEqual("nesting", metadata["layout_mode"])
            self.assertEqual(3, metadata["placed_pages"])
            self.assertEqual({1, 2, 3}, {item["page"] for item in metadata["placements"]})
            dimensions = {
                item["page"]: (item["width_mm"], item["height_mm"])
                for item in metadata["placements"]
            }
            self.assertEqual((50.0, 35.0), dimensions[1])
            self.assertEqual((30.0, 30.0), dimensions[2])
            self.assertEqual((20.0, 40.0), dimensions[3])

    def test_nesting_opens_additional_sheets_when_needed(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "large.pdf"
            output = Path(directory) / "nested.pdf"
            self.make_pdf(source, [(70, 70), (70, 70)])

            metadata = impose(str(source), str(output), self.config())

            self.assertEqual(2, len(PdfReader(output).pages))
            self.assertEqual(2, metadata["sheets"])

    def test_rotation_can_make_an_item_fit(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "rotation.pdf"
            output = Path(directory) / "nested.pdf"
            self.make_pdf(source, [(70, 40)])
            config = self.config(
                sheet_width_mm=60,
                sheet_height_mm=90,
                rotate=True,
            )

            metadata = impose(str(source), str(output), config)

            self.assertEqual(1, metadata["rotated_pages"])
            self.assertTrue(metadata["placements"][0]["rotated"])
            self.assertAlmostEqual(40, metadata["placements"][0]["width_mm"], places=3)
            self.assertAlmostEqual(70, metadata["placements"][0]["height_mm"], places=3)

    def test_item_that_cannot_fit_has_a_clear_error(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "too-large.pdf"
            output = Path(directory) / "nested.pdf"
            self.make_pdf(source, [(70, 40)])

            with self.assertRaisesRegex(ValueError, "pagina 1.*non entra"):
                impose(
                    str(source), str(output),
                    self.config(sheet_width_mm=60, sheet_height_mm=90, rotate=False),
                )

    def test_trim_sheet_height_uses_only_the_required_roll_length(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "small.pdf"
            output = Path(directory) / "nested.pdf"
            self.make_pdf(source, [(30, 40)])

            metadata = impose(
                str(source), str(output),
                self.config(sheet_height_mm=200, trim_sheet_height=True),
            )

            page = PdfReader(output).pages[0]
            height_mm = float(page.mediabox.height) / self.POINTS_PER_MM
            self.assertAlmostEqual(50, height_mm, places=2)
            self.assertAlmostEqual(50, metadata["output_sheet_heights_mm"][0], places=2)

    def test_nesting_rejects_duplex_mode(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "source.pdf"
            output = Path(directory) / "nested.pdf"
            self.make_pdf(source, [(30, 30)])

            with self.assertRaisesRegex(ValueError, "non supporta.*fronte/retro"):
                impose(
                    str(source), str(output),
                    self.config(double_sided_mode="horizontal"),
                )


class BookletImpositionTest(unittest.TestCase):
    POINTS_PER_MM = 72 / 25.4

    def make_pdf(self, path: Path, pages: int) -> None:
        writer = PdfWriter()
        for _ in range(pages):
            writer.add_blank_page(
                width=100 * self.POINTS_PER_MM,
                height=140 * self.POINTS_PER_MM,
            )
        with path.open("wb") as output:
            writer.write(output)

    def config(self, **overrides) -> dict:
        config = {
            "layout_mode": "booklet",
            "sheet_width_mm": 320,
            "sheet_height_mm": 450,
            "margin_left_mm": 10,
            "margin_right_mm": 10,
            "margin_top_mm": 10,
            "margin_bottom_mm": 10,
            "signature_pages": 8,
            "booklet_up": "2",
            "binding": "left",
            "gutter_mm": 0,
            "creep_mm": 0.5,
            "marks": {
                "crop": True,
                "registration": True,
                "fold": True,
                "color_bars": True,
                "job_info": True,
                "offset_mm": 2,
                "length_mm": 5,
                "line_width_pt": 0.35,
            },
        }
        config.update(overrides)
        return config

    def test_eight_page_saddle_uses_two_up_half_fold_spreads(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "booklet.pdf"
            output = Path(directory) / "imposed.pdf"
            self.make_pdf(source, 8)

            metadata = impose(str(source), str(output), self.config())

            self.assertEqual(4, len(PdfReader(output).pages))
            self.assertEqual(2, metadata["physical_sheets"])
            self.assertEqual(2, metadata["pages_per_side"])
            self.assertEqual("JDF_F4-1_half_fold_2up", metadata["scheme"])
            spreads = [
                item["page"]
                for item in metadata["placements"]
            ]
            self.assertEqual([8, 1, 2, 7, 6, 3, 4, 5], spreads)
            creep_by_sheet = {
                sheet: {item["creep_mm"] for item in metadata["placements"] if item["sheet"] == sheet}
                for sheet in (1, 2)
            }
            self.assertEqual({0.0}, creep_by_sheet[1])
            self.assertEqual({0.5}, creep_by_sheet[2])

    def test_incomplete_signature_is_padded_with_blank_pages(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "booklet.pdf"
            output = Path(directory) / "imposed.pdf"
            self.make_pdf(source, 5)

            metadata = impose(str(source), str(output), self.config())

            self.assertEqual(3, metadata["inserted_blank_pages"])
            self.assertEqual(8, metadata["output_document_pages"])
            self.assertEqual(4, len(PdfReader(output).pages))

    def test_perfect_bound_uses_separate_configured_signatures(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "book.pdf"
            output = Path(directory) / "perfect-bound.pdf"
            self.make_pdf(source, 20)

            metadata = impose(
                str(source), str(output),
                self.config(binding_method="perfect_bound", signature_pages=8),
            )

            self.assertEqual("perfect_bound", metadata["binding_method"])
            self.assertEqual(3, metadata["signatures"])
            self.assertEqual(0, metadata["inserted_blank_pages"])
            self.assertEqual([8, 8, 4], metadata["signature_sizes"])
            self.assertEqual(10, len(PdfReader(output).pages))

    def test_repeat_booklet_duplicates_the_same_two_up_form(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "booklet.pdf"
            output = Path(directory) / "repeat.pdf"
            self.make_pdf(source, 8)

            metadata = impose(
                str(source), str(output),
                self.config(booklet_repeat_mode="auto", booklet_repeat_gap_mm=4, auto_rotate=False, booklet_up="2"),
            )

            self.assertEqual(3, metadata["booklet_repeats_per_sheet"])
            self.assertEqual(6, metadata["positions_per_side"])
            first_side = [
                item["page"] for item in metadata["placements"]
                if item["sheet"] == 1 and item["side"] == "fronte"
            ]
            self.assertEqual([8, 1, 8, 1, 8, 1], first_side)

    def test_four_up_uses_fold_pattern_rotations_and_pairing(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "booklet.pdf"
            output = Path(directory) / "four-up.pdf"
            self.make_pdf(source, 8)

            metadata = impose(str(source), str(output), self.config(booklet_up="4"))

            self.assertEqual(2, len(PdfReader(output).pages))
            self.assertEqual(4, metadata["pages_per_side"])
            self.assertEqual("JDF_F8-7_saddle_4up", metadata["scheme"])
            front = [item for item in metadata["placements"] if item["side"] == "fronte"]
            back = [item for item in metadata["placements"] if item["side"] == "retro"]
            self.assertEqual([8, 1, 5, 4], [item["page"] for item in front])
            self.assertEqual([0, 0, 180, 180], [item["rotation"] for item in front])
            self.assertEqual([2, 7, 3, 6], [item["page"] for item in back])
            self.assertEqual([0, 0, 180, 180], [item["rotation"] for item in back])

    def test_four_up_sixteen_page_signature_nests_two_eight_page_sections(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "booklet.pdf"
            output = Path(directory) / "four-up-16.pdf"
            self.make_pdf(source, 16)

            metadata = impose(str(source), str(output), self.config(booklet_up="4"))

            self.assertEqual(4, len(PdfReader(output).pages))
            self.assertEqual(2, metadata["physical_sheets"])
            by_sheet_side = {}
            for item in metadata["placements"]:
                by_sheet_side.setdefault((item["sheet"], item["side"]), []).append(item["page"])
            # Outer section carries pages 1-4 and 13-16, inner section 5-12.
            self.assertEqual([16, 1, 13, 4], by_sheet_side[(1, "fronte")])
            self.assertEqual([2, 15, 3, 14], by_sheet_side[(1, "retro")])
            self.assertEqual([12, 5, 9, 8], by_sheet_side[(2, "fronte")])
            self.assertEqual([6, 11, 7, 10], by_sheet_side[(2, "retro")])

    def test_every_page_is_imposed_exactly_once(self):
        for pages, overrides in (
            (16, {"booklet_up": "4"}),
            (32, {"booklet_up": "4", "signature_pages": 32, "binding_method": "nested_saddle"}),
            (24, {"booklet_up": "2"}),
            (16, {"booklet_up": "4", "binding": "right"}),
        ):
            with self.subTest(pages=pages, **overrides):
                with tempfile.TemporaryDirectory() as directory:
                    source = Path(directory) / "booklet.pdf"
                    output = Path(directory) / "imposed.pdf"
                    self.make_pdf(source, pages)

                    metadata = impose(str(source), str(output), self.config(**overrides))

                    imposed = sorted(
                        item["page"] for item in metadata["placements"]
                        if item["page"] is not None
                    )
                    self.assertEqual(list(range(1, pages + 1)), imposed)

    def test_spread_pages_always_add_up_to_signature_size_plus_one(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "booklet.pdf"
            output = Path(directory) / "imposed.pdf"
            self.make_pdf(source, 32)

            metadata = impose(
                str(source), str(output),
                self.config(booklet_up="4", signature_pages=32, binding_method="nested_saddle"),
            )

            rows = {}
            for item in metadata["placements"]:
                rows.setdefault((item["sheet"], item["side"], item["row"]), []).append(item)
            for pair in rows.values():
                left, right = sorted(pair, key=lambda item: item["column"])
                self.assertEqual(33, left["page"] + right["page"])

    def test_head_trim_separates_the_two_rows_of_a_four_up_form(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "booklet.pdf"
            output = Path(directory) / "four-up.pdf"
            self.make_pdf(source, 8)

            metadata = impose(
                str(source), str(output),
                self.config(booklet_up="4", head_trim_mm=6),
            )

            self.assertEqual(6, metadata["head_trim_mm"])
            top = next(item for item in metadata["placements"] if item["row"] == 1)
            bottom = next(item for item in metadata["placements"] if item["row"] == 2)
            self.assertAlmostEqual(
                6.0,
                top["y_mm"] - (bottom["y_mm"] + bottom["height_mm"]),
                places=3,
            )

    def test_two_up_form_has_no_head_trim(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "booklet.pdf"
            output = Path(directory) / "imposed.pdf"
            self.make_pdf(source, 8)

            metadata = impose(str(source), str(output), self.config(booklet_up="2"))

            self.assertEqual(0, metadata["head_trim_mm"])

    def test_bleed_is_kept_outside_and_cut_at_the_spine(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "bleed.pdf"
            output = Path(directory) / "imposed.pdf"
            writer = PdfWriter()
            for _ in range(4):
                page = writer.add_blank_page(
                    width=106 * self.POINTS_PER_MM,
                    height=146 * self.POINTS_PER_MM,
                )
                page.trimbox = RectangleObject([
                    3 * self.POINTS_PER_MM, 3 * self.POINTS_PER_MM,
                    103 * self.POINTS_PER_MM, 143 * self.POINTS_PER_MM,
                ])
                page.bleedbox = RectangleObject([0, 0, 106 * self.POINTS_PER_MM, 146 * self.POINTS_PER_MM])
            with source.open("wb") as handle:
                writer.write(handle)

            impose(str(source), str(output), self.config(booklet_bleed_mm=3, creep_mm=0))

            first_side = PdfReader(output).pages[0]
            clips = [
                [float(value) for value in match]
                for match in re.findall(
                    r"q ([\d.-]+) ([\d.-]+) ([\d.-]+) ([\d.-]+) re W n",
                    first_side.get_contents().get_data().decode("ascii"),
                )
            ]
            self.assertEqual(2, len(clips))
            left, right = sorted(clips, key=lambda clip: clip[0])
            # 100x140 trim plus 3 mm of bleed on the three outer sides only.
            self.assertAlmostEqual(103.0, left[2] / self.POINTS_PER_MM, places=3)
            self.assertAlmostEqual(146.0, left[3] / self.POINTS_PER_MM, places=3)
            self.assertAlmostEqual(103.0, right[2] / self.POINTS_PER_MM, places=3)
            # The two clips meet at the fold: continuous artwork, no overlap.
            self.assertAlmostEqual(0.0, right[0] - (left[0] + left[2]), places=6)

    def test_the_spine_stays_on_the_long_edge_whichever_way_the_sheet_runs(self):
        # 100x140 source: the spine belongs on the 140 mm edge. A sheet that
        # only fits the form sideways must turn the whole form, not the pages.
        # The 4-up form measures 200x286 mm: 320x450 takes it upright, 320x230
        # only sideways.
        for sheet, expected_rotation in (((320, 450), 0), ((320, 230), 90)):
            with self.subTest(sheet=sheet):
                with tempfile.TemporaryDirectory() as directory:
                    source = Path(directory) / "booklet.pdf"
                    output = Path(directory) / "imposed.pdf"
                    self.make_pdf(source, 8)

                    metadata = impose(
                        str(source), str(output),
                        self.config(
                            sheet_width_mm=sheet[0], sheet_height_mm=sheet[1],
                            booklet_up="4", creep_mm=0,
                        ),
                    )

                    self.assertEqual(expected_rotation, metadata["form_rotation"])
                    self.assertEqual(1.0, metadata["scale"])
                    first, second = metadata["placements"][:2]
                    if expected_rotation:
                        # Turned form: the pair meets along a horizontal edge.
                        self.assertAlmostEqual(first["x_mm"], second["x_mm"], places=3)
                        shared_edge = first["width_mm"]
                    else:
                        self.assertAlmostEqual(first["y_mm"], second["y_mm"], places=3)
                        shared_edge = first["height_mm"]
                    self.assertAlmostEqual(140.0, shared_edge, places=3)

    def test_four_up_rejects_signatures_that_are_not_multiples_of_eight(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "booklet.pdf"
            output = Path(directory) / "imposed.pdf"
            self.make_pdf(source, 12)

            with self.assertRaises(ValueError):
                impose(str(source), str(output), self.config(booklet_up="4"))

    def test_nested_saddle_can_complete_last_group_only_to_multiple_of_four(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "book.pdf"
            output = Path(directory) / "nested.pdf"
            self.make_pdf(source, 18)

            metadata = impose(
                str(source), str(output),
                self.config(binding_method="nested_saddle", signature_pages=16),
            )

            self.assertEqual([16, 4], metadata["signature_sizes"])
            self.assertEqual(2, metadata["inserted_blank_pages"])
            self.assertEqual(10, len(PdfReader(output).pages))


class InsertBlankPagesTest(unittest.TestCase):
    def make_pdf(self, path: Path, pages: int) -> None:
        writer = PdfWriter()
        for _ in range(pages):
            writer.add_blank_page(width=100, height=80)
        with path.open("wb") as output:
            writer.write(output)

    def test_repeating_rule_inserts_after_source_page_intervals(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "source.pdf"
            output = Path(directory) / "with-blanks.pdf"
            self.make_pdf(source, 20)

            metadata = insert_blank_pages(
                str(source),
                str(output),
                {
                    "quantity": 50,
                    "rules": [{
                        "label": "Gruppi da nove",
                        "target": "all",
                        "position": "after",
                        "after_page": 9,
                        "count": 6,
                        "repeat": True,
                        "interval": 9,
                    }],
                },
            )

            self.assertEqual(32, len(PdfReader(output).pages))
            self.assertEqual(12, metadata["inserted_blank_pages"])
            self.assertEqual(12, metadata["inserted_by_side"]["document"])

    def test_rule_is_applied_to_each_duplex_side_separately(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "paired.pdf"
            output = Path(directory) / "with-blanks.pdf"
            self.make_pdf(source, 8)

            metadata = insert_blank_pages(
                str(source),
                str(output),
                {
                    "quantity": 50,
                    "side_page_counts": [4, 4],
                    "rules": [{
                        "target": "all",
                        "position": "start",
                        "count": 1,
                    }],
                },
            )

            self.assertEqual(10, len(PdfReader(output).pages))
            self.assertEqual([5, 5], metadata["input_page_counts"])
            self.assertEqual({"front": 1, "back": 1}, metadata["inserted_by_side"])

    def test_front_only_and_quantity_conditions(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "paired.pdf"
            output = Path(directory) / "with-blanks.pdf"
            self.make_pdf(source, 8)

            metadata = insert_blank_pages(
                str(source),
                str(output),
                {
                    "quantity": 50,
                    "side_page_counts": [4, 4],
                    "rules": [
                        {
                            "target": "front",
                            "position": "end",
                            "count": 2,
                            "min_quantity": 25,
                            "max_quantity": 100,
                        },
                        {
                            "target": "all",
                            "position": "start",
                            "count": 10,
                            "min_quantity": 200,
                        },
                    ],
                },
            )

            self.assertEqual([6, 4], metadata["input_page_counts"])
            self.assertEqual(2, metadata["inserted_blank_pages"])

    def test_blank_inherits_rotation_and_print_boxes(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "rotated.pdf"
            output = Path(directory) / "with-blank.pdf"
            writer = PdfWriter()
            page = writer.add_blank_page(width=100, height=80)
            page.rotate(90)
            page.trimbox = RectangleObject([5, 6, 95, 74])
            with source.open("wb") as stream:
                writer.write(stream)

            insert_blank_pages(
                str(source),
                str(output),
                {
                    "rules": [{
                        "target": "all",
                        "position": "end",
                        "count": 1,
                    }],
                },
            )

            blank = PdfReader(output).pages[1]
            self.assertEqual(90, blank.rotation)
            self.assertEqual([5, 6, 95, 74], list(blank.trimbox))


class BarcodeLabelTest(unittest.TestCase):
    def test_brother_label_defaults_to_90_by_29_mm(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "label.pdf"

            metadata = barcode_pdf("EU13810", str(output), {})

            page = PdfReader(output).pages[0]
            self.assertAlmostEqual(90, float(page.mediabox.width) * 25.4 / 72, places=2)
            self.assertAlmostEqual(29, float(page.mediabox.height) * 25.4 / 72, places=2)
            self.assertEqual("Code 128", metadata["symbology"])
            self.assertEqual("EU13810", metadata["data"])


if __name__ == "__main__":
    unittest.main()
