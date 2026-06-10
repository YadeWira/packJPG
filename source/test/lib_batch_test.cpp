// lib_batch_test.cpp — verify pjglib_convert_batch byte-exact vs sequential
// single-file calls across a grid of (inter_threads × intra_threads) settings.
//
// Strategy:
//   1. Load N JPEGs into memory.
//   2. Reference: compress+decompress each file via the single-file API
//      with intra=OFF, inter=1. Save the round-tripped JPEGs as baseline.
//   3. For each (inter, intra) in the grid, call pjglib_convert_batch to
//      compress all N files, then call it again to decompress them, and
//      byte-compare the round-tripped JPEGs with the baseline.
//   4. Also verify each batch's .pjg output is byte-exact with a single-
//      file call on the same input (proves batch == sequential at the
//      compressed-format level).
//
// Usage: ./lib_batch_test file1.jpg [file2.jpg ...]
//
// Exit code 0 on full success, 1 on any mismatch.

#include "packjpglib.h"

#include <atomic>
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>

namespace {

struct JpegFile {
    std::string             path;
    std::vector<unsigned char> bytes;
};

std::vector<JpegFile> load_corpus( int argc, char** argv, int start_idx ) {
    std::vector<JpegFile> corpus;
    for ( int i = start_idx; i < argc; i++ ) {
        FILE* f = std::fopen( argv[i], "rb" );
        if ( !f ) continue;
        std::fseek( f, 0, SEEK_END );
        long n = std::ftell( f );
        std::fseek( f, 0, SEEK_SET );
        if ( n <= 0 ) { std::fclose( f ); continue; }
        JpegFile jf;
        jf.path = argv[i];
        jf.bytes.resize( (size_t) n );
        size_t got = std::fread( jf.bytes.data(), 1, (size_t) n, f );
        std::fclose( f );
        if ( got == (size_t) n ) corpus.push_back( std::move( jf ) );
    }
    return corpus;
}

// Compress one in-memory JPEG, return malloc'd PJG buffer + size.
// Returns false on lib failure. Caller frees the buffer.
bool compress_one( const std::vector<unsigned char>& jpg_in,
                   std::vector<unsigned char>& pjg_out, std::string& err ) {
    unsigned char* buf  = nullptr;
    unsigned int   size = 0;
    char msg[PJG_MSG_SIZE] = {0};
    pjglib_init_streams( (void*) jpg_in.data(), 1, (int) jpg_in.size(),
                         nullptr, 1 );
    if ( !pjglib_convert_stream2mem( &buf, &size, msg ) ) {
        err = msg;
        return false;
    }
    pjg_out.assign( buf, buf + size );
    std::free( buf );
    return true;
}

// Compress all jpg_in[i] through pjglib_convert_batch with the given
// threading settings. pjg_out[i] is filled with the .pjg bytes.
bool batch_compress( const std::vector<JpegFile>& corpus,
                     int inter, int intra,
                     std::vector<std::vector<unsigned char>>& pjg_out,
                     std::string& err ) {
    pjglib_set_inter_file_threads( inter );
    pjglib_set_intra_file_threads( intra );
    pjg_out.assign( corpus.size(), {} );

    std::vector<pjglib_batch_io> ops( corpus.size() );
    for ( size_t i = 0; i < corpus.size(); i++ ) {
        ops[i].in_src   = const_cast<unsigned char*>( corpus[i].bytes.data() );
        ops[i].in_type  = 1;
        ops[i].in_size  = (unsigned int) corpus[i].bytes.size();
        ops[i].out_dest = nullptr;
        ops[i].out_type = 1;
    }

    // Batch contract: out memory buffers are owned by the library and must
    // be freed by us. To keep the test simple we route batch outputs to
    // temporary files, read them back, and let the lib free its buffers
    // before file deletion. For the mem-to-mem case we use a small shim:
    // pre-allocate a header file that the lib writes to, then read it.
    //
    // Simpler: do the batch with file I/O. Write inputs to /tmp, run the
    // batch against those files, then read back the .pjg outputs.
    char tmpdir[] = "/tmp/pjg_batch_XXXXXX";
    if ( !mkdtemp( tmpdir ) ) { err = "mkdtemp failed"; return false; }

    // Path strings must outlive the batch call (workers read them after
    // we've returned from this scope). Own them in a vector indexed by op.
    std::vector<std::string> in_paths( corpus.size() );
    for ( size_t i = 0; i < corpus.size(); i++ ) {
        in_paths[i] = std::string( tmpdir ) + "/in_" +
                      std::to_string( i ) + ".jpg";
        FILE* f = std::fopen( in_paths[i].c_str(), "wb" );
        if ( !f ) { err = "fopen in failed"; return false; }
        std::fwrite( corpus[i].bytes.data(), 1, corpus[i].bytes.size(), f );
        std::fclose( f );
        ops[i].in_src  = (void*) in_paths[i].c_str();
        ops[i].in_type = 0;
    }
    // Outputs: out_dest=NULL means lib writes next to input with .pjg
    for ( auto& op : ops ) {
        op.out_dest = nullptr;
        op.out_type = 0;
    }

    char msg[PJG_MSG_SIZE] = {0};
    bool ok = pjglib_convert_batch( ops.data(), (int) ops.size(), msg );
    if ( !ok ) { err = msg; return false; }

    // Read back .pjg outputs
    for ( size_t i = 0; i < corpus.size(); i++ ) {
        std::string out_path = std::string( tmpdir ) + "/in_" +
                               std::to_string( i ) + ".pjg";
        FILE* f = std::fopen( out_path.c_str(), "rb" );
        if ( !f ) { err = "fopen out failed"; return false; }
        std::fseek( f, 0, SEEK_END );
        long n = std::ftell( f );
        std::fseek( f, 0, SEEK_SET );
        pjg_out[i].resize( (size_t) n );
        size_t got = std::fread( pjg_out[i].data(), 1, (size_t) n, f );
        std::fclose( f );
        if ( got != (size_t) n ) { err = "short read"; return false; }
        std::remove( out_path.c_str() );
    }
    for ( size_t i = 0; i < corpus.size(); i++ ) {
        std::remove( in_paths[i].c_str() );
    }
    rmdir( tmpdir );
    (void)0;
    return true;
}

} // namespace

