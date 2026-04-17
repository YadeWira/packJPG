// lib_concurrent_test.cpp — hammer packJPGlib from N threads at once.
//
// Each thread repeatedly picks a random JPEG from argv[], compresses it
// to memory, decompresses it back, and compares byte-for-byte with the
// original. Any mismatch, crash, or silent corruption indicates that a
// non-THREAD_LOCAL global is being stomped across threads.
//
// Build:
//   g++ -O2 -std=c++17 -I.. lib_concurrent_test.cpp ../packJPGlib.a \
//       -o lib_concurrent_test -lpthread
//
// Usage: ./lib_concurrent_test <threads> <iters_per_thread> <jpg_files...>

#include <atomic>
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <mutex>
#include <random>
#include <string>
#include <thread>
#include <vector>

#include "../packjpglib.h"

namespace {

struct JpegFile {
    std::string path;
    std::vector<unsigned char> bytes;
};

std::vector<JpegFile> load_corpus(int argc, char** argv, int start_idx) {
    std::vector<JpegFile> corpus;
    for (int i = start_idx; i < argc; i++) {
        std::ifstream f(argv[i], std::ios::binary);
        if (!f) continue;
        f.seekg(0, std::ios::end);
        auto sz = f.tellg();
        f.seekg(0, std::ios::beg);
        if (sz <= 0) continue;
        JpegFile jf;
        jf.path = argv[i];
        jf.bytes.resize(static_cast<size_t>(sz));
        f.read(reinterpret_cast<char*>(jf.bytes.data()), sz);
        if (f.gcount() == sz) corpus.push_back(std::move(jf));
    }
    return corpus;
}

struct ThreadStats {
    int iters_ok     = 0;
    int iters_pack_err = 0;
    int iters_unpack_err = 0;
    int mismatches   = 0;
};

void worker(int tid, int iters, const std::vector<JpegFile>* corpus,
            std::atomic<bool>* stop, ThreadStats* out) {
    std::mt19937 rng(static_cast<uint32_t>(tid * 9973u + 1));
    for (int i = 0; i < iters && !stop->load(); i++) {
        const auto& jf = (*corpus)[rng() % corpus->size()];

        // compress jpg (mem) -> pjg (mem)
        char msg[PJG_MSG_SIZE] = {0};
        pjglib_init_streams(const_cast<unsigned char*>(jf.bytes.data()), 1,
                            static_cast<int>(jf.bytes.size()), nullptr, 1);
        unsigned char* pjg_buf = nullptr;
        unsigned int   pjg_size = 0;
        if (!pjglib_convert_stream2mem(&pjg_buf, &pjg_size, msg)) {
            out->iters_pack_err++;
            fprintf(stderr, "[tid %d] pack fail: %s — %s\n", tid, jf.path.c_str(), msg);
            continue;
        }

        // decompress pjg (mem) -> jpg (mem)
        std::vector<unsigned char> pjg_copy(pjg_buf, pjg_buf + pjg_size);
        pjglib_init_streams(pjg_copy.data(), 1, static_cast<int>(pjg_copy.size()),
                            nullptr, 1);
        unsigned char* out_buf = nullptr;
        unsigned int   out_size = 0;
        if (!pjglib_convert_stream2mem(&out_buf, &out_size, msg)) {
            out->iters_unpack_err++;
            continue;
        }

        if (out_size != jf.bytes.size() ||
            std::memcmp(out_buf, jf.bytes.data(), out_size) != 0) {
            out->mismatches++;
            fprintf(stderr, "[tid %d] MISMATCH on %s (orig=%zu round=%u)\n",
                    tid, jf.path.c_str(), jf.bytes.size(), out_size);
            stop->store(true);
            return;
        }
        out->iters_ok++;
    }
}

} // namespace

int main(int argc, char** argv) {
    if (argc < 4) {
        fprintf(stderr, "usage: %s <threads> <iters> <jpg_files...>\n", argv[0]);
        return 2;
    }
    int nthreads = std::atoi(argv[1]);
    int iters    = std::atoi(argv[2]);
    if (nthreads < 1) nthreads = 1;
    if (iters    < 1) iters    = 1;

    auto corpus = load_corpus(argc, argv, 3);
    if (corpus.empty()) {
        fprintf(stderr, "no readable JPEGs in argv\n");
        return 3;
    }
    fprintf(stdout, "corpus: %zu JPEGs, threads=%d, iters/thread=%d\n",
            corpus.size(), nthreads, iters);

    std::atomic<bool> stop(false);
    std::vector<ThreadStats> stats(nthreads);
    std::vector<std::thread> threads;
    auto t0 = std::chrono::steady_clock::now();
    for (int i = 0; i < nthreads; i++) {
        threads.emplace_back(worker, i, iters, &corpus, &stop, &stats[i]);
    }
    for (auto& t : threads) t.join();
    auto t1 = std::chrono::steady_clock::now();

    ThreadStats total;
    for (auto& s : stats) {
        total.iters_ok         += s.iters_ok;
        total.iters_pack_err   += s.iters_pack_err;
        total.iters_unpack_err += s.iters_unpack_err;
        total.mismatches       += s.mismatches;
    }
    double secs = std::chrono::duration<double>(t1 - t0).count();
    printf("── summary ─────────────────────────────────────\n");
    printf(" ok:             %d\n", total.iters_ok);
    printf(" pack errors:    %d (expected for corpus with known fails)\n", total.iters_pack_err);
    printf(" unpack errors:  %d\n", total.iters_unpack_err);
    printf(" mismatches:     %d\n", total.mismatches);
    printf(" wall time:      %.2fs\n", secs);
    return total.mismatches > 0 ? 1 : 0;
}
