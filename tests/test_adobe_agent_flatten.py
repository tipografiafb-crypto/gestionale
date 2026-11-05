import importlib.util
import json
from pathlib import Path
import tempfile
import unittest


spec = importlib.util.spec_from_file_location(
    "adobe_agent", Path(__file__).parents[1] / "tools/adobe_agent/adobe_agent.py"
)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class PhotoshopFlattenTest(unittest.TestCase):
    def test_flatten_disables_original_png_bypass(self):
        for enabled in (False, True):
            with self.subTest(enabled=enabled), tempfile.TemporaryDirectory() as directory:
                workdir = Path(directory)
                source = workdir / "source.png"
                source.write_bytes(b"\x89PNG\r\n\x1a\n")
                agent = module.AdobeAgent.__new__(module.AdobeAgent)
                agent.photoshop_app = "Photoshop"

                def execute_jsx(app, jsx, script_path):
                    flag = "false" if enabled else "true"
                    self.assertIn("var bypassOriginalPng = " + flag, jsx)
                    self.assertLess(jsx.index("documentRef.flatten();"), jsx.index("documentRef.saveAs("))
                    self.assertIn("finally {\n    app.backgroundColor = previousBackground;", jsx)
                    report = {
                        "pixels_before": [1417, 1417],
                        "pixels_after": [1417, 1417],
                        "dpi": 300,
                        "flatten_transparency": enabled,
                        "bypassed_original_png": not enabled,
                    }
                    (workdir / "photoshop-dpi.json").write_text(json.dumps(report))

                agent.execute_jsx = execute_jsx
                result = agent.execute_photoshop(
                    str(source), str(workdir / "out.png"),
                    {"output_format": "png", "flatten_transparency": enabled}, {}, workdir,
                )
                self.assertEqual(result["flatten_transparency"], enabled)
                if not enabled:
                    self.assertEqual((workdir / "out.png").read_bytes(), source.read_bytes())


if __name__ == "__main__":
    unittest.main()
