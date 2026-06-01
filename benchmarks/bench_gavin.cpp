// bench_gavin.cpp – benchmark the gavinband/bgen C++ library.
//
// Access pattern: reads variant offsets from the .bgi SQLite index and seeks
// directly to each byte offset, matching the approach used by limix/cbgen.
// This ensures the comparison is index-based (not genomic-range-based).
//
// Output: single JSON object written to stdout.
//
// Build (see scripts/build_libraries.sh):
//   c++ -std=c++11 -O2 -o bench_gavin bench_gavin.cpp \
//       -I<gavinband>/genfile/include -I<gavinband>/3rd_party/zlib-1.2.11 \
//       -L<gavinband>/build/src -lbgen -lsqlite3 -lz

#include <algorithm>
#include <chrono>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <functional>
#include <iostream>
#include <random>
#include <stdexcept>
#include <string>
#include <vector>

#include <sqlite3.h>

// gavinband/bgen low-level API
#include "genfile/bgen/bgen.hpp"

// ── Timing helper ────────────────────────────────────────────────────────────

static double timed(std::function<void()> f) {
    auto start = std::chrono::high_resolution_clock::now();
    f();
    auto end = std::chrono::high_resolution_clock::now();
    return std::chrono::duration<double>(end - start).count();
}

// ── .bgi offset reader ───────────────────────────────────────────────────────

static std::vector<int64_t> get_offsets(const std::string& bgi_path, int limit = -1) {
    sqlite3* db = nullptr;
    if (sqlite3_open_v2(bgi_path.c_str(), &db, SQLITE_OPEN_READONLY, nullptr) != SQLITE_OK) {
        throw std::runtime_error(std::string("Cannot open .bgi: ") + bgi_path);
    }

    std::string sql =
        "SELECT file_start_position FROM Variant ORDER BY file_start_position";
    if (limit > 0) {
        sql += " LIMIT " + std::to_string(limit);
    }

    sqlite3_stmt* stmt = nullptr;
    sqlite3_prepare_v2(db, sql.c_str(), -1, &stmt, nullptr);

    std::vector<int64_t> offsets;
    while (sqlite3_step(stmt) == SQLITE_ROW) {
        offsets.push_back(static_cast<int64_t>(sqlite3_column_int64(stmt, 0)));
    }

    sqlite3_finalize(stmt);
    sqlite3_close(db);
    return offsets;
}

// ── One variant read ─────────────────────────────────────────────────────────
// Reads variant identifying data + full genotype probability block at `offset`.

static void read_variant_at(
    std::istream& stream,
    int64_t offset,
    const genfile::bgen::Context& context,
    std::vector<genfile::byte_t>& geno_buf,
    std::vector<genfile::byte_t>& uncomp_buf
) {
    stream.seekg(static_cast<std::streamoff>(offset));

    // Read identifying data (rsid, chromosome, position, alleles).
    std::string SNPID, rsid, chromosome;
    uint32_t position = 0;
    std::vector<std::string> alleles;
    genfile::bgen::read_snp_identifying_data(
        stream, context,
        &SNPID, &rsid, &chromosome, &position,
        [&alleles](std::size_t n) { alleles.resize(n); },
        [&alleles](std::size_t i, std::string const& a) { alleles[i] = a; }
    );

    // Read and decompress the probability block (BGEN v1.2/v1.3 compressed).
    genfile::bgen::read_genotype_data_block(stream, context, &geno_buf);
    genfile::bgen::uncompress_probability_data(context, geno_buf, &uncomp_buf);

    // Parse probabilities (forces full decode of the block).
    // Lambda must be stored as a named variable because parse_probability_data
    // takes Setter by non-const lvalue reference and cannot bind to an rvalue.
    auto setter = [](std::size_t /*sample*/, std::size_t /*allele*/,
                     double const* /*probs*/, std::size_t /*n_probs*/) {};
    genfile::bgen::parse_probability_data(
        uncomp_buf.data(),
        uncomp_buf.data() + uncomp_buf.size(),
        context,
        setter
    );
}

// ── JSON helpers ─────────────────────────────────────────────────────────────

static std::string json_str(const std::string& s) {
    std::string out = "\"";
    for (char c : s) {
        if (c == '"') out += "\\\"";
        else if (c == '\\') out += "\\\\";
        else if (c == '\n') out += "\\n";
        else out += c;
    }
    out += "\"";
    return out;
}

// ── main ─────────────────────────────────────────────────────────────────────

static void usage(const char* prog) {
    std::cerr << "Usage: " << prog
              << " --bgen FILE --bgi FILE"
              << " [--full-load-max-variants N]"
              << " [--random-seed N]\n";
    std::exit(1);
}

