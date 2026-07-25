# packJPG Changelog

## v5.0b (2026-07-25) — Linux .deb portability fix, formalizes post-v5.0a hotfixes

> Retags 3 commits that shipped as GitHub Release asset updates under the
> v5.0a tag without a matching git tag move or CHANGELOG entry — this
> release corrects that bookkeeping gap and adds one more small fix found
> while investigating it. On-disk `.pjg` format unchanged.

### Bug fixes

- **`.deb` `Depends` hardcoded `libjxl0.11`, breaks on other libjxl
  versions**: the v5.0a `.deb` was built on `ubuntu-latest` (CI), where
  the binary actually linked against `libjxl.so.0.7` — but `build_pkg.sh`
  hardcoded `Depends: libcharls2, libjxl0.11`. Result: `apt install`
  succeeded (dpkg doesn't check SONAMEs, only the declared Depends) but
  the binary crashed at runtime with `error while loading shared
  libraries: libjxl.so.0.7: cannot open shared object file` on any
  system without that exact package (e.g. Debian trixie, which only has
  `libjxl0.11`). Fixed by deriving `Depends` from the built binary's
  actual `NEEDED` sonames via `objdump` + `dpkg -S`, instead of a
  hardcoded guess.
- **Statically link CharLS+libjxl on Linux — no more runtime deps**: the
  `Depends` fix above was still a band-aid — a `.deb` built on
  `ubuntu-latest` only installs cleanly on distros that happen to ship
  the same libjxl SONAME (Debian trixie doesn't have `libjxl0.7` at
  all, so the fixed `.deb` still failed to *install* there, just with a
  clean apt error instead of a runtime crash). Root-caused by vendoring
  static CharLS 2.4.2 + libjxl 0.11.2 (+ highway/brotli/lcms2) for Linux
  x86_64 under `source/linuxlibs/`, same pattern as `source/winlibs/`
  for Windows. `packJPG`/`libpackJPG.so`/the `.deb` now depend on
  nothing but `libstdc++`/`libgcc_s`/`libm`/`libc` — no `Depends` line
  needed for JPEG-LS at all. Verified end-to-end against the real
  `pack-apt` shared repo: `apt install packjpg` on Debian trixie,
  JPEG-LS round-trip byte-exact, zero extra dependencies.
- **`sourcelegacy/` still targeted `_WIN32_WINNT`/`WINVER`/`_WIN32_IE`
  `0x0501` (Windows XP SP2 API level)**, left over from before v5.0
  dropped Windows XP support and moved the documented minimum to
  Windows 7/8 — a doc/policy vs. compiled-target mismatch, not a
  functional bug (0x0501 is backward-compatible with 7/8/10/11, and no
  code here uses any WINNT-gated API introduced between XP and 7).
  Bumped to `0x0601` (Windows 7) to match. Verified on real hardware:
  both `packJPG_win_legacy_x64.exe` and `packJPG_win_legacy_x86.exe`
  round-trip JPEG-LS and JPEG byte-exact (SHA-256 verified) on the
  Windows 7 SP1 test VM, with `-ver -sfth` combined.

## v5.0a (2026-07-17) — JPEG-LS everywhere, legacy x64 goes official

> Follow-up to v5.0: closes the two gaps that release left open. JPEG-LS
> now works on every shipped Windows artifact (not just Linux), and the
> x64 legacy (Windows 7/8) build moves from community-maintained to
> officially supported, same bar as x86. **On-disk `.pjg` format is
> unchanged** — this is a platform/support-policy release, not a format
> break.

### Platform support changes

- **x64 legacy build (Windows 7/8) is now officially supported** —
  tested by the maintainer on real hardware/VM before each release,
  same bar as x86. Previously community-maintained.
- **Modern win-x86 CLI target revived** (`packJPG_win_x86.exe`,
  previously dropped in v5.0 as "vanishingly small audience") — brought
  back specifically to carry JPEG-LS to 32-bit Windows.

### JPEG-LS on Windows

JPEG-LS (`.jls`) recompression, added in v5.0 for Linux x64 only, now
works on every Windows build:

- **`source/` win-x64 / win-x86** — CharLS 2.4.2 + libjxl 0.11.2 (+
  highway/brotli/lcms2) cross-compiled once and vendored under
  `source/winlibs/` (no MinGW packages of either library exist).
  `make win-x64`/`make win-x86` and `build_all.sh` auto-detect the
  vendored libs by file presence and fall back to no-JPEG-LS if absent
  (e.g. a stripped-down fork).
- **`sourcelegacy/` (Windows 7/8, x86 + x64)** — same vendored libs,
  wired into the C++14/Win32-API legacy tree (`JLS=1` by default).
  Initial port contributed by the sibling `packJPG-lab` fork, reviewed
  and merged here.
- **`packJPG.dll` / library SDK archives** — the DLL needed its own
  vendor set (`source/winlibs-dll/`, posix thread model): the DLL must
  be built with the posix-model mingw compiler to avoid a crash at
  `DLL_PROCESS_DETACH`, but the plain-compiler `winlibs/` libjxl is
  ABI-incompatible with that (`__gthr_win32_*` vs `__gthr_posix_*`
  symbols). `build_lib_pkg.sh`'s win64/win32 archives now ship JPEG-LS
  automatically, transparent to the library API.

### Bug fixes

- **sourcelegacy JPEG-LS decompress crash** (found during review of the
  packJPG-lab port, before merge): `process_file()`'s F_JPG/F_PJG
  dispatch was missing the `if (!jpg_jpegls)` guard around
  `adapt_icos`/`unpredict_dc`/`recode_jpeg` that `source/` already has.
  JPEG-LS images never go through the normal baseline-JPEG scan setup,
  so `recode_jpeg()` wrote through an unallocated `scnp` pointer —
  null-pointer write, reproduced identically on both x86 and x64 under
  Wine. Fixed before merge; never shipped.
- **`-ver` false-positive on JPEG-LS decompress** (pre-existing since
  v5.0's JPEG-LS launch, affecting `source/` too): the decompress
  verify path (`x -ver`) called `decode_jpeg` and friends unconditionally
  on the re-read merged output. JPEG-LS has no baseline Huffman/DCT scan
  structure, so the entropy-decode loop didn't consume the bitstream
  correctly, leaving a bogus "surplus data found after coded image
  data" warning on every JPEG-LS `-ver` decompress. Not a crash (caught
  as a warning), but a real false positive — fixed with the same
  `jpg_jpegls` guard pattern, on both `source/` and `sourcelegacy/`.
- **`padbit` declared as bare `char`** — heap-buffer-overflow on ARM64.
  x86_64's char defaults to signed, so the `-1` sentinel worked by
  accident; AArch64 defaults to unsigned char, silently turning `-1`
  into `255` and corrupting the arithmetic coder's model. Fixed by
  declaring it `signed char` explicitly across `source/`, `sourcePre/`,
  and `sourcelegacy/`. Verified natively with `-funsigned-char` and
  under real ARM64 via `qemu-user`.
- Two pre-existing `cross-platform-verification` CI bugs fixed: `set -e`
  was killing the round-trip step before its own skip-handling could
  run, and a comment misattributed a compress-skip branch to an
  "ImageMagick JPEG quirk" when the actual cause was the padbit bug
  above.

### Tooling

- **`build_lib_pkg.sh`** — new script automating the library/SDK
  release archives (`packJPG-<ver>-{linux-x64,win64,win32}-lib.{tar.gz,zip}`),
  previously built and uploaded by hand.

## v5.0 (2026-07-16) — new LTS baseline: bomb-guard, JPEG-LS, drops Windows XP

> Major version bump, not a v4.0g bugfix nor a v4.1 feature-only release —
> three things land together: Windows XP support is dropped entirely, a
> 3-layer decompression-bomb defense ships, and JPEG-LS (`.jls`)
> recompression is added as a genuine new capability. **The on-disk `.pjg`
> format is unchanged** (`format_version_current` stays `40` / `0x28`) —
> this is a version/support-policy bump, not a format break. Verified
> empirically, bidirectionally: v5.0 decodes v4.0f `.pjg` output byte-exact,
> and v4.0f decodes v5.0 output byte-exact (non-JPEG-LS content) — the
> whole v4.0.x line remains fully interchangeable with v5.0.

### Platform support changes

- **Windows XP support dropped entirely** (not just frozen at bugfix-only,
  as the v4.0 entry below had signaled — accelerated to a clean cut).
- **x86 legacy build (Windows 7/8) is now officially supported** by the
  upstream maintainer — tested on real hardware/VM before each release,
  same bar as `source/`. Previously community-maintained like x64.
- **x64 legacy build minimum moves from Vista to Windows 7** and remains
  community-maintained (validated via Wine only; a maintainer with real
  Windows 7/8 x64 hardware is wanted — see README).

### Security / hardening

- **3-layer decompression-bomb defense** for `.pjg` decoding (contributed
  by the sibling `packJPG-lab` fork, reviewed and independently verified
  before merge):
  1. Codec-level exhaustion detection in the range coder (`aricoder.cpp`):
     `ArithmeticDecoder::is_exhausted()` — a truncated/malicious stream
     that keeps "generating" symbols past its real end is caught within a
     64 KB tolerance.
  2. Always-on blowup-ratio guard in `merge_jpeg()`: reconstructed JPEG
     must not exceed `input_size × 500 + 1 MB`, checked at both the
     pre-decode estimate and the exact post-decode size.
  3. Absolute output-size cap, `pjglib_set_max_output_size()` /
     `-maxout<MB>` — default 256 MB (was unbounded).
  Plus a cap on untrusted `csizes[]` length-prefixed allocation in the
  `-sfth` per-component decode path.
  Verified against a real fuzzer-found bomb sample (7,738 B → 6.25 MB
  unpatched, cleanly rejected patched) on `source/` and `sourcelegacy/`
  (each catches it via a different layer — exhaustion vs. ratio — a
  live demonstration that the defense-in-depth actually helps), 151/151
  legitimate-file regression, and a clean ASan+UBSan fuzzing pass.
- **CharLS decoder/encoder handle leaks in the JPEG-LS path** (found by
  extending the fuzzer to cover JPEG-LS, which had never been fuzzed
  before): `JLS_CHECK`'s early return never destroyed the CharLS
  handle on failure — all 12 call sites leaked. Fixed by adding a
  `cleanup` argument to the macro.
- **Unchecked CharLS calls in `jpegls_reconstruct()`** risked a heap
  buffer overflow: `info.width/height/bits_per_sample` there come from a
  deserialized recipe — untrusted, attacker-controlled — and a rejected
  `set_frame_info` would leave the estimated-size variable uninitialized,
  sizing the destination buffer from garbage before `encode_from_buffer`
  wrote into it. Now checked the same way as the rest of the JPEG-LS path.
- **ODR violation in `sourcelegacy/aricoder.h`**: a stale duplicate,
  missing the bomb-guard's `exhausted_`/`is_exhausted()` fields, that
  `sourcelegacy/packjpg.cpp`'s quoted `#include` resolved to — while the
  shared `../source/aricoder.cpp` in the same binary resolved to the
  current header. Two translation units disagreeing on the same class
  layout is undefined behavior, not just a warning. Found via LTO
  type-mismatch warnings once `build_all.sh` built against a synced
  header. Fixed by deleting the duplicate.

### JPEG-LS support (new, Linux x64 only)

- **Lossless recompression of JPEG-LS (`.jls`, ISO/IEC 14495, SOF F7)
  files** — same `a`/`x` workflow as classic JPEG, typically ~16%
  smaller, byte-exact reconstruction. Strategy: decode to pixels,
  recompress losslessly with JPEG XL (`libjxl`), and on decompression
  regenerate the *exact* original entropy bytes via CharLS — works
  because a default-parameter JPEG-LS scan (`ILV=0`, `NEAR=0`) is a pure
  function of pixels + scan layout, with no encoder-side free choices.
  Non-default scans (interleaved, near-lossless) are detected and
  refused with a clear error rather than silently mis-encoding.
- Requires `libcharls-dev` + `libjxl-dev`; feature-gated behind
  `-DHAVE_JPEGLS`, auto-detected by `source/Makefile` and `build_all.sh`
  (override with `JLS=1`/`JLS=0`). Without the flag, `jpegls.cpp` compiles
  to an empty translation unit and `jpegls.h`'s functions degrade to
  no-op stubs — zero added dependency for anyone who doesn't need it.
  Windows (`packJPG.dll`, `packJPG_win_x64.exe`) and `sourcelegacy/`
  never get it: no MinGW builds of CharLS/libjxl exist.
- Original commit (`e23bdf9`) shipped without going through the
  cross-session diff-review protocol used for the bomb-guard; the
  gaps below were all found and fixed during that review, before this
  release:
  - `build_all.sh` and CI never actually got `-DHAVE_JPEGLS` (deps
    weren't installed / the Linux target didn't request them) — every
    "official" build would have silently shipped without JPEG-LS.
  - `linux-x64` Makefile target was missing `$(LIBS)` on its link line
    entirely (pre-existing, invisible before because `-lpthread` is a
    no-op on modern glibc — became a hard failure once `-lcharls`/`-ljxl`
    were sometimes present).
  - Grayscale (1-channel) JPEG-LS crashed the JXL encode step: the
    embedded ICC profile is hardcoded 3-channel sRGB, which JXL rejects
    for any other channel count. Now uses `JxlColorEncodingSetToSRGB`
    for non-3-channel input.
  - `-r` directory recursion didn't recognize `.jls` at all (content
    detection still worked for files named explicitly).
  - Decompressing a `.pjg` that reconstructs to JPEG-LS wrote the output
    under the default `.jpg` name; now correctly renamed to `.jls`
    on success.
