# Vendored Windows JPEG-LS libraries

`source/winlibs/` holds static libraries for CharLS + libjxl (and libjxl's
own dependencies: highway, brotli, lcms2), cross-compiled for MinGW. They
exist because **no MinGW packages of CharLS or libjxl exist** — building
them from source is a real, non-instant task (cmake + several sub-projects),
so the result is vendored here and committed instead of rebuilt on every
release.

```
winlibs/
  include/
    charls/*.h   — CharLS 2.4.2 public headers
    jxl/*.h      — libjxl 0.11.2 public headers (identical for x86_64/i686)
  x86_64/
    libcharls.a libjxl.a libjxl_threads.a libjxl_cms.a
    liblcms2.a libhwy.a libbrotlienc.a libbrotlidec.a libbrotlicommon.a
  i686/
    (same 9 files, i686 build)
```

`source/Makefile` (`win-x64`/`win-x86` targets) and `build_all.sh` both
auto-detect these by file presence (`winlibs/<arch>/libcharls.a`) and
gracefully build without JPEG-LS if the directory is missing — e.g. a
shallow clone or a fork that stripped `winlibs/` out.

## Library versions

| library | version |
|---|---|
| CharLS | 2.4.2 |
| libjxl | 0.11.2 |
| lcms2 | 2.16 |
| highway | 1.2.0 |
| brotli | 1.1.0 |

## Consumer flags

```
-DHAVE_JPEGLS -DCHARLS_STATIC -DJXL_STATIC_DEFINE -Iwinlibs/include
```

Link order matters — libcharls before libjxl before libjxl's own deps:

```
libcharls.a libjxl.a libjxl_threads.a libjxl_cms.a
liblcms2.a libhwy.a libbrotlienc.a libbrotlidec.a libbrotlicommon.a
```

## Reproducing the build

Needed only to update a library version — the Makefile/build_all.sh never
rebuild these, they just link the committed `.a` files.

### Prerequisites

```bash
sudo apt install mingw-w64 cmake
```

### 1. Download sources

```bash
# CharLS 2.4.2
apt-get source libcharls-dev   # → charls-2.4.2/

# libjxl 0.11.2 (release tarball — git submodules come empty in it)
curl -sL https://github.com/libjxl/libjxl/archive/refs/tags/v0.11.2.tar.gz | tar xz
# → libjxl-0.11.2/

# Bundled deps: libjxl's third_party/ submodules are empty in the release
# tarball and must be fetched by hand.
cd libjxl-0.11.2/third_party

curl -sL https://github.com/google/highway/archive/refs/tags/1.2.0.tar.gz | tar xz
mv highway-1.2.0 highway

curl -sL https://github.com/google/brotli/archive/refs/tags/v1.1.0.tar.gz | tar xz
mv brotli-1.1.0 brotli

curl -sL https://github.com/mm2/Little-CMS/archive/refs/tags/lcms2.16.tar.gz | tar xz
mv Little-CMS-lcms2.16 lcms
touch lcms/.git   # cmake checks for .git to detect a bundled lcms2
```

### 2. Toolchain file

`toolchain-x86_64.cmake` (swap `x86_64`/`x86_64-w64-mingw32` for
`i686`/`i686-w64-mingw32` for the win32 variant):

```cmake
set(CMAKE_SYSTEM_NAME Windows)
set(CMAKE_SYSTEM_PROCESSOR x86_64)
set(TOOLCHAIN_PREFIX x86_64-w64-mingw32)
set(CMAKE_C_COMPILER   ${TOOLCHAIN_PREFIX}-gcc)
set(CMAKE_CXX_COMPILER ${TOOLCHAIN_PREFIX}-g++)
set(CMAKE_RC_COMPILER  ${TOOLCHAIN_PREFIX}-windres)
set(CMAKE_AR           ${TOOLCHAIN_PREFIX}-ar)
set(CMAKE_RANLIB       ${TOOLCHAIN_PREFIX}-ranlib)
set(CMAKE_FIND_ROOT_PATH /usr/${TOOLCHAIN_PREFIX})
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)
```

