from pathlib import Path
from tempfile import TemporaryDirectory
import json
import unittest

from benchmarks.report import render_html_report, write_html_report, write_json


class ReportTests(unittest.TestCase):
    def test_render_html_includes_backends(self) -> None:
        payload = {
            "title": "My Report",
            "dataset": {"path": "/tmp/example.bgen", "size_bytes": 10},
            "backends": [
                {
                    "name": "backend-a",
                    "status": "ok",
                    "metrics": {
                        "metadata": 1.0,
                        "consecutive_slices": 2.0,
                        "random_single": 3.0,
                        "random_slices": 4.0,
                        "full_load": 5.0,
                        "notes": "note",
                    },
                }
            ],
        }
        html = render_html_report(payload)
        self.assertIn("My Report", html)
        self.assertIn("backend-a", html)
        self.assertIn("1.000000s", html)

    def test_write_json_and_html(self) -> None:
        payload = {"title": "T", "dataset": {}, "backends": []}
        with TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            json_path = tmp_path / "results.json"
            html_path = tmp_path / "report.html"
            write_json(json_path, payload)
            write_html_report(html_path, payload)

            loaded = json.loads(json_path.read_text(encoding="utf-8"))
            self.assertEqual(loaded["title"], "T")
            self.assertIn("<html", html_path.read_text(encoding="utf-8"))


if __name__ == "__main__":
    unittest.main()
