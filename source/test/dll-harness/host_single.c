/* Minimal C control host: LoadLibrary a packJPG DLL and compress one JPEG.
   Mirrors what ytool's Pascal binding does, minus the FreePascal runtime.
   Every step flushes, so a hang is pinned to an exact line. */
#include <stdio.h>
#include <stdlib.h>
#include <windows.h>

typedef void (*init_streams_t)(void*, int, int, void*, int);
typedef int  (*convert_s2m_t)(char**, unsigned int*, char*);
typedef char* (*version_t)(void);
typedef void (*set_intra_t)(int);

#define STEP(n, msg) do { printf("[%d] %s\n", n, msg); fflush(stdout); } while(0)

int main(int argc, char** argv) {
    if (argc < 3) { printf("usage: host <dll> <jpeg>\n"); return 2; }

    STEP(1, "LoadLibrary...");
    HMODULE h = LoadLibraryA(argv[1]);
    if (!h) { printf("    FAILED err=%lu\n", GetLastError()); return 1; }
    printf("    handle=%p\n", (void*)h); fflush(stdout);

    STEP(2, "GetProcAddress...");
    version_t       ver   = (version_t)      GetProcAddress(h, "pjglib_version_info");
    init_streams_t  init  = (init_streams_t) GetProcAddress(h, "pjglib_init_streams");
    convert_s2m_t   conv  = (convert_s2m_t)  GetProcAddress(h, "pjglib_convert_stream2mem");
    set_intra_t     intra = (set_intra_t)    GetProcAddress(h, "pjglib_set_intra_file_threads");
    printf("    ver=%p init=%p conv=%p intra=%p\n",
           (void*)ver, (void*)init, (void*)conv, (void*)intra); fflush(stdout);
    if (!init || !conv) { printf("    missing symbols\n"); return 1; }

    if (intra) { STEP(3, "set_intra_file_threads(1)... (ytool does this)"); intra(1); }
    else       { STEP(3, "set_intra_file_threads absent, skipping"); }

    if (ver) { STEP(4, "version_info..."); printf("    %s\n", ver()); fflush(stdout); }

    STEP(5, "read input jpeg...");
    FILE* f = fopen(argv[2], "rb");
    if (!f) { printf("    cannot open\n"); return 1; }
    fseek(f, 0, SEEK_END); long n = ftell(f); fseek(f, 0, SEEK_SET);
    char* buf = (char*)malloc(n);
    if (fread(buf, 1, n, f) != (size_t)n) { printf("    short read\n"); return 1; }
    fclose(f);
    printf("    %ld bytes\n", n); fflush(stdout);

    STEP(6, "init_streams (mem in, mem out)...");
    init(buf, 1 /*pjglib_memory*/, (int)n, NULL, 1);

    STEP(7, "convert_stream2mem... <-- the call that hangs under ytool");
    char* out = NULL; unsigned int outsz = 0; char msg[1024] = {0};
    int ok = conv(&out, &outsz, msg);
    printf("    ok=%d out=%u msg=%s\n", ok, outsz, msg); fflush(stdout);

    STEP(8, "FreeLibrary...");
    FreeLibrary(h);

    STEP(9, "DONE (no hang)");
    return ok ? 0 : 1;
}
