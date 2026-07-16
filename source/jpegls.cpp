// jpegls.cpp — JPEG-LS lossless recompression handler for packJPG
//
// See jpegls.h for high-level design.

#ifdef HAVE_JPEGLS
#include "jpegls.h"

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <vector>

#include <charls/charls.h>
#include <jxl/encode.h>
#include <jxl/decode.h>
#include <jxl/thread_parallel_runner.h>

// ---------------------------------------------------------------------------
// internal helpers
// ---------------------------------------------------------------------------

static constexpr charls_interleave_mode ILV_NONE = static_cast<charls_interleave_mode>(0);

#define JLS_CHECK(expr, msg, errmsg, errmsg_size) do { \
    charls_jpegls_errc e_ = (expr); \
    if (e_ != charls_jpegls_errc::success) { \
        snprintf(errmsg, errmsg_size, "JPEG-LS: %s (errc %d)", msg, (int)e_); \
        return false; \
    } \
} while(0)

// sRGB ICC profile — required by JXL v0.11+ for lossless encoding.
// Contains only metadata; pixel values pass through byte-exact.
static const uint8_t SRGB_ICC[] = {
#include "srgb_icc.inc"
};
static constexpr size_t SRGB_ICC_LEN = sizeof(SRGB_ICC);

// Planar → interleaved: [P0][P1][P2] → [R0G0B0][R1G1B1]...
static void planar_to_interleaved(const uint8_t* planar, uint8_t* interleaved,
                                   size_t plane_sz, int comps) {
    for (size_t i = 0; i < plane_sz; i++)
        for (int c = 0; c < comps; c++)
            interleaved[i * comps + c] = planar[c * plane_sz + i];
}

// Interleaved → planar
static void interleaved_to_planar(const uint8_t* interleaved, uint8_t* planar,
                                   size_t plane_sz, int comps) {
    for (size_t i = 0; i < plane_sz; i++)
        for (int c = 0; c < comps; c++)
            planar[c * plane_sz + i] = interleaved[i * comps + c];
}

// ---------------------------------------------------------------------------
// JPEG-LS detection
// ---------------------------------------------------------------------------

bool jpegls_detect(const uint8_t* data, size_t size) {
    if (size < 4) return false;
    if (data[0] != 0xFF || data[1] != 0xD8) return false; // SOI
    for (size_t i = 2; i + 1 < size && i < 4096; i++)
        if (data[i] == 0xFF && data[i+1] == 0xF7)
            return true;
    return false;
}

// ---------------------------------------------------------------------------
// JPEG-LS parsing
// ---------------------------------------------------------------------------

