#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
THIRD_PARTY_DIR="${ROOT_DIR}/third_party"
BUILD_DIR="${ROOT_DIR}/build"
VENV_DIR="${ROOT_DIR}/.venv"

: "${BGENBENCH_CFLAGS:=-O3 -DNDEBUG -fPIC}"
: "${BGENBENCH_CXXFLAGS:=-O3 -DNDEBUG -fPIC}"

export CFLAGS="${BGENBENCH_CFLAGS}"
export CXXFLAGS="${BGENBENCH_CXXFLAGS}"

mkdir -p "${THIRD_PARTY_DIR}" "${BUILD_DIR}" "${VENV_DIR}"

clone_if_missing() {
  local repo_url="$1"
  local target="$2"
  if [[ ! -d "${target}/.git" ]]; then
    git clone --recurse-submodules "${repo_url}" "${target}"
  fi
}

clone_if_missing "https://github.com/jeremymcrae/bgen.git" "${THIRD_PARTY_DIR}/jeremymcrae-bgen"
clone_if_missing "https://github.com/limix/bgen.git" "${THIRD_PARTY_DIR}/limix-bgen"
clone_if_missing "https://github.com/limix/cbgen.git" "${THIRD_PARTY_DIR}/limix-cbgen"
clone_if_missing "https://github.com/gavinband/bgen.git" "${THIRD_PARTY_DIR}/gavinband-bgen"
if [[ -f "${THIRD_PARTY_DIR}/gavinband-bgen/src/View.cpp" ]]; then
  sed -i 's/std::ios::streampos origin = m_stream->tellg() ;/std::streampos origin = m_stream->tellg() ;/' "${THIRD_PARTY_DIR}/gavinband-bgen/src/View.cpp"
fi

python3 -m venv "${VENV_DIR}/jeremy"
python3 -m venv "${VENV_DIR}/limix"

"${VENV_DIR}/jeremy/bin/pip" install --upgrade pip setuptools wheel cython numpy
"${VENV_DIR}/jeremy/bin/pip" install --no-binary :all: "${THIRD_PARTY_DIR}/jeremymcrae-bgen"

cmake -S "${THIRD_PARTY_DIR}/limix-bgen" -B "${BUILD_DIR}/limix-bgen" -DCMAKE_BUILD_TYPE=Release -DCMAKE_C_FLAGS="${CFLAGS}" -DCMAKE_CXX_FLAGS="${CXXFLAGS}"
cmake --build "${BUILD_DIR}/limix-bgen" --parallel

"${VENV_DIR}/limix/bin/pip" install --upgrade pip setuptools wheel cffi numpy
"${VENV_DIR}/limix/bin/pip" install --no-binary :all: "${THIRD_PARTY_DIR}/limix-cbgen"
"${VENV_DIR}/jeremy/bin/pip" install --no-binary :all: "${THIRD_PARTY_DIR}/limix-cbgen"

pushd "${THIRD_PARTY_DIR}/gavinband-bgen" >/dev/null
./waf configure CC="${CC:-gcc}" CXX="${CXX:-g++}" CFLAGS="${CFLAGS}" CXXFLAGS="${CXXFLAGS}"
./waf
popd >/dev/null

if [[ ! -x "${THIRD_PARTY_DIR}/gavinband-bgen/build/apps/bgenix" ]]; then
  echo "bgenix build output not found" >&2
  exit 1
fi

# ── Compile bench_gavin C++ benchmark binary ─────────────────────────────────
GAVIN_DIR="${THIRD_PARTY_DIR}/gavinband-bgen"
BENCH_SRC="${ROOT_DIR}/benchmarks/bench_gavin.cpp"
BENCH_BIN="${BUILD_DIR}/bench_gavin"

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
  echo "Could not locate libbgen.a – skipping bench_gavin compilation" >&2
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
    -lsqlite3 -lz -lpthread \
    2>&1 | sed "s|^|[bench_gavin] |"

  if [[ -x "${BENCH_BIN}" ]]; then
    echo "bench_gavin compiled successfully: ${BENCH_BIN}"
  else
    echo "bench_gavin compilation failed – gavinband/bgen will be skipped" >&2
  fi
fi

echo "Libraries built successfully with CFLAGS='${CFLAGS}' and CXXFLAGS='${CXXFLAGS}'."
