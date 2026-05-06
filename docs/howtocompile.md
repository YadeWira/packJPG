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
| `make lib` | static library (`BUILD_LIB`) |
| `make dll` | shared library / DLL (`BUILD_LIB` + `BUILD_DLL`) |

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
make lib    # static library (.a)
make dll    # shared library (.dll / .so)
```

- `packjpglib.h` declares the public API for static library use.
- `packjpgdll.h` declares the public API for shared library use.


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
| `BUILD_DLL` | required additionally for shared library (DLL) builds |
| `DEV_BUILD` | includes developer/debug functions in the executable |
| `UNIX` | defined automatically by the Makefile for Linux builds |

---
packJPG by Yade Bravo, 05/06/2026
