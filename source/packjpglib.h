// packJPGlib.h - function declarations for the packJPG library
#if defined BUILD_DLL
	// DLL build: C-linkage + dllexport. The order matters — __declspec
	// attaches to the C-linkage declaration that follows.
	#define EXPORT extern "C" __declspec( dllexport )
#elif defined BUILD_SO
	// Unix shared object (.so): C-linkage + explicit default visibility, so
	// the public API stays exported even when the .so is built with
	// -fvisibility=hidden. Only set by the Makefile `so` target (gcc/clang),
	// so the attribute never reaches MSVC.
	#define EXPORT extern "C" __attribute__(( visibility( "default" ) ))
#elif defined __cplusplus
	#define EXPORT extern "C"   // ensure C-linkage when building as a static lib for FFI hosts
#else
	#define EXPORT extern
#endif

/* ---------------------------------------------------------------------------
   WINDOWS / MinGW CONSUMERS: THREAD MODEL MUST BE "posix"
   ---------------------------------------------------------------------------
   The shipped Windows binaries (packJPG.dll + libpackJPG.a import lib, and any
   packJPGlib.a you cross-build yourself) are compiled with the *posix*
   thread-model MinGW driver — the one with the -posix suffix, e.g.
   x86_64-w64-mingw32-g++-posix. The codec's internal std::mutex / std::once
   objects are therefore backed by winpthreads.

   You must build YOUR OWN objects with the same -posix driver. On Debian and
   Ubuntu the unsuffixed driver (x86_64-w64-mingw32-g++) is the *win32* model,
   so the default choice is the wrong one.

   Why this warning is unusually loud: the mismatch does not fail to link. It
   links clean, the process starts, compression completes and returns correct
   data — and then the first decode blocks forever on a lock, sitting at ~0%
   CPU. There is no error message, no crash and no timeout; the symptom is a
   process that simply never finishes. Verified on Windows x64 with the same
   static lib linked both ways: -posix round-trips byte-exact in ~100ms, the
   unsuffixed driver hangs indefinitely after a successful compress.

   Nothing in the build or the API can detect this for you, because a
   posix-built library absorbed into a win32-model host binary is
   indistinguishable at link time from a correct build. Check your driver:

       x86_64-w64-mingw32-g++-posix -v 2>&1 | grep 'Thread model'
       -> Thread model: posix

   (Linux/Unix consumers are unaffected — this is a MinGW-only hazard.)
   --------------------------------------------------------------------------- */

/* C99 / C++ bool shim. The lib API uses `bool` in three places; C
   consumers need stdbool.h, C++ gets it from the language. */
#if !defined(__cplusplus)
#include <stdbool.h>
#endif

// Minimum buffer size callers must allocate for the msg parameter
// in pjglib_convert_* functions.
#define PJG_MSG_SIZE 512

// Output buffers returned by pjglib_convert_stream2mem via *out_file
// are allocated with malloc(). Callers must free them with free(),
// NOT with delete[] (mixing allocators is undefined behaviour and is
// flagged as an error by AddressSanitizer).

/* -----------------------------------------------
	function declarations: library only functions
	----------------------------------------------- */

EXPORT bool pjglib_convert_stream2stream( char* msg );
EXPORT bool pjglib_convert_file2file( char* in, char* out, char* msg );
EXPORT bool pjglib_convert_stream2mem( unsigned char** out_file, unsigned int* out_size, char* msg );
EXPORT void pjglib_init_streams( void* in_src, int in_type, int in_size, void* out_dest, int out_type );
EXPORT const char* pjglib_version_info( void );
EXPORT const char* pjglib_short_name( void );

/* Concurrency model — two kinds of state, and the split matters more than
   it looks:

   PER-THREAD. The stream objects set up by pjglib_init_streams, plus the
   error state a failed convert reports, live in thread-local storage.
   Two consequences, one a requirement and one a permission:

     * pjglib_init_streams and the pjglib_convert_* that consumes it MUST
       run on the SAME thread. Split the pair across two threads — easy to
       do by accident on a task queue or a language runtime's thread pool,
       where consecutive statements need not stay on one thread — and the
       converting thread finds no streams at all, because it never
       initialised its own.
     * N threads may each run their own init + convert concurrently with
       no lock of yours. That is not an accident of the implementation; it
       is what the thread-local state is for, and it is covered by
       test/lib_concurrent_test and by the LoadLibrary harness in
       test/dll-harness/.

   PROCESS-WIDE. The configuration setters below — intra/inter file threads
   and max_output_size — are ordinary globals shared by every thread. This
   is why a per-file output cap needs a caller-held lock covering set +
   convert, while the converts themselves do not.

   So a mutex around the whole API is not needed for thread safety and
   costs you the parallelism above; a mutex is needed when you change
   configuration per item, or to keep an init/convert pair together. */

/* -----------------------------------------------
	function declarations: library threading controls
	----------------------------------------------- */