- Verified: grayscale and RGB round-trips byte-exact, 151/151 regular-JPEG
  regression unaffected, all 7 build target configurations (native,
  `JLS=0`/`1`, `linux-x64`, `dll`, `win-x64`, `win-x86`, `lib`, `so`) build
  clean, clean ASan+UBSan fuzzing pass with JPEG-LS-derived seeds included.

### Fixed

- `test-files/*.jpg` were silently excluded from git by a blanket `*.jpg`
  ignore rule that predates the directory — CI's checkout had no test
  fixtures. `test-files/grayscale.jls` added as a small JPEG-LS CI fixture
  (encoded from the existing `grayscale.jpg`, no third-party licensing
  question).
- Two comments in `source/packjpg.cpp` / `sourcelegacy/packjpg.cpp` had a
  double-encoded UTF-8 em-dash (mojibake) — comment-only, no functional
  change.

### Docs

- README documents JPEG-LS support, the `HAVE_JPEGLS`/`JLS` build flag,
  and updates every Windows-XP-era platform reference.

---

## v4.0f (2026-07-11) — native arithmetic-coded JPEG support

> New feature: native arithmetic-coded JPEG support (SOF C9/CA —
> sequential + progressive; lossless arithmetic (C11/CB) stays out of
> scope, same as packJPG never having supported lossless Huffman (C3)).

