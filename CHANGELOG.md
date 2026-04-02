# packJPG Changelog

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
