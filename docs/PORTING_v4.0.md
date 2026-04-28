# packJPG v4.0 — porting notes (macOS / ARM64 / other platforms)

Status: **audit only**. v4.0-β has been built and validated on Linux x64
(g++ 14.2). macOS and ARM64 are unverified by measurement; this document
records what is expected to work, what is known to need attention, and
what hasn't been checked.

## Endianness

The PJG container is byte-oriented. Everything that needs to fit in more
than one byte is serialised explicitly little-endian by byte-shifting,
not by memcpy of a word:

- `hle[4] = { (uint8_t)hsz, (uint8_t)(hsz>>8), (uint8_t)(hsz>>16),
  (uint8_t)(hsz>>24) }` at `source/packjpg.cpp:4278` (sfth header size)
- component size array at `source/packjpg.cpp:4322`
- matching byte-shift reconstruction at `source/packjpg.cpp:4503`, `4525`

The arithmetic coder in `source/aricoder.cpp` works bit-by-bit through
`ArithmeticBitWriter::write_bit<0/1>()`; state is held in explicitly-
sized `uint32_t` variables (`CODER_USE_BITS = 31`,
`CODER_LIMIT100 = 1 << 31`). No `reinterpret_cast<uint32_t*>(byte_ptr)`,
no `memcpy` of multi-byte words into the file stream, no `htonl` /
`ntohl` / `bswap` calls in the compression path.

JPEG segment length reads (`(segment[2] << 8) | segment[3]`) are explicit
big-endian byte extraction from the JPEG side of the pipeline (JPEG
markers are network-order per the spec). These are also endian-clean
regardless of host byte order.

Conclusion: v4.0 **should be endian-safe on big-endian and ARM little-
endian hosts without modification.**

## 64-bit `long` vs 32-bit `long` (LP64 vs LLP64)

Sizes and offsets in the hot path use `int64_t` / `size_t`:

- `jpgfilesize`, `pjgfilesize` were migrated to `int64_t` in v3.0
- Windows `FileReader` / `FileWriter` use `_fseeki64` / `_ftelli64` (v3.1a+)
- MemoryReader/MemoryWriter use `size_t`

One pre-existing minor: `source/packjpg.cpp:8574` inside `list_pjg`
(CLI-only, excluded from `BUILD_LIB`) casts file size to `long` for display
purposes. On LP64 hosts (Linux x64, macOS x64, macOS ARM64, Linux ARM64)
`long` is 64-bit and this is correct. On LLP64 (Windows MSVC 64-bit) `long`
is 32-bit and the display truncates >2 GB; not new in v4.0 and not a
correctness issue for compression/decompression.

## Strict alignment (ARM, SPARC)

No packed structs, no pragma-pack directives, no casts of unaligned byte
pointers to wider integer types in the encoder/decoder. The model
vectors in `aricoder.h` are `std::vector<uint32_t>` / `std::vector<uint16_t>`
which are always naturally aligned. Safe on strict-alignment CPUs.

## Threading primitives

The v4.0 sequential path uses `std::async` + `std::future`. The `-sfth`
path uses the existing thread pool. No OS-specific threading code on the
Unix path (`source/packjpg.cpp` under `#ifdef UNIX` uses pthreads through
the C++ standard library). Should port directly to macOS and Linux-ARM64
with the system libc++ / libstdc++.

Windows XP (`sourcelegacy/`) uses Win32 `CreateThread` and is unaffected by
v4.0's new changes on non-Windows platforms.

## Build system status

- `source/Makefile` — Linux x64 + mingw cross builds. Verified on v4.0-β.
- `source/Makefile_osx` — **stale**. Dates to 2014, still specifies
  `-std=c++14` and doesn't know about `lib` / `dll` targets or about the
  v4.0 `std::async` / `std::filesystem` usage. Will need a refresh for
  v4.0 macOS builds: bump to `-std=c++17`, add `-lpthread`, drop the
  `-lstdc++fs` link flag (C++17 folds filesystem into libstdc++ / libc++).
- No ARM64 Linux target. Easy to add: it's the default Makefile with a
  `-target aarch64-linux-gnu` clang invocation, once the sysroot is on
  the build host.

## Untested on this machine

- macOS Intel / Apple Silicon: no SDK, no cross toolchain.
- Linux ARM64: no `aarch64-linux-gnu-g++` installed.
- Big-endian hosts (ppc64be, s390x): unchanged since pre-v4.0; endian
  audit above suggests safe, but not measured.

## Recommended verification before tagging v4.0 stable

1. macOS Apple Silicon native build (`clang -std=c++17 -O3`, `-lpthread`)
   with full corpus round-trip.
2. Linux ARM64 build (same) with full corpus round-trip; also run
   `lib_roundtrip_test` to exercise the library path.
3. Make sure existing v3.1d PJGs produced on Linux x64 decode to
   byte-identical JPEGs on macOS ARM64 (cross-platform archive
   compatibility).
4. Refresh `source/Makefile_osx` and consider adding an ARM64 target to
   `source/Makefile`.

None of these are expected to uncover issues based on the code audit, but
"expected" is not "measured".
