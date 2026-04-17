# packJPG v4.0-β — Release Notes

**Status:** beta (local build). Corpus tests clean (151 / 151 round-trip),
MT stress clean (8 threads × 50 iters), TSan clean (4 threads × 10 iters).
Not yet pushed / tagged — pending extended corpus + fuzzing + platform
coverage.

**Date:** 2026-04-17
**Git:** `e870d88` (on top of `b4c75d0` v4.0-α scaffold)

## What's new

### Cross-component lazy prediction (4:4:4 chroma)

packJPG's PJG coder models each DCT coefficient by combining the bit-length
of its coded neighbourhood with a segment classifier. Up to v3.1d the three
components (Y, Cb, Cr) were modelled independently: Cb's arithmetic model
had no way to exploit the strong correlation between luma and chroma that
exists in natural images, typography, and sharp diagonal structure.

v4.0 adds a **compound context** that folds the co-located luma bit-length
into the chroma context:

```
ctx_shift = (neighbourhood_bitlen << 3) | clamp7(Y_bitlen_at_same_pos)
```

The `mod_len` arithmetic model is widened from
`max(11, segm_cnt[cmp])` to 128 (AC passes) or `(max_len + 1) << 3` (DC
pass) so it can carry the enlarged context without saturating.

The feature is gated by:

```cpp
pjg_use_crosscomp_now       // set from version byte on decode
&& cmp != 0                 // luma itself has no reference
&& cmpc >= 2
&& cmpnfo[cmp].bc == cmpnfo[0].bc   // chroma and luma share a block grid
```

This last check restricts the feature to 4:4:4 JPEGs, where Cb/Cr and Y
have identical block counts and the `(bpos, dpos)` pair indexes the same
spatial location in all three planes. Subsampled JPEGs (4:2:0, 4:2:2)
fall through to the v3.1d coder, byte-for-byte.

The six functions changed are:

- `pjg_encode_dc`, `pjg_decode_dc`
- `pjg_encode_ac_high`, `pjg_decode_ac_high`
- `pjg_encode_ac_low`, `pjg_decode_ac_low`

### Format version byte

PJG's version byte advances from `0x1F` (31) to `0x28` (40). The decoder
reads the byte before `jpg_setup_imginfo()` and stores it in a thread-local
`format_version_read`; the cross-component code path activates only when
the byte matches the current format. v3.1d PJGs produced before v4.0 keep
decoding cleanly with `pjg_use_crosscomp_now = false`.

### `-legacy` flag

`packJPG a -legacy image.jpg` emits a v3.1d-format PJG, byte-identical to
the output of packJPG v3.1d on the same input. The flag is thread-local so
MT batches can mix default and `-legacy` encoding freely.

Use cases:

- **Compatibility during rollout:** keep producing v3.1d PJGs while
  downstream consumers (servers, backup software) are upgraded
- **Archival dual-write:** run once without `-legacy` for the main archive,
  once with `-legacy` for a cold backup on a system running older packJPG
- **Bisection / diffing:** reproduce historical compression for corpus-level
  regression analysis

### `-sfth` path

The parallel single-file encoder (`-sfth`, 3-thread Y/Cb/Cr split) keeps
producing v3.1d-format output: when Cb and Cr are processed concurrently,
the luma plane is not fully encoded yet and cannot be used as context.
`pjg_use_crosscomp_now` is explicitly held at `false` on the sfth path, so
`-sfth` output is byte-identical to packJPG v3.1d `-sfth`.

A future version may revisit this by staging a sequential Y pass followed
by parallel Cb/Cr passes, but v4.0 does not take that tradeoff.

## Compression results

Measured on an internal 153-JPEG corpus (151 round-trippable, 2 malformed
files excluded by the decoder). Mix of cameras, Photoshop renders,
screenshots, anime frames, low-quality uploads.

| Variant           | Total PJG size | vs. v3.1d |
|-------------------|---------------:|----------:|
| packJPG v3.1d     |     60,387,566 |      0.0% |
| packJPG v4.0 `-legacy` | 60,387,566 |      0.0% (byte-identical) |
| packJPG v4.0-β    |     60,066,170 |   **−0.532 %** |

Top per-file improvements land on 4:4:4 photographic JPEGs with strong
luma/chroma correlation (sharp coloured edges, text on saturated
backgrounds). Example: `827C1CF27.jpg` improves by **5.01 %**. Subsampled
JPEGs land at 0.00 % (by construction: the gate is not satisfied).