/* Intra-file threads: parallelism within a single file (Y/Cb/Cr in
   parallel). Same code path as the CLI -sfth flag.

   n =  0  default = auto: ON if host has >=3 logical cores
   n =  1  force OFF (single-threaded per file)
   n >= 3  force ON  (each file uses 3 worker threads)

   Affects all subsequent pjglib_convert_* and pjglib_convert_batch calls.
   Default resolution happens lazily on the first convert call. Setters
   are NOT thread-safe — call them during single-threaded init, before
   spawning workers.

   Scope of the thread-safety claims in this header: measured with C and
   C++ hosts. Concurrent pjglib_convert_* from several host threads is
   verified there — including, on Windows, four raw CreateThread threads
   entering the DLL at once (measured on Windows 7 SP1 x64 and Windows 10
   x64 against the released packJPG.dll).

   KNOWN DEFECT, Windows DLL only: LOAD THE DLL BEFORE YOU CREATE THREADS.
   If packJPG.dll is loaded with LoadLibrary into a process whose threads
   already exist, and those pre-existing threads then call the codec, the
   process hangs — measured 6 of 6 runs against the released v5.0d DLL on
   Windows 10 Enterprise LTSC 21H2 (build 19044.7291) x64, with 4 and with
   8 threads. Not reproduced on Windows 7 SP1 x64 (3 runs), so the OS
   dependence is an observation over two machines, not a mechanism.

   The work completes first: every thread returns a correct result, and the
   hang lands afterwards while thread-local storage is torn down. That is
   why the symptom is a process that never exits rather than a bad output,
   and why it is invisible to a round-trip check.

   Threads created AFTER the load are unaffected, single-threaded use is
   unaffected, and the static library is unaffected — this is specific to
   the dynamically loaded DLL. So the workaround is ordering, not locking:
   LoadLibrary during startup, before spawning your pool. A host whose
   runtime starts its own threads before your code runs (packJPG hit this
   with a FreePascal host) may not be able to control that ordering, in
   which case the win32-thread-model build does not exhibit it (0 of 6
   runs) — but see the thread-model warning above for what that costs.

   test/dll-harness/ reproduces all of this from four small C hosts,
   contributed by the consumer who found it. */
EXPORT void pjglib_set_intra_file_threads( int n );
EXPORT int  pjglib_get_intra_file_threads( void );

/* Inter-file threads: parallelism across files inside pjglib_convert_batch.
   Each worker handles one op at a time and uses intra_file_threads for the
   encode/decode inside that op.

   n =  0  default = 1 (sequential batch)
   n >= 1  N concurrent worker threads

   Same thread-safety rule as the intra setter: call during init only. */
EXPORT void pjglib_set_inter_file_threads( int n );
EXPORT int  pjglib_get_inter_file_threads( void );

/* Decompression-bomb guard. Cap the size (bytes) of a JPEG the decoder will
   reconstruct from a .pjg. Decoding a .pjg whose output would exceed n bytes
   fails cleanly instead of producing it. Recommended for hosts that decode
   untrusted .pjg input.

   Default is 256 MB, NOT unlimited — n = 0 disables the guard. Callers that
   want to restore a previous value should save it with the getter rather than
   assume any particular default.

   Process-wide; set during single-threaded init. It is, however, safe to
   change between calls if the caller serializes: the value is read only
   inside the convert call, nothing caches it earlier. A per-file limit is
   therefore fine under a caller-held lock covering set + convert — but it is
   NOT compatible with pjglib_convert_batch when the ops need different
   limits, since the workers share this one process-wide value (it is not
   part of the per-thread state) and the last setter wins for all of them.

   Diagnosing a rejection: the cap can produce four distinct messages in
   the pjglib_convert_* msg buffer, and which one appears depends on how the
   .pjg was written, not on how it is decoded. Hosts that classify errors
   should match all four rather than assume one:

     "output size limit exceeded: reconstructed JPEG would be at least ..."
     "output size limit exceeded: reconstructed JPEG is ..."
     "sfth component stream too large: ..."       (-sfth-format .pjg only)
     "corrupt data: decoder exceeded size limit"  (per-field limit)

   None of the four can occur on a valid .pjg with a large enough cap, so all
   four mean "rejected by the guard" and not "corrupt input". A fifth message,
   "blowup ratio exceeded: ...", comes from the always-on ratio guard
   (output > input * 500 + 1 MB) and is not affected by this setter. */
EXPORT void         pjglib_set_max_output_size( unsigned int n );
EXPORT unsigned int pjglib_get_max_output_size( void );

/* Helper: pjglib_suggest_batch_threads() returns max(1, cores/3), which
   keeps total thread budget (inter * intra) close to cores. Useful for
   archivers picking a default value at startup. */
EXPORT int  pjglib_suggest_batch_threads( void );

/* One input/output pair in a batch conversion. Same stream-type semantics
   as pjglib_init_streams (in_type/out_type: 0=file, 1=memory, 2=stream).
   For memory I/O the caller must keep in_src's buffer alive until
   pjglib_convert_batch returns. For file I/O the library creates output
   files unless out_dest is NULL (in which case the default extension
   logic from the single-file API is used). */
typedef struct {
	void*         in_src;
	int           in_type;
	unsigned int  in_size;
	void*         out_dest;
	int           out_type;
} pjglib_batch_io;

/* Convert N (in,out) pairs in parallel over pjglib_get_inter_file_threads()
   workers. Each worker calls pjglib_convert_stream2mem internally with the
   currently configured intra_file_threads (sfth auto/on/off).

   Returns true iff all N conversions succeeded. On the first failure, msg
   is filled with the failing worker's error message (truncated to PJG_MSG_SIZE
   bytes including the null terminator) and remaining workers are allowed
   to finish; their results are discarded. */
EXPORT bool pjglib_convert_batch( pjglib_batch_io* ops, int n_ops, char* msg );

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