### 3. Build CharLS

```bash
mkdir build-charls-x64 && cd build-charls-x64
cmake ../charls-2.4.2 \
  -DCMAKE_TOOLCHAIN_FILE=../toolchain-x86_64.cmake \
  -DCMAKE_BUILD_TYPE=Release \
  -DBUILD_SHARED_LIBS=OFF \
  -DCHARLS_BUILD_TESTS=OFF \
  -DCHARLS_BUILD_SAMPLES=OFF \
  -DCHARLS_INSTALL=OFF \
  -DCMAKE_CXX_FLAGS="-O2 -static-libgcc -static-libstdc++"
cmake --build . --target charls -j$(nproc)
# → libcharls.a
```

### 4. Build libjxl

```bash
mkdir build-jxl-x64 && cd build-jxl-x64
cmake ../libjxl-0.11.2 \
  -DCMAKE_TOOLCHAIN_FILE=../toolchain-x86_64.cmake \
  -DCMAKE_BUILD_TYPE=Release \
  -DBUILD_SHARED_LIBS=OFF -DBUILD_TESTING=OFF \
  -DJPEGXL_ENABLE_TOOLS=OFF -DJPEGXL_ENABLE_DEVTOOLS=OFF \
  -DJPEGXL_ENABLE_BENCHMARK=OFF -DJPEGXL_ENABLE_EXAMPLES=OFF \
  -DJPEGXL_ENABLE_DOXYGEN=OFF -DJPEGXL_ENABLE_MANPAGES=OFF \
  -DJPEGXL_ENABLE_JNI=OFF -DJPEGXL_ENABLE_SJPEG=OFF \
  -DJPEGXL_ENABLE_OPENEXR=OFF -DJPEGXL_ENABLE_VIEWERS=OFF \
  -DJPEGXL_ENABLE_PLUGINS=OFF -DJPEGXL_ENABLE_JPEGLI=OFF \
  -DJPEGXL_ENABLE_TRANSCODE_JPEG=OFF -DJPEGXL_ENABLE_SKCMS=OFF \
  -DJPEGXL_BUNDLE_LIBPNG=OFF -DJPEGXL_ENABLE_AVX512=OFF \
  -DJPEGXL_FORCE_SYSTEM_BROTLI=OFF \
  -DCMAKE_CXX_FLAGS="-O2 -static-libgcc -static-libstdc++"
cmake --build . --target jxl jxl_threads -j$(nproc)
# → libjxl.a, libjxl_threads.a, libjxl_cms.a, liblcms2.a,
#   libhwy.a, libbrotlienc.a, libbrotlidec.a, libbrotlicommon.a
```

### win32 notes

Same procedure with `TOOLCHAIN_PREFIX=i686-w64-mingw32`. Highway's SIMD
targets auto-detect at configure time (unsupported ones disable themselves
for x86). No extra flags needed.

### 5. Copy the result

```bash
cp build-charls-x64/libcharls.a source/winlibs/x86_64/
cp build-jxl-x64/lib/{libjxl,libjxl_threads,libjxl_cms}.a source/winlibs/x86_64/
cp build-jxl-x64/lib/lcms2/liblcms2.a source/winlibs/x86_64/
cp build-jxl-x64/third_party/highway/libhwy.a source/winlibs/x86_64/
cp build-jxl-x64/third_party/brotli/{libbrotlienc,libbrotlidec,libbrotlicommon}.a source/winlibs/x86_64/
# headers are identical between x86_64/i686 builds — copy once
cp -r charls-2.4.2/include/charls source/winlibs/include/
cp -r build-jxl-x64/lib/include/jxl source/winlibs/include/
```

Repeat the CharLS/libjxl build steps with the i686 toolchain file for
`source/winlibs/i686/`.

## Verifying a rebuild

After copying new `.a` files, sanity-check before committing:

```bash
cd source
make win-x64 && make win-x86
wine bin/packJPG_win_x64.exe a -np some.jls   # or win-x86, via Wine or real Windows
```

Round-trip should stay byte-exact — compare against the previous library
version's output on the same `.jls` file.