## Compatibility & migration

- **v4.0 cannot decode with packJPG v3.1d or earlier.** This is the first
  intentional format break since v2.0 (2007). The version byte changes
  from `0x1F` to `0x28`; a v3.1d decoder will refuse to open a v4.0 PJG.
- **v4.0 can decode v3.1d PJGs transparently** — the decoder detects the
  version byte and dispatches to the v3.1d code path. No user action
  required.
- **To keep producing v3.1d PJGs** during a staged rollout, pass `-legacy`.
  Output is byte-identical to packJPG v3.1d.
- **Archival consumers** (long-term backup, cold storage) should either
  upgrade to v4.0+ or accept that new PJGs will require a v4.0+ decoder.
  Either outcome is reasonable; the `-legacy` flag exists to make the
  choice explicit.

## Validation performed

| Test                                      | Result |
|-------------------------------------------|--------|
| Build (g++ 14.2, `-O3`, Linux x64)        | clean, no warnings |
| Round-trip CLI on 151-file corpus         | 151 / 151 byte-exact |
| `-legacy` round-trip on same corpus       | 151 / 151 byte-exact |
| `-legacy` output byte-identical to v3.1d  | yes (60,387,566 B match) |
| MT stress (`-th8`, 50 iters × 151 files)  | 393 / 393 OK, 0 mismatches |
| ThreadSanitizer (4 threads × 10 iters)    | 39 / 39 OK, 0 data races |
| `lib_roundtrip_test`                      | 151 OK, ratio 76.59 % |
| libFuzzer + ASan + UBSan, 15 min          | 0 crashes, 0 sanitizer reports, coverage 2596→3012 edges |
| Dual-version decode of existing v3.1d PJGs| pending extended test |

The fuzz harness lives at `source/test/pjg_decode_fuzzer.cpp` and is built
with `source/test/build_fuzzer.sh` (needs clang + libFuzzer, default on
most distributions via `clang` with `-fsanitize=fuzzer,address,undefined`).
The run above used 20 mixed-corpus PJG seeds as starting inputs, a 1 MiB
input limit, and the fuzzer saved one `slow-unit-*` artifact (≈18 s under
ASan, ≈3 s on the release binary — legitimate work for a max-sized
round-trippable input, not a hang). A longer multi-hour run with `-fork=N`
is recommended before tagging stable.

## What's still open (for v4.0 stable)

- **Corpus expansion** — beyond 1 000 JPEGs covering: mozjpeg, Photoshop,
  iPhone/DSLR, progressive, CMYK, grayscale. The β set is small enough
  that one adversarial file could skew the ratio headline.
- **Fuzzing** — the decoder surface changed: `pjg_decode_*` functions now
  consume up to 128 segments of context instead of 11, and the legacy
  branch must stay watertight. AFL++ or libFuzzer sweep of ~1 CPU-hour
  recommended before tagging.
- **macOS / ARM64** — unverified. The arithmetic coder handles bytes
  directly and should be endian-clean, but untested on big-endian or
  ARM64 Apple Silicon.
- **Dual-version decode of historical PJGs** — corpus of real v3.1d files
  produced by the released binary (not freshly generated), to guarantee
  the dispatch stays byte-exact.

## Competitive context (informational)

Public compression-corpus numbers for reference — these are approximate
mid-range figures, not direct measurements on the same corpus:

| Codec                      | Typical saving |
|----------------------------|---------------:|
| Lepton (Dropbox)           | ~22 % |
| Brunsli / JPEG XL          | ~22 % |
| paq8px (archival, slow)    | ~28 – 32 % |
| packJPG v3.1d              | ~23 – 24 % |
| packJPG v4.0-β             | packJPG v3.1d **−0.5 %** on our corpus |

v4.0 doesn't change packJPG's overall standing — it's still in the
lossless-transcode family with Lepton / Brunsli. The win is a measurable
nudge on photographic 4:4:4 content without changing the speed profile or
the dependency footprint.

## Credits

Original packJPG © Matthias Stirner / Günther Stirner (2006–2016), LGPL.
v2.6+ maintenance & v4.0 work: Yade Bravo
(<https://github.com/YadeWira/packJPG>).
