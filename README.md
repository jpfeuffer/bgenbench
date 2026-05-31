# bgenbench

Benchmarking three BGEN libraries in a reproducible way:

- `jeremymcrae/bgen` (Python/Cython binding)
- `limix/bgen` + `limix/cbgen` (C library and Python bindings)
- `gavinband/bgen` (reference C++ implementation)

## What this repository runs

- Builds all libraries from source with shared compiler flags (`BGENBENCH_CFLAGS`, `BGENBENCH_CXXFLAGS`)
- Downloads a large BGEN file directly (`BGENBENCH_BGEN_URL`) or, by default, downloads a large public genomics dataset and converts it into a large BGEN file (chr1 from 1000 Genomes)
- Benchmarks common access patterns:
  - Metadata extraction
  - Consecutive slice access
  - Random single-variant access
  - Random jumping slices
  - Bulk load loop (configurable cap)
- Generates HTML + JSON benchmark reports
- Uploads reports as GitHub Actions artifacts

## Local run

```bash
chmod +x scripts/*.sh
scripts/run_benchmarks.sh
```

Outputs are written to `outputs/report.html` and `outputs/results.json`.

To force a direct large-BGEN download path:

```bash
export BGENBENCH_BGEN_URL="https://.../large.bgen"
export BGENBENCH_BGI_URL="https://.../large.bgen.bgi" # optional
scripts/run_benchmarks.sh
```