bool jpegls_parse(const uint8_t* data, size_t size,
                  JlsFileInfo& info,
                  uint8_t*& template_bytes, size_t& template_size,
                  uint8_t*& pixels, size_t& pixels_size,
                  char* errmsg, size_t errmsg_size) {
    template_bytes = nullptr; template_size = 0;
    pixels = nullptr; pixels_size = 0;
    memset(&info, 0, sizeof(info));

    // --- 1. CharLS decode ---
    charls_jpegls_decoder* dec = charls_jpegls_decoder_create();
    if (!dec) {
        snprintf(errmsg, errmsg_size, "JPEG-LS: failed to create CharLS decoder");
        return false;
    }

    JLS_CHECK(charls_jpegls_decoder_set_source_buffer(dec, data, size),
              "set source buffer", errmsg, errmsg_size);
    JLS_CHECK(charls_jpegls_decoder_read_header(dec),
              "read header", errmsg, errmsg_size);

    charls_frame_info fi;
    JLS_CHECK(charls_jpegls_decoder_get_frame_info(dec, &fi),
              "get frame info", errmsg, errmsg_size);

    info.width = fi.width; info.height = fi.height;
    info.bits_per_sample = fi.bits_per_sample;
    info.component_count = fi.component_count;

    if (info.component_count > 16) {
        snprintf(errmsg, errmsg_size, "JPEG-LS: too many components (%d > 16)", info.component_count);
        charls_jpegls_decoder_destroy(dec); return false;
    }

    int32_t near_lossless;
    JLS_CHECK(charls_jpegls_decoder_get_near_lossless(dec, 0, &near_lossless),
              "get NEAR", errmsg, errmsg_size);
    charls_interleave_mode ilv;
    JLS_CHECK(charls_jpegls_decoder_get_interleave_mode(dec, &ilv),
              "get ILV", errmsg, errmsg_size);

    if (near_lossless != 0) {
        snprintf(errmsg, errmsg_size,
                 "JPEG-LS: near-lossless (NEAR=%d) not supported", (int)near_lossless);
        charls_jpegls_decoder_destroy(dec); return false;
    }
    if (ilv != ILV_NONE) {
        snprintf(errmsg, errmsg_size,
                 "JPEG-LS: interleaved scan (ILV=%d) not supported", (int)ilv);
        charls_jpegls_decoder_destroy(dec); return false;
    }

    size_t dest_sz;
    JLS_CHECK(charls_jpegls_decoder_get_destination_size(dec, 0, &dest_sz),
              "get dest size", errmsg, errmsg_size);
    std::vector<uint8_t> planar(dest_sz);
    JLS_CHECK(charls_jpegls_decoder_decode_to_buffer(dec, planar.data(), dest_sz, 0),
              "decode", errmsg, errmsg_size);
    charls_jpegls_decoder_destroy(dec);

    size_t plane_sz = (size_t)info.width * info.height;

    // --- 2. Parse container for SOS markers and entropy regions ---
    struct RawScan {
        size_t sos_offset, header_len, ent_start, ent_end;
        int comp_id;
    };
    std::vector<RawScan> raw_scans;

    size_t pos = 0;
    while (pos + 1 < size) {
        if (data[pos] == 0xFF && data[pos+1] == 0xDA) {
            RawScan rs;
            rs.sos_offset = pos;
            rs.header_len = 2 + ((data[pos+2] << 8) | data[pos+3]);
            rs.ent_start = pos + rs.header_len;

            const uint8_t* body = data + pos + 4;
            int Ns = body[0];
            if (Ns != 1) { pos += rs.header_len; continue; } // only single-comp scans
            rs.comp_id = body[1];

            size_t j = rs.ent_start;
            while (j + 1 < size) {
                if (data[j] == 0xFF && data[j+1] != 0x00) {
                    if (data[j+1] >= 0x80 && !(0xD0 <= data[j+1] && data[j+1] <= 0xD7)) {
                        rs.ent_end = j; break;
                    }
                }
                j++;
            }
            if (rs.ent_end <= rs.ent_start) {
                rs.ent_end = size;
                if (rs.ent_end >= 2 && data[rs.ent_end-2] == 0xFF && data[rs.ent_end-1] == 0xD9)
                    rs.ent_end -= 2;
            }
            raw_scans.push_back(rs);
            pos += rs.header_len;
            continue;
        }
        pos++;
    }

    if (raw_scans.empty()) {
        snprintf(errmsg, errmsg_size, "JPEG-LS: no SOS markers found");
        return false;
    }
    if (raw_scans.size() > 16) {
        snprintf(errmsg, errmsg_size, "JPEG-LS: too many scans (%zu > 16)", raw_scans.size());
        return false;
    }

    // --- 3. Parse SOF55 for component ID → plane index mapping ---
    int comp_id_to_plane[256];
    memset(comp_id_to_plane, -1, sizeof(comp_id_to_plane));

    for (size_t i = 2; i + 10 < size && i < 4096; i++) {
        if (data[i] == 0xFF && data[i+1] == 0xF7) {
            int Nf = data[i+9];
            for (int c = 0; c < Nf && c < 16; c++)
                comp_id_to_plane[data[i+10 + 3*c]] = c;
            break;
        }
    }

    // --- 4. Populate scan info ---
    info.scan_count = (uint8_t)raw_scans.size();
    for (size_t s = 0; s < raw_scans.size(); s++) {
        int plane_idx = comp_id_to_plane[raw_scans[s].comp_id];
        if (plane_idx < 0) {
            snprintf(errmsg, errmsg_size,
                     "JPEG-LS: SOS component ID %d not found in SOF", raw_scans[s].comp_id);
            return false;
        }
        info.channels[s] = (uint8_t)plane_idx;
        info.entropy_lengths[s] = (uint32_t)(raw_scans[s].ent_end - raw_scans[s].ent_start);
    }

    // --- 5. Build template parts ---
    info.part_count = info.scan_count + 1;

    // Part 0: before first entropy
    info.part_sizes[0] = (uint32_t)(raw_scans[0].ent_start);
    // Parts 1..N-1: between entropy end of scan k-1 and entropy start of scan k
    for (int s = 1; s < info.scan_count; s++)
        info.part_sizes[s] = (uint32_t)(raw_scans[s].ent_start - raw_scans[s-1].ent_end);
    // Part N: after last entropy
    info.part_sizes[info.scan_count] = (uint32_t)(size - raw_scans.back().ent_end);

    template_size = 0;
    for (int p = 0; p < info.part_count; p++)
        template_size += info.part_sizes[p];

    template_bytes = (uint8_t*)malloc(template_size);
    if (!template_bytes) {
        snprintf(errmsg, errmsg_size, "JPEG-LS: out of memory for template (%zu B)", template_size);
        return false;
    }
    uint8_t* outp = template_bytes;
    // Part 0
    memcpy(outp, data, info.part_sizes[0]); outp += info.part_sizes[0];
    // Parts 1..N-1
    for (int s = 1; s < info.scan_count; s++) {
        memcpy(outp, data + raw_scans[s-1].ent_end, info.part_sizes[s]);
        outp += info.part_sizes[s];
    }
    // Part N
    memcpy(outp, data + raw_scans.back().ent_end, info.part_sizes[info.scan_count]);

    // --- 6. Verify byte-exact reproducibility ---
    for (int s = 0; s < info.scan_count; s++) {
        int ch = info.channels[s];
        size_t orig_len = info.entropy_lengths[s];

        charls_jpegls_encoder* enc = charls_jpegls_encoder_create();
        charls_frame_info fi_one = {info.width, info.height, info.bits_per_sample, 1};
        JLS_CHECK(charls_jpegls_encoder_set_frame_info(enc, &fi_one),
                  "verify: frame info", errmsg, errmsg_size);
        JLS_CHECK(charls_jpegls_encoder_set_near_lossless(enc, 0),
                  "verify: NEAR", errmsg, errmsg_size);
        JLS_CHECK(charls_jpegls_encoder_set_interleave_mode(enc, ILV_NONE),
                  "verify: ILV", errmsg, errmsg_size);

        size_t est;
        JLS_CHECK(charls_jpegls_encoder_get_estimated_destination_size(enc, &est),
                  "verify: est size", errmsg, errmsg_size);
        std::vector<uint8_t> re_enc(est);
        JLS_CHECK(charls_jpegls_encoder_set_destination_buffer(enc, re_enc.data(), est),
                  "verify: dest buffer", errmsg, errmsg_size);

        const uint8_t* plane = planar.data() + (size_t)ch * plane_sz;
        JLS_CHECK(charls_jpegls_encoder_encode_from_buffer(enc, plane, plane_sz, 0),
                  "verify: encode", errmsg, errmsg_size);

        size_t re_total;
        JLS_CHECK(charls_jpegls_encoder_get_bytes_written(enc, &re_total),
                  "verify: bytes written", errmsg, errmsg_size);
        charls_jpegls_encoder_destroy(enc);

        // Extract entropy from re-encode
        size_t rs = 0;
        while (rs + 1 < re_total && !(re_enc[rs] == 0xFF && re_enc[rs+1] == 0xDA)) rs++;
        if (rs + 1 >= re_total) {
            snprintf(errmsg, errmsg_size, "JPEG-LS: no SOS in re-encode (scan %d)", s);
            free(template_bytes); template_bytes = nullptr; return false;
        }
        size_t rhl = 2 + ((re_enc[rs+2] << 8) | re_enc[rs+3]);
        size_t re_start = rs + rhl;
        size_t re_len = re_total - re_start;
        if (re_len >= 2 && re_enc[re_total-2] == 0xFF && re_enc[re_total-1] == 0xD9)
            re_len -= 2;

        const uint8_t* orig_ent = data + raw_scans[s].ent_start;
        if (orig_len != re_len || memcmp(orig_ent, re_enc.data() + re_start, orig_len) != 0) {
            snprintf(errmsg, errmsg_size,
                     "JPEG-LS: scan %d entropy mismatch (orig %zu B, re %zu B) — "
                     "non-default coding parameters likely", s, orig_len, re_len);
            free(template_bytes); template_bytes = nullptr; return false;
        }
    }

    // --- 7. Return pixels (planar) ---
    pixels_size = dest_sz;
    pixels = (uint8_t*)malloc(dest_sz);
    if (!pixels) {
        snprintf(errmsg, errmsg_size, "JPEG-LS: OOM for pixels (%zu B)", dest_sz);
        free(template_bytes); template_bytes = nullptr; return false;
    }
    memcpy(pixels, planar.data(), dest_sz);
    return true;
}

