# packJPG Multi-threaded

packJPG is a lossless JPEG compression program. It compresses JPEG files
to the PJG format and decompresses them back with bit-for-bit identical
reconstruction. Typical file size reduction: ~20%.

**Supported platforms:** Linux x64, Windows 7 and later (x86/x64).


## Installation

### Linux (one-liner)

```bash
curl -sL https://raw.githubusercontent.com/YadeWira/packJPG/master/install.sh | bash
```

On **Debian/Ubuntu**, this sets up the apt repository so future updates
arrive via `apt upgrade`. On other distros it installs from the latest
GitHub release directly.

#### Debian/Ubuntu — apt repository (manual setup)

```bash
curl -fsSL https://raw.githubusercontent.com/YadeWira/packJPG/master/packjpg.gpg \
  | sudo tee /etc/apt/trusted.gpg.d/packjpg.asc > /dev/null

echo "deb https://yadewira.github.io/packJPG stable main" \
  | sudo tee /etc/apt/sources.list.d/packjpg.list

sudo apt update && sudo apt install packjpg
```

### Windows

Download the latest `.exe` from the [Releases](https://github.com/YadeWira/packJPG/releases) page:

| File | Target |
|---|---|
| `packJPG_win_x64.exe` | Windows 10/11 64-bit (Win7/8 works without ANSI colors) |
| `packJPG_win_legacy_x64.exe` | Windows XP x64 / Vista / 7 / 8 — 64-bit (experimental) |
| `packJPG_win_legacy_x86.exe` | Windows XP / Vista / 7 / 8 — 32-bit (experimental) |


## Format policy and version layout (v4.0b+)

Starting at v4.0b, packJPG separates **target** from **format**:

| Directory | Target platforms | Maintained by | Format |
|---|---|---|---|
| `source/` | Windows 10+, Linux, macOS | upstream | byte `0x28` + sub-marker `0x02` (v4.0b features) |
| `sourcelegacy/` | Windows XP SP2+, Windows 7, Windows 8 (x86 + x64) | community best-effort, no SLA | byte `0x28` + sub-marker `0x02` (v4.0b features, ported) |

**Why the split.** `source/` uses C++17 `std::filesystem`, which has known
correctness issues on Windows XP and Windows 7 (intermittent `0.00 %` ratio
display and accented-path bugs reported on encode.su). `sourcelegacy/`
keeps a parallel codebase using Win32 native API
(`GetFileAttributesEx`, `FindFirstFileW`, etc.) via `xp_compat.h`, which
is correct on every Windows from XP SP2 onward. This split was previously
implicit (`source4xp/` for "Windows XP only"); v4.0b makes it explicit
and renames it to `sourcelegacy/` to reflect that it covers Win7/Win8 too.

**Versioning policy.** Going forward:

- **N.0x releases** (`4.0`, `4.0a`, `4.0b`, `4.0c`, …) are LTS-style,
  binary filename `packJPG`. Bug-fix only after the initial feature
  drop, except v4.0b which is a one-time rebrand of the unreleased v4.1
  diagonal-DC change.
- **N.Mx releases** (`4.1`, `4.1a`, `4.2`, …) are feature-bearing,
  binary filename `packJPG-N.Mx`. Format breaks land here.

**Format break in v4.0b.** v4.0b introduces a sub-marker (`0x02`) before
the version byte to flag the new diagonal DC neighbor context inherited
from the unreleased v4.1 work. The `-legacy` flag (which previously
emitted v3.1d-compatible output) was removed — v4.0b is the clean
starting point of the new lineage.

- v4.0b decoders **read v4.0/v4.0a files transparently** (no sub-marker
  → diag DC off, decoder behaves exactly like v4.0a).
- v4.0/v4.0a decoders **reject v4.0b files cleanly** with
  `"unknown header code, use newer version of packjpg"` — no silent
  corruption.
- v3.1d files (legacy from packJPG 3.x line) are no longer decoded by
  v4.0b. Users with v3.1d archives need to keep an older binary
  (v3.1d, v4.0, or v4.0a) on hand.

**Bench (43 mixed JPGs, 10.86 MB).** Diagonal DC ctx delivers a small but
consistent ratio win without speed regression:

| Variant | Output | Ratio | Time |
|---|---|---|---|
| v4.0a | 6,730,670 B | 65.574 % | 12.09 s |
| **v4.0b** | **6,727,753 B** | **65.566 %** | **12.02 s** |

Δ: −0.043 % bytes, 0.994× wall time, all round-trips byte-exact.

### Windows XP / Vista / 7 / 8 build (community-maintained)

The `sourcelegacy/` directory contains the legacy-Windows port for both
x86 and x64. Compiled with C++14 and Win32 API in place of
`std::filesystem` — `xp_compat.h` provides the shim layer. Both
single-file parallel compression (`-sfth`) and multi-file batch threading
(`-thN`) are supported via Win32 `CreateThread` + `CRITICAL_SECTION` +
`InterlockedIncrement` (no C++17 `<thread>`/`<future>` required).
As of v4.0b the legacy code is at full feature parity with `source/`
(diagonal DC neighbor context, `0x02` sub-marker, single accepted format
byte, MT batch with auto-verify).

> **WARNING:** This build is community-maintained best-effort. The
> upstream maintainer does not own legacy-Windows test hardware and
> validates the build only via Wine cross-runs against `source/`. Real
> XP / Vista / 7 / 8 hardware testing is not in the upstream loop, so
> regressions specific to those platforms may slip through. Bug reports
> with self-contained reproduction steps on real hardware are welcome
> and can be opened as issues on GitHub.

To build it, from `sourcelegacy/`:

```
make        # -> bin/packJPG_win_legacy_x86.exe + bin/packJPG_win_legacy_x64.exe
make x86    # -> bin/packJPG_win_legacy_x86.exe only
make x64    # -> bin/packJPG_win_legacy_x64.exe only
make dev    # -> bin/packJPG_win_legacy_x86_dev.exe (with developer functions)
```

Requires `i686-w64-mingw32-g++` and `x86_64-w64-mingw32-g++` (mingw-w64 package).

#### Maintainers wanted

The legacy build needs a maintainer who runs Windows XP, Vista, 7, or 8
(real hardware or VM) and is willing to:

- **Test releases** on actual legacy Windows before they go out — at
  minimum, a self round-trip on a few JPEGs and a sanity check that the
  binary launches without missing-DLL errors.
- **Triage legacy-only bugs** filed against `sourcelegacy/` (issues
  upstream cannot reproduce because they don't have the platform).
- **Port new features** from `source/` to `sourcelegacy/` when they
  land — typically format changes, new flags, or algorithm tweaks. Each
  port is a few discrete blocks (encoder, decoder, CLI) plus rebuilding
  the `xp_compat.h` shims if a `source/` change pulled in new C++17
  facilities.

If interested, open an issue titled `legacy-maintainer: <handle>` with
which Windows version(s) you can cover and which scope you're up for
(release testing only / bug triage / feature ports). Maintainers get
direct credit in CHANGELOG.md and the README, and can flag legacy-only
PRs for fast-track review.


## License

All programs in this package are free software; you can redistribute
them and/or modify them under the terms of the GNU Lesser General Public
License as published by the Free Software Foundation; either version 3
of the License, or (at your option) any later version.

The package is distributed in the hope that it will be useful, but
WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU Lesser
General Public License for more details at
http://www.gnu.org/copyleft/lgpl.html.

If the LGPL v3 license is not compatible with your software project you
might contact us and ask for a special permission to use the packJPG
library under different conditions. In any case, usage of the packJPG
algorithm under the LGPL v3 or above is highly advised and special
permissions will only be given where necessary on a case by case basis.
This offer is aimed mainly at closed source freeware developers seeking
to add PJG support to their software projects.

Copyright 2006...2014 by HTW Aalen University and Matthias Stirner.
Copyright 2006...2026 by Yade Bravo & Matthias Stirner.


## Usage

A subcommand is required to tell packJPG what to do:

```
packJPG <subcommand> [switches] [filename(s)]
```

### Subcommands

| Subcommand | Description |
|---|---|
| `a` | compress JPEG files to PJG (archive) |
| `x` | decompress PJG files back to JPEG (extract) |
| `mix` | auto-detect and process both directions (use with caution) |
| `list` | display info about PJG files without decompressing |
| `stats` | show JPEG file info (size, dimensions, color mode) without compressing |

packJPG recognizes file types by content, not by extension. Files that
are neither JPEG nor PJG are silently skipped.

packJPG supports wildcards like `*.jpg`, `*.*` and drag and drop of
multiple files. Filenames for output files are created automatically.
In default mode, files are never overwritten. If a filename is already
in use, packJPG creates a new filename by adding underscores.

On Windows, wildcard expansion is handled internally by packJPG since
`cmd.exe` does not expand wildcards automatically. Filenames with accented
or special characters are fully supported on Windows 7 and later.

Directories in the file list are silently ignored unless `-r` is given.
To recurse into subdirectories, pass the `-r` flag explicitly.

If `"-"` is used as a filename, input is read from stdin and output is
written to stdout. This can be useful if jpegtran is used as a
preprocessor.

### Usage examples

```
packJPG a *.jpg
packJPG a lena.jpg
packJPG a kodim??.jpg
packJPG x *.pjg
packJPG x -r archive/
packJPG mix *.*
packJPG list *.pjg
packJPG - < sail.pjg > sail.jpg
packJPG a -th0 -o -np -odout/ *.jpg
```


## CLI output

### Default (per-file table)

```
packJPG v3.1  •  by Yade Bravo

  ⠸  kodim01.jpg               ✓  kodim01.jpg                762 KB →   593 KB   77.8%   1.23s
  ⠸  kodim02.jpg               ✓  kodim02.jpg                768 KB →   619 KB   80.6%   1.31s
  ⠸  kodim03.jpg               ✓  kodim03.jpg                762 KB →   560 KB   73.5%   1.19s

3 file(s)  3 ok  0 error(s)  0 warning(s)
 compressed: 3 JPG
 ─────────────────────────────────────
 time      3.73 sec
 speed    601.58 MB/s
 ratio     77.30 %
 ─────────────────────────────────────
```

### Progress bar mode (`-vp`, recommended for large batches)

```
packJPG v3.1  •  by Yade Bravo

Using 4 of 4 detected thread(s) (verify enabled)
  ⠹  18 / 24  [████████████░░░░░░░░░░░░░░░░░░]

✓  24 / 24  [██████████████████████████████]

24 file(s)  24 ok  0 error(s)  0 warning(s)
 compressed: 24 JPG
 ─────────────────────────────────────
 time     28.41 sec
 speed    498.22 MB/s
 ratio     78.14 %
 ─────────────────────────────────────
```

### No-color mode (`--no-color`)

Colors are automatically disabled when stdout is not a terminal.
The `NO_COLOR` environment variable is also respected.
Pass `--no-color` explicitly to force plain output.


## Subcommands in detail

### `a` — compress (archive)

Processes JPEG files and compresses them to PJG. PJG files and
unrecognized file types are silently skipped.

```
packJPG a -th0 -o -np *.jpg
packJPG a -r -np photos/
```

### `x` — decompress (extract)

Processes PJG files and decompresses them back to JPEG. JPEG files
and unrecognized file types are silently skipped.

```
packJPG x -th0 -o -np *.pjg
packJPG x -r -np archive/
```

### `mix` — mixed mode

Auto-detects each file and compresses or decompresses accordingly.
Useful for folders containing both JPG and PJG files.

> **WARNING:** Running mix on a folder that was already compressed will
> decompress the PJG files back — potentially undoing previous work.
> A warning is printed at the end if both directions were used.

```
packJPG mix -o -np *.*
```

### `list` — list PJG info

Displays version and packed size for each PJG file without
decompressing it.

```
packJPG list *.pjg
packJPG list -r archive/
```

Output examples:

```
photos/lena.pjg
  version : v3.0
  packed  : 288.1 KB

photos/lena_fast.pjg         (compressed with -sfth)
  version : v3.0 (parallel)
  packed  : 288.2 KB
```


## Command line switches

| Switch | Description |
|---|---|
| `-ver` | verify files after processing |
| `-v?` | level of verbosity; 0, 1 or 2 (default 0) |
| `-vp` | progress bar mode (replaces per-file table) |
| `-np` | no pause after processing files |
| `--no-color` | disable ANSI color output (also respected via `NO_COLOR` env var) |
| `-o` | overwrite existing files |
| `-od<path>` | write output files to directory `<path>` (created if needed) |
| `-th<n>` | number of worker threads; 0 = auto-detect (default: 1) |
| `-sfth` | parallel single-file compression using 3 threads (Y/Cb/Cr) |
| `-r` | recurse into subdirectories |
| `-dry` | dry run: simulate without writing output files |
| `-module` | machine-friendly output: OK/ERROR + elapsed seconds |
| `-p` | proceed on warnings |
| `-d` | discard meta-info |

By default, compression is cancelled on warnings. If warnings are
skipped by using `-p`, most files with warnings can also be compressed,
but JPEG files reconstructed from PJG files might not be bitwise
identical with the original JPEG files. There won't be any loss to
image data or quality however.

Unnecessary meta information can be discarded using `-d`. This reduces
compressed files' sizes. Be warned though, reconstructed files won't be
bitwise identical with the original files and meta information will be
lost forever. As with `-p` there won't be any loss to image data or quality.

There is no known case in which a file compressed by packJPG (without
the `-p` option) couldn't be reconstructed to exactly the state it was
before. If you want an additional layer of safety you can also use the
verify option `-ver`. In this mode, files are compressed, then
decompressed and the decompressed file compared to the original file.
If this test doesn't pass there will be an error message and the
compressed file won't be written to the drive.

Please note that the `-ver` option should never be used in conjunction
with the `-d` and/or `-p` options, as those may lead to reconstructed
JPG files not being bitwise identical to the originals.


## Multi-threaded mode (`-th`)

The `-th<n>` switch enables parallel batch processing using n worker
threads. Use `-th0` to auto-detect the number of CPU cores (on x86
builds the auto limit is 2 to prevent out-of-memory errors with large
images; on x64 there is no cap).

In multi-threaded mode, verification is always enabled automatically:
each file is compressed and immediately decompressed and compared
bit-for-bit before the output is written. This ensures no silent
corruption can occur even under heavy parallel load.

Pressing Ctrl+C during multi-threaded processing stops all workers
cleanly, removes any partial output files, and prints a summary of
how many files were completed before the interrupt.

Single-threaded mode (default, no `-th` flag) behaves exactly as in
previous versions.


## Single-file parallel mode (`-sfth`)

Standard packJPG processes the components of a JPEG (Y, Cb, Cr)
sequentially — one after another in a single thread. The `-sfth` switch
changes this by encoding all three components simultaneously, each in
its own thread. This is fundamentally different from `-th`, which
parallelizes across files, not within a single file.

| Flag | Behavior |
|---|---|
| `-th<n>` | runs N files at the same time, each file uses 1 thread |
| `-sfth` | runs 1 file at a time, but splits it into 3 parallel threads |
| `-th<n> -sfth` | runs N files at the same time, each using 3 threads |

This means `-sfth` is useful even when processing a single file, while
`-th` only helps when processing multiple files in a batch.

**Benchmark on a single file (Intel Xeon E5-2697 v4):**

```
without -sfth :  0.23 sec  1.81 MB/s  ratio 67.29%
with    -sfth :  0.16 sec  2.54 MB/s  ratio 67.30%
```

The ratio difference (0.01%) comes from the fact that each component
uses its own independent arithmetic coder context. This is the expected
and documented behavior — files are still valid and fully lossless.

**Important notes:**
- Files compressed with `-sfth` use a new PJG format (0x01 marker).
  They require packJPG v3.0 or later to decompress.
- Files compressed without `-sfth` remain fully compatible with v2.x.
- A warning is shown if `-sfth` is used with fewer than 3 detected cores.

**Optimal usage for machines with N threads:**

```
packJPG a -th<N/3> -sfth -o -np *.jpg
```

This fills all N cores: N/3 files in parallel, each using 3 threads.
Example on an 18-core machine: `-th6 -sfth` = 6 × 3 = 18 threads.


## FreeArc integration

packJPG can be used as an external compressor in FreeArc, acting as a
JPEG preprocessor before FreeArc applies its own compression on top.
Since FreeArc processes one file at a time in this mode, `-sfth` is the
right flag to use here — `-th` would have no effect.

Add the following to your `arc.ini`:

```ini
[External compressor:jpg]
packcmd   = packjpg a -sfth -module -np -o $$arcdatafile$$.jpg
unpackcmd = packjpg x -sfth -module -np -o $$arcdatafile$$.pjg
datafile   = $$arcdatafile$$.jpg
packedfile = $$arcdatafile$$.pjg
solid = 0
```

Then use it when creating an archive:

```
arc a -m"jpg" archive.arc *.jpg
```

FreeArc will convert each JPEG to PJG before storing it, and
automatically convert back when extracting.


## Dry run mode (`-dry`)

The `-dry` switch simulates processing without writing any output
files. Useful for previewing compression ratios before committing
to a batch operation.

```
packJPG a -dry -np *.jpg       # preview ratios, no files written
packJPG a -dry -th0 -np *.jpg  # same, using all cores
```


## Module mode (`-module`)

The `-module` switch produces minimal machine-friendly output: a single
line with OK or ERROR and the elapsed time in seconds. Useful for
integration with external tools like FreeArc.

```
packJPG a -module -np file.jpg  ->  OK 0.72
packJPG a -module -np bad.jpg   ->  ERROR 1 0.00
```


## Known Limitations

packJPG is a compression program for JPEG files only. Other file types
are silently skipped.

packJPG has low error tolerance. JPEG files might not work with packJPG
even if they work perfectly with other image processing software. This
happens because packJPG needs to understand the internal structure of a
JPEG deeply enough to re-compress the DCT coefficients — it is more
strict than a regular image viewer that just renders the pixels.

**Common causes of warnings or errors that `-p` can work around:**

- **Inefficient Huffman coding:** some encoders generate Huffman tables
  where the last AC coefficient in a block is zero. Technically valid,
  but packJPG cannot reconstruct it bit-for-bit without `-p`.
- **Incorrect RST markers:** restart markers inserted at wrong positions
  or with wrong counters. Other decoders ignore them; packJPG counts
  and validates them.
- **Inconsistent padding bits:** bits used to fill the last byte of a
  Huffman scan. The spec requires 1-bits; some encoders write 0-bits.
- **Garbage data after EOI:** some files have extra bytes after the end-
  of-image marker. packJPG preserves them but may warn on edge cases.

With `-p`, packJPG accepts all these cases and compresses them anyway.
The reconstructed image will be visually identical but may not be
bit-for-bit equal to the original. For this reason, `-p` should never
be combined with `-ver`.

If you try to drag and drop too many files at once on Windows, there
might be a windowed error message about missing privileges. In that
case try again with fewer files or use the command prompt instead.

Compressed PJG files are not compatible between different packJPG
versions. You will get an error message if you try to decompress PJG
files with a different version than the one used for compression. You
may download older versions of packJPG from:
https://github.com/packjpg/packJPG

On 32-bit Windows builds (x86), the ratio and speed summary may display
as 0.00% and 0.00 MB/s. This is a display-only cosmetic issue — the
compressed files are valid and can be decompressed normally. It affects
the statistics output only and is caused by integer size limitations in
32-bit builds. Use `-th2` maximum on 32-bit to avoid out-of-memory errors
with large images.


## Building from source

### Prerequisites

| Target | Compiler |
|---|---|
| Linux x64 | `g++` ≥ 13 or `clang++` ≥ 18 (C++17) |
| Windows x64 | `x86_64-w64-mingw32-g++` |
| Windows legacy x86 (XP/Vista/7/8) | `i686-w64-mingw32-g++` (C++14 mode) |
| Windows legacy x64 (XP/Vista/7/8) | `x86_64-w64-mingw32-g++` (C++14 mode) |

On Debian/Ubuntu, install cross-compilers with:
```
sudo apt install build-essential mingw-w64
```

### Build scripts (project root)

| Script | What it builds |
|---|---|
| `build_all.sh` | All targets: Linux x64, Windows x64, Windows legacy x86 + x64 |
| `build_legacy.sh` | Windows legacy x86 + x64 only (XP/Vista/7/8) |
| `build_pkg.sh` | Linux packages: `.tar.gz`, `.deb`, `.rpm`, `.snap` |

```bash
bash build_all.sh              # all binaries → dist/
bash build_legacy.sh           # legacy only  → dist/packJPG_win_legacy_x86.exe + _x64.exe
bash build_pkg.sh              # all packages → dist/
bash build_pkg.sh --deb --rpm  # selected formats only
```

Output binaries are collected in `dist/`:
```
dist/packJPG_linux_x64
dist/packJPG_linux_x64_native   (optimized for this machine, do not distribute)
dist/packJPG_win_x64.exe
dist/packJPG_win_legacy_x86.exe
dist/packJPG_win_legacy_x64.exe
dist/packjpg-4.0b-linux-x64.tar.gz
dist/packjpg_4.0b_amd64.deb
dist/packjpg-4.0b-1.x86_64.rpm
```

**Legacy Windows (from `sourcelegacy/`):**
```
cd sourcelegacy/
make                  # bin/packJPG_win_legacy_x86.exe + bin/packJPG_win_legacy_x64.exe
```

Binaries are stripped automatically to reduce file size.


## History

See [CHANGELOG.md](CHANGELOG.md) for the full version history.


## Acknowledgements

packJPG is the result of countless hours of research and development. It
is part of Matthias Stirner's final year project for Hochschule Aalen.

Prof. Dr. Gerhard Seelmann from Hochschule Aalen supported the
development of packJPG with his extensive knowledge in the field of data
compression. Without his advice, packJPG would not be possible.

packJPG logo and icon are designed by Michael Kaufmann.


## Contact

- **Repository:** https://github.com/YadeWira/packJPG
- **Support:** https://www.patreon.com/YadeWira
- **Issues:** https://github.com/YadeWira/packJPG/issues
- **Original developer blog:** http://packjpg.encode.ru/

---
packJPG by Yade Bravo, 04/02/2026
