// jpegls.h — JPEG-LS lossless recompression handler for packJPG
//
// PackJPG recompresses classic JPEG by replacing Huffman/arithmetic entropy
// with its own arithmetic coder. JPEG-LS (SOF F7, ISO 14495) uses a
// different entropy scheme (LOCO-I predictor + Golomb-Rice coder) that is
// already near-optimal. The entropy itself has little redundancy left to
// exploit, so a different strategy is needed: decode to pixels, recompress
// the pixels with JPEG XL lossless (~16% smaller than the original), then
// on reconstruction regenerate the entropy bytes via CharLS.
//
// This byte-exact replay works because a default-parameter JPEG-LS scan
// (ILV=0, NEAR=0, default Golomb params) is fully deterministic: the
// entropy bytes are a pure function of the pixels + scan layout, with no
// encoder free choices. We verify this property before storing and refuse
// any scan that cannot be reproduced (interleaved, near-lossless, non-default
// coding parameters) rather than silently corrupting the output.
//
// Dependencies: libcharls (JPEG-LS codec), libjxl (JPEG XL codec).
// Only the C ABI interfaces are used — no C++ exceptions from either library.

#ifndef PACKJPG_JPEGLS_H
#define PACKJPG_JPEGLS_H

#include <cstdint>
#include <cstddef>

// --- public types -----------------------------------------------------------

struct JlsScanInfo {
    int      component_index;   // 0-based component this scan codes
    uint32_t entropy_start;     // byte offset in original file
    uint32_t entropy_end;       // byte offset after entropy
};

struct JlsFileInfo {
    uint16_t width;
    uint16_t height;
    uint8_t  bits_per_sample;
    uint8_t  component_count;

    // Template: the original file with entropy regions stripped.
    // The template is stored as num_scans+1 contiguous byte blobs.
    // Reconstruction: part[0] + encode(ch[0]) + part[1] + ... + part[N]
    // The template_parts vector holds all parts concatenated, with
    // part_offsets[] / part_lengths[] indexing into it.
    // first_scan_entropy_offset is recorded to allow the reconstruction
    // to reuse the original entropy when JLS reconstruction is triggered
    // by repacking (the encode step is skipped — the original bytes are
    // already present).

    // Scan channel assignments (one entry per scan)
    // These point into the planar pixel buffer: plane_sz = width*height
    // pixel for scan s at row r, col c is pixels[channel[s]*plane_sz + r*width + c]
    uint8_t  scan_count;
    uint8_t  channels[16];  // max 16 components (JPEG-LS limit is 255, practical << 16)

    // Template parts: num_scans + 1 blobs stored contiguously
    uint32_t part_count;
    uint32_t part_sizes[17]; // N+1 sizes (max 16 scans + 1 tail = 17)

    // Offset and length of each scan's entropy in the output (filled during reconstruction)
    uint32_t entropy_lengths[16]; // original entropy length for each scan
};

// --- JPEG-LS container parsing ---------------------------------------------

// Detect whether a buffer is a JPEG-LS file (has SOI + SOF F7 marker).
// Returns true if the buffer looks like JPEG-LS.
bool jpegls_detect(const uint8_t* data, size_t size);

// Parse a JPEG-LS file. On success:
//   - info is filled with scan metadata and template breakdown
//   - template_bytes receives the concatenated template parts
//   - pixels receives the planar pixel data (CharLS decode)
//   - Validates that every scan is byte-exact reproducible (ILV=0, NEAR=0).
//     Returns false (with errmsg) if a scan cannot be reproduced.
//   - The returned pixel buffer is planar: pixels[channel * width*height + ...]
//     for each channel assigned by info.channels[].
bool jpegls_parse(const uint8_t* data, size_t size,
                  JlsFileInfo& info,
                  uint8_t*& template_bytes, size_t& template_size,
                  uint8_t*& pixels, size_t& pixels_size,
                  char* errmsg, size_t errmsg_size);

// Free buffers returned by jpegls_parse (template_bytes and pixels).
void jpegls_free_buffers(uint8_t* template_bytes, uint8_t* pixels);

// --- PJG recipe serialization -----------------------------------------------

// Serialize the recipe (info + template_bytes) into a compact byte buffer
// suitable for storing as packJPG hdrdata.
// Format (all integers little-endian):
//   u8 version = 1
//   u8 scan_count
//   u8 component_count
//   u8 bits_per_sample
//   u16 width
//   u16 height
//   for each scan: u8 channel_index, u32 entropy_length
//   u32 total_template_size
//   u8[total_template_size] template parts (concatenated, same layout as parsing)
//
// The caller is responsible for freeing the returned buffer with free().
bool jpegls_serialize_recipe(const JlsFileInfo& info,
                             const uint8_t* template_bytes, size_t template_size,
                             uint8_t*& recipe_blob, size_t& recipe_size,
                             char* errmsg, size_t errmsg_size);

// Deserialize recipe from packJPG hdrdata into JlsFileInfo + template buffer.
// The template_bytes buffer is allocated and must be freed with free().
bool jpegls_deserialize_recipe(const uint8_t* data, size_t size,
                               JlsFileInfo& info,
                               uint8_t*& template_bytes, size_t& template_size,
                               char* errmsg, size_t errmsg_size);

// --- JXL pixel compression --------------------------------------------------

// Compress planar pixel data to a JPEG XL lossless blob.
// pixels: planar format (channel 0 plane, channel 1 plane, ...)
// The sRGB ICC profile is embedded as metadata; pixel values are preserved
// byte-exact regardless of actual color space.
bool jpegls_compress_jxl(const uint8_t* pixels, size_t pixels_size,
                         uint32_t width, uint32_t height,
                         uint8_t bits_per_sample, uint8_t component_count,
                         uint8_t*& jxl_blob, size_t& jxl_size,
                         char* errmsg, size_t errmsg_size);

// Decompress a JPEG XL blob to planar pixel data.
// jxl_blob/jxl_size are caller-owned and freed by the caller.
bool jpegls_decompress_jxl(const uint8_t* jxl_blob, size_t jxl_size,
                           uint8_t*& pixels, size_t& pixels_size,
                           uint32_t& width, uint32_t& height,
                           uint8_t& bits_per_sample, uint8_t& component_count,
                           char* errmsg, size_t errmsg_size);

// Free buffers returned by compress/decompress functions.
void jpegls_free_jxl_buffers(uint8_t* jxl_blob, uint8_t* pixels);

// --- JPEG-LS reconstruction -------------------------------------------------

// Reconstruct a JPEG-LS file from template + pixels.
// For each scan in info, re-encodes the corresponding component plane
// via CharLS and splices the entropy between template parts.
// The output is byte-identical to the original if the scan params are
// default (ILV=0, NEAR=0).
bool jpegls_reconstruct(const JlsFileInfo& info,
                        const uint8_t* template_bytes, size_t template_size,
                        const uint8_t* pixels, size_t pixels_size,
                        uint8_t*& output, size_t& output_size,
                        char* errmsg, size_t errmsg_size);

// Free reconstruction output buffer.
void jpegls_free_output(uint8_t* output);

#endif // PACKJPG_JPEGLS_H