void jpegls_free_buffers(uint8_t* template_bytes, uint8_t* pixels) {
    free(template_bytes);
    free(pixels);
}

// ---------------------------------------------------------------------------
// Recipe serialization
// ---------------------------------------------------------------------------

bool jpegls_serialize_recipe(const JlsFileInfo& info,
                             const uint8_t* template_bytes, size_t template_size,
                             uint8_t*& recipe_blob, size_t& recipe_size,
                             char* errmsg, size_t errmsg_size) {
    recipe_blob = nullptr; recipe_size = 0;

    // Format: version(1) + scan_count(1) + comp_count(1) + bps(1) +
    //         width(2) + height(2) +
    //         per_scan[channel(1) + entropy_len(4)] +
    //         per_part[part_size(4)] +
    //         template_data(template_size)
    size_t hdr = 8;
    size_t per_scan = (size_t)info.scan_count * 5;
    size_t per_part = (size_t)info.part_count * 4;
    recipe_size = hdr + per_scan + per_part + template_size;

    recipe_blob = (uint8_t*)malloc(recipe_size);
    if (!recipe_blob) {
        snprintf(errmsg, errmsg_size, "JPEG-LS: OOM for recipe (%zu B)", recipe_size);
        return false;
    }

    uint8_t* p = recipe_blob;
    *p++ = 1;  // version
    *p++ = info.scan_count;
    *p++ = info.component_count;
    *p++ = info.bits_per_sample;
    p[0] = info.width & 0xFF;  p[1] = (info.width >> 8) & 0xFF;  p += 2;
    p[0] = info.height & 0xFF; p[1] = (info.height >> 8) & 0xFF; p += 2;

    for (int s = 0; s < info.scan_count; s++) {
        *p++ = info.channels[s];
        uint32_t el = info.entropy_lengths[s];
        p[0] = el & 0xFF; p[1] = (el >> 8) & 0xFF;
        p[2] = (el >> 16) & 0xFF; p[3] = (el >> 24) & 0xFF;
        p += 4;
    }

    for (int i = 0; i < info.part_count; i++) {
        uint32_t ps = info.part_sizes[i];
        p[0] = ps & 0xFF; p[1] = (ps >> 8) & 0xFF;
        p[2] = (ps >> 16) & 0xFF; p[3] = (ps >> 24) & 0xFF;
        p += 4;
    }

    memcpy(p, template_bytes, template_size);
    return true;
}

