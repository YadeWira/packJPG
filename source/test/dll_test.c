/* dll_test.c — minimal C test for packJPG.dll (v4.0e)
 *
 * Reads N JPEGs from disk, calls pjglib_convert_batch to compress
 * them to sibling .pjg files in parallel, then decompresses each
 * back to memory and byte-compares with the original.
 *
 * Build (MSVC):  cl dll_test.c /I..\source ..\win64\packJPG.lib
 *                (generate packJPG.lib first: lib /def:packJPG.def /machine:x64)
 * Build (MinGW): x86_64-w64-mingw32-gcc dll_test.c -o dll_test.exe \
 *                                       -I../source ../win64/libpackJPG.a
 *
 * Usage: dll_test.exe file1.jpg [file2.jpg ...]
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "packjpglib.h"

static unsigned char* read_file(const char* path, unsigned int* out_size) {
    FILE* f = fopen(path, "rb");
    if (!f) return NULL;
    fseek(f, 0, SEEK_END);
    long n = ftell(f);
    fseek(f, 0, SEEK_SET);
    unsigned char* buf = (unsigned char*) malloc((size_t) n);
    if (!buf) { fclose(f); return NULL; }
    if (fread(buf, 1, (size_t) n, f) != (size_t) n) { free(buf); fclose(f); return NULL; }
    fclose(f);
    *out_size = (unsigned int) n;
    return buf;
}

int main(int argc, char** argv) {
    if (argc < 2) {
        fprintf(stderr, "usage: %s file1.jpg [file2.jpg ...]\n", argv[0]);
        return 1;
    }

    printf("packJPG.dll: %s\n", pjglib_version_info());
    int cores_hint = pjglib_suggest_batch_threads();
    printf("suggested batch threads: %d\n", cores_hint);

    /* Enable MT: batch parallelism = suggested (cores/3),
       intra-file (SFTH) = auto (ON if >=3 cores). */
    pjglib_set_inter_file_threads(cores_hint);
    pjglib_set_intra_file_threads(0);
    printf("intra_file_threads:  %d (0=auto)\n", pjglib_get_intra_file_threads());
    printf("inter_file_threads:  %d\n", pjglib_get_inter_file_threads());

    /* --- Phase 1: compress N jpgs in parallel ---------------------- */
    int n = argc - 1;
    pjglib_batch_io* ops = (pjglib_batch_io*) calloc((size_t) n, sizeof(pjglib_batch_io));
    for (int i = 0; i < n; i++) {
        ops[i].in_src   = argv[i + 1];
        ops[i].in_type  = 0;          /* file */
        ops[i].in_size  = 0;
        ops[i].out_dest = NULL;       /* lib writes sibling .pjg */
        ops[i].out_type = 0;
    }
    char msg[PJG_MSG_SIZE] = {0};
    if (!pjglib_convert_batch(ops, n, msg)) {
        fprintf(stderr, "batch compress failed: %s\n", msg);
        free(ops);
        return 2;
    }
    printf("compressed %d files OK\n", n);

    /* --- Phase 2: round-trip each .pjg back to .jpg and compare --- */
    int mismatches = 0;
    for (int i = 0; i < n; i++) {
        char pjg_path[1024];
        snprintf(pjg_path, sizeof(pjg_path), "%s", argv[i + 1]);
        char* dot = strrchr(pjg_path, '.');
        if (dot) snprintf(dot, sizeof(pjg_path) - (size_t)(dot - pjg_path), ".pjg");
        else     snprintf(pjg_path + strlen(pjg_path),
                          sizeof(pjg_path) - strlen(pjg_path), ".pjg");

        /* Read the .pjg file written by the batch, decompress to memory.
           The result is the reconstructed JPG bytes — that's what we
           compare against the original on disk. */
        unsigned char* jpg_buf  = NULL;
        unsigned int   jpg_size = 0;
        char dmsg[PJG_MSG_SIZE] = {0};
        pjglib_init_streams(pjg_path, 0, 0, NULL, 1);
        if (!pjglib_convert_stream2mem(&jpg_buf, &jpg_size, dmsg)) {
            fprintf(stderr, "  decompress %s failed: %s\n", pjg_path, dmsg);
            mismatches++;
            continue;
        }

        unsigned int orig_size = 0;
        unsigned char* orig = read_file(argv[i + 1], &orig_size);
        int ok = (orig && orig_size == jpg_size &&
                  memcmp(orig, jpg_buf, jpg_size) == 0);
        printf("  %-40s  %6u -> %6u  %s\n",
               argv[i + 1], orig_size, jpg_size, ok ? "OK" : "MISMATCH");
        if (!ok) mismatches++;
        free(orig);
        free(jpg_buf);
    }

    free(ops);
    printf("\nresult: %d / %d files round-tripped byte-exact\n",
           n - mismatches, n);
    return mismatches == 0 ? 0 : 3;
}