int main(int argc, char** argv) {
    std::string bgen_path, bgi_path;
    int full_load_max = 2000;
    unsigned int seed = 1;

    for (int i = 1; i < argc; ++i) {
        std::string arg = argv[i];
        if ((arg == "--bgen") && i + 1 < argc)          { bgen_path = argv[++i]; }
        else if ((arg == "--bgi") && i + 1 < argc)       { bgi_path  = argv[++i]; }
        else if ((arg == "--full-load-max-variants") && i + 1 < argc) {
            full_load_max = std::atoi(argv[++i]);
        } else if ((arg == "--random-seed") && i + 1 < argc) {
            seed = static_cast<unsigned int>(std::atoi(argv[++i]));
        } else {
            usage(argv[0]);
        }
    }
    if (bgen_path.empty() || bgi_path.empty()) usage(argv[0]);

    // ── Open BGEN and read header ────────────────────────────────────────────
    std::ifstream stream(bgen_path, std::ios::binary);
    if (!stream) throw std::runtime_error("Cannot open BGEN: " + bgen_path);

    uint32_t bgen_offset = 0;
    genfile::bgen::Context context;
    genfile::bgen::read_offset(stream, &bgen_offset);
    genfile::bgen::read_header_block(stream, &context);

    uint32_t variant_count = context.number_of_variants;
    uint32_t sample_count  = context.number_of_samples;
    (void)sample_count;

    // ── Load all offsets from .bgi ───────────────────────────────────────────
    std::vector<int64_t> offsets = get_offsets(bgi_path);
    if (offsets.empty()) throw std::runtime_error("No variants in .bgi index");

    // ── Build random access set ──────────────────────────────────────────────
    std::mt19937 rng(seed);
    std::uniform_int_distribution<std::size_t> dist(0, offsets.size() - 1);

    const int n_random = static_cast<int>(std::min<std::size_t>(128, offsets.size()));
    std::vector<int64_t> random_offsets(n_random);
    for (int i = 0; i < n_random; ++i) random_offsets[i] = offsets[dist(rng)];

    // Re-seed for random_slices (same as Python side: same rng, first 64)
    const int n_slice = std::min(64, n_random);

    // Reusable decode buffers
    std::vector<genfile::byte_t> geno_buf, uncomp_buf;

    // ── Metadata ────────────────────────────────────────────────────────────
    // Report the header info (context already loaded above; re-open counts).
    double t_metadata = timed([&]() {
        std::ifstream tmp(bgen_path, std::ios::binary);
        uint32_t off2 = 0;
        genfile::bgen::Context ctx2;
        genfile::bgen::read_offset(tmp, &off2);
        genfile::bgen::read_header_block(tmp, &ctx2);
        (void)ctx2.number_of_variants;
        (void)ctx2.number_of_samples;
    });

    // ── Consecutive slices (first 1024 variants sequentially) ────────────────
    const int n_consec = static_cast<int>(std::min<std::size_t>(1024, offsets.size()));
    double t_consecutive = timed([&]() {
        for (int i = 0; i < n_consec; ++i) {
            read_variant_at(stream, offsets[i], context, geno_buf, uncomp_buf);
        }
    });

    // ── Random single (128 random variants) ─────────────────────────────────
    double t_random_single = timed([&]() {
        for (int i = 0; i < n_random; ++i) {
            read_variant_at(stream, random_offsets[i], context, geno_buf, uncomp_buf);
        }
    });

    // ── Random slices (64 random starts, 8 consecutive each) ────────────────
    double t_random_slices = timed([&]() {
        for (int i = 0; i < n_slice; ++i) {
            // Find position of random_offsets[i] in the sorted offsets array
            // and read 8 consecutive variants from there.
            auto it = std::lower_bound(offsets.begin(), offsets.end(), random_offsets[i]);
            std::size_t idx = static_cast<std::size_t>(it - offsets.begin());
            std::size_t end_idx = std::min(idx + 8, offsets.size());
            for (std::size_t j = idx; j < end_idx; ++j) {
                read_variant_at(stream, offsets[j], context, geno_buf, uncomp_buf);
            }
        }
    });

    // ── Full load (up to full_load_max_variants sequentially) ───────────────
    const int n_full = static_cast<int>(
        std::min<std::size_t>(static_cast<std::size_t>(full_load_max), offsets.size()));
    double t_full_load = timed([&]() {
        for (int i = 0; i < n_full; ++i) {
            read_variant_at(stream, offsets[i], context, geno_buf, uncomp_buf);
        }
    });

    // ── Emit JSON ────────────────────────────────────────────────────────────
    std::string notes = "variants=" + std::to_string(static_cast<int>(offsets.size()));
    std::cout
        << "{\n"
        << "  \"metadata\": "          << t_metadata       << ",\n"
        << "  \"consecutive_slices\": " << t_consecutive    << ",\n"
        << "  \"random_single\": "     << t_random_single  << ",\n"
        << "  \"random_slices\": "     << t_random_slices  << ",\n"
        << "  \"full_load\": "         << t_full_load       << ",\n"
        << "  \"notes\": "             << json_str(notes)   << "\n"
        << "}\n";

    return 0;
}