bool jpegls_deserialize_recipe(const uint8_t* data, size_t size,
                               JlsFileInfo& info,
                               uint8_t*& template_bytes, size_t& template_size,
                               char* errmsg, size_t errmsg_size) {
    template_bytes = nullptr; template_size = 0;
    memset(&info, 0, sizeof(info));

    if (size < 8) {
        snprintf(errmsg, errmsg_size, "JPEG-LS recipe: too small (%zu < 8)", size); return false;
    }

    const uint8_t* p = data;
    uint8_t version = *p++;
    if (version != 1) {
        snprintf(errmsg, errmsg_size, "JPEG-LS recipe: version %d unsupported", version); return false;
    }

    info.scan_count      = *p++;
    info.component_count = *p++;
    info.bits_per_sample = *p++;
    info.width  = p[0] | (p[1] << 8); p += 2;
    info.height = p[0] | (p[1] << 8); p += 2;

    if (info.scan_count > 16 || info.component_count > 16) {
        snprintf(errmsg, errmsg_size, "JPEG-LS recipe: scan(%d)/comp(%d) > 16",
                 info.scan_count, info.component_count); return false;
    }
    info.part_count = info.scan_count + 1;

    // Per-scan
    size_t needed = (size_t)(p - data) + (size_t)info.scan_count * 5;
    if (needed > size) {
        snprintf(errmsg, errmsg_size, "JPEG-LS recipe: truncated at scans"); return false;
    }
    for (int s = 0; s < info.scan_count; s++) {
        info.channels[s] = *p++;
        info.entropy_lengths[s] = p[0] | (p[1] << 8) | (p[2] << 16) | (p[3] << 24);
        p += 4;
    }

    // Part sizes
    needed = (size_t)(p - data) + (size_t)info.part_count * 4;
    if (needed > size) {
        snprintf(errmsg, errmsg_size, "JPEG-LS recipe: truncated at part sizes"); return false;
    }
    for (int i = 0; i < info.part_count; i++) {
        info.part_sizes[i] = p[0] | (p[1] << 8) | (p[2] << 16) | (p[3] << 24);
        p += 4;
    }

    // Template data
    size_t tpl_off = (size_t)(p - data);
    template_size = size - tpl_off;
    template_bytes = (uint8_t*)malloc(template_size);
    if (!template_bytes) {
        snprintf(errmsg, errmsg_size, "JPEG-LS: OOM for template (%zu B)", template_size); return false;
    }
    memcpy(template_bytes, p, template_size);
    return true;
}