- Huffman `.pjg` output stays byte-compatible with v4.0e; no new
  sub-marker was needed for arithmetic — `hdrdata` already round-trips
  the original SOF byte losslessly, so `jpg_arith_coded` is re-derived
  from it during unpack.
- Verified: standalone codec tests, full `packjpg.cpp` integration, real
  Windows 10/7 VMs, a widened corpus (CMYK, 4:4:4/4:2:2, 20 diverse real
  photos), and a clean ASan+UBSan fuzzing pass (2 bugs found and fixed
  first, then 851s / 4,904 execs with zero further findings).

---

## v4.0e (2026-06-03) — library MT defaults + batch API

> Adds a multithreading-friendly C API for embedding packJPG in
> archivers, image tools, and other FFI hosts. **No change to the
> on-disk `.pjg` format** — output is byte-exact equivalent to v4.0d
> (and v4.0b/v4.0c) on the same input.

### Bug fixes (release QA)

Two defects in the new batch path, found by a QA pass over a 153-file
real-world JPEG corpus plus ASan/UBSan/TSan runs:

- **`pjglib_convert_batch` file→file with `out_dest == NULL` wrote the
  wrong extension on decompress.** The sibling-output path always
  appended `.pjg`, so decompressing `foo.pjg` reconstructed the JPEG
  straight back onto `foo.pjg` — silently destroying the compressed
  source. The output extension now follows the input's actual type
  (peek the magic: `FF D8` JPEG → `.pjg`, `'J''S'` PJG → `.jpg`).
  Compression was unaffected; only the decompress sibling path was wrong.
  Regression-covered by the new `lib_filemode_test`.
