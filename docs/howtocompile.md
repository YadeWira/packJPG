# How to Compile packJPG

This document explains how to compile packJPG as an executable or as a
static/shared library. Requires a C++17 compliant compiler.

**Tested with:** clang 18, g++ 13.
**Supported targets:** Linux x64, Linux ARM64 (cross or native), macOS 10.15+ (universal: Apple Silicon + Intel), Windows x64 (cross), Windows x86 (cross) — all Windows 7 SP1+.


## Quick build (all platforms at once)

From the `source/` directory, run:

```
./build_all.sh
```

This builds Linux x64, Linux ARM64, Windows x64, and Windows x86 binaries
into `dist/`. Requires clang++ (or g++) for Linux, g++-aarch64-linux-gnu for
ARM64, and mingw-w64 (**posix** thread model, see below) for Windows targets.
A missing cross compiler skips that target.

```
# Ubuntu/Debian
sudo apt install clang mingw-w64 g++-aarch64-linux-gnu

# Arch
sudo pacman -S clang mingw-w64-gcc
```

### macOS

Supported again since v5.0g. It was dropped after v5.0c because the Apple
Silicon CI job failed on every run from 2026-07-19 on; the cause was the
Makefile, which linked the Linux x86_64 libraries on every host. It now picks
the vendored set by host, and macOS has its own: `source/maclibs/universal/`.

On a Mac, with the Xcode command line tools (`xcode-select --install`):

```
cd source
make            # this Mac's architecture
make macos      # bin/packJPG_macos: universal (arm64 + x86_64), macOS 10.15+
```

CI builds the universal binary on Apple Silicon and runs it on an Intel
runner too, so each slice is executed on its own hardware.

### Linux ARM64

`make linux-arm64` cross-compiles `bin/packJPG_linux_arm64` with
`aarch64-linux-gnu-g++` (on an ARM64 host it uses the native compiler), and
plain `make` on an ARM64 host builds natively. Both link
`source/linuxlibs/aarch64/`. The release binary is cross-built on the same
Ubuntu 22.04 runner as the x64 one, so it needs glibc 2.35 or later; CI runs
it under qemu and checks that its `.pjg` match the x64 binary's byte for byte,
and the cross-platform workflow also builds and round-trips on a real ARM64
runner.


## Compiling with make

Individual targets are available via the Makefile:

| Target | Description |
|---|---|
| `make` (or `make all`) | Linux x64 executable (default, portable) |
| `make linux-x64` | Linux x64 executable into `bin/` |
| `make linux-arm64` | Linux ARM64 executable into `bin/` (cross with `aarch64-linux-gnu-g++`, or native) |
| `make macos` | macOS universal executable into `bin/` (on a Mac) |
| `make win-x64` | Windows x64 executable (requires mingw-w64's posix thread model — used automatically, see below) |
| `make win-x86` | Windows x86 executable (requires mingw-w64's posix thread model — used automatically, see below) |
| `make all-platforms` | all three targets above |
| `make native` | Linux x64 with `-march=native -mtune=native` (max-perf, non-portable) |
| `make pgo` | two-phase profile-guided build (see below) |
| `make dev` | Linux x64 with developer functions (`DEV_BUILD`) |
| `make lib` | static library `packJPGlib.a` (`BUILD_LIB`; when cross-compiling for Windows, MinGW posix model required — enforced, see below) |
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

**Every** Windows target requires the *posix* thread-model mingw compiler,
not the plain/win32-model one: the DLL, the win-x64/win-x86 CLI executables,
**and a `packJPGlib.a` you cross-compile for Windows**. `win-x64`/`win-x86`
already default to it (`x86_64-w64-mingw32-g++-posix` /
`i686-w64-mingw32-g++-posix`); `dll` and `lib` need it passed explicitly,
since they share plumbing with the native Linux build:

```
make dll CXX=x86_64-w64-mingw32-g++-posix   # x64
make dll CXX=i686-w64-mingw32-g++-posix     # x86
make lib CXX=x86_64-w64-mingw32-g++-posix   # static lib, cross for Windows
```

Both targets **refuse to build** under the win32 model rather than produce
a broken artifact. The `lib` guard was added in v5.0d after the mismatch
cost a downstream project (packMP3) ten hours of debugging.

Three independent reasons the plain/win32-model alias is a portability
trap, found the hard way — one per artifact kind:

1. **The DLL crashes at exit.** What is *measured*: a DLL built with the
   MinGW **win32** thread model faults (`0xC0000005`) at process exit
   after the first conversion — the conversion succeeds, then the host
   crashes on teardown; the same source built with the **posix** model
   (winpthread-backed) does not. Switching only the thread model makes the
   fault appear and disappear. The `dll` target refuses to build with the
   win32 model.

   What is *inferred*, and deliberately not called a root cause: the codec
   keeps per-thread state in `thread_local` objects with non-trivial
   destructors (`std::unique_ptr`, `std::string`), and per-thread teardown
   in dynamically-loaded DLLs is a known-awkward area. That is context
   consistent with the trigger, not evidence of a particular failure mode —
   nobody here has stepped through the teardown path to confirm which one
   it is.

2. **The plain alias doesn't compile `std::async`/`std::future` at all**
   on some distros' mingw-w64 packaging (Ubuntu 22.04's, notably — the
   headers declare `std::future` but the implementation is incomplete,
   a compile-time "declared but never defined" error) — affecting the
   win-x64/win-x86 CLI too, since the codec uses `std::async` for
   intra-file parallelism (`-sfth`).

3. **The static lib hangs the host — silently.** This is the worst of the
   three because there is no noisy variant of it. `packJPGlib.a` gets
   absorbed into someone else's binary, and its `std::mutex`/`std::once`
   resolve against whichever threading runtime the *host's* driver picked.
   Mixing the two models in one image **does not fail to link**: exit 0, no
   warning, a complete executable. The only symptom is that the first decode
   blocks forever on a lock, process pinned at ~0% CPU — no error, no crash,
   no timeout. Measured on real Windows x64 with one `.a` linked both ways:
   posix round-trips byte-exact in ~104 ms, the plain driver never returns
   from decompression (killed at 90 s having burned 0.09 s of CPU).

   The `lib` guard covers producing the `.a`. It cannot cover the case that
   actually bit packMP3 — a *posix* `.a` inside a win32-model host — because
   that is indistinguishable at link time from a correct build. **Consumers
   must build their own objects with the `-posix` driver too**; that is the
   only instrument that exists, and it is why `packjpglib.h` opens with a
   thread-model warning. To check a `.a` after the fact, look at which
   symbols it wants: `nm`/`objdump` showing `pthread_*` means posix,
   `__gthr_win32_*` means win32.

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
