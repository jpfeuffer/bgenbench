#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_DIR="${ROOT_DIR}/outputs"
mkdir -p "${OUTPUT_DIR}"

"${ROOT_DIR}/scripts/build_libraries.sh"
"${ROOT_DIR}/scripts/prepare_large_bgen.sh"

BGEN_PATH="${BGENBENCH_DATASET_PREFIX:-${ROOT_DIR}/data/chr1_1000g}.bgen"
BGI_PATH="${BGENBENCH_DATASET_PREFIX:-${ROOT_DIR}/data/chr1_1000g}.bgen.bgi"
GAVIN_BENCH_BIN="${ROOT_DIR}/build/bench_gavin"

"${ROOT_DIR}/.venv/jeremy/bin/python" "${ROOT_DIR}/benchmarks/run_benchmarks.py" \
  --bgen "${BGEN_PATH}" \
  --bgi "${BGI_PATH}" \
  --gavin-bench-bin "${GAVIN_BENCH_BIN}" \
  --output-dir "${OUTPUT_DIR}" \
  --full-load-max-variants "${BGENBENCH_FULL_LOAD_MAX_VARIANTS:-2000}"
