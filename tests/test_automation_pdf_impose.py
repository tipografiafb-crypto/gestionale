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