// ---------------------------------------------------------------------------
// JXL pixel compression
// ---------------------------------------------------------------------------

bool jpegls_compress_jxl(const uint8_t* pixels, size_t pixels_size,
                         uint32_t width, uint32_t height,
                         uint8_t bits_per_sample, uint8_t component_count,
                         uint8_t*& jxl_blob, size_t& jxl_size,
                         char* errmsg, size_t errmsg_size) {
    jxl_blob = nullptr; jxl_size = 0;

    void* runner = JxlThreadParallelRunnerCreate(NULL,
        JxlThreadParallelRunnerDefaultNumWorkerThreads());
    if (!runner) { snprintf(errmsg, errmsg_size, "JXL: thread runner"); return false; }

    JxlEncoder* enc = JxlEncoderCreate(NULL);
    if (!enc) { JxlThreadParallelRunnerDestroy(runner);
        snprintf(errmsg, errmsg_size, "JXL: encoder"); return false; }

    JxlEncoderSetParallelRunner(enc, JxlThreadParallelRunner, runner);

    JxlBasicInfo bi;
    JxlEncoderInitBasicInfo(&bi);
    bi.xsize = width; bi.ysize = height;
    bi.bits_per_sample = bits_per_sample;
    bi.num_color_channels = component_count;
    bi.uses_original_profile = JXL_TRUE;

    if (JxlEncoderSetBasicInfo(enc, &bi) != JXL_ENC_SUCCESS ||
        JxlEncoderSetICCProfile(enc, SRGB_ICC, SRGB_ICC_LEN) != JXL_ENC_SUCCESS) {
        JxlEncoderDestroy(enc); JxlThreadParallelRunnerDestroy(runner);
        snprintf(errmsg, errmsg_size, "JXL: setup"); return false;
    }

    JxlEncoderFrameSettings* fs = JxlEncoderFrameSettingsCreate(enc, NULL);
    JxlEncoderSetFrameLossless(fs, JXL_TRUE);
    JxlEncoderFrameSettingsSetOption(fs, JXL_ENC_FRAME_SETTING_EFFORT, 9);

    // Interleave planar → interleaved
    size_t plane_sz = (size_t)width * height;
    std::vector<uint8_t> interleaved(pixels_size);
    planar_to_interleaved(pixels, interleaved.data(), plane_sz, component_count);

    JxlPixelFormat pf = {(uint32_t)component_count, JXL_TYPE_UINT8, JXL_NATIVE_ENDIAN, 1};
    if (JxlEncoderAddImageFrame(fs, &pf, interleaved.data(), interleaved.size()) != JXL_ENC_SUCCESS) {
        JxlEncoderDestroy(enc); JxlThreadParallelRunnerDestroy(runner);
        snprintf(errmsg, errmsg_size, "JXL: add frame"); return false;
    }
    JxlEncoderCloseInput(enc);

    std::vector<uint8_t> out(interleaved.size() / 4 + 4096);
    uint8_t* nxt = out.data(); size_t avl = out.size();
    while (JxlEncoderProcessOutput(enc, &nxt, &avl) == JXL_ENC_NEED_MORE_OUTPUT) {
        size_t off = nxt - out.data();
        out.resize(out.size() * 2);
        nxt = out.data() + off; avl = out.size() - off;
    }
    out.resize(nxt - out.data());
    JxlEncoderDestroy(enc); JxlThreadParallelRunnerDestroy(runner);

    jxl_size = out.size();
    jxl_blob = (uint8_t*)malloc(jxl_size);
    if (!jxl_blob) { snprintf(errmsg, errmsg_size, "JXL: OOM (%zu B)", jxl_size); return false; }
    memcpy(jxl_blob, out.data(), jxl_size);
    return true;
}