- **Per-thread memory leak of the `jpgfilename`/`pjgfilename` buffers.**
  These THREAD_LOCAL buffers were freed only at the *next*
  `pjglib_init_streams` call, but a batch worker thread exits after its
  last op without ever making that call — leaking its final pair per
  worker (caught by LeakSanitizer). They are now freed at the end of
  every `pjglib_convert_stream2mem`. Matters for long-running hosts that
  issue many batches.

### Security / hardening

- **New `pjglib_set_max_output_size(n)` / `pjglib_get_max_output_size()`**
  — decompression-bomb guard. A fuzz pass over the decoder surfaced that
  a tiny malformed `.pjg` can reconstruct into a much larger JPEG (e.g.
  a 7.7 KB input expanding to a 6.25 MB output via a crafted
  trailing-garbage blob) — the decode terminates and is memory-safe
  (ASan/UBSan clean), but it is a time/memory amplification vector for a
  host decoding untrusted `.pjg`. The new cap (bytes; `0` = unlimited,
  the default — no behavior change) makes the decoder fail cleanly when
  the reconstructed JPEG would exceed it. Enforced in two layers: an
  early per-field limit in `pjg_decode_generic` (bounds peak memory
  during the garbage/header decode) and an exact check on the produced
  output in `merge_jpeg`. Pre-existing decode behavior, not a v4.0e
  regression. Covered by `lib_maxoutput_test`.
