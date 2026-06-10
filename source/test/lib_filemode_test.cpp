// lib_filemode_test.cpp — regression test for the file→file batch path with
// out_dest == NULL (the "lib writes a sibling file" convenience documented in
// the README and used by dll_test.c).
//
// Covers two bugs fixed during v4.0e QA:
//   1. Extension direction: a fixed ".pjg" guess made decompressing foo.pjg
//      write the reconstructed JPEG straight back onto foo.pjg, destroying the
//      compressed source. The sibling extension must follow the input type
//      (JPEG -> .pjg, PJG -> .jpg).
//   2. Per-thread filename leak: each batch worker leaked its last
//      jpgfilename/pjgfilename pair at thread exit (caught by ASan; this test
//      exercises the same path so a sanitized build re-flags any regression).
//
// Strategy:
//   - Copy N source JPEGs into a scratch dir.
//   - Batch-compress them (file in, out_dest=NULL) -> expect sibling .pjg.
//   - Snapshot the .pjg bytes.
//   - Batch-decompress the .pjg (file in, out_dest=NULL) -> expect sibling .jpg
//     AND the .pjg must be left byte-for-byte intact.
//   - The reconstructed .jpg must be byte-exact with the original.
//
// Usage: ./lib_filemode_test <scratch_dir> file1.jpg [file2.jpg ...]
// Exit 0 on success, non-zero on any failure.

#include "packjpglib.h"

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

namespace {

std::vector<unsigned char> read_all( const std::string& path ) {
    std::vector<unsigned char> v;
    FILE* f = fopen( path.c_str(), "rb" );
    if ( !f ) return v;
    fseek( f, 0, SEEK_END );
    long n = ftell( f );
    fseek( f, 0, SEEK_SET );
    if ( n > 0 ) {
        v.resize( (size_t) n );
        if ( fread( v.data(), 1, (size_t) n, f ) != (size_t) n ) v.clear();
    }
    fclose( f );
    return v;
}

bool write_all( const std::string& path, const std::vector<unsigned char>& v ) {
    FILE* f = fopen( path.c_str(), "wb" );
    if ( !f ) return false;
    bool ok = ( v.empty() || fwrite( v.data(), 1, v.size(), f ) == v.size() );
    fclose( f );
    return ok;
}

std::string swap_ext( std::string p, const char* ext ) {
    size_t dot = p.find_last_of( '.' );
    if ( dot != std::string::npos ) p.erase( dot );
    return p + ext;
}

} // namespace

int main( int argc, char** argv ) {
    if ( argc < 3 ) {
        fprintf( stderr, "usage: %s <scratch_dir> file1.jpg [file2.jpg ...]\n", argv[0] );
        return 2;
    }
    std::string dir = argv[1];
    if ( !dir.empty() && dir.back() != '/' ) dir += '/';

    int n = argc - 2;
    std::vector<std::string>              base;   // scratch jpg paths
    std::vector<std::vector<unsigned char>> orig; // original jpg bytes

    // Stage source files into the scratch dir.
    for ( int i = 0; i < n; i++ ) {
        std::vector<unsigned char> b = read_all( argv[i + 2] );
        if ( b.empty() ) { fprintf( stderr, "cannot read %s\n", argv[i + 2] ); return 2; }
        const char* fwd  = strrchr( argv[i + 2], '/' );
        const char* back = strrchr( argv[i + 2], '\\' );
        const char* slash = ( fwd > back ) ? fwd : back; // last of either separator
        std::string name  = slash ? slash + 1 : argv[i + 2];
        std::string dst   = dir + name;
        if ( !write_all( dst, b ) ) { fprintf( stderr, "cannot write %s\n", dst.c_str() ); return 2; }
        base.push_back( dst );
        orig.push_back( b );
    }

    pjglib_set_inter_file_threads( 4 );
    pjglib_set_intra_file_threads( 0 ); // auto

    // --- Phase 1: batch compress (file in, out_dest = NULL) ---
    {
        std::vector<pjglib_batch_io> ops( n );
        for ( int i = 0; i < n; i++ )
            ops[i] = { (void*) base[i].c_str(), 0, 0, NULL, 0 };
        char msg[PJG_MSG_SIZE] = {0};
        if ( !pjglib_convert_batch( ops.data(), n, msg ) ) {
            fprintf( stderr, "FAIL: batch compress: %s\n", msg );
            return 1;
        }
    }

    // Snapshot the produced .pjg files.
    std::vector<std::string>               pjg( n );
    std::vector<std::vector<unsigned char>> pjg_snap( n );
    for ( int i = 0; i < n; i++ ) {
        pjg[i]      = swap_ext( base[i], ".pjg" );
        pjg_snap[i] = read_all( pjg[i] );
        if ( pjg_snap[i].empty() ) {
            fprintf( stderr, "FAIL: no .pjg produced for %s\n", base[i].c_str() );
            return 1;
        }
    }

    // --- Phase 2: batch decompress the .pjg (file in, out_dest = NULL) ---
    {
        std::vector<pjglib_batch_io> ops( n );
        for ( int i = 0; i < n; i++ )
            ops[i] = { (void*) pjg[i].c_str(), 0, 0, NULL, 0 };
        char msg[PJG_MSG_SIZE] = {0};
        if ( !pjglib_convert_batch( ops.data(), n, msg ) ) {
            fprintf( stderr, "FAIL: batch decompress: %s\n", msg );
            return 1;
        }
    }

    // --- Verify ---
    int fails = 0;
    for ( int i = 0; i < n; i++ ) {
        // (a) the .pjg must be untouched (bug #1 overwrote it).
        std::vector<unsigned char> pjg_now = read_all( pjg[i] );
        if ( pjg_now != pjg_snap[i] ) {
            fprintf( stderr, "FAIL: %s was modified by decompress (extension-direction bug)\n", pjg[i].c_str() );
            fails++;
            continue;
        }
        // (b) the reconstructed .jpg must be byte-exact with the original.
        std::string rec = swap_ext( pjg[i], ".jpg" );
        std::vector<unsigned char> got = read_all( rec );
        if ( got != orig[i] ) {
            fprintf( stderr, "FAIL: %s not byte-exact (%zu vs %zu bytes)\n",
                     rec.c_str(), got.size(), orig[i].size() );
            fails++;
            continue;
        }
        printf( "  OK  %s  -> .pjg intact, .jpg byte-exact\n", base[i].c_str() );
    }

    printf( "\nlib_filemode_test: %d/%d files passed\n", n - fails, n );
    return fails == 0 ? 0 : 1;
}
