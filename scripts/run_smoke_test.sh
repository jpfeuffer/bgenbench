#!/usr/bin/env bash
# Run a quick smoke-test benchmark against a small synthetic BGEN file.
# Every agent session must call this script before returning to the user.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DATA_DIR="${ROOT_DIR}/data"
TOOLS_DIR="${ROOT_DIR}/tools"
OUTPUT_DIR="${ROOT_DIR}/outputs/smoke"
SMALL_PREFIX="${DATA_DIR}/test_small"
BGEN_PATH="${SMALL_PREFIX}.bgen"
BGI_PATH="${SMALL_PREFIX}.bgen.bgi"
BGENIX="${ROOT_DIR}/third_party/gavinband-bgen/build/apps/bgenix"

mkdir -p "${DATA_DIR}" "${TOOLS_DIR}" "${OUTPUT_DIR}"

# ── Locate or download plink2 ────────────────────────────────────────────────
PLINK2_BIN="${TOOLS_DIR}/plink2"
if [[ ! -x "${PLINK2_BIN}" ]]; then
  if command -v plink2 >/dev/null 2>&1; then
    PLINK2_BIN="$(command -v plink2)"
  else
    echo "Downloading plink2..."
    curl -fsSL -o "${TOOLS_DIR}/plink2.zip" \
      "https://s3.amazonaws.com/plink2-assets/alpha7/plink2_linux_avx2_20260504.zip"
    unzip -o "${TOOLS_DIR}/plink2.zip" -d "${TOOLS_DIR}"
    chmod +x "${PLINK2_BIN}"
  fi
fi

# ── Build libraries if not already built ────────────────────────────────────
if [[ ! -x "${BGENIX}" ]]; then
  echo "Libraries not found – running build_libraries.sh first..."
  chmod +x "${ROOT_DIR}/scripts/build_libraries.sh"
  "${ROOT_DIR}/scripts/build_libraries.sh"
fi

# ── Generate small synthetic BGEN ───────────────────────────────────────────
if [[ ! -f "${BGEN_PATH}" ]]; then
  VCF_TMP="$(mktemp /tmp/test_small_XXXXXX.vcf)"
  trap 'rm -f "${VCF_TMP}"' EXIT
  python3 "${ROOT_DIR}/scripts/generate_test_bgen.py" > "${VCF_TMP}"
  "${PLINK2_BIN}" \
    --vcf "${VCF_TMP}" \
    --max-alleles 2 \
    --export bgen-1.2 compression=zlib \
    --out "${SMALL_PREFIX}" \
    --double-id \
    --allow-extra-chr
fi

# ── Create index if missing ──────────────────────────────────────────────────
if [[ ! -f "${BGI_PATH}" ]]; then
  "${BGENIX}" -g "${BGEN_PATH}" -index
fi

# ── Run smoke-test benchmark ─────────────────────────────────────────────────
echo "Running smoke-test benchmark on ${BGEN_PATH}..."
PLINK2_ARG=""
if [[ -x "${PLINK2_BIN}" ]]; then
  PLINK2_ARG="--plink2-bin ${PLINK2_BIN}"
fi

# shellcheck disable=SC2086
"${ROOT_DIR}/.venv/jeremy/bin/python" "${ROOT_DIR}/benchmarks/run_benchmarks.py" \
  --bgen "${BGEN_PATH}" \
  --bgi "${BGI_PATH}" \
  --gavin-bgenix "${BGENIX}" \
  --output-dir "${OUTPUT_DIR}" \
  --full-load-max-variants 100 \
  ${PLINK2_ARG}

echo ""
echo "Smoke test complete. Results written to ${OUTPUT_DIR}."

# ── Fail if any backend errored ───────────────────────────────────────────────
if python3 - "${OUTPUT_DIR}/results.json" <<'PYEOF'
import json, sys
data = json.loads(open(sys.argv[1]).read())
errors = [b for b in data["backends"] if b["status"] != "ok"]
if errors:
    for e in errors:
        print(f"[FAIL] {e['name']}: {e.get('error','unknown error')}", file=sys.stderr)
    sys.exit(1)
PYEOF
then
  echo "All backends passed smoke test."
fi