- **Also exposed on the CLI as `-maxout<MB>`** (both `source/` and
  `sourcelegacy/` builds) — same guard, in megabytes, for command-line
  use: `packjpg x -maxout64 file.pjg`. Sets the same
  `pjg_max_output_size` global; default off (`0` = unlimited) in CLI and
  API alike.

### Legacy build (Windows XP/Vista/7/8)

- **`sourcelegacy/` brought to v4.0e.** The on-disk `.pjg` format is
  unchanged, so the legacy CLI already produced v4.0e-compatible output;
  this bumps its version string and ports the decompression-bomb guard.
- **New `-maxout<MB>` CLI switch** — the legacy build has no library API,
  so the guard is exposed as a command-line flag instead of
  `pjglib_set_max_output_size`. `packjpg x -maxout64 file.pjg` refuses to
  reconstruct a JPEG larger than 64 MB (decode fails cleanly, no partial
  output). Default off (unlimited). Same two-layer enforcement as the
  library (per-field cap in `pjg_decode_generic` + exact check in
  `merge_jpeg`).
- Uses a plain process-global for the cap (no `thread_local` needed): the
  XP build's `-th` multi-file batch is disabled, so decoding is
  single-threaded. The v4.0e *library* MT API was **not** ported to
  legacy — it relies on `thread_local` for thread-safe concurrent calls,
  which the XP toolchain does not provide.
- Verified on real Windows 7 (x64 + x86): round-trip byte-exact (MD5
  match), guard aborts an oversized decode and leaves no partial file,
  and does not affect legitimate files under the cap.

### Library API additions

- **New `pjglib_convert_batch(ops, n_ops, msg)`** — convert N
  (in,out) pairs in parallel over a worker pool. Each worker calls
  `pjglib_init_streams` + `pjglib_convert_stream2mem` internally, so
  every per-op output goes through the standard stream I/O path. Job
  stealing: workers grab the next unprocessed op from an atomic
  counter, no fixed partitioning. On the first failure, `msg` is
  filled with the failing op's index and error; remaining workers
  are allowed to finish (their results are discarded). Returns true
  iff all ops succeeded.
