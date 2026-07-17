# Vendored Windows JPEG-LS libraries — DLL variant (posix thread model)

Same purpose as `source/winlibs/` (static CharLS + libjxl + deps for
MinGW, since no MinGW packages of either exist), but built with the
**posix-thread-model** mingw compilers (`x86_64-w64-mingw32-g++-posix`,
`i686-w64-mingw32-g++-posix`) instead of the plain ones.

## Why a separate vendor set

`packJPG.dll` (the `make dll` target) must be built with the posix
thread model — using the plain (win32 thread model) compiler makes
`std::thread`/`thread_local` destructors crash at `DLL_PROCESS_DETACH`
on real Windows (see the thread-model check in `source/Makefile`'s
`dll` target). But `source/winlibs/libjxl_threads.a` was built with the
*plain* compiler, so it references `__gthr_win32_*` symbols — linking
it into a posix-model DLL fails with undefined references to
`__gthr_win32_mutex_*` (ABI mismatch between the two gthr backends).

The CLI targets (`win-x64`/`win-x86`) don't have this constraint — an
`.exe` doesn't hit the `DLL_PROCESS_DETACH` teardown path — so they
keep using the plain-compiler `winlibs/` set unchanged.

```
winlibs-dll/
  x86_64/   (same 9 files as winlibs/x86_64, rebuilt with -posix)
  i686/     (same 9 files as winlibs/i686, rebuilt with -posix)
```

Headers are shared with `source/winlibs/include/` — no ABI difference
there, only the compiled object code differs.

## Reproducing the build

Same recipe as `source/winlibs/README.md`, but the toolchain file's
`CMAKE_C_COMPILER`/`CMAKE_CXX_COMPILER` point at the `-posix` compiler
variants:

```cmake
set(CMAKE_C_COMPILER   ${TOOLCHAIN_PREFIX}-gcc-posix)
set(CMAKE_CXX_COMPILER ${TOOLCHAIN_PREFIX}-g++-posix)
```

Everything else (source versions, CMake flags, third_party fetch steps
for libjxl's highway/brotli/lcms2) is identical.

## Verifying a rebuild

```bash
cd source
make dll CXX=x86_64-w64-mingw32-g++-posix   # -> packJPG.dll (win64)
make dll CXX=i686-w64-mingw32-g++-posix     # -> packJPG.dll (win32)
```

Test via Wine (or real Windows) with `test/dll_test.c` — compress +
decompress a `.jls` file through the DLL API and confirm byte-exact,
and confirm the process exits cleanly (no `DLL_PROCESS_DETACH` crash).
