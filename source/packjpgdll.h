// packJPGdll.h - function import declarations for the packJPG DLL
//
// Use this header when consuming packJPG.dll from MSVC (or any compiler
// that understands __declspec(dllimport)). For MinGW/Clang you can instead
// include packjpglib.h and link libpackJPG.a directly.
//
// All exports are undecorated C-linkage symbols, so a C++ consumer must
// keep the extern "C" wrapper below for the names to resolve.
#define IMPORT __declspec( dllimport )

#if defined __cplusplus
extern "C" {
#endif

/* C99 / C++ bool shim. The lib API uses `bool` in its convert/batch
   functions; C consumers need stdbool.h, C++ gets it from the language. */
#if !defined(__cplusplus)
#include <stdbool.h>
#endif

// Minimum buffer size callers must allocate for the msg parameter
// in pjglib_convert_* functions.
#define PJG_MSG_SIZE 512

/* -----------------------------------------------
	function declarations: library only functions
	----------------------------------------------- */

IMPORT bool pjglib_convert_stream2stream( char* msg );
IMPORT bool pjglib_convert_file2file( char* in, char* out, char* msg );
IMPORT bool pjglib_convert_stream2mem( unsigned char** out_file, unsigned int* out_size, char* msg );
IMPORT void pjglib_init_streams( void* in_src, int in_type, int in_size, void* out_dest, int out_type );
IMPORT const char* pjglib_version_info( void );
IMPORT const char* pjglib_short_name( void );

/* -----------------------------------------------
	function declarations: library threading controls (v4.0e)
	----------------------------------------------- */

/* Intra-file threads: parallelism within a single file (Y/Cb/Cr in
   parallel). Same code path as the CLI -sfth flag.
     n =  0  default = auto: ON if host has >=3 logical cores
     n =  1  force OFF (single-threaded per file)
     n >= 3  force ON  (each file uses 3 worker threads)
   Setters are NOT thread-safe — call during single-threaded init. */
IMPORT void pjglib_set_intra_file_threads( int n );
IMPORT int  pjglib_get_intra_file_threads( void );

/* Inter-file threads: parallelism across files inside pjglib_convert_batch.
     n =  0  default = 1 (sequential batch)
     n >= 1  N concurrent worker threads */
IMPORT void pjglib_set_inter_file_threads( int n );
IMPORT int  pjglib_get_inter_file_threads( void );

/* Helper: returns max(1, cores/3), the canonical packing that keeps total
   thread budget (inter * intra) close to the host's core count. */
IMPORT int  pjglib_suggest_batch_threads( void );

/* Decompression-bomb guard. Cap the size (bytes) of a JPEG reconstructed from
   a .pjg; 0 = unlimited (default). Decoding a .pjg whose output would exceed n
   bytes then fails cleanly. Recommended for untrusted .pjg input. */
IMPORT void         pjglib_set_max_output_size( unsigned int n );
IMPORT unsigned int pjglib_get_max_output_size( void );

/* One input/output pair in a batch conversion. Same stream-type semantics
   as pjglib_init_streams (in_type/out_type: 0=file, 1=memory, 2=stream). */
typedef struct {
	void*         in_src;
	int           in_type;
	unsigned int  in_size;
	void*         out_dest;
	int           out_type;
} pjglib_batch_io;

/* Convert N (in,out) pairs in parallel over pjglib_get_inter_file_threads()
   workers. Returns true iff all N conversions succeeded. On the first
   failure, msg is filled with the failing op's index and error. */
IMPORT bool pjglib_convert_batch( pjglib_batch_io* ops, int n_ops, char* msg );

#if defined __cplusplus
}
#endif

/* a short reminder about input/output stream types
   for the pjglib_init_streams() function

	if input is file
	----------------
	in_scr -> name of input file
	in_type -> 0
	in_size -> ignore

	if input is memory
	------------------
	in_scr -> array containg data
	in_type -> 1
	in_size -> size of data array

	if input is *FILE (f.e. stdin)
	------------------------------
	in_src -> stream pointer
	in_type -> 2
	in_size -> ignore

	vice versa for output streams! */
