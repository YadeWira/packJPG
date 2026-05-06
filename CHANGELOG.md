# packJPG Changelog

## v4.0d (2026-05-06) — LTS speed-polish release

> v4.0d is the final feature release of the v4.0.x line. After this,
> packJPG enters long-term support: bug fixes only, no new features.
> Format is identical to v4.0c — `.pjg` output is byte-exact, full
> backward compatibility with all v4.0/4.0a/4.0b/4.0c streams.
>
> Three speed wins, all ratio-neutral:
>
> 1. **Link-Time Optimization** — `-flto` added to default build flags.
>    Cross-translation-unit inlining of small accessors. ~3% encode
>    and decode speedup with no source changes.
>
> 2. **Branch hints** on the arithmetic-coder hot path. New `PJG_LIKELY`
>    / `PJG_UNLIKELY` macros (gcc/clang `__builtin_expect`, MSVC fallback)
>    annotate the non-escape branch in `convert_int_to_symbol` and the
>    escape branch in `convert_symbol_to_int`. ~2-3% additional speedup.
>
> 3. **New `make pgo` target** — two-phase profile-guided build:
>    Phase 1 compiles with `-fprofile-generate`, runs an encode + decode
>    workload, and emits `.gcda` profile data. Phase 2 rebuilds with
>    `-fprofile-use` linking the profile. Override `PGO_WORKLOAD` to
>    point at a richer corpus. Default workload is `../test-files`.
>
> 4. **New `make native` target** — adds `-march=native -mtune=native`
>    for max-performance binaries built from source. Distribution
>    releases stay portable.
>
> Benchmark on a 8.59 MB / 20-file JPEG corpus (mean of 5 runs each):
>
> | Build                              | Encode    | Decode    | Ratio Δ |
> |------------------------------------|-----------|-----------|---------|
> | v4.0c (baseline)                   |  5.26 s   |  5.04 s   |  0 (ref)|
> | v4.0d default (LTO + branch hints) |  4.93 s   |  4.83 s   |  0 ✓    |
> | v4.0d `make pgo` (balanced)        |  4.50 s   |  4.44 s   |  0 ✓    |
>
> Default: -6.3% encode / -4.2% decode, no rebuild ceremony required.
> PGO: -14.4% encode / -11.9% decode, two-phase make.
>
> All variants roundtrip-verified bit-exact 20/20 vs v4.0c.
>
> **Why packJPG is now in LTS / maintenance mode:** ratio plateau
> confirmed empirically by five measurements — SITX-style 2-way DC
> ensemble, SITX-style 2-way AC bpos ensemble (4 weight variants),
> pre-trained PPM priors (3 strength variants). All lost ratio vs v4.0c.
> External comparisons confirm packJPG sits on the Pareto frontier:
> Brunsli is faster but loses 1-2% ratio; Lepton matches packJPG
> (NSDI '17); JXL `--lossless_jpeg` trails packJPG by 4.3% on tested
> corpora. Future releases will be bug fixes and platform support only.

## v4.0c (2026-04-27) — `-fs` flag for folder structure preservation

> Adds the `-fs` flag, which when combined with `-r` and `-od` mirrors
> the source directory structure under the output directory (caesium-clt
> `-RS` semantics). Format unchanged from v4.0b.

## v4.0b (2026-04-27) — format simplification + diagonal DC neighbor context

> v4.0b is the new starting point of the post-v4.0 lineage. It collapses
> the three-format dispatch (v4.0 + v4.0a + v3.1d-via-legacy) into a single
> accepted version byte (`0x28` / 40) plus an optional sub-marker (`0x02`)
> that flags the new diagonal DC neighbor context. The `-legacy` flag is
> removed; v3.1d archives are no longer decoded by this build.
>
> **Versioning policy** (new): `N.0x` releases (4.0, 4.0a, 4.0b, …) are
> LTS-style with binary filename `packJPG`, bug-fix only after their
> initial drop. `N.Mx` releases (4.1, 4.1a, 4.2, …) are feature-bearing
> with binary filename `packJPG-N.Mx`, format breaks land here. v4.0b is
> a one-time exception — it carries the diagonal DC change that was
> originally tagged v4.1 (never released publicly), rebranded so the v4.1
> slot stays available for a real feature drop.
>
> The diagonal DC change adds a 4-bucket variance context computed from
> `|L − T| + |T − TR|` (absolute values of the already-encoded left, top
> and top-right DC neighbors). It captures directional gradient patterns
> that the existing weighted-average context blends away. Result: a small
> but consistent ratio win at neutral wall time.
>
> Inspired by the SITX (StuffIt JPEG) reverse-engineered codebase shared
> by Melirius on encode.su. SITX dequant achieves ~5 % better than
> packJPG via ensemble-blended context models (4 parallel histograms with
> weights 8/6/4/2); packJPG's single-context arith coder can't replicate
> that without a major refactor. Of three SITX-inspired ideas tested
> (diagonal context, multi-resolution variance, zigzag-position AC priors)
> only the diagonal context paid off — multi-resolution variance
> correlated too tightly with the existing `ctx_len`, and zigzag AC priors
> spread statistics too thin across the well-tuned AC bit-length model.

### Format

- new: **0x02 sub-marker** before the version byte (`0x28`) signals
  v4.0b features. Decoder semantics:
  - `JS 28 …`     → v4.0 / v4.0a file, `pjg_use_diag_dc_now = false`
    (old DC context, full backward-compat decode of legacy archives)
  - `JS 02 28 …`  → v4.0b file, `pjg_use_diag_dc_now = true`
    (new diagonal DC context active)
  - v4.0 / v4.0a binaries reading a v4.0b file see `0x02`, fall through
    to "unknown header code" → clean error, no silent corruption.
- removed: `-legacy` CLI flag and `format_version_legacy = 31` /
  `format_version_v40_compat = 40` constants. Single accepted format byte.
- removed: `legacy_mode` THREAD_LOCAL global and its MT-worker propagation.

### Encoder / decoder

- new: **diagonal/anti-diagonal DC neighbor context** in `pjg_encode_dc`
  and `pjg_decode_dc`. 4 buckets from `|L − T| + |T − TR|` of the
  absolute-value neighbors, multiplying `mod_len_maxc` by 4 (or 32 when
  stacked with cross-component). Gated by `pjg_use_diag_dc_now`.
- the v4.0a cross-component DC prediction stays on permanently in the
  sequential encode/decode path. Sfth workers keep it off (no Y available
  during parallel Cb/Cr encoding) — unchanged from v4.0.

### Repository

- renamed `source4xp/` → `sourcelegacy/` and `build4xp.sh` → `build_legacy.sh`
  (Win XP/Win7/Win8 community-maintained port now lives here; documents
  the boundary explicitly: `source/` targets Win10+/Linux/macOS via
  `std::filesystem`, `sourcelegacy/` targets legacy Windows via Win32 API
  through `xp_compat.h`).
- `source/` Win-version-specific comments updated to reflect Win10+ scope.

### Bench

43 mixed JPGs / 10.86 MB on Linux x64:

| | Output | Ratio | Time |
|---|---|---|---|
| v4.0a | 6,730,670 B | 65.574 % | 12.09 s |
| **v4.0b** | **6,727,753 B** | **65.566 %** | **12.02 s** |

Δ: −0.043 % bytes, 0.994× wall time, all round-trips byte-exact. All
v4.0/v4.0a-encoded files in the test corpus decoded byte-exactly with
v4.0b (backward-compat verified).

### Migration notes

- Existing v4.0 / v4.0a `.pjg` archives keep working — v4.0b reads them
  transparently.
- v4.0b-encoded `.pjg` files are NOT readable by v4.0/v4.0a binaries
  (clean rejection, no crash).
- v3.1d archives need the original v3.1d binary (or v4.0 with `-legacy`,
  for which a v4.0a build is still archived in `dist/` of the v4.0a tag).

---

## v4.0a (2026-04-21) — bugfix

- fix: `decode_jpeg()` leaked a `BitReader` (32 bytes) when `jpg_parse_jfif()`
  returned an error mid-scan loop. Found by libFuzzer + LeakSanitizer on a
  malformed JPEG; added `delete huffr` before the early return.

## v4.0 (2026-04-21) — format break: cross-component lazy prediction

> packJPG v4.0 introduces a **format change** (version byte `0x28` / 40) that
> adds cross-component adaptation to the PJG coder: when encoding the chroma
> components (Cb/Cr) of 4:4:4 JPEGs, the bit-length of the co-located luma
> (Y) coefficient is folded into the arithmetic model context. This tightens
> the prediction in exactly the frames where chroma is most correlated with
> luma (portraits, text, sharp diagonals) and delivers a measurable ratio
> win on photographic corpora.
>
> A `-legacy` flag is provided to emit and decode PJG v3.1d (`0x1F` / 31)
> files for interoperability. The decoder detects the version byte and
> dispatches accordingly, so all existing v3.1d archives decompress to
> byte-identical JPEGs without user intervention.

- new: **cross-component lazy prediction** for 4:4:4 chroma DC and AC passes
  in `pjg_encode_dc`, `pjg_encode_ac_high`, `pjg_encode_ac_low` and their
  decoder counterparts. Y coefficient bit-length (`BITLEN1024P`, clamped to
  7) is combined with the existing neighbourhood bit-length into a compound
  context `ctx_shift = (ctx_len << 3) | y_clen`. The `mod_len` model is
  widened from `max(11, segm_cnt)` to 128 (AC) or `(max_len+1) << 3` (DC).
  Gated on `cmp != 0 && cmpc >= 2 && cmpnfo[cmp].bc == cmpnfo[0].bc` so
  subsampled (4:2:0 / 4:2:2) files fall back to the v3.1d path byte-for-byte
- new: `-legacy` flag — emit v3.1d-format PJGs; output is byte-identical to
  packJPG v3.1d on the same input. Thread-local so concurrent MT batches
  can mix v4.0 and v3.1d encoding safely
- new: dual-version decoder — v3.1d PJGs are detected by their version byte
  and decoded via the v3.1d path (no cross-component context). v4.0 PJGs
  require packJPG v4.0+ to decompress
- measurement (153-JPEG mixed corpus, 151 round-trippable):
  - v4.0 total PJG: **60,066,170 B** vs v3.1d **60,387,566 B** → **−0.532 %**
  - `-legacy` output: **60,387,566 B**, byte-identical to v3.1d
  - top per-file wins: 4:4:4 photographic JPEGs (e.g. `827C1CF27.jpg −5.01 %`);
    subsampled JPEGs neutral by design (gate bypasses cross-comp)
- `-sfth` path continues to emit v3.1d-format PJGs: the parallel encoder
  processes components concurrently, so Y is not available as context when
  Cb/Cr are being encoded. `pjg_use_crosscomp_now` is kept `false` for sfth;
  sfth output remains byte-identical to v3.1d
- validation:
  - 151 / 151 round-trip byte-exact on corpus
  - `-legacy` round-trip: 151 / 151 byte-exact
  - MT stress (`-th8`, 50 iters on 151 files): 393 / 393 OK, 0 mismatches
  - ThreadSanitizer (4 threads × 10 iters): 39 / 39 OK, 0 data races
  - `lib_roundtrip_test`: 151 OK, ratio 76.59 %
  - libFuzzer + ASan + UBSan 15 min: 0 crashes, 0 sanitizer reports,
    coverage grew 2596→3012 edges, corpus 20→23
- new: `source/test/pjg_decode_fuzzer.cpp` + `build_fuzzer.sh` — libFuzzer
  harness over `pjglib_convert_stream2mem` covering both directions of the
  codec (auto-detects JPG vs PJG by leading bytes)
- incompatibility notice: **PJG files produced by v4.0 cannot be decoded
  by packJPG v3.1d or earlier.** Use `-legacy` during the transition if
  downstream consumers have not been upgraded. This is the first intentional
  format break since v2.0 (2007)
- build: Linux builds now use `-flto=thin` (clang) for ~8 % encode speedup
  via cross-TU inlining; ratio and output are bit-identical
- build: `check_value_range` rewritten with `std::minmax_element` for
  cleaner SIMD-friendly range validation
- test corpus: `test-files/` directory added (5 representative JPEGs:
  baseline 4:2:0, 4:4:4, grayscale, photographic, solid color) for CI
  smoke tests
- **Windows XP support policy:** v4.0 is the **last feature release** for
  Windows XP. Future XP releases will be bugfix-only (versioned v4.0a,
  v4.0b, …). New features introduced in v4.1 and later will not be
  backported to the XP build
- maintainer: Yade Bravo (https://github.com/YadeWira/packJPG)

---

## v3.1d (unreleased) — thread safety + UB cleanup

> Originally planned as v3.2 with an algorithmic improvement; the
> proposed per-component arithmetic-model reset was measured against
> the current `-sfth` path (which already does exactly that) and came
> out *worse* than the sequential shared-state path by ~3 KB on the
> 153-JPEG corpus. Cross-component adaptation is a net win for this
> format, so the change is not pursued and v3.2 is left reserved for
> a future algorithmic overhaul. This release ships the thread-safety
> and UB cleanup work that stands on its own.


- fixed: six undefined-behaviour sites in the progressive-JPEG decoder where
  negative signed short coefficients were left-shifted by `cs_sal`. Under
  C++17 §8.8 shifting a negative value is UB; coefficients are now cast via
  `(unsigned int)` before the shift. UBSan reports clean on the full corpus;
  production output is byte-identical (fixes are semantically neutral)
- fixed (lib MT safety): `action`, `sfth_mode`, `lib_in_type`, `lib_out_type`
  were declared process-wide (`INTERN`) but written during per-file
  processing. Concurrent `pjglib_convert_*` calls from different host
  threads would race on these globals. All four are now `THREAD_LOCAL`;
  CLI MT workers propagate `sfth_mode` from the main thread next to
  `auto_set` / `nois_trs` / `segm_cnt`. ThreadSanitizer reports clean
  with 4 threads × 50 iters on the 152-JPEG corpus
- docs: `packjpglib.h` now documents that buffers returned via
  `pjglib_convert_stream2mem` are allocated with `malloc()` and must be
  freed with `free()` (not `delete[]`). Existing test harnesses updated
  accordingly
- tests: new `source/test/lib_concurrent_test.cpp` — hammers the lib from
  N threads to validate TLS correctness. Used together with ASan / UBSan /
  TSan builds as a repeatable audit
- fixed: entropy decode error message no longer suggests the misleading
  `-p` hint. `-p` only relaxes warnings (errorlevel=1) — real Huffman
  decode failures are errorlevel=2 and cannot be "recovered". Files that
  trigger this are typically malformed JPEGs (`djpeg -strict` rejects
  them too); the new message points users at that diagnostic instead
---

## v3.1c (04/02/2026) — public

- fixed: `-module` flag with batch MT showed full UI output (progress bar,
  "Using N of M detected thread(s)", error/warning lists, mix-mode warning)
  instead of only the final `OK time` / `ERROR n time` line; all UI elements
  now check `!module_mode` before printing
- fixed (XP): same `module_mode` guards missing in `source4xp/` for error list,
  warning list, and mix-mode warning
- fixed (XP): `%ld` format specifier with `(long)` cast in the non-Windows path
  of `source4xp/` replaced with `%lld` / `long long` for correctness

---

## v3.1b (04/02/2026) — public

- fixed: `Using N of N detected thread(s)` message was suppressed in progress
  bar mode (`-vp` sets `verbosity = -1`); now always shown when MT is active
- fixed: time/speed/ratio summary was never shown after decompression batches —
  `acc_jpgsize`/`acc_pjgsize` were only accumulated for `F_JPG` files; added
  accumulation for `F_PJG` in both single-thread and MT paths, in both builds
- fixed (ci): Release file heredoc in `apt-repo.yml` had leading spaces causing
  malformed apt metadata; fixed with unindented `'EOF'` heredoc
- maintainer: Yade Bravo (https://github.com/YadeWira/packJPG)

---

## v3.1a (04/02/2026) — public

- fixed: decompression per-file display showed `0 KB → X KB 0.0%` instead of
  the correct sizes and ratio; root cause was `merge_jpeg()` assigning the JPEG
  output size to `pjgfilesize` instead of `jpgfilesize` — also caused speed and
  ratio to read 0.00% in `-v1`/`-v2` verbose mode and in batch summaries
- fixed: `-ver` save/restore used `int` instead of `int64_t` for
  `saved_jpgsize`/`saved_pjgsize`, causing size truncation on files ≥ 2 GB
- fixed (XP): when `-th>1` was requested on the XP build, the fallback
  sequential path omitted `acc_jpgsize`/`acc_pjgsize` accumulation for PJG
  files, leaving batch decompression stats at zero
- fixed (Windows): `--no-color` skipped `SetConsoleOutputCP(CP_UTF8)`, causing
  Unicode characters (✓ ✗ → ░ █ braille spinner) to render as garbage in
  cmd.exe; UTF-8 codepage is now set unconditionally on Windows
- fixed (Windows): `FileReader`/`FileWriter` used `long`/`ftell` on the Windows
  path, which is 32-bit even on x64 and overflows for files > ~2.14 GB;
  replaced with `_fseeki64`/`_ftelli64` in both `source/` and `source4xp/`
- fixed: `list` subcommand batch summary incorrectly displayed
  `decompressed: N PJG`; now correctly shows `listed: N PJG`

---

## v3.1 (04/02/2026) — public

- color output: program header and status lines now use ANSI colors
  (suppressed when output is not a terminal)
- Windows XP build (`source4xp/`): added `-sfth` support via Win32 CreateThread
  (`-th` remains unsupported on XP; single-file parallel is now available)
- help text: removed example lines from both builds; removed `-th` from XP help
- docs: converted Readme.txt and changelog.txt to Markdown; removed email reference
- improved: DC sign now uses 9-state neighbor context (left × top signs)
  instead of no context; ~0.25% better compression on average
- fixed: progress bar displayed "Processed N-1 of N files" at end of batch
- fixed: corrupt PJG caused infinite loop in header parser (EOF not checked)
- fixed: corrupt PJG caused infinite loop in `pjg_decode_generic`; added 1MB
  decode limit — generates clean error instead of hanging
- fixed: `main()` always returned exit 0 even when files failed
- fixed: `filetype` not reset at start of `check_file()` — inaccessible files
  inherited the previous file's type, corrupting progress counter
- fixed: inaccessible files not counted in `file_proc_cnt` pre-scan
- fixed: compression ratio showed >100% in mix mode due to `jpgfilesize=0`
  during decompression; ratio accumulation now only runs for F_JPG files
- fixed: stale `-list` flag shown in help (replaced by `list` subcommand)
- security: added bounds checks in JPEG segment parser to prevent out-of-bounds
  reads from maliciously crafted JPEG files (DHT, DQT, DRI, SOS, SOF segments
  and all header parser loops); no impact on valid JPEG files
- ui: modernized CLI interface — new header format, Unicode block progress bar
  (█/░), braille spinner animation (⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏) in multi-thread mode,
  check/cross marks (✓/✗) for results, and cleaner summary with Unicode
  separators (─); Windows fallback uses ASCII equivalents
- fixed: Windows console set to UTF-8 at startup (`SetConsoleOutputCP(CP_UTF8)`)
  so header/UI characters display correctly in cmd.exe and PowerShell
- fixed: Unicode-safe file I/O on Windows — `FileReader`/`FileWriter` now use
  `_wfopen` + `MultiByteToWideChar(CP_ACP)` instead of `std::fopen`/`std::ifstream`;
  fixes accented and special characters in filenames on Windows 7+
- fixed: in multi-thread mode, error/warning messages no longer interrupt the
  progress bar; collected and printed cleanly after the bar completes
- build: added `build4xp.sh` to project root for standalone Windows XP builds
- fixed: header bullet `•` now uses Windows-1252 `\x95` on Windows — renders
  correctly in cmd.exe on Windows 7 regardless of console codepage
- build: added `build_pkg.sh` — produces `.tar.gz`, `.deb`, `.rpm`, and `.snap`
  packages from source; individual formats selectable via `--tar`/`--deb`/`--rpm`/`--snap`
- ci: GitHub Actions release workflow builds and publishes all packages automatically
  when a `v*` tag is pushed
- feat: added `install.sh` — one-liner installer that detects `apt`/`dnf`/`yum`
  and downloads the matching package from the latest GitHub release
- docs: added installation section to README; updated build scripts table
- maintainer: Yade Bravo (https://github.com/YadeWira/packJPG)

---

## v3.0 (03/30/2026) — public

- new flag: `-sfth` — parallel single-file compression using 3 threads (Y/Cb/Cr);
  ~25-30% faster on 3+ thread machines; ratio preserved (~0.01% delta);
  generates new PJG format (0x01 marker); requires v3.0+ to decompress;
  both encode and decode are parallelized
- warning shown when `-sfth` is used with fewer than 3 detected threads
- optimal batch+single-file usage: `-th<N/3> -sfth` on an N-thread machine
- fixed: `[a]` mode no longer creates empty `.pjg` files for skipped JPEGs
- fixed: `[x]` mode no longer creates empty `.jpg` files for skipped PJGs
- fixed: skipped files in `a`/`x` mode are now silent (no warning printed)
- fixed: unrecognized flags (e.g. `-th=`) now print a clear error message
  instead of being silently treated as filenames
- fixed: `jpgfilesize`/`pjgfilesize` changed from `int` to `int64_t` — prevents
  0.00% ratio reporting on large files (>2GB) and on 32-bit builds
- fixed: `-th0` on x86 now caps at 2 threads to prevent OOM; x64/Linux
  still uses all available cores
- fixed: progress counter now shows only processable files (e.g. "2 of 2"
  instead of "5 of 5" when 3 of the 5 files are skipped)
- fixed: verbose mode (`-v1`/`-v2`) no longer prints header lines for skipped
  files — only processed files appear in the output
- fixed: skipped files (wrong type) no longer print warnings in MT mode (`-th2` or higher)
- fixed: directories from wildcard expansion are now silently ignored;
  use `-r` explicitly to recurse into subdirectories
- fixed: decompressing `-sfth` files with `-ver` incorrectly reported "file sizes
  do not match" even when the output was bit-for-bit correct; verify now
  re-encodes using the same format (sfth or standard) as the original PJG
- fixed: `mix` mode warning incorrectly referenced `-c` (non-existent flag);
  message now correctly reads `a` (compress only)
- fixed: `list` subcommand displayed `v0.1` for `-sfth` files instead of the
  correct version; sfth files now show `v3.0 (parallel)`
- maintainer: Yade Bravo (https://github.com/YadeWira/packJPG)

---

## v2.9 (03/25/2026) — public

- new subcommand interface: `a` (compress), `x` (decompress), `mix`, `list`;
  subcommand is now required; running without one shows the help screen
- new subcommand: `a` — compress only, process JPG files, skip PJG
- new subcommand: `x` — decompress only, process PJG files, skip JPG
- new subcommand: `mix` — mixed mode, auto-detect, warns if both directions used
- new subcommand: `list` — list PJG info (replaces `-list` flag)
- new switch: `-module` — machine-friendly output: OK/ERROR + elapsed seconds
- passing a directory as argument now automatically recurses into it
- fixed: crash with accented/special characters in path (Windows drag & drop)
- fixed: file count wrong with wildcard expansion on Windows
- fixed: wildcard expansion now uses `FindFirstFileW` (Unicode filenames)
- fixed: comp. ratio 0.00% in single-thread mode
- fixed: comp. ratio 100% in multi-thread mode with verify
- fixed: unknown file types (`.exe`, `.png`, etc.) now skipped silently
- fixed: em dash display issue in Windows console (codepage)
- help screen now shows program description
- build: binaries stripped automatically (`strip --strip-unneeded`)
- minimum supported platform: Linux x64, Windows 7+
- maintainer: Yade Bravo (https://github.com/YadeWira)

---

## v2.8 (03/21/2026) — public

- compression: improved AC sign context using top-left diagonal neighbor
  (mod_sgn 9→27 states), ~0.04% better ratio on typical camera photos
- new switch: `-r` — recurse into subdirectories
- new switch: `-list` — display PJG file info without decompressing
- new switch: `-dry` — dry run: simulate without writing output files
- MT mode: Ctrl+C stops workers cleanly, removes partial output files
- summary now reports speed in MB/s
- thread info shows detected core count
- fixed: `-list` no longer creates empty `.jpg` output files
- fixed: MT progress bar no longer shows stray characters after completion
- fixed: `unique_filename()` now respects `-od` output directory
- maintainer: Yade Bravo (https://github.com/YadeWira)

---

## v2.7 (03/20/2026) — public

- new switch: `-th<n>` — multi-threaded batch processing (0 = auto-detect cores)
- multi-threaded mode automatically enables bit-for-bit verification per file
- Windows: wildcard expansion now handled internally (`*.jpg` works in `cmd.exe`)
- `-od<path>` now creates the output directory automatically if it does not exist
- build: fixed icon embedding for Windows x64/x86 targets (`windres -O coff`)
- build: wall-clock time now reported correctly in multi-threaded mode
- maintainer: Yade Bravo (https://github.com/YadeWira)

---

## v2.6 (03/19/2026) — public

- ported to C++17; removed dependency on `std::experimental::filesystem`
- clang 18 support: removed GCC-only `-fsched-spec-load` flag
- fixed segfault: `current_order` going negative on malformed input (#41/#35)
- fixed heap-buffer-overflow: `shift_context()` lacked bounds check on `links[]` (#33)
- fixed global-buffer-overflow: `qtable_id` not validated before indexing `qtables[]` (#32)
- fixed global-buffer-overflow: errormessage buffer 128→512 bytes, `sprintf`→`snprintf` (#30)
- fixed alloc-dealloc mismatch: `BitWriter::get_c_bytes()` now uses `malloc` (#31)
- fixed memory leaks: early returns in `read_jpeg()` now clean up all allocations (#34)
- fixed undefined behaviour: DEVLI macro triggered negative shift when s=0
- removed dead code: `plocoi`, `median_int`, `median_float`, unused `ccode` field
- new switch: `-od<path>` — write output files to a specified directory (#37)
- performance: `BitWriter` and `MemoryWriter` pre-allocate buffers using input size hint
- cross-compilation targets for Linux x64, Windows x64 and Windows x86 added to Makefile
- maintainer: Yade Bravo (https://github.com/YadeWira)

---

## v2.5k (01/22/2016) — public

- updated contact info
- fixed a minor bug

---

## v2.5j (01/15/2014) — public

- various source code optimizations (using cppcheck)

---

## v2.5i (12/26/2013) — public

- fixed possible crash with malformed JPEG (thanks to Moinak Ghosh)

---

## v2.5h (12/07/2013) — public

- added a warning for inefficient huffman coding (thanks to Moinak Ghosh)

---

## v2.5g (09/14/2013) — public

- fixed a rare crash bug with manipulated JPEG files

---

## v2.5f (02/24/2013) — public

- fixed a minor bug in the JPG parser (thanks to Stephan Busch)

---

## v2.5e (07/03/2012) — public

- some minor source code optimizations
- changed packJPG licensing to LGPL
- moved packARC to a separate package

---

## v2.5d (07/03/2012) — public

- fixed a rare bug with progressive JPEG

---

## v2.5c (04/13/2012) — public

- various source code optimizations

---

## v2.5b (01/27/2012) — public

- further removal of redundant code
- some fixes for the packJPG static library
- compiler fix for Mac OS (thanks to Sergio Lopez)
- improved compression ratio calculation
- eliminated the need for temp files

---

## v2.5a (11/21/2011) — public

- source code compatibility improvements (Gerhard Seelmann)
- avoid some compiler warnings (Gerhard Seelmann)
- source code clean up (Gerhard Seelmann)

---

## v2.5 (11/11/2011) — public

- improvements (~0.5%) to overall compression
- several minor bugfixes
- major code cleanup
- removed packJPX from the package
- added packARC to the package
- packJPG is now open source!

---

## v2.4 (03/24/2010) — public

- major improvements (1%...2%) to overall compression
- around 10% faster compression & decompression
- major improvements to JPG compatibility
- size of executable reduced to ~33%
- new switch: `-ver` (verify file after processing)
- new switch: `-np` (no pause after processing)
- new progress bar output mode
- arithmetic coding routines rewritten from scratch
- various smaller improvements too numerous to list here
- new SFX (self extracting) archive format

---

## v2.3b (12/20/2007) — public

- some minor errors in the packJPG library fixed
- compatibility with packJPG v2.3 maintained

---

## v2.3a (11/21/2007) — public

- crash issue with certain images fixed
- compatibility with packJPG v2.3 maintained

---

## v2.3 (09/18/2007) — public

- compatibility with JPEG progressive mode
- compatibility with JPEG extended sequential mode
- compatibility with the CMYK color space
- compatibility with older CPUs
- around 15% faster compression & decompression
- new switch: `-d` (discard meta-info)
- various bugfixes

---

## v2.2 (08/05/2007) — public

- around 40% faster compression & decompression
- major improvements to overall compression (around 2% on average)
- reading from stdin, writing to stdout
- smaller executable
- minor bugfixes
- various minor improvements

---

## v2.0 (05/28/2007) — public

- first public version of packJPG
- minor improvements to overall compression
- minor bugfixes

---

## v1.9a (04/20/2007) — non public

- first released version
- only for testing purposes