- **New `pjglib_set_intra_file_threads(int n)` /
  `pjglib_get_intra_file_threads(void)`** — controls SFTH (3-thread
  Y/Cb/Cr parallelism within a single file). `n=0` (default) means
  *auto*: ON if the host has ≥3 logical cores, OFF otherwise. `n=1`
  forces OFF. `n≥3` forces ON.
- **New `pjglib_set_inter_file_threads(int n)` /
  `pjglib_get_inter_file_threads(void)`** — controls batch
  parallelism across files in `pjglib_convert_batch`. `n=0` (default)
  means 1 worker (sequential batch). `n≥1` means N concurrent
  workers.
- **New `pjglib_suggest_batch_threads(void)`** — returns
  `max(1, cores/3)`, the canonical packing that keeps total thread
  budget (inter × intra) close to the host's core count. Useful as a
  archiver's startup default.
- **New `pjglib_batch_io` struct** — one input/output pair for
  `pjglib_convert_batch`. Same stream-type semantics as
  `pjglib_init_streams` (`in_type`/`out_type`: 0=file, 1=memory,
  2=stream).

### Threading behavior change

> **The library's single-file convert path is now multithreaded by
> default** when the host has ≥3 cores. Each call to
> `pjglib_convert_stream2mem` (and the related single-file entry
> points) now uses 3 worker threads internally via the same SFTH
> path as the CLI's `-sfth` flag.

- **Effect on existing FFI consumers:** each `pjglib_convert_*` call
  uses up to 3 cores instead of 1. **No code change required** in
  the host application.
- **Output bytes:** byte-exact equivalent to v4.0d's SFTH path on
  the same input. Round-trip is verified byte-exact by
  `lib_batch_test` across a 6-cell grid
  (`inter ∈ {1,2,4}` × `intra ∈ {off,on}`).
- **Opt-out:** call `pjglib_set_intra_file_threads(1)` once at
  startup to restore the pre-v4.0e single-threaded behavior for
  every subsequent convert call.
- **No MT lockouts:** the setters are INTERN process-wide
  configuration. They are NOT thread-safe to set; call them once
  during single-threaded init, before spawning workers.

### Implementation notes

- The two configuration values (`pjg_inter_file_threads`,
  `pjg_intra_file_threads`) are INTERN globals, not THREAD_LOCAL.
  This is required so workers spawned by `pjglib_convert_batch` see
  the same configuration as the calling thread (a worker that
  inherits a default TL value of 0 would auto-resolve to SFTH=ON
  and produce different .pjg bytes than the caller expected).
  Setting them is documented to be single-threaded, so no
  synchronization is needed.
- Each call to `pjglib_convert_stream2mem` resolves
  `pjg_intra_file_threads` once at entry and copies the resulting
  boolean into the THREAD_LOCAL `sfth_mode` flag that the existing
  `par_pre_pack()` machinery already reads. Zero changes to the
  intra-file parallelism code path.
- `pjglib_convert_batch` uses a `std::thread` pool, not `std::async`
  + `std::future`, because the per-op result map is keyed by the
  original op index (workers steal jobs out of order).

### Tests

- **New `source/test/lib_batch_test.cpp`** — sweeps
  `inter ∈ {1,2,4}` × `intra ∈ {off,on}` against two baselines
  (one per intra setting) and asserts each `.pjg` is byte-exact
  with its single-file counterpart. Also asserts round-trip back
  to the original JPEG. Total run time ~80 ms on a 4-core host.
- `lib_concurrent_test` re-run with the new auto-SFTH-on default:
  4 host threads × 50 iters × 5 JPEGs = 200 ops, 0 mismatches.
- `lib_roundtrip_test` unchanged, still byte-exact on the test
  corpus.
- **New `source/test/lib_filemode_test.cpp`** — regression test for the
  file→file batch path with `out_dest == NULL`: compresses to sibling
  `.pjg`, decompresses back, and asserts the `.pjg` is left intact and
  the reconstructed `.jpg` is byte-exact. Locks in the extension-
  direction fix above.

### Windows DLL

