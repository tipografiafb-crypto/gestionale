import tempfile
import unittest
from pathlib import Path

from pypdf import PdfReader, PdfWriter

from tools.automation_pdf.cli import impose


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


if __name__ == "__main__":
    unittest.main()
