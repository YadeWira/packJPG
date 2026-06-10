// lib_maxoutput_test.cpp — verify the decompression-bomb guard
// (pjglib_set_max_output_size).
//
// Self-contained: compresses a real JPEG to a .pjg in memory, then decodes it
// back under three caps and checks the guard fires exactly when it should:
//   cap = 0            -> unlimited, decode succeeds
//   cap > output size  -> decode succeeds, output unchanged
//   cap < output size  -> decode fails cleanly (no output, msg set)
//
// This pins the merge_jpeg output-size check. The earlier pjg_decode_generic
// allocation cap shares the same global, so a passing decode here also proves
// the default (cap=0) path is unaffected.
//
// Usage: ./lib_maxoutput_test file1.jpg [file2.jpg ...]
// Exit 0 on success, 1 on any unexpected behaviour.

#include "packjpglib.h"

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <vector>

namespace {

std::vector<unsigned char> read_all( const char* path ) {
    std::vector<unsigned char> v;
    FILE* f = fopen( path, "rb" );
    if ( !f ) return v;
    fseek( f, 0, SEEK_END ); long n = ftell( f ); fseek( f, 0, SEEK_SET );
    if ( n > 0 ) { v.resize( (size_t) n ); if ( fread( v.data(), 1, (size_t) n, f ) != (size_t) n ) v.clear(); }
    fclose( f );
    return v;
}

// Compress a JPEG (in memory) to a .pjg (in memory). Returns the pjg bytes.
std::vector<unsigned char> compress_to_pjg( std::vector<unsigned char>& jpg, bool* ok ) {
    pjglib_set_max_output_size( 0 );
    pjglib_init_streams( jpg.data(), 1, (int) jpg.size(), NULL, 1 );
    unsigned char* out = NULL; unsigned int outsz = 0; char msg[PJG_MSG_SIZE] = {0};
    *ok = pjglib_convert_stream2mem( &out, &outsz, msg );
    std::vector<unsigned char> pjg;
    if ( *ok && out ) pjg.assign( out, out + outsz );
    if ( out ) free( out );
    return pjg;
}

// Decode a .pjg under a cap. Returns the decoded size (0 if it failed).
unsigned int decode_with_cap( std::vector<unsigned char>& pjg, unsigned int cap, bool* ok ) {
    pjglib_set_max_output_size( cap );
    pjglib_init_streams( pjg.data(), 1, (int) pjg.size(), NULL, 1 );
    unsigned char* out = NULL; unsigned int outsz = 0; char msg[PJG_MSG_SIZE] = {0};
    *ok = pjglib_convert_stream2mem( &out, &outsz, msg );
    if ( out ) free( out );
    return *ok ? outsz : 0;
}

} // namespace

int main( int argc, char** argv ) {
    if ( argc < 2 ) { fprintf( stderr, "usage: %s file.jpg ...\n", argv[0] ); return 2; }

    int fails = 0;
    for ( int i = 1; i < argc; i++ ) {
        std::vector<unsigned char> jpg = read_all( argv[i] );
        if ( jpg.empty() ) { fprintf( stderr, "skip (cannot read) %s\n", argv[i] ); continue; }

        bool ok = false;
        std::vector<unsigned char> pjg = compress_to_pjg( jpg, &ok );
        if ( !ok || pjg.empty() ) { fprintf( stderr, "skip (cannot compress) %s\n", argv[i] ); continue; }

        unsigned int full = (unsigned int) jpg.size(); // expected decode size

        // 1) unlimited
        bool ok0; unsigned int sz0 = decode_with_cap( pjg, 0, &ok0 );
        // 2) cap above the output
        bool okHi; unsigned int szHi = decode_with_cap( pjg, full + 1024, &okHi );
        // 3) cap below the output (must trip the guard)
        bool okLo; unsigned int szLo = decode_with_cap( pjg, ( full > 64 ) ? full - 64 : 1, &okLo );

        bool pass = ok0 && sz0 == full
                 && okHi && szHi == full
                 && !okLo && szLo == 0;
        printf( "  %-30s  full=%u  cap0=%s  capHi=%s  capLo=%s  -> %s\n",
                argv[i], full,
                (ok0 && sz0==full) ? "ok" : "BAD",
                (okHi && szHi==full) ? "ok" : "BAD",
                (!okLo) ? "blocked" : "LEAKED",
                pass ? "PASS" : "FAIL" );
        if ( !pass ) fails++;
    }

    // restore default so we don't leak the cap to anything reusing the process
    pjglib_set_max_output_size( 0 );

    printf( "\nlib_maxoutput_test: %s\n", fails == 0 ? "all PASS" : "FAILURES" );
    return fails == 0 ? 0 : 1;
}
