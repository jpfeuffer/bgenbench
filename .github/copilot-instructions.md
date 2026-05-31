# GitHub Copilot Agent Instructions

## Mandatory smoke-test requirement

**Before returning any response to the user, every agent session on this repository MUST run the smoke-test benchmark.**

The smoke test exercises all benchmark backends (`jeremymcrae/bgen`, `limix/cbgen`, `gavinband/bgen`, and `plink2`) against a small synthetic BGEN file and reports pass/fail for each.

### How to run it

```bash
chmod +x scripts/run_smoke_test.sh
scripts/run_smoke_test.sh
```

The script will:
1. Build the BGEN libraries if they are not already built.
2. Download `plink2` if it is not available.
3. Generate a small synthetic BGEN file (`data/test_small.bgen`, 200 variants, 50 samples) if it does not already exist.
4. Run `benchmarks/run_benchmarks.py` against that file with a cap of 100 variants for the full-load benchmark.
5. Exit with a non-zero status and print which backends failed if any errors occur.

### When to run it

- After **any** code change — to confirm no backend is broken.
- After adding or updating dependencies or build scripts.
- After modifying benchmark logic in `benchmarks/`.
- Before opening a pull request or marking a task as complete.

### Full benchmark

For a full benchmark run against the large 1000 Genomes chr1 BGEN file use:

```bash
chmod +x scripts/*.sh
scripts/run_benchmarks.sh
```

Outputs are written to `outputs/report.html` and `outputs/results.json`.