- **`source/Makefile` `dll` target now produces a self-contained DLL.**
  libgcc / libstdc++ / winpthread are statically linked, so the shipped
  `packJPG.dll` depends only on `KERNEL32.dll` + `msvcrt.dll` and can be
  dropped next to a host `.exe` on a clean Win7/Win10 box.
- **The DLL must be cross-compiled with the MinGW *posix* thread model**
  (`make dll CXX=x86_64-w64-mingw32-g++-posix`). The codec's
  `thread_local` objects with non-trivial destructors crash
  (`0xC0000005`) at process exit under the win32 thread model — the
  conversion succeeds, then the host faults on teardown. The `dll`
  target now hard-fails if a win32-model compiler is passed.
- `packjpgdll.h` (the `__declspec(dllimport)` header for MSVC consumers)
  updated to declare the full v4.0e API — the threading setters,
  `pjglib_suggest_batch_threads`, `pjglib_convert_batch` and the
  `pjglib_batch_io` struct — plus a `<stdbool.h>` shim and `extern "C"`
  guard. A `packJPG.def` is shipped so MSVC users can generate a native
  import lib (`lib /def:packJPG.def`).
- Verified on real VMs (Win10 x64, Win7 x64, Win7 x86): batch compress +
  per-file round-trip 5/5 byte-exact, exit 0; forced MT (4 batch
  workers × 3 intra threads) stable across repeated runs.

### Unix shared library (.so)

- **New `source/Makefile` `so` target** → `libpackJPG.so`, the native
  Linux/macOS shared object exposing the same C-linkage API as the
  Windows DLL. Built with `-fPIC -fvisibility=hidden` and a new
  `BUILD_SO` define that tags the `pjglib_*` entry points with default
  ELF visibility, so the `.so` exports exactly the 12 public symbols and
  nothing else. Verified by both direct linking and `dlopen`/`dlsym`
  (plugin-style) loading; round-trip 5/5 byte-exact.

### Build / CI

- `source/Makefile`: new `lib-tests` target builds all three
  lib harnesses.
- `.github/workflows/cross-platform.yml`: builds and runs
  `lib_batch_test` and `lib_concurrent_test` on every push
  (macOS Intel, macOS ARM, Linux x64, Linux ARM64).
- `.github/workflows/ci.yml`: adds a `lib_batch_test` smoke step
  on the Ubuntu CI matrix.
- Docs: `README.md` gains a "Library / DLL API" section with
  embedding example and threading contract.

### Migration notes

- **Existing v4.0d lib consumers:** your code keeps working
  unchanged. Calls now use 3 cores per convert instead of 1 (no
  behavioral change beyond speed). If you need to keep the old
  single-threaded behavior, call
  `pjglib_set_intra_file_threads(1)` once during init.
- **Format compatibility:** unchanged. v4.0e reads and writes the
  same `.pjg` format as v4.0b/c/d. Existing v4.0-line binaries
  decode v4.0e output transparently.
- **v3.1d callers:** unchanged from v4.0b — v3.1d binaries cannot
  decode v4.0e output. Keep an old v3.1d binary on hand for
  legacy archives.

---

## v4.0d (2026-05-06) — speed update for the v4.0 LTS

> Speed update for the v4.0 LTS line. Format unchanged from v4.0c —
> `.pjg` output is byte-exact, full backward compatibility with all
> v4.0/4.0a/4.0b/4.0c streams.
>
> 1. **Link-Time Optimization** — `-flto` added to default build flags.
>    Cross-translation-unit inlining of small accessors.
>
> 2. **Branch hints** on the arithmetic-coder hot path. New `PJG_LIKELY`
>    / `PJG_UNLIKELY` macros (gcc/clang `__builtin_expect`, MSVC fallback)
>    annotate the non-escape branch in `convert_int_to_symbol` and the
>    escape branch in `convert_symbol_to_int`.
>
> 3. **New `make pgo` target** — two-phase profile-guided build:
>    Phase 1 compiles with `-fprofile-generate`, runs an encode + decode
>    workload, and emits `.gcda` profile data. Phase 2 rebuilds with
>    `-fprofile-use` linking the profile. Override `PGO_WORKLOAD` to
>    point at a richer corpus.
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
