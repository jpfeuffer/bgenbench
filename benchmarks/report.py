from __future__ import annotations

import html
import json
from pathlib import Path
from typing import Any


def write_json(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2, sort_keys=True), encoding="utf-8")


def _format_seconds(value: Any) -> str:
    if value is None:
        return "n/a"
    return f"{float(value):.6f}s"


def render_html_report(results: dict[str, Any]) -> str:
    title = html.escape(results.get("title", "BGEN benchmark report"))
    dataset = results.get("dataset", {})
    rows = []
    for backend in results.get("backends", []):
        backend_name = html.escape(str(backend.get("name", "unknown")))
        if backend.get("status") != "ok":
            err = html.escape(str(backend.get("error", "unknown error")))
            rows.append(
                f"<tr><td>{backend_name}</td><td colspan='6'>FAILED: {err}</td></tr>"
            )
            continue

        metrics = backend.get("metrics", {})
        rows.append(
            "<tr>"
            f"<td>{backend_name}</td>"
            f"<td>{_format_seconds(metrics.get('metadata'))}</td>"
            f"<td>{_format_seconds(metrics.get('consecutive_slices'))}</td>"
            f"<td>{_format_seconds(metrics.get('random_single'))}</td>"
            f"<td>{_format_seconds(metrics.get('random_slices'))}</td>"
            f"<td>{_format_seconds(metrics.get('full_load'))}</td>"
            f"<td>{html.escape(str(metrics.get('notes', '')))}</td>"
            "</tr>"
        )

    dataset_path = html.escape(str(dataset.get("path", "n/a")))
    dataset_bytes = html.escape(str(dataset.get("size_bytes", "n/a")))

    return f"""<!doctype html>
<html lang=\"en\">
  <head>
    <meta charset=\"utf-8\" />
    <title>{title}</title>
    <style>
      body {{ font-family: Arial, sans-serif; margin: 24px; }}
      table {{ border-collapse: collapse; width: 100%; }}
      th, td {{ border: 1px solid #ccc; padding: 8px; text-align: left; }}
      th {{ background: #f2f2f2; }}
      code {{ background: #f6f8fa; padding: 2px 4px; }}
    </style>
  </head>
  <body>
    <h1>{title}</h1>
    <p><strong>Dataset:</strong> <code>{dataset_path}</code></p>
    <p><strong>Dataset size (bytes):</strong> {dataset_bytes}</p>
    <table>
      <thead>
        <tr>
          <th>Backend</th>
          <th>Metadata</th>
          <th>Consecutive slices</th>
          <th>Random single</th>
          <th>Random slices</th>
          <th>Full load</th>
          <th>Notes</th>
        </tr>
      </thead>
      <tbody>
        {''.join(rows)}
      </tbody>
    </table>
  </body>
</html>
"""


def write_html_report(path: Path, results: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(render_html_report(results), encoding="utf-8")
