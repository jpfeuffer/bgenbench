#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DATA_DIR="${ROOT_DIR}/data"
TOOLS_DIR="${ROOT_DIR}/tools"
mkdir -p "${DATA_DIR}" "${TOOLS_DIR}"

: "${BGENBENCH_VCF_URL:=https://ftp.1000genomes.ebi.ac.uk/vol1/ftp/release/20130502/ALL.chr1.phase3_shapeit2_mvncall_integrated_v5a.20130502.genotypes.vcf.gz}"
: "${BGENBENCH_DATASET_PREFIX:=${DATA_DIR}/chr1_1000g}"
: "${BGENBENCH_MIN_BGEN_BYTES:=1000000000}"
: "${BGENBENCH_BGEN_URL:=}"
: "${BGENBENCH_BGI_URL:=}"

BGEN_PATH="${BGENBENCH_DATASET_PREFIX}.bgen"
BGI_PATH="${BGENBENCH_DATASET_PREFIX}.bgen.bgi"
VCF_PATH="${DATA_DIR}/$(basename "${BGENBENCH_VCF_URL}")"
PLINK2_BIN="${TOOLS_DIR}/plink2"

if [[ ! -x "${PLINK2_BIN}" ]]; then
  curl -fsSL -o "${TOOLS_DIR}/plink2.zip" "https://s3.amazonaws.com/plink2-assets/alpha6/plink2_linux_avx2_20250129.zip"
  unzip -o "${TOOLS_DIR}/plink2.zip" -d "${TOOLS_DIR}"
  chmod +x "${PLINK2_BIN}"
fi

if [[ -n "${BGENBENCH_BGEN_URL}" ]]; then
  if [[ ! -f "${BGEN_PATH}" ]]; then
    curl -fL "${BGENBENCH_BGEN_URL}" -o "${BGEN_PATH}"
  fi
  if [[ -n "${BGENBENCH_BGI_URL}" && ! -f "${BGI_PATH}" ]]; then
    curl -fL "${BGENBENCH_BGI_URL}" -o "${BGI_PATH}"
  fi
else
  if [[ ! -f "${VCF_PATH}" ]]; then
    curl -fL "${BGENBENCH_VCF_URL}" -o "${VCF_PATH}"
  fi

  if [[ ! -f "${BGEN_PATH}" ]]; then
    "${PLINK2_BIN}" --vcf "${VCF_PATH}" --export bgen-1.2 --out "${BGENBENCH_DATASET_PREFIX}" --double-id --allow-extra-chr
  fi
fi

if [[ ! -f "${BGI_PATH}" ]]; then
  if [[ -x "${ROOT_DIR}/third_party/gavinband-bgen/build/apps/bgenix" ]]; then
    "${ROOT_DIR}/third_party/gavinband-bgen/build/apps/bgenix" -g "${BGEN_PATH}" -index
  else
    echo "Missing bgenix for index creation: ${ROOT_DIR}/third_party/gavinband-bgen/build/apps/bgenix" >&2
    exit 1
  fi
fi

actual_size=$(stat -c%s "${BGEN_PATH}")
if (( actual_size < BGENBENCH_MIN_BGEN_BYTES )); then
  echo "Generated BGEN file is too small (${actual_size} bytes). Expected >= ${BGENBENCH_MIN_BGEN_BYTES}." >&2
  exit 1
fi

echo "BGEN_PATH=${BGEN_PATH}"
echo "BGI_PATH=${BGI_PATH}"
