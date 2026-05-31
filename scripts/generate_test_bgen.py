#!/usr/bin/env python3
"""Generate a minimal synthetic VCF that plink2 can convert to a small test BGEN.

Usage:
    python3 scripts/generate_test_bgen.py > /tmp/test_small.vcf
"""
import sys

N_SAMPLES = 50
N_VARIANTS = 200  # enough to exercise all benchmark access patterns

samples = [f"SAMPLE{i:03d}" for i in range(N_SAMPLES)]

print("##fileformat=VCFv4.1")
print("##contig=<ID=1,length=1000000>")
print(
    "#CHROM\tPOS\tID\tREF\tALT\tQUAL\tFILTER\tINFO\tFORMAT\t"
    + "\t".join(samples)
)

GT_TABLE = ("0|0", "0|1", "1|1")

for i in range(N_VARIANTS):
    pos = (i + 1) * 1000
    gts = "\t".join(GT_TABLE[(i + j) % 3] for j in range(N_SAMPLES))
    print(f"1\t{pos}\trs{i + 1}\tA\tG\t.\tPASS\t.\tGT\t{gts}")