bool jpegls_decompress_jxl(const uint8_t* jxl_blob, size_t jxl_size,
                           uint8_t*& pixels, size_t& pixels_size,
                           uint32_t& width, uint32_t& height,
                           uint8_t& bits_per_sample, uint8_t& component_count,
                           char* errmsg, size_t errmsg_size) {
    pixels = nullptr; pixels_size = 0;

    JxlDecoder* dec = JxlDecoderCreate(NULL);
    JxlDecoderSubscribeEvents(dec, JXL_DEC_BASIC_INFO | JXL_DEC_FULL_IMAGE);
    JxlDecoderSetInput(dec, jxl_blob, jxl_size);
    JxlDecoderCloseInput(dec);

    JxlBasicInfo bi; memset(&bi, 0, sizeof(bi));
    std::vector<uint8_t> interleaved;

    for (;;) {
        JxlDecoderStatus ds = JxlDecoderProcessInput(dec);
        if (ds == JXL_DEC_ERROR) { JxlDecoderDestroy(dec);
            snprintf(errmsg, errmsg_size, "JXL: decode error"); return false; }
        if (ds == JXL_DEC_SUCCESS) break;
        if (ds == JXL_DEC_BASIC_INFO)
            JxlDecoderGetBasicInfo(dec, &bi);
        if (ds == JXL_DEC_NEED_IMAGE_OUT_BUFFER && bi.num_color_channels > 0) {
            JxlPixelFormat pf = {(uint32_t)bi.num_color_channels, JXL_TYPE_UINT8, JXL_NATIVE_ENDIAN, 1};
            size_t buf_sz;
            JxlDecoderImageOutBufferSize(dec, &pf, &buf_sz);
            interleaved.resize(buf_sz);
            JxlDecoderSetImageOutBuffer(dec, &pf, interleaved.data(), buf_sz);
        }
    }
    JxlDecoderDestroy(dec);

    width = bi.xsize; height = bi.ysize;
    bits_per_sample = bi.bits_per_sample;
    component_count = bi.num_color_channels;

    // Deinterleave → planar
    size_t plane_sz = (size_t)width * height;
    pixels_size = plane_sz * component_count;
    pixels = (uint8_t*)malloc(pixels_size);
    if (!pixels) { snprintf(errmsg, errmsg_size, "JXL: OOM pixels (%zu B)", pixels_size); return false; }
    interleaved_to_planar(interleaved.data(), pixels, plane_sz, component_count);
    return true;
}

