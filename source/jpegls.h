// jpegls.h — JPEG-LS lossless recompression handler for packJPG
//
// Compile with -DHAVE_JPEGLS to enable JPEG-LS support (requires libcharls-dev
// + libjxl-dev). Without the flag, all functions degrade to no-op stubs and
// JPEG-LS files are silently skipped — no external dependencies needed.
//
// When enabled, the handler decodes JPEG-LS to planar pixels (via CharLS),
// recompresses them with JPEG XL lossless (~16% smaller), and stores the
// container template. On reconstruction, CharLS regenerates the exact
// Golomb-Rice entropy bytes, which are spliced back into the template.
//
// Only default-parameter scans (ILV=0, NEAR=0) are supported — interleaved or
// near-lossless scans are detected and refused with a clear error.

#ifndef PACKJPG_JPEGLS_H
#define PACKJPG_JPEGLS_H

#include <cstdint>
#include <cstddef>

// --- public types (always available — JlsFileInfo is a THREAD_LOCAL global) ---

struct JlsFileInfo {
    uint16_t width;
    uint16_t height;
    uint8_t  bits_per_sample;
    uint8_t  component_count;

    uint8_t  scan_count;
    uint8_t  channels[16];

    uint32_t part_count;
    uint32_t part_sizes[17];

    uint32_t entropy_lengths[16];
};

// ---------------------------------------------------------------------------
// When HAVE_JPEGLS is NOT defined, all functions are no-op stubs.
// packjpg.cpp calls them unconditionally — the compiler will inline them away.
// ---------------------------------------------------------------------------

#ifdef HAVE_JPEGLS

// --- real declarations (HAVE_JPEGLS) ---------------------------------------

bool jpegls_detect(const uint8_t* data, size_t size);

bool jpegls_parse(const uint8_t* data, size_t size,
                  JlsFileInfo& info,
                  uint8_t*& template_bytes, size_t& template_size,
                  uint8_t*& pixels, size_t& pixels_size,
                  char* errmsg, size_t errmsg_size);

void jpegls_free_buffers(uint8_t* template_bytes, uint8_t* pixels);

bool jpegls_serialize_recipe(const JlsFileInfo& info,
                             const uint8_t* template_bytes, size_t template_size,
                             uint8_t*& recipe_blob, size_t& recipe_size,
                             char* errmsg, size_t errmsg_size);

bool jpegls_deserialize_recipe(const uint8_t* data, size_t size,
                               JlsFileInfo& info,
                               uint8_t*& template_bytes, size_t& template_size,
                               char* errmsg, size_t errmsg_size);

bool jpegls_compress_jxl(const uint8_t* pixels, size_t pixels_size,
                         uint32_t width, uint32_t height,
                         uint8_t bits_per_sample, uint8_t component_count,
                         uint8_t*& jxl_blob, size_t& jxl_size,
                         char* errmsg, size_t errmsg_size);

bool jpegls_decompress_jxl(const uint8_t* jxl_blob, size_t jxl_size,
                           uint8_t*& pixels, size_t& pixels_size,
                           uint32_t& width, uint32_t& height,
                           uint8_t& bits_per_sample, uint8_t& component_count,
                           char* errmsg, size_t errmsg_size);

void jpegls_free_jxl_buffers(uint8_t* jxl_blob, uint8_t* pixels);

bool jpegls_reconstruct(const JlsFileInfo& info,
                        const uint8_t* template_bytes, size_t template_size,
                        const uint8_t* pixels, size_t pixels_size,
                        uint8_t*& output, size_t& output_size,
                        char* errmsg, size_t errmsg_size);

void jpegls_free_output(uint8_t* output);

#else // !HAVE_JPEGLS — no-op inline stubs

inline bool jpegls_detect(const uint8_t*, size_t) { return false; }

inline bool jpegls_parse(const uint8_t*, size_t,
                         JlsFileInfo&, uint8_t*&, size_t&,
                         uint8_t*&, size_t&, char*, size_t) { return false; }

inline void jpegls_free_buffers(uint8_t*, uint8_t*) {}

inline bool jpegls_serialize_recipe(const JlsFileInfo&, const uint8_t*, size_t,
                                    uint8_t*&, size_t&, char*, size_t) { return false; }

inline bool jpegls_deserialize_recipe(const uint8_t*, size_t,
                                      JlsFileInfo&, uint8_t*&, size_t&,
                                      char*, size_t) { return false; }

inline bool jpegls_compress_jxl(const uint8_t*, size_t,
                                uint32_t, uint32_t, uint8_t, uint8_t,
                                uint8_t*&, size_t&, char*, size_t) { return false; }

inline bool jpegls_decompress_jxl(const uint8_t*, size_t,
                                  uint8_t*&, size_t&,
                                  uint32_t&, uint32_t&,
                                  uint8_t&, uint8_t&,
                                  char*, size_t) { return false; }

inline void jpegls_free_jxl_buffers(uint8_t*, uint8_t*) {}

inline bool jpegls_reconstruct(const JlsFileInfo&,
                               const uint8_t*, size_t,
                               const uint8_t*, size_t,
                               uint8_t*&, size_t&, char*, size_t) { return false; }

inline void jpegls_free_output(uint8_t*) {}

#endif // HAVE_JPEGLS

#endif // PACKJPG_JPEGLS_H
