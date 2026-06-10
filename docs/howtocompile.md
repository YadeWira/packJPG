# How to Compile packJPG

This document explains how to compile packJPG as an executable or as a
static/shared library. Requires a C++17 compliant compiler.

**Tested with:** clang 18, g++ 13.
**Supported targets:** Linux x64, Windows x64 (cross), Windows legacy x86/x64 (cross).


## Quick build (all platforms at once)

From the `source/` directory, run:

```
./build_all.sh
```

This builds Linux x64, Windows x64, and Windows legacy x86/x64 binaries
into `bin/`. Requires clang++ (or g++) for Linux and mingw-w64 for
Windows targets.

```
# Ubuntu/Debian
sudo apt install clang mingw-w64

# Arch
sudo pacman -S clang mingw-w64-gcc

# macOS
brew install llvm mingw-w64
```


## Compiling with make

Individual targets are available via the Makefile:

| Target | Description |
|---|---|
| `make` (or `make all`) | Linux x64 executable (default, portable) |
| `make linux-x64` | Linux x64 executable into `bin/` |
| `make win-x64` | Windows x64 executable (requires mingw-w64) |
| `make win-x86` | Windows x86 executable (requires mingw-w64) |
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
make lib    # static library (packJPGlib.a) — Linux/macOS/Windows
make so     # Unix shared object (libpackJPG.so) — Linux/macOS
make dll    # Windows shared library (packJPG.dll) — MinGW cross-compile
```

- `packjpglib.h` declares the public API for static-lib and `.so` use
  (works from C and C++; the `.so` exports only the `pjglib_*` symbols).
- `packjpgdll.h` declares the public API (`__declspec(dllimport)`) for
  MSVC consumers of the Windows DLL.
- The same C-linkage API is exposed by all three: the static `.a`, the
  Unix `.so`, and the Windows `.dll`.

### Cross-compiling the Windows DLL — use the posix thread model

When building `packJPG.dll` with MinGW-w64, you **must** use the *posix*
thread-model compiler, not the win32 one:

```
make dll CXX=x86_64-w64-mingw32-g++-posix   # x64
make dll CXX=i686-w64-mingw32-g++-posix     # x86
```

The codec keeps per-thread state in `thread_local` objects with
non-trivial destructors (`std::unique_ptr`, `std::string`). Under the
MinGW **win32** thread model these destructors are torn down through a
broken `__cxa_thread_atexit` path inside a DLL, so the process faults
(`0xC0000005`) at exit *after* the first conversion — the conversion
succeeds, then the host crashes on teardown. The **posix** model
(winpthread-backed) tears them down cleanly. The `dll` target refuses to
build with the win32 model. The produced DLL is self-contained (libgcc /
libstdc++ / winpthread are statically linked; it depends only on
`KERNEL32.dll` + `msvcrt.dll`).


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