int main( int argc, char** argv ) {
    if ( argc < 2 ) {
        std::fprintf( stderr, "usage: %s file1.jpg [file2.jpg ...]\n", argv[0] );
        return 2;
    }

    auto corpus = load_corpus( argc, argv, 1 );
    if ( corpus.empty() ) {
        std::fprintf( stderr, "no readable JPEGs in argv\n" );
        return 3;
    }
    std::printf( "packJPGlib: %s\n", pjglib_version_info() );
    std::printf( "corpus: %zu JPEGs\n", corpus.size() );
    std::printf( "suggested batch threads: %d\n\n", pjglib_suggest_batch_threads() );

    // Two baselines: one with intra=OFF, one with intra=ON. SFTH and
    // sequential are different encoding paths (cross-component prediction
    // is disabled inside SFTH workers, so the bitstream differs in a
    // documented way) — they are NOT byte-comparable to each other. We
    // check that each (inter, intra) config produces a .pjg byte-equal
    // to its own kind's baseline.
    auto build_baseline = [&]( int intra_setting,
                               std::vector<std::vector<unsigned char>>& pjgs,
                               std::vector<std::vector<unsigned char>>& rt_jpgs ) {
        pjglib_set_intra_file_threads( intra_setting );
        pjglib_set_inter_file_threads( 1 );
        pjgs.assign( corpus.size(), {} );
        rt_jpgs.assign( corpus.size(), {} );
        for ( size_t i = 0; i < corpus.size(); i++ ) {
            std::string err;
            if ( !compress_one( corpus[i].bytes, pjgs[i], err ) ) {
                std::fprintf( stderr, "[baseline intra=%d] compress failed: %s\n",
                              intra_setting, err.c_str() );
                std::exit( 1 );
            }
            unsigned char* rt_buf  = nullptr;
            unsigned int   rt_size = 0;
            char msg[PJG_MSG_SIZE] = {0};
            pjglib_init_streams( (void*) pjgs[i].data(), 1,
                                 (int) pjgs[i].size(), nullptr, 1 );
            if ( !pjglib_convert_stream2mem( &rt_buf, &rt_size, msg ) ) {
                std::fprintf( stderr, "[baseline intra=%d] decompress failed: %s\n",
                              intra_setting, msg );
                std::exit( 1 );
            }
            rt_jpgs[i].assign( rt_buf, rt_buf + rt_size );
            std::free( rt_buf );
        }
    };

    std::vector<std::vector<unsigned char>> baseline_off_pjg, baseline_off_rt;
    std::vector<std::vector<unsigned char>> baseline_on_pjg,  baseline_on_rt;
    build_baseline( 1, baseline_off_pjg, baseline_off_rt );
    build_baseline( 3, baseline_on_pjg,  baseline_on_rt );
    std::printf( "baselines: intra=off (%zu) and intra=on (%zu) built OK\n\n",
                 baseline_off_pjg.size(), baseline_on_pjg.size() );

    // For each (inter, intra) in the grid, run the batch and compare
    // against the matching baseline. The batch uses file I/O while the
    // baselines use mem I/O — that's fine, the encoder is stream-agnostic
    // and the bytes are stable across stream types (only the encoding
    // path matters: OFF vs ON).
    struct Cfg { int inter; int intra; const char* label;
                 const std::vector<std::vector<unsigned char>>* pjgs; };
    Cfg grid[] = {
        { 1, 1, "inter=1, intra=off",  &baseline_off_pjg },
        { 2, 1, "inter=2, intra=off",  &baseline_off_pjg },
        { 4, 1, "inter=4, intra=off",  &baseline_off_pjg },
        { 1, 3, "inter=1, intra=on",   &baseline_on_pjg  },
        { 2, 3, "inter=2, intra=on",   &baseline_on_pjg  },
        { 4, 3, "inter=4, intra=on",   &baseline_on_pjg  },
    };
    int n_cfg = (int) ( sizeof( grid ) / sizeof( grid[0] ) );

    std::printf( "%-32s  %10s  %10s  %8s  %s\n",
                 "config", "pjg_match", "rt_match", "time_ms", "status" );
    std::printf( "--------------------------------------------------------------------------\n" );

    int fail = 0;
    for ( int c = 0; c < n_cfg; c++ ) {
        auto t0 = std::chrono::steady_clock::now();
        std::vector<std::vector<unsigned char>> test_pjg;
        std::string err;
        bool ok = batch_compress( corpus, grid[c].inter, grid[c].intra,
                                  test_pjg, err );
        auto t1 = std::chrono::steady_clock::now();
        double ms = std::chrono::duration<double, std::milli>( t1 - t0 ).count();

        if ( !ok ) {
            std::printf( "%-32s  %10s  %10s  %8.0f  BATCH FAIL: %s\n",
                         grid[c].label, "-", "-", ms, err.c_str() );
            fail++;
            continue;
        }

        const auto& ref_pjgs = *grid[c].pjgs;
        int pjg_match = 0;
        for ( size_t i = 0; i < corpus.size(); i++ ) {
            if ( test_pjg[i].size() == ref_pjgs[i].size() &&
                 std::memcmp( test_pjg[i].data(), ref_pjgs[i].data(),
                              test_pjg[i].size() ) == 0 ) {
                pjg_match++;
            }
        }

        // Round-trip each test pjg and compare jpg bytes
        const auto& ref_rt = ( grid[c].intra == 1 ) ? baseline_off_rt
                                                     : baseline_on_rt;
        int rt_match = 0;
        for ( size_t i = 0; i < corpus.size(); i++ ) {
            unsigned char* rt_buf  = nullptr;
            unsigned int   rt_size = 0;
            char msg[PJG_MSG_SIZE] = {0};
            pjglib_init_streams( (void*) test_pjg[i].data(), 1,
                                 (int) test_pjg[i].size(), nullptr, 1 );
            if ( !pjglib_convert_stream2mem( &rt_buf, &rt_size, msg ) ) {
                continue;
            }
            if ( rt_size == ref_rt[i].size() &&
                 std::memcmp( rt_buf, ref_rt[i].data(), rt_size ) == 0 ) {
                rt_match++;
            }
            std::free( rt_buf );
        }

        bool all_ok = ( pjg_match == (int) corpus.size() ) &&
                      ( rt_match  == (int) corpus.size() );
        std::printf( "%-32s  %7d/%-2zu  %7d/%-2zu  %8.0f  %s",
                     grid[c].label, pjg_match, corpus.size(),
                     rt_match,  corpus.size(), ms,
                     all_ok ? "OK" : "FAIL" );
        if ( !all_ok ) {
            std::printf( "  [sizes: " );
            for ( size_t i = 0; i < corpus.size(); i++ )
                std::printf( "%zu%s", test_pjg[i].size(),
                             i + 1 < corpus.size() ? "," : "" );
            std::printf( " vs ref " );
            for ( size_t i = 0; i < corpus.size(); i++ )
                std::printf( "%zu%s", ref_pjgs[i].size(),
                             i + 1 < corpus.size() ? "," : "" );
            std::printf( "]" );
        }
        std::printf( "\n" );
        if ( !all_ok ) fail++;
    }

    std::printf( "\n── summary ─────────────────────────────────────\n" );
    std::printf( " configs run:  %d\n", n_cfg );
    std::printf( " failures:     %d\n", fail );
    return fail == 0 ? 0 : 1;
}
