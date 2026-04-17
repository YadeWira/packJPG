// lib_roundtrip_test.cpp — mem→mem roundtrip test for packJPGlib
//
// For each JPEG in argv[]:
//   1. load into RAM
//   2. call pjglib_convert_stream2mem to compress (JPG -> PJG in RAM)
//   3. call pjglib_convert_stream2mem again to decompress (PJG -> JPG in RAM)
//   4. compare byte-for-byte with the original
//
// Usage: ./lib_roundtrip_test file1.jpg file2.jpg ...

#include "packjpglib.h"
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <vector>
#include <string>

static std::vector<unsigned char> read_file( const char* path ) {
    FILE* f = fopen( path, "rb" );
    if ( !f ) return {};
    fseek( f, 0, SEEK_END );
    long n = ftell( f );
    fseek( f, 0, SEEK_SET );
    std::vector<unsigned char> buf( (size_t)n );
    if ( fread( buf.data(), 1, (size_t)n, f ) != (size_t)n ) buf.clear();
    fclose( f );
    return buf;
}

int main( int argc, char** argv ) {
    if ( argc < 2 ) {
        fprintf( stderr, "usage: %s file1.jpg [file2.jpg ...]\n", argv[0] );
        return 2;
    }

    printf( "packJPGlib: %s\n", pjglib_version_info() );
    printf( "%-40s  %10s  %10s  %6s  %s\n",
            "file", "jpg_size", "pjg_size", "ratio", "status" );

    int ok = 0, fail_pack = 0, fail_unpack = 0, mismatch = 0;
    long long tot_jpg = 0, tot_pjg = 0;

    for ( int i = 1; i < argc; i++ ) {
        const char* path = argv[i];
        auto jpg = read_file( path );
        if ( jpg.empty() ) { printf( "%-40s  READ FAIL\n", path ); continue; }

        // ── step 1: JPG mem -> PJG mem ────────────────────────────
        unsigned char* pjg_buf  = NULL;
        unsigned int   pjg_size = 0;
        char msg[PJG_MSG_SIZE] = {0};
        pjglib_init_streams( (void*)jpg.data(), 1, (int)jpg.size(),
                             (void*)&pjg_buf, 1 );
        if ( !pjglib_convert_stream2mem( &pjg_buf, &pjg_size, msg ) ) {
            printf( "%-40s  %10zu  %10s  %6s  PACK FAIL: %s\n",
                    path, jpg.size(), "-", "-", msg );
            fail_pack++;
            continue;
        }

        // ── step 2: PJG mem -> JPG mem ────────────────────────────
        unsigned char* jpg2_buf  = NULL;
        unsigned int   jpg2_size = 0;
        char msg2[PJG_MSG_SIZE] = {0};
        pjglib_init_streams( (void*)pjg_buf, 1, (int)pjg_size,
                             (void*)&jpg2_buf, 1 );
        if ( !pjglib_convert_stream2mem( &jpg2_buf, &jpg2_size, msg2 ) ) {
            printf( "%-40s  %10zu  %10u  %6s  UNPACK FAIL: %s\n",
                    path, jpg.size(), pjg_size, "-", msg2 );
            fail_unpack++;
            delete[] pjg_buf;
            continue;
        }

        // ── step 3: roundtrip compare ─────────────────────────────
        bool same = ( jpg2_size == jpg.size() ) &&
                    ( memcmp( jpg2_buf, jpg.data(), jpg.size() ) == 0 );
        double ratio = 100.0 * pjg_size / jpg.size();
        printf( "%-40s  %10zu  %10u  %5.2f%%  %s\n",
                path, jpg.size(), pjg_size, ratio,
                same ? "OK" : "MISMATCH" );

        if ( same ) { ok++; tot_jpg += jpg.size(); tot_pjg += pjg_size; }
        else         mismatch++;

        delete[] pjg_buf;
        delete[] jpg2_buf;
    }

    printf( "\n── summary ─────────────────────────────────────\n" );
    printf( " ok:            %d\n", ok );
    printf( " pack fails:    %d\n", fail_pack );
    printf( " unpack fails:  %d\n", fail_unpack );
    printf( " mismatches:    %d\n", mismatch );
    if ( tot_jpg > 0 ) {
        printf( " total jpg:     %lld bytes\n", tot_jpg );
        printf( " total pjg:     %lld bytes\n", tot_pjg );
        printf( " overall ratio: %.2f%% (saved %.2f%%)\n",
                100.0 * tot_pjg / tot_jpg,
                100.0 * ( tot_jpg - tot_pjg ) / tot_jpg );
    }

    return ( mismatch || fail_unpack ) ? 1 : 0;
}
