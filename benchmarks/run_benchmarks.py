#!/usr/bin/env python3
from __future__ import annotations

import argparse
import random
import sqlite3
import subprocess
import sys
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Callable

from report import write_html_report, write_json


@dataclass
class BenchmarkConfig:
    bgen_path: Path
    bgi_path: Path
    output_dir: Path
    full_load_max_variants: int
    random_seed: int
    gavin_bgenix: Path


class BenchmarkError(RuntimeError):
    pass


def _timed(func: Callable[[], None]) -> float:
    start = time.perf_counter()
    func()
    return time.perf_counter() - start


def _get_offsets_from_bgi(path: Path, limit: int | None = None) -> list[int]:
    with sqlite3.connect(path) as conn:
        cursor = conn.execute("SELECT file_start_position FROM Variant ORDER BY file_start_position")
        rows = [int(row[0]) for row in cursor.fetchall()]
    if limit is not None:
        return rows[:limit]
    return rows


def _safe_backend(name: str, run: Callable[[], dict[str, Any]]) -> dict[str, Any]:
    try:
        return {"name": name, "status": "ok", "metrics": run()}
    except (
        BenchmarkError,
        ImportError,
        ModuleNotFoundError,
        OSError,
        RuntimeError,
        sqlite3.Error,
        subprocess.SubprocessError,
        ValueError,
    ) as exc:
        return {"name": name, "status": "error", "error": str(exc)}


def _bench_jeremy(cfg: BenchmarkConfig) -> dict[str, Any]:
    from bgen import BgenReader  # type: ignore

    rng = random.Random(cfg.random_seed)

    with BgenReader(str(cfg.bgen_path), delay_parsing=False) as reader:
        variant_count = len(reader.positions())
        if variant_count == 0:
            raise BenchmarkError("no variants found")

        def metadata() -> None:
            _ = reader.rsids()
            _ = reader.positions()

        def consecutive() -> None:
            width = min(64, variant_count)
            for start in range(0, min(variant_count, 1024), width):
                for variant in reader[start : min(start + width, variant_count)]:
                    _ = variant.minor_allele_dosage

        random_ids = [rng.randrange(variant_count) for _ in range(min(128, variant_count))]

        def random_single() -> None:
            for index in random_ids:
                _ = reader[index].minor_allele_dosage

        def random_slices() -> None:
            for index in random_ids[:64]:
                for variant in reader[index : min(index + 8, variant_count)]:
                    _ = variant.minor_allele_dosage

        def full_load() -> None:
            for index in range(min(cfg.full_load_max_variants, variant_count)):
                _ = reader[index].minor_allele_dosage

        return {
            "metadata": _timed(metadata),
            "consecutive_slices": _timed(consecutive),
            "random_single": _timed(random_single),
            "random_slices": _timed(random_slices),
            "full_load": _timed(full_load),
            "notes": f"variants={variant_count}",
        }


def _bench_cbgen(cfg: BenchmarkConfig) -> dict[str, Any]:
    import cbgen  # type: ignore

    offsets = _get_offsets_from_bgi(cfg.bgi_path)
    if not offsets:
        raise BenchmarkError("index contains no variants")

    rng = random.Random(cfg.random_seed)
    random_offsets = [rng.choice(offsets) for _ in range(min(128, len(offsets)))]

    with cbgen.bgen_file(cfg.bgen_path) as bgen:
        def metadata() -> None:
            _ = bgen.nvariants
            _ = bgen.nsamples

        def consecutive() -> None:
            for offset in offsets[: min(1024, len(offsets))]:
                _ = bgen.read_probability(offset)

        def random_single() -> None:
            for offset in random_offsets:
                _ = bgen.read_probability(offset)

        def random_slices() -> None:
            for offset in random_offsets[:64]:
                _ = bgen.read_probability(offset)

        def full_load() -> None:
            for offset in offsets[: min(cfg.full_load_max_variants, len(offsets))]:
                _ = bgen.read_probability(offset)

        return {
            "metadata": _timed(metadata),
            "consecutive_slices": _timed(consecutive),
            "random_single": _timed(random_single),
            "random_slices": _timed(random_slices),
            "full_load": _timed(full_load),
            "notes": f"variants={len(offsets)}",
        }


