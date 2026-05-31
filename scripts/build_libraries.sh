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
    git clone "${repo_url}" "${target}"
  fi
}

clone_if_missing "https://github.com/jeremymcrae/bgen.git" "${THIRD_PARTY_DIR}/jeremymcrae-bgen"
clone_if_missing "https://github.com/limix/bgen.git" "${THIRD_PARTY_DIR}/limix-bgen"
clone_if_missing "https://github.com/limix/cbgen.git" "${THIRD_PARTY_DIR}/limix-cbgen"
clone_if_missing "https://github.com/gavinband/bgen.git" "${THIRD_PARTY_DIR}/gavinband-bgen"

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

echo "Libraries built successfully with CFLAGS='${CFLAGS}' and CXXFLAGS='${CXXFLAGS}'."
