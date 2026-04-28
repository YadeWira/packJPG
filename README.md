# packJPG Multi-threaded

packJPG is a lossless JPEG compression program. It compresses JPEG files
to the PJG format and decompresses them back with bit-for-bit identical
reconstruction. Typical file size reduction: ~20%.

**Supported platforms:** Linux x64, Windows 10/11 x64, Windows XP / Vista / 7 / 8 (x86 + x64, community-maintained).


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

Download the latest binary from the [Releases](https://github.com/YadeWira/packJPG/releases) page:

| File | Target |
|---|---|
| `packJPG_win_x64.exe` | Windows 10/11 64-bit (also runs on Win7/8 x64 without ANSI colors) |
| `packJPG_win_legacy_x64.exe` | Windows XP x64 / Vista / 7 / 8 — 64-bit (community-maintained) |
| `packJPG_win_legacy_x86.exe` | Windows XP / Vista / 7 / 8 — 32-bit (community-maintained) |


## Usage

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

packJPG recognizes file types by content, not extension. Files that are
neither JPEG nor PJG are silently skipped. Wildcards (`*.jpg`, `*.*`)
and drag-and-drop work; on Windows, wildcard expansion is handled
internally because `cmd.exe` doesn't expand them.

In default mode files are never overwritten — packJPG appends underscores
to make a fresh name. Pass `-o` to overwrite. Directories are silently
ignored unless `-r` is given.

If `"-"` is used as a filename, input is read from stdin and output is
written to stdout (handy for piping through `jpegtran` etc.).

### Examples

```
packJPG a *.jpg                       # compress everything in cwd
packJPG a -th0 -o -np -odout/ *.jpg   # all cores, overwrite, no pause, output to dout/
packJPG a -r photos/                  # recurse into photos/
packJPG x *.pjg                       # decompress
packJPG mix *.*                       # auto-detect each file
packJPG list *.pjg                    # show version + size, no decompress
packJPG - < sail.pjg > sail.jpg       # stream
```

### `mix` — mixed mode

Auto-detects each file and compresses or decompresses accordingly.

> **Warning:** running `mix` on a folder that was already compressed
> will decompress the PJG files back, undoing previous work. A summary
> warning is printed at the end if both directions were used.

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
  version : v4.0b
  packed  : 288.1 KB

photos/lena_fast.pjg         (compressed with -sfth)
  version : v4.0b (parallel)
  packed  : 288.2 KB
```


## Command-line switches

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

### `-p` / `-d` / `-ver` — what they trade off

By default packJPG cancels on warnings to guarantee bit-exact round-trip.

* `-p` accepts non-spec-compliant JPEG quirks (inefficient Huffman
  tables, RST marker mismatches, padding-bit deviations, EOI garbage).
  The reconstructed JPEG will be **visually identical but may not be
  byte-equal** to the original.
* `-d` discards meta-info (EXIF, JFIF comments, etc.) for smaller
  output. Reconstruction is no longer byte-equal.
* `-ver` does a full encode → decode → byte-compare per file. Files
  that fail verification are not written.

`-ver` should never be combined with `-p` or `-d` — those flags
intentionally drop byte-equality, so verification will always fail.


## Threading

packJPG has two orthogonal threading modes that compose:

| Flag | Granularity | Effect |
|---|---|---|
| `-th<n>` | across files | run N files in parallel, each on 1 thread |
| `-sfth` | within a file | encode Y/Cb/Cr in parallel (3 threads) |
| `-th<n> -sfth` | both | run N files in parallel, each using 3 threads |

### `-th<n>` (multi-file batch)

`-th0` auto-detects core count. In MT batch mode, **verification is
forced on automatically** — every file is encode→decode→compared
before the output is committed.

Optimal usage on a machine with N threads:

```
packJPG a -th$((N/3)) -sfth -o -np *.jpg
```

This fills all N cores: `N/3` files in parallel, each using 3 threads.
On an 18-core box: `-th6 -sfth` = 6 × 3 = 18 threads.

**Ctrl+C behavior.** On `source/` builds (Linux + Windows 10/11 x64),
Ctrl+C in MT batch stops workers cleanly and removes any partial output
files. On `sourcelegacy/` builds (Windows XP/Vista/7/8), Ctrl+C
terminates the process abruptly — partial output files may be left
behind. Clean up manually if interrupted.

### `-sfth` (single-file parallel)

Standard packJPG processes the components of a JPEG (Y, Cb, Cr)
sequentially. `-sfth` runs them concurrently. Useful even on a single
file, unlike `-th` which only helps for batches.

```
without -sfth :  0.23 s   1.81 MB/s   ratio 67.29 %
with    -sfth :  0.16 s   2.54 MB/s   ratio 67.30 %
```

The 0.01 % ratio difference is the documented cost of giving each
component its own arithmetic-coder context. Files remain fully
lossless. A warning is shown if `-sfth` is used on fewer than 3 cores.


## Other modes

### `-dry` — dry run

Simulates processing without writing any output. Useful to preview
ratios before committing to a batch.

```
packJPG a -dry -np *.jpg
packJPG a -dry -th0 -np *.jpg
```

### `-module` — machine-friendly output

Single-line output: `OK <seconds>` or `ERROR <code> <seconds>`.

```
packJPG a -module -np file.jpg  ->  OK 0.72
packJPG a -module -np bad.jpg   ->  ERROR 1 0.00
```

### FreeArc integration

packJPG works as an external compressor in FreeArc, acting as a JPEG
preprocessor. FreeArc processes one file at a time in this mode, so
`-sfth` is the right flag — `-th` is a no-op here.

`arc.ini`:

```ini
[External compressor:jpg]
packcmd   = packjpg a -sfth -module -np -o $$arcdatafile$$.jpg
unpackcmd = packjpg x -sfth -module -np -o $$arcdatafile$$.pjg
datafile   = $$arcdatafile$$.jpg
packedfile = $$arcdatafile$$.pjg
solid = 0
```

Then:

```
arc a -m"jpg" archive.arc *.jpg
```


## Format and versioning policy

Starting at v4.0b, packJPG separates **target platform** from **on-disk
format**:

| Source tree | Target platforms | Format produced |
|---|---|---|
| `source/` | Linux, macOS, Windows 10/11 | byte `0x28` + sub-marker `0x02` |
| `sourcelegacy/` | Windows XP / Vista / 7 / 8 (x86 + x64) | byte `0x28` + sub-marker `0x02` (full v4.0b parity) |

Both trees produce the same `.pjg` format — files are interchangeable
between them.

**Version numbering:**

* **N.0x releases** (`4.0`, `4.0a`, `4.0b`, …) are LTS-style. Binary
  filename `packJPG`. Bug-fix only after the initial drop.
* **N.Mx releases** (`4.1`, `4.1a`, `4.2`, …) are feature-bearing.
  Binary filename `packJPG-N.Mx`. Format breaks land here.

v4.0b is a one-time exception — it carries the diagonal-DC change
originally tagged as the unreleased v4.1, rebranded so the v4.1 slot
stays available for a real feature drop.

**Compatibility matrix:**

| File version | Decoded by v4.0b | Decoded by v4.0/v4.0a | Decoded by v3.1d |
|---|---|---|---|
| v4.0b | ✅ | ❌ (clean error) | ❌ |
| v4.0/v4.0a | ✅ (transparent) | ✅ | ❌ |
| v3.1d | ❌ | ❌ | ✅ |

v4.0b decoders read v4.0/v4.0a files transparently. v3.1d files are
no longer decoded — keep an old binary on hand if you have v3.1d
archives.


## Legacy Windows build (community-maintained)

The `sourcelegacy/` directory contains the legacy-Windows port for both
x86 and x64. Compiled with C++14 and Win32 API in place of
`std::filesystem` (`xp_compat.h` provides the shim layer). Both
single-file parallel compression (`-sfth`) and multi-file batch threading
(`-thN`) work natively via `CreateThread` + `CRITICAL_SECTION` +
`InterlockedIncrement` — no C++17 `<thread>`/`<future>` needed.

As of v4.0b, `sourcelegacy/` is at full feature parity with `source/`
(diagonal DC neighbor context, `0x02` sub-marker, single accepted
format byte, MT batch with auto-verify).

> **Warning:** The upstream maintainer does not own legacy-Windows test
> hardware — `sourcelegacy/` is validated only via Wine cross-runs
> against `source/`. Real XP / Vista / 7 / 8 hardware testing is not in
> the upstream loop, so platform-specific regressions may slip through.
> Bug reports with self-contained reproduction steps on real hardware
> are welcome.

To build from `sourcelegacy/`:

```
make        # -> bin/packJPG_win_legacy_x86.exe + bin/packJPG_win_legacy_x64.exe
make x86    # -> x86 only
make x64    # -> x64 only
make dev    # -> bin/packJPG_win_legacy_x86_dev.exe (with developer functions)
```

Requires `i686-w64-mingw32-g++` and `x86_64-w64-mingw32-g++` (mingw-w64 package).

### Maintainers wanted

The legacy build needs a maintainer who runs Windows XP, Vista, 7, or 8
(real hardware or VM) and is willing to:

* **Test releases** before they go out — at minimum, a self round-trip
  on a few JPEGs and a sanity check that the binary launches without
  missing-DLL errors.
* **Triage legacy-only bugs** filed against `sourcelegacy/`.
* **Port new features** from `source/` when they land.

If interested, open an issue titled `legacy-maintainer: <handle>` with
the Windows version(s) you can cover and the scope you're up for.
Maintainers get direct credit in `CHANGELOG.md` and the README, plus
fast-track review on legacy-only PRs.


## Building from source

### Prerequisites

| Target | Compiler |
|---|---|
| Linux x64 | `g++` ≥ 13 or `clang++` ≥ 18 (C++17) |
| Windows x64 | `x86_64-w64-mingw32-g++` |
| Windows legacy x86 (XP/Vista/7/8) | `i686-w64-mingw32-g++` (C++14 mode) |
| Windows legacy x64 (XP/Vista/7/8) | `x86_64-w64-mingw32-g++` (C++14 mode) |

On Debian/Ubuntu:
```
sudo apt install build-essential mingw-w64
```

### Build scripts

| Script | What it builds |
|---|---|
| `build_all.sh` | All targets: Linux x64, Windows x64, Windows legacy x86 + x64 |
| `build_legacy.sh` | Windows legacy x86 + x64 only |
| `build_pkg.sh` | Linux packages: `.tar.gz`, `.deb`, `.rpm`, `.snap` |

```bash
bash build_all.sh              # all binaries → dist/
bash build_legacy.sh           # legacy only
bash build_pkg.sh              # all packages
bash build_pkg.sh --deb --rpm  # selected formats only
```

Outputs in `dist/`:

```
dist/packJPG_linux_x64
dist/packJPG_win_x64.exe
dist/packJPG_win_legacy_x86.exe
dist/packJPG_win_legacy_x64.exe
dist/packjpg-<ver>-linux-x64.tar.gz
dist/packjpg_<ver>_amd64.deb
dist/packjpg-<ver>-1.x86_64.rpm
```

`build_pkg.sh` derives `<ver>` from `source/packjpg.cpp` automatically —
no manual version bump per release.


## Known limitations

packJPG is a JPEG-only compressor. Other file types are silently
skipped.

packJPG has low error tolerance compared to typical image viewers — it
needs to understand the JPEG bitstream deeply enough to re-compress the
DCT coefficients, and rejects files it can't perfectly reconstruct.
The most common quirks that trigger warnings (and how `-p` works around
them):

* **Inefficient Huffman coding** — last AC coefficient in a block is
  zero. Technically valid; not bit-exact reconstructable without `-p`.
* **Incorrect RST markers** — wrong positions or counters. Other
  decoders ignore them; packJPG validates.
* **Inconsistent padding bits** — spec says 1-bits, some encoders
  write 0-bits.
* **Garbage data after EOI**.

With `-p`, packJPG accepts these and compresses anyway. The
reconstructed image is visually identical but not necessarily
byte-equal. This is why `-p` is incompatible with `-ver`.

Compressed `.pjg` files are not always cross-version compatible — see
the **Format and versioning policy** section for the matrix. Older
binaries (v3.x and earlier) are available at
https://github.com/packjpg/packJPG.

On Windows, dragging too many files at once may show a missing-privileges
error. Use the command line instead.


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


## History

See [CHANGELOG.md](CHANGELOG.md) for the full version history.


## Acknowledgements

packJPG started as Matthias Stirner's final-year project at Hochschule
Aalen, with extensive support from Prof. Dr. Gerhard Seelmann in the
field of data compression.

Logo and icon designed by Michael Kaufmann.


## Contact

* **Repository:** https://github.com/YadeWira/packJPG
* **Issues:** https://github.com/YadeWira/packJPG/issues
* **Discussion thread (encode.su):** https://encode.su/threads/4482-packJPG-Multi-threaded
* **Support:** https://www.patreon.com/YadeWira
* **Original developer blog:** http://packjpg.encode.ru/