def _bench_gavin(cfg: BenchmarkConfig) -> dict[str, Any]:
    if not cfg.gavin_bgenix.exists():
        raise BenchmarkError(f"missing bgenix at {cfg.gavin_bgenix}")

    with sqlite3.connect(cfg.bgi_path) as conn:
        rows = conn.execute(
            "SELECT chromosome, position FROM Variant ORDER BY position LIMIT 2048"
        ).fetchall()
    if not rows:
        raise BenchmarkError("no chromosome/position data in index")

    rng = random.Random(cfg.random_seed)

    def run_cmd(*args: str) -> None:
        subprocess.run(
            [str(cfg.gavin_bgenix), "-g", str(cfg.bgen_path), *args],
            check=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )

    def metadata() -> None:
        run_cmd("-list")

    def consecutive() -> None:
        chrom = str(rows[0][0])
        start = int(rows[0][1])
        stop_index = min(256, len(rows) - 1)
        stop = int(rows[stop_index][1])
        run_cmd("-incl-range", f"{chrom}:{start}-{stop}")

    random_rows = [rng.choice(rows) for _ in range(min(128, len(rows)))]

    def random_single() -> None:
        for chrom, pos in random_rows:
            run_cmd("-incl-range", f"{chrom}:{pos}-{pos}")

    def random_slices() -> None:
        for chrom, pos in random_rows[:64]:
            run_cmd("-incl-range", f"{chrom}:{pos}-{int(pos) + 10000}")

    def full_load() -> None:
        start = int(rows[0][1])
        end = int(rows[-1][1])
        chrom = str(rows[0][0])
        run_cmd("-incl-range", f"{chrom}:{start}-{end}")

    return {
        "metadata": _timed(metadata),
        "consecutive_slices": _timed(consecutive),
        "random_single": _timed(random_single),
        "random_slices": _timed(random_slices),
        "full_load": _timed(full_load),
        "notes": f"positions={len(rows)}",
    }


def parse_args(argv: list[str]) -> BenchmarkConfig:
    parser = argparse.ArgumentParser(description="Run BGEN backend benchmarks")
    parser.add_argument("--bgen", required=True, type=Path)
    parser.add_argument("--bgi", required=True, type=Path)
    parser.add_argument("--output-dir", required=True, type=Path)
    parser.add_argument("--full-load-max-variants", type=int, default=2000)
    parser.add_argument("--random-seed", type=int, default=1)
    parser.add_argument("--gavin-bgenix", type=Path, required=True)
    args = parser.parse_args(argv)
    return BenchmarkConfig(
        bgen_path=args.bgen,
        bgi_path=args.bgi,
        output_dir=args.output_dir,
        full_load_max_variants=args.full_load_max_variants,
        random_seed=args.random_seed,
        gavin_bgenix=args.gavin_bgenix,
    )


def main(argv: list[str]) -> int:
    cfg = parse_args(argv)

    results: dict[str, Any] = {
        "title": "BGEN backend benchmark report",
        "dataset": {
            "path": str(cfg.bgen_path),
            "size_bytes": cfg.bgen_path.stat().st_size,
        },
        "backends": [
            _safe_backend("jeremymcrae/bgen", lambda: _bench_jeremy(cfg)),
            _safe_backend("limix/cbgen", lambda: _bench_cbgen(cfg)),
            _safe_backend("gavinband/bgen", lambda: _bench_gavin(cfg)),
        ],
    }

    cfg.output_dir.mkdir(parents=True, exist_ok=True)
    write_json(cfg.output_dir / "results.json", results)
    write_html_report(cfg.output_dir / "report.html", results)
    print(f"Wrote benchmark results to {cfg.output_dir}")
    for backend in results["backends"]:
        status = backend["status"]
        if status == "ok":
            print(f"[ok] {backend['name']}")
        else:
            print(f"[error] {backend['name']}: {backend['error']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
