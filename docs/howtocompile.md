# How to Compile packJPG

This document explains how to compile packJPG as an executable or as a
static/shared library. Requires a C++17 compliant compiler.

**Tested with:** clang 18, g++ 13.
**Supported targets:** Linux x64, Windows x64 (cross), Windows x86 (cross) — all Windows 7 SP1+.


## Quick build (all platforms at once)

From the `source/` directory, run:

```
./build_all.sh
```

This builds Linux x64, Windows x64, and Windows x86 binaries into
`bin/`. Requires clang++ (or g++) for Linux and mingw-w64 (**posix**
thread model, see below) for Windows targets.

```
# Ubuntu/Debian
sudo apt install clang mingw-w64

# Arch
sudo pacman -S clang mingw-w64-gcc
```

> **macOS is not a supported build host.** It was covered by the
> cross-platform CI workflow up to and including v5.0c, and removed after it:
> the Apple Silicon job had failed on every run for weeks while the rest of CI
> stayed green, so it verified nothing and hid its own breakage. The code is
> portable C++17 and probably still builds there (`brew install llvm
> mingw-w64` used to be the recipe), but nothing measures it, so no claim is
> made. The verified set is the **Supported targets** line at the top of this
> document, plus Linux ARM64, which CI builds and round-trip-checks.


## Compiling with make

Individual targets are available via the Makefile:

| Target | Description |
|---|---|
| `make` (or `make all`) | Linux x64 executable (default, portable) |
| `make linux-x64` | Linux x64 executable into `bin/` |
| `make win-x64` | Windows x64 executable (requires mingw-w64's posix thread model — used automatically, see below) |
| `make win-x86` | Windows x86 executable (requires mingw-w64's posix thread model — used automatically, see below) |
| `make all-platforms` | all three targets above |
| `make native` | Linux x64 with `-march=native -mtune=native` (max-perf, non-portable) |
| `make pgo` | two-phase profile-guided build (see below) |
| `make dev` | Linux x64 with developer functions (`DEV_BUILD`) |
| `make lib` | static library `packJPGlib.a` (`BUILD_LIB`) |
| `make so` | Unix shared object `libpackJPG.so` (`BUILD_LIB` + `BUILD_SO`, `-fPIC`) |
| `make dll` | Windows DLL `packJPG.dll` (`BUILD_DLL`; MinGW posix model required) |

The default compiler is clang++, with automatic fallback to g++. The
default build now includes `-flto` (link-time optimization) and branch
hints on the arithmetic-coder hot path — both are ratio-neutral
speedups introduced in v4.0d.

Compiler flags: `-O3 -Wall -funroll-loops -ffast-math -flto -std=c++17`


## Profile-guided optimization (PGO)

`make pgo` builds packJPG in two phases:

1. **Phase 1** — compile with `-fprofile-generate`, run an encode +
   decode workload to produce `.gcda` profile data.
2. **Phase 2** — rebuild with `-fprofile-use`, linking the profile data
   so the optimizer makes branch and inlining decisions guided by the
   actual hot paths of the workload.

The default workload directory is `../test-files`. Override
`PGO_WORKLOAD` to point at a richer corpus for better profile data:

```
make pgo PGO_WORKLOAD=/path/to/many/jpgs
```

Measured speedup on a representative 8.59 MB / 20-file corpus:
`-14.4 %` encode and `-11.9 %` decode vs the default v4.0d build,
ratio identical.


## Compiling as a static or shared library

Define `BUILD_LIB` when compiling to produce a library instead of an
executable. Define `BUILD_DLL` in addition for a shared library (DLL).

```
make lib    # static library (packJPGlib.a) — Linux/Windows
make so     # Unix shared object (libpackJPG.so) — Linux
make dll    # Windows shared library (packJPG.dll) — MinGW cross-compile
```

- `packjpglib.h` declares the public API for static-lib and `.so` use
  (works from C and C++; the `.so` exports only the `pjglib_*` symbols).
- `packjpgdll.h` declares the public API (`__declspec(dllimport)`) for
  MSVC consumers of the Windows DLL.
- The same C-linkage API is exposed by all three: the static `.a`, the
  Unix `.so`, and the Windows `.dll`.

### Cross-compiling for Windows — always use the posix thread model

**Every** Windows target (the DLL, and the win-x64/win-x86 CLI
executables) requires the *posix* thread-model mingw compiler, not the
plain/win32-model one — `win-x64`/`win-x86` already default to it
(`x86_64-w64-mingw32-g++-posix`/`i686-w64-mingw32-g++-posix`); the `dll`
target needs it passed explicitly since it shares plumbing with the
native Linux `lib`/`so` targets:

```
make dll CXX=x86_64-w64-mingw32-g++-posix   # x64
make dll CXX=i686-w64-mingw32-g++-posix     # x86
```

Two independent reasons the plain/win32-model alias is a portability
trap, found the hard way:

1. **The DLL crashes at exit.** The codec keeps per-thread state in
   `thread_local` objects with non-trivial destructors (`std::unique_ptr`,
   `std::string`). Under the MinGW **win32** thread model these
   destructors are torn down through a broken `__cxa_thread_atexit` path
   inside a DLL, so the process faults (`0xC0000005`) at exit *after*
   the first conversion — the conversion succeeds, then the host crashes
   on teardown. The **posix** model (winpthread-backed) tears them down
   cleanly. The `dll` target refuses to build with the win32 model.

2. **The plain alias doesn't compile `std::async`/`std::future` at all**
   on some distros' mingw-w64 packaging (Ubuntu 22.04's, notably — the
   headers declare `std::future` but the implementation is incomplete,
   a compile-time "declared but never defined" error) — affecting the
   win-x64/win-x86 CLI too, since the codec uses `std::async` for
   intra-file parallelism (`-sfth`).

The produced DLL is self-contained (libgcc / libstdc++ / winpthread are
statically linked; it depends only on `KERNEL32.dll` + `msvcrt.dll`),
and so are the win-x64/win-x86 CLI executables.

**A third, i686-specific gotcha** surfaced once the CLI also moved to
the posix model: on 32-bit Windows only, some vendored libjxl SIMD
dispatch teardown code (`enc_group.cc`, highway-based runtime
CPU-feature selection) faults during the same exit-time destructor
cascade — harmless to correctness (it happens strictly after all
compression/decompression work is done and flushed), but crashes the
process under Wine/Windows anyway. Worked around by calling
`std::_Exit()` at the end of `main()` on Windows builds, skipping the
destructor cascade entirely — see the comment at `main()`'s return in
`source/packjpg.cpp`.


## Compiling with developer functions

Define `DEV_BUILD` to include developer/debug functions in the executable.
Developer functions are not available in library builds.

```
make dev
```

See [developer.md](developer.md) for a description of the available developer switches.


## Preprocessor defines summary

| Define | Description |
|---|---|
| `BUILD_LIB` | required for static or shared library builds |
| `BUILD_DLL` | required additionally for Windows DLL builds (`__declspec(dllexport)`) |
| `BUILD_SO` | required additionally for Unix `.so` builds (default-visibility export attribute) |
| `DEV_BUILD` | includes developer/debug functions in the executable |
| `UNIX` | defined automatically by the Makefile for Linux builds |

---
packJPG by Yade Bravo, 05/06/2026
