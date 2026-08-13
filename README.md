# packJPG Multi-threaded

packJPG is a lossless JPEG compression program. It compresses JPEG files
to the PJG format and decompresses them back with bit-for-bit identical
reconstruction. Typical file size reduction: ~20%.

It also recompresses **JPEG-LS** (`.jls`) files, typically ~16% smaller —
see [JPEG-LS support](#jpeg-ls-support).

**Supported platforms:** Linux x64, Windows 7 SP1+ (x86 + x64).

**📖 [Wiki](https://github.com/YadeWira/packJPG/wiki)** — FAQ, troubleshooting, use cases, comparison with other tools, release archive.


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
| `packJPG_win_x64.exe` | Windows 7 SP1+ 64-bit (no ANSI colors before Windows 10) |
| `packJPG_win_x86.exe` | Windows 7 SP1+ 32-bit (no ANSI colors before Windows 10) |


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

packJPG recognizes file types by content, not extension: `.jpg`, `.jls`
(if built with JPEG-LS support) and `.pjg` are all detected by their
magic bytes regardless of what they're named. Files that are none of
these are silently skipped. Wildcards (`*.jpg`, `*.*`) and drag-and-drop
work; on Windows, wildcard expansion is handled internally because
`cmd.exe` doesn't expand them.

`-r` (directory recursion) is the one place extension *does* matter —
it only descends into files named `.jpg`/`.jpeg`/`.pjg`/`.jls`, since
walking every file in a tree and content-sniffing each one would be
needlessly slow.

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
  version : v4.0d
  packed  : 288.1 KB

photos/lena_fast.pjg         (compressed with -sfth)
  version : v4.0d (parallel)
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
| `-fs` | preserve the source folder structure under `-od` (use with `-r`); without it every output lands flat in the target directory |
| `-dry` | dry run: simulate without writing output files |
| `-module` | machine-friendly output: OK/ERROR + elapsed seconds |
| `-maxout<MB>` | when decoding, refuse to reconstruct a JPEG larger than `<MB>` megabytes (decompression-bomb guard; default 256 MB, 0 = unlimited) |
| `-p` | proceed on warnings |
| `-d` | discard meta-info |

Most of these switches — subcommands `a`/`x`/`list`, `-od`/`-r`/`-fs`/`-dry`/`-ver`/`-np`/`-o`/`-module`/`-th<n>`/`-v<n>` — follow a shared CLI convention coordinated with the sibling lossless-recompressor projects [packMP3](https://github.com/YadeWira/packMP3) and [packPNG](https://github.com/YadeWira/packPNG). Release binaries also share the `<name>_<platform>_<arch>[.exe]` naming pattern across all three.

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

`-th<n>` works on every release binary (Linux and Windows, both archs) —
one codebase (`source/`), real `thread_local`.

**Ctrl+C behavior.** Ctrl+C in MT batch stops workers cleanly and removes
any partial output files.

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
ratios before committing to a batch. The codec does all the work — the
per-file lines, sizes and ratios are the real ones — only the writer is
discarded, so the summary ends with an explicit marker (added in v5.0d,
before which a dry run's output was indistinguishable from a real one):

```
packJPG a -dry -np *.jpg
packJPG a -dry -th0 -np *.jpg
```

```
2 file(s)  2 ok  0 error(s)  0 warning(s)
 compressed: 2 JPG
 dry run: no output files were written
```

The machine-readable `-module` format is unaffected: a script that passes
`-dry` already knows it did.

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


## Library / DLL API

v4.0e adds a C-linkage library API for embedding packJPG into other
applications (archivers, image tools, webservers, etc.). Same `.pjg`
format as the CLI, with **multithreading enabled by default**.

### Building

```bash
cd source
make lib        # → packJPGlib.a   static lib (Linux/Windows)
make so         # → libpackJPG.so  Unix shared object (Linux)
make dll        # → packJPG.dll + libpackJPG.a (Windows; MinGW posix model)

# Static lib + tests
make lib-tests  # → test/lib_roundtrip_test, lib_concurrent_test, lib_batch_test
```

> **Windows builds — use the MinGW `-posix` driver, for the DLL *and* the
> static lib** (`make dll CXX=x86_64-w64-mingw32-g++-posix`, same for
> `make lib`). Both targets refuse to build under the win32 model. For the
> DLL the win32 model miscompiles the codec's `thread_local` destructors and
> the DLL faults at process exit. For the static lib it is worse, because
> there is no noisy failure: a thread-model mismatch between the `.a` and the
> host **links clean with exit 0** and then deadlocks on the first decode,
> process at ~0% CPU. **Consumers must build their own objects with `-posix`
> too** — a posix `.a` inside a win32 host is undetectable at link time. See
> the warning at the top of `packjpglib.h`. The produced DLL is
> self-contained (no external runtime DLLs).
>
> **Load the DLL before creating threads.** If `packJPG.dll` is loaded with
> `LoadLibrary` into a process whose threads already exist, and those
> pre-existing threads call the codec, the process hangs after the work
> completes, while thread-local storage is torn down — 6 of 6 runs on
> Windows 10 21H2 x64, not reproduced on Windows 7 SP1 x64. Threads created
> after the load are fine, and the static library is unaffected. Full
> scope, numbers and workarounds in `packjpglib.h`; reproducer in
> `source/test/dll-harness/`.

Header: `source/packjpglib.h`. Consumers `#include "packjpglib.h"` and
link against the static lib, the `.so`, or the DLL — the C-linkage API is
identical across all three. MSVC consumers can instead include
`packjpgdll.h` and generate an import lib from the shipped `packJPG.def`.

### Functions

| Function | Purpose |
|---|---|
| `pjglib_convert_stream2mem(in_buf, in_size, **out, *out_size, msg)` | Single-file convert (mem→mem) |
| `pjglib_convert_stream2stream(msg)` | Single-file convert (stdin→stdout) |
| `pjglib_convert_file2file(in, out, msg)` | Single-file convert (file→file) |
| `pjglib_init_streams(in_src, in_type, in_size, out_dest, out_type)` | Bind I/O streams for the next convert call |
| `pjglib_set_intra_file_threads(n)` | SFTH per-file parallelism (`0`=auto, `1`=off, `≥3`=on) |
| `pjglib_set_inter_file_threads(n)` | Batch parallelism across files (`0`=default 1, `≥1`=N workers) |
| `pjglib_suggest_batch_threads()` | Helper: returns `max(1, cores/3)` |
| `pjglib_set_max_output_size(n)` | Decompression-bomb guard: cap reconstructed-JPEG size (default 256 MB, `0`=unlimited) |
| `pjglib_convert_batch(ops, n_ops, msg)` | Convert N (in,out) pairs in parallel |
| `pjglib_version_info()`, `pjglib_short_name()` | Version metadata |

### Threading defaults (v4.0e)

- **Intra-file (SFTH)**: `auto` is **ON** if the host has ≥3 logical
  cores, OFF otherwise. To force OFF, call
  `pjglib_set_intra_file_threads(1)` once at startup. To force ON,
  call with `3` or higher.
- **Inter-file (batch)**: default is 1 worker. Use
  `pjglib_set_inter_file_threads(N)` to enable N workers for
  `pjglib_convert_batch`. `pjglib_suggest_batch_threads()` is a
  good default for filling all cores (`cores/3` so each worker can
  use 3 SFTH threads).
- **Setters are NOT thread-safe** — call them during single-threaded
  init, before spawning any workers.

### Example: archiver use case

```c
#include "packjpglib.h"
#include <stdio.h>
#include <stdlib.h>

int main(int argc, char** argv) {
    pjglib_set_inter_file_threads(pjglib_suggest_batch_threads());
    pjglib_set_intra_file_threads(0);  // 0 = auto SFTH

    pjglib_batch_io ops[argc-1];
    for (int i = 1; i < argc; i++) {
        ops[i-1].in_src   = argv[i];
        ops[i-1].in_type  = 0;  // file
        ops[i-1].in_size  = 0;
        ops[i-1].out_dest = NULL;  // lib writes sibling .pjg
        ops[i-1].out_type = 0;
    }
    char msg[PJG_MSG_SIZE] = {0};
    if (!pjglib_convert_batch(ops, argc-1, msg)) {
        fprintf(stderr, "batch failed: %s\n", msg);
        return 1;
    }
    return 0;
}
```

### Thread-safety contract

- Multiple host threads may call `pjglib_convert_stream2mem` etc.
  concurrently — the codec is THREAD_LOCAL-clean (validated by
  `lib_concurrent_test`).
- `pjglib_convert_batch` is the recommended path for parallelism
  across files; it manages worker threads internally.
- Memory outputs returned via `**out_file` are allocated with
  `malloc()` — free with `free()`, not `delete[]`.

### Decoding untrusted `.pjg` input

The decoder reconstructs whatever a `.pjg` describes, and a crafted/malformed
`.pjg` can expand a tiny input into a much larger JPEG (a "decompression bomb",
e.g. via a large trailing-garbage blob). This amplification vector is inherent
to lossless compression and is present in upstream packJPG too. The decode is
memory-safe and always terminates, but it is a resource-amplification vector.

**Two-layer defense (always active):**

| Layer | Mechanism | Default | What it catches |
|---|---|---|---|
| Absolute cap | `-maxout<N>` / `pjglib_set_max_output_size()` | 256 MB | Memory exhaustion from large legitimate or malicious JPEGs |
| Blowup ratio | built-in (not user-configurable) | 500× + 1 MB floor | Amplification attacks: tiny PJG → huge JPEG |

The blowup-ratio guard rejects any decode where the reconstructed JPEG exceeds
`input_pjg_size × 500 + 1 MB`. The 1 MB floor prevents false positives on tiny
legitimate files (a 100-byte PJG producing a 500 KB JPEG is fine). In practice
this catches 100% of bombs — the worst legitimate blowup is ~50×, while bombs
start at 1000×.

Both layers must pass. Decoding a `.pjg` that fails either guard fails cleanly
(returns false, fills `msg`) instead of producing the oversized output.

Hosts that need a different absolute limit can adjust it once at startup:

```c
pjglib_set_max_output_size(64u * 1024 * 1024);  // tighter: refuse >64 MB
pjglib_set_max_output_size(0);                  // disable absolute cap (ratio guard stays active)
```

CLI: `packjpg x -maxout64 file.pjg` (tighter) or `packjpg x -maxout0 file.pjg`
(disable absolute cap). The `-maxout` value is in megabytes; 0 means "no limit"
for the absolute cap only — the ratio guard cannot be disabled.


### v3.1d callers

The v4.0 line emits format `0x28 0x02` which is incompatible with
the v3.1d binary's `-legacy` path (which is gone since v4.0a). If
your downstream consumers have v3.1d-only decoders, hold off on
v4.0e until they're upgraded.


## Format and versioning policy

Starting at v4.0b, packJPG separates **target platform** from **on-disk
format**:

| Source tree | Target platforms | Format produced |
|---|---|---|
| `source/` | Linux x64, Linux ARM64, Windows 7 SP1+ (x86 + x64) | byte `0x28` + sub-marker `0x02` |

A single codebase now covers every platform — the former `sourcelegacy/`
(C++14, Win32-API-only) tree existed solely to support Windows XP, which
v5.0 dropped entirely; once Windows 7 became the floor, `source/`'s
C++17/`std::filesystem` code already worked there, making the second
codebase redundant (removed in v5.0c). v4.0c through v5.0 did not change
the on-disk format —
their `.pjg` output is byte-exact/interchangeable with v4.0b's (v5.0
was verified bidirectionally against v4.0f: each decodes the other's
output byte-exact for non-JPEG-LS content).

The platforms in that table are the ones CI builds and round-trip-verifies.
The code is portable C++17 and other Unix hosts (macOS among them) are
expected to build, but nothing measures it: macOS was covered by the
cross-platform workflow up to and including v5.0c, and removed after it
because the Apple Silicon job had failed on every run for weeks while the
rest of CI stayed green — a permanently red check verifies nothing and hides
its own breakage. Treat macOS as unsupported until someone measures it.

**Version numbering:**

* **N.0x releases** (`4.0`, `4.0a`, … `4.0f`) are LTS-style, bug-fix
  and additive-only (no format break). Binary filename `packJPG`.
* **N.Mx releases** (`4.1`, `4.1a`, `4.2`, …) are feature-bearing
  within the same major line. Binary filename `packJPG-N.Mx`. Format
  breaks land here, if any.
* **A major bump** (`4.0.x` → `5.0`) happens when several things
  converge into one release rather than trickling in as `N.Mx`/`N.0x`
  bumps: v5.0 dropped a previously-supported platform baseline
  (Windows XP) *and* shipped a security hardening pass *and* added a
  genuinely new capability (JPEG-LS) at the same time. Still **not**
  a format break by itself — see the compatibility matrix below. A
  major bump is a support-policy/scope signal, not a promise about the
  wire format; check the matrix, not the version number, for decode
  compatibility.

v4.0b was a one-time exception — it carried the diagonal-DC change
originally tagged as the unreleased v4.1, rebranded so the v4.1 slot
stayed available for a real feature drop. That feature drop ended up
being folded into v5.0 instead of shipping as v4.1, once the platform
and security changes above made a major bump the more honest signal.

**Compatibility matrix:**

| File version | Decoded by v5.0 | Decoded by v4.0e/f | Decoded by v4.0b/c/d | Decoded by v4.0/v4.0a | Decoded by v3.1d |
|---|---|---|---|---|---|
| v5.0 (non-JPEG-LS) | ✅ | ✅ (byte-exact) | ✅ (byte-exact) | ❌ (clean error) | ❌ |
| v5.0 (JPEG-LS) | ✅ | ❌ (clean error) | ❌ (clean error) | ❌ (clean error) | ❌ |
| v4.0e/v4.0f | ✅ (byte-exact) | ✅ | ✅ | ❌ (clean error) | ❌ |
| v4.0b/c/d | ✅ | ✅ | ✅ | ❌ (clean error) | ❌ |
| v4.0/v4.0a | ✅ (transparent) | ✅ (transparent) | ✅ (transparent) | ✅ | ❌ |
| v3.1d | ❌ | ❌ | ❌ | ✅ |

v4.0d decoders read v4.0/v4.0a/v4.0b/v4.0c files transparently. v4.0c
and v4.0d are byte-exact equivalents of v4.0b at the format level —
they share the same `0x02` sub-marker and version byte. v3.1d files
are no longer decoded — keep an old binary on hand if you have v3.1d
archives.


## Building from source

### Prerequisites

| Target | Compiler |
|---|---|
| Linux x64 | `g++` ≥ 13 or `clang++` ≥ 18 (C++17) |
| Windows x64 (Windows 7 SP1+) | `x86_64-w64-mingw32-g++-posix` |
| Windows x86 (Windows 7 SP1+) | `i686-w64-mingw32-g++-posix` |

The `-posix` (not plain/win32-model) mingw compiler variant is required:
the plain alias doesn't implement `std::async`/`std::future` at all on
some distros' mingw-w64 packaging (compile-time errors) — see
`source/winlibs/README.md` for the full story.

On Debian/Ubuntu:
```
sudo apt install build-essential mingw-w64
```

JPEG-LS support (see [JPEG-LS support](#jpeg-ls-support)) works out of
the box in a full checkout via the vendored static libs — no extra
packages needed. Only relevant for a stripped-down fork/checkout
missing `source/linuxlibs/`, as a Linux x64 dynamic-link fallback:
```
sudo apt install libcharls-dev libjxl-dev
```

### Build scripts

| Script | What it builds |
|---|---|
| `build_all.sh` | All targets: Linux x64, Windows x64, Windows x86 |
| `build_pkg.sh` | Linux packages: `.tar.gz`, `.deb`, `.rpm`, `.snap` |
| `build_lib_pkg.sh` | Library/SDK archives for embedders: Linux x64, win64, win32 |

```bash
bash build_all.sh              # all binaries → dist/
bash build_pkg.sh              # all packages
bash build_pkg.sh --deb --rpm  # selected formats only
bash build_lib_pkg.sh          # library/SDK archives
```

Outputs in `dist/`:

```
dist/packJPG_linux_x64
dist/packJPG_win_x64.exe
dist/packJPG_win_x86.exe
dist/packjpg-<ver>-linux-x64.tar.gz
dist/packjpg_<ver>_amd64.deb
dist/packjpg-<ver>-1.x86_64.rpm
dist/packJPG-<ver>-linux-x64-lib.tar.gz
dist/packJPG-<ver>-win64-lib.zip
dist/packJPG-<ver>-win32-lib.zip
```

`build_pkg.sh`/`build_lib_pkg.sh` derive `<ver>` from `source/packjpg.cpp`
automatically — no manual version bump per release. The win64/win32
library archives need mingw's posix-thread-model variant
(`x86_64-w64-mingw32-g++-posix`/`i686-w64-mingw32-g++-posix`, both part
of the `mingw-w64` package) — see the DLL thread-model warning above.


## JPEG-LS support

packJPG can also losslessly recompress **JPEG-LS** (`.jls`, ISO/IEC
14495, `SOF F7`) files — typically ~16% smaller, same `a`/`x` workflow
as regular JPEG, byte-for-byte reconstructable.

JPEG-LS's own entropy coding (Golomb-Rice) is already near-optimal, so
there's little to gain by re-encoding it directly. Instead packJPG
decodes to raw pixels, recompresses those losslessly with JPEG XL
(~16% smaller than the original JPEG-LS bytes), and on decompression
regenerates the *exact* original entropy bytes — this works because a
default-parameter JPEG-LS scan (`ILV=0`, `NEAR=0`) is fully
deterministic: the entropy bytes are a pure function of the pixels and
scan layout, with no encoder-side free choices. Scans that don't meet
this (interleaved, near-lossless) are detected and refused with a clear
error rather than silently producing lossy or non-reproducible output.

**Platform availability:**

| Build | JPEG-LS? | Notes |
|---|---|---|
| Linux x64 (`packJPG_linux_x64`) | ✅ | via vendored static libs (`source/linuxlibs/`), zero runtime deps |
| Windows x64 (`packJPG_win_x64.exe`) | ✅ | via vendored static libs (`source/winlibs/`) |
| Windows x86 (`packJPG_win_x86.exe`) | ✅ | via vendored static libs (`source/winlibs/`) |
| `packJPG.dll` / library SDK archives | ✅ | via the same `winlibs/` vendored set (posix thread model, shared with the CLI) |

No MinGW *packages* of CharLS/libjxl exist, and dynamically linking
against the system's `libcharls`/`libjxl` on Linux ties the binary's
runtime dependency to whichever SONAME the build machine happens to
have (this broke a `.deb` release once — see CHANGELOG v5.0b). Both
Windows and Linux builds instead link static libs cross-compiled/built
once and vendored under `source/winlibs/` and `source/linuxlibs/`
respectively — see their READMEs for the reproducible build recipes.
A `.pjg` produced from JPEG-LS still can't be decoded on a build that
lacks JPEG-LS support (clean error, not a crash).

### Building with JPEG-LS

```bash
cd source
make            # auto-detects source/linuxlibs/ (Linux) or falls back to
                 # a dynamic libcharls-dev/libjxl-dev probe if missing
make JLS=0      # force off — builds with zero extra dependencies

# Windows cross-compile (needs source/winlibs/, already vendored in a full checkout)
make win-x64    # auto-detects source/winlibs/x86_64/
make win-x86    # auto-detects source/winlibs/i686/

# packJPG.dll (needs source/winlibs/, same vendored set as the CLI —
# posix thread model, see source/winlibs/README.md)
make dll CXX=x86_64-w64-mingw32-g++-posix   # win64, auto-detects winlibs/x86_64/
make dll CXX=i686-w64-mingw32-g++-posix     # win32, auto-detects winlibs/i686/
```

`build_all.sh` does the same auto-detection for all release binaries.
Without the relevant vendored libs present, everything still builds —
`.jls` files are just skipped like any other unsupported file type.


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

This project would not exist without **Matthias Stirner**
([@packjpg](https://github.com/packjpg)), the original creator of
packJPG. He designed the algorithm, wrote the original C/C++
implementation, and maintained the upstream
[`packjpg/packJPG`](https://github.com/packjpg/packJPG) repository for
years. Everything in this fork — the modern C++ port, the multi-threaded
extensions, the v4.0 LTS line — builds on top of his work. Huge thanks
to him for releasing packJPG as open source so the project could keep
moving forward.

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
