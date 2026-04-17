// libFuzzer harness for the packJPG library decoder.
//
// Targets the memory-in / memory-out path of pjglib_convert_stream2mem.
// The lib auto-detects filetype from the first two bytes ("JS" = PJG,
// 0xFF 0xD8 = JPG) so we feed the input through unmodified and let the
// dispatch code exercise whichever branch matches. That way a single
// corpus covers both the decode and the encode surface; the v4.0
// cross-component additions live in the pjg_{encode,decode}_{dc,ac_high,
// ac_low} functions and are reached from both directions.
//
// Build via source/test/build_fuzzer.sh.

#include <cstdint>
#include <cstdlib>
#include <cstring>

#include "../packjpglib.h"

extern "C" int LLVMFuzzerTestOneInput( const uint8_t* data, size_t size ) {
    if ( size == 0 || size > (8 * 1024 * 1024) ) return 0;

    // pjglib_init_streams takes non-const pointers. Copy so the lib can
    // mutate the buffer if it wants to; we own the storage.
    unsigned char* in_copy = static_cast<unsigned char*>( std::malloc( size ) );
    if ( !in_copy ) return 0;
    std::memcpy( in_copy, data, size );

    unsigned char* out_buf  = nullptr;
    unsigned int   out_size = 0;

    char msg[ PJG_MSG_SIZE ];
    msg[ 0 ] = '\0';

    // in_type = 1 (memory), out_type is ignored for stream2mem.
    pjglib_init_streams( in_copy, 1, static_cast<int>( size ), nullptr, 1 );
    pjglib_convert_stream2mem( &out_buf, &out_size, msg );

    // pjglib_convert_stream2mem allocates out_buf with malloc(); the
    // header documents we must free with free() (not delete[]).
    if ( out_buf ) std::free( out_buf );
    std::free( in_copy );

    return 0;
}