void jpegls_free_jxl_buffers(uint8_t* jxl_blob, uint8_t* pixels) {
    free(jxl_blob); free(pixels);
}

// ---------------------------------------------------------------------------
// JPEG-LS reconstruction — template + regenerated entropy → .jls file
// ---------------------------------------------------------------------------

bool jpegls_reconstruct(const JlsFileInfo& info,
                        const uint8_t* template_bytes, size_t template_size,
                        const uint8_t* pixels, size_t pixels_size,
                        uint8_t*& output, size_t& output_size,
                        char* errmsg, size_t errmsg_size) {
    output = nullptr; output_size = 0;
    size_t plane_sz = (size_t)info.width * info.height;

    // Total output = template parts + regenerated entropy
    size_t total = 0;
    for (int i = 0; i < info.part_count; i++) total += info.part_sizes[i];
    for (int s = 0; s < info.scan_count; s++) total += info.entropy_lengths[s];

    output = (uint8_t*)malloc(total);
    if (!output) {
        snprintf(errmsg, errmsg_size, "JPEG-LS: OOM for output (%zu B)", total); return false;
    }

    const uint8_t* tpl = template_bytes;
    uint8_t* out = output;

    for (int s = 0; s < info.scan_count; s++) {
        // Write template part before this scan
        if (info.part_sizes[s] > 0) {
            memcpy(out, tpl, info.part_sizes[s]);
            out += info.part_sizes[s];
            tpl += info.part_sizes[s];
        }

        // Re-encode component plane via CharLS
        int ch = info.channels[s];
        charls_jpegls_encoder* enc = charls_jpegls_encoder_create();
        charls_frame_info fi_one = {info.width, info.height, info.bits_per_sample, 1};
        charls_jpegls_encoder_set_frame_info(enc, &fi_one);
        charls_jpegls_encoder_set_near_lossless(enc, 0);
        charls_jpegls_encoder_set_interleave_mode(enc, ILV_NONE);

        size_t est;
        charls_jpegls_encoder_get_estimated_destination_size(enc, &est);
        std::vector<uint8_t> re_enc(est);
        charls_jpegls_encoder_set_destination_buffer(enc, re_enc.data(), est);

        const uint8_t* plane = pixels + (size_t)ch * plane_sz;
        charls_jpegls_errc e = charls_jpegls_encoder_encode_from_buffer(enc, plane, plane_sz, 0);
        size_t re_total;
        charls_jpegls_encoder_get_bytes_written(enc, &re_total);
        charls_jpegls_encoder_destroy(enc);

        if (e != charls_jpegls_errc::success) {
            snprintf(errmsg, errmsg_size,
                     "JPEG-LS: CharLS re-encode failed for scan %d (errc %d)", s, (int)e);
            free(output); output = nullptr; return false;
        }

        // Extract entropy from re-encode
        size_t rs = 0;
        while (rs + 1 < re_total && !(re_enc[rs] == 0xFF && re_enc[rs+1] == 0xDA)) rs++;
        size_t rhl = 2 + ((re_enc[rs+2] << 8) | re_enc[rs+3]);
        size_t re_start = rs + rhl;
        size_t re_len = re_total - re_start;
        if (re_len >= 2 && re_enc[re_total-2] == 0xFF && re_enc[re_total-1] == 0xD9)
            re_len -= 2;

        if (re_len != info.entropy_lengths[s]) {
            snprintf(errmsg, errmsg_size,
                     "JPEG-LS: entropy length mismatch scan %d (got %zu, expected %u)",
                     s, re_len, info.entropy_lengths[s]);
            free(output); output = nullptr; return false;
        }
        memcpy(out, re_enc.data() + re_start, re_len);
        out += re_len;
    }

    // Write final template part (tail)
    if (info.part_sizes[info.scan_count] > 0) {
        memcpy(out, tpl, info.part_sizes[info.scan_count]);
    }

    output_size = total;
    return true;
}

void jpegls_free_output(uint8_t* output) {
    free(output);
}

#endif // HAVE_JPEGLS
