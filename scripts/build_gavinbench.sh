# ── Compile bench_gavin C++ benchmark binary ─────────────────────────────────
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
THIRD_PARTY_DIR="${ROOT_DIR}/third_party"
GAVIN_DIR="${THIRD_PARTY_DIR}/gavinband-bgen"
BENCH_SRC="${ROOT_DIR}/benchmarks/bench_gavin.cpp"
BENCH_BIN="${BUILD_DIR}/bench_gavin"
BUILD_DIR="${ROOT_DIR}/build"
VENV_DIR="${ROOT_DIR}/.venv"

# Locate the bgen static library produced by waf.
LIBBGEN=""
for candidate in \
    "${GAVIN_DIR}/build/src/libbgen.a" \
    "${GAVIN_DIR}/build/src/libbgen_static.a" \
    "${GAVIN_DIR}/build/apps/libbgen.a"; do
  if [[ -f "${candidate}" ]]; then
    LIBBGEN="${candidate}"
    break
  fi
done

if [[ -z "${LIBBGEN}" ]]; then
  # Fallback: search recursively
  LIBBGEN="$(find "${GAVIN_DIR}/build" -name "libbgen*.a" | head -1 || true)"
fi
if [[ -z "${LIBBGEN}" ]]; then
  echo "Could not locate libbgen.a - skipping bench_gavin compilation" >&2
else
  # Include paths: gavinband uses genfile/include + 3rd_party zlib.
  GAVIN_INC="${GAVIN_DIR}/genfile/include"
  # Some versions put headers under db/ or directly under the repo root.
  EXTRA_INC=""
  [[ -d "${GAVIN_DIR}/db/include" ]] && EXTRA_INC="-I${GAVIN_DIR}/db/include"
  ZLIB_INC="${GAVIN_DIR}/3rd_party/zlib-1.2.11"
  [[ ! -d "${ZLIB_INC}" ]] && ZLIB_INC=""

  ZLIB_FLAG=""
  [[ -n "${ZLIB_INC}" ]] && ZLIB_FLAG="-I${ZLIB_INC}"

  ${CXX:-g++} ${CXXFLAGS} -std=c++11 \
    -I"${GAVIN_INC}" ${EXTRA_INC} ${ZLIB_FLAG} \
    -o "${BENCH_BIN}" \
    "${BENCH_SRC}" \
    "${LIBBGEN}" \
    -lsqlite3 -lz -lzstd -lpthread \
    2>&1 | sed "s|^|[bench_gavin] |"

  if [[ -x "${BENCH_BIN}" ]]; then
    echo "bench_gavin compiled successfully: ${BENCH_BIN}"
  else
    echo "bench_gavin compilation failed - gavinband/bgen will be skipped" >&2
  fi
fi