# Vendored Linux JPEG-LS libraries (static)

`source/linuxlibs/` holds static libraries for CharLS + libjxl (and
libjxl's own dependencies: highway, brotli, lcms2), built natively for
Linux x86_64. Unlike `source/winlibs/` (needed because no MinGW
packages of CharLS/libjxl exist), Debian/Ubuntu *do* ship `libcharls-dev`
and `libjxl-dev` — but only as shared libraries, and dynamically linking
against them ties the resulting binary to whatever SONAME happened to
be installed on the build machine.

## Why this exists

The v5.0a `.deb` was built on a CI runner where `libjxl-dev` resolved to
`libjxl.so.0.7`. The package's `Depends` line, however it's derived, can
only describe *that one machine's* library version — on a system with a
different libjxl (e.g. Debian trixie ships `libjxl0.11`), the `.deb`
either fails to install (unmet dependency) or, worse, installs cleanly
and then crashes at runtime with `error while loading shared libraries`
if the wrong SONAME is declared. Static linking removes the runtime
dependency entirely — the binary carries its own copy of CharLS/libjxl,
so it runs identically regardless of what (if anything) is installed
system-wide.

```
linuxlibs/
  x86_64/
    libcharls.a libjxl.a libjxl_threads.a libjxl_cms.a
    liblcms2.a libhwy.a libbrotlienc.a libbrotlidec.a libbrotlicommon.a
```

Headers are shared with `source/winlibs/include/` (portable C API;
`CHARLS_STATIC`/`JXL_STATIC_DEFINE` make the export-macro annotations
no-ops on any platform, so the same headers work for both).

`source/Makefile`, `build_all.sh`, and `build_pkg.sh` all auto-detect
these by file presence (`linuxlibs/x86_64/libcharls.a`) and fall back to
a dynamic link against system `libcharls-dev`/`libjxl-dev` if the
vendored libs are missing (e.g. a stripped-down fork), same pattern as
the Windows targets.

## Library versions

| library | version |
|---|---|
| CharLS | 2.4.2 |
| libjxl | 0.11.2 |
| lcms2 | 2.16 |
| highway | 1.2.0 |
| brotli | 1.1.0 |

## Reproducing the build

Needed only to update a library version — the build scripts never
rebuild these, they just link the committed `.a` files. Same source
tarballs/recipe as `source/winlibs/README.md`, but built natively (no
cross-compile toolchain file, no mingw prefix):

```bash
sudo apt install cmake build-essential

# CharLS 2.4.2
apt-get source libcharls-dev   # → charls-2.4.2/
mkdir build-charls && cd build-charls
cmake ../charls-2.4.2 \
  -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF \
  -DCHARLS_BUILD_TESTS=OFF -DCHARLS_BUILD_SAMPLES=OFF -DCHARLS_INSTALL=OFF \
  -DCMAKE_POSITION_INDEPENDENT_CODE=ON -DCMAKE_CXX_FLAGS="-O2"
cmake --build . --target charls -j$(nproc)
# → libcharls.a
cd ..

# libjxl 0.11.2 (release tarball — git submodules come empty in it)
curl -sL https://github.com/libjxl/libjxl/archive/refs/tags/v0.11.2.tar.gz | tar xz
cd libjxl-0.11.2/third_party
curl -sL https://github.com/google/highway/archive/refs/tags/1.2.0.tar.gz | tar xz && mv highway-1.2.0 highway
curl -sL https://github.com/google/brotli/archive/refs/tags/v1.1.0.tar.gz | tar xz && mv brotli-1.1.0 brotli
curl -sL https://github.com/mm2/Little-CMS/archive/refs/tags/lcms2.16.tar.gz | tar xz && mv Little-CMS-lcms2.16 lcms
touch lcms/.git
cd ../..

mkdir build-jxl && cd build-jxl
cmake ../libjxl-0.11.2 \
  -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF -DBUILD_TESTING=OFF \
  -DJPEGXL_ENABLE_TOOLS=OFF -DJPEGXL_ENABLE_DEVTOOLS=OFF \
  -DJPEGXL_ENABLE_BENCHMARK=OFF -DJPEGXL_ENABLE_EXAMPLES=OFF \
  -DJPEGXL_ENABLE_DOXYGEN=OFF -DJPEGXL_ENABLE_MANPAGES=OFF \
  -DJPEGXL_ENABLE_JNI=OFF -DJPEGXL_ENABLE_SJPEG=OFF \
  -DJPEGXL_ENABLE_OPENEXR=OFF -DJPEGXL_ENABLE_VIEWERS=OFF \
  -DJPEGXL_ENABLE_PLUGINS=OFF -DJPEGXL_ENABLE_JPEGLI=OFF \
  -DJPEGXL_ENABLE_TRANSCODE_JPEG=OFF -DJPEGXL_ENABLE_SKCMS=OFF \
  -DJPEGXL_BUNDLE_LIBPNG=OFF -DJPEGXL_ENABLE_AVX512=OFF \
  -DJPEGXL_FORCE_SYSTEM_BROTLI=OFF \
  -DCMAKE_POSITION_INDEPENDENT_CODE=ON -DCMAKE_CXX_FLAGS="-O2"
cmake --build . --target jxl jxl_threads -j$(nproc)
# → libjxl.a, libjxl_threads.a, libjxl_cms.a, liblcms2.a,
#   libhwy.a, libbrotlienc.a, libbrotlidec.a, libbrotlicommon.a

cp build-charls/libcharls.a source/linuxlibs/x86_64/
cp build-jxl/lib/{libjxl,libjxl_threads,libjxl_cms}.a source/linuxlibs/x86_64/
cp build-jxl/third_party/lcms2/liblcms2.a source/linuxlibs/x86_64/
cp build-jxl/third_party/highway/libhwy.a source/linuxlibs/x86_64/
cp build-jxl/third_party/brotli/{libbrotlienc,libbrotlidec,libbrotlicommon}.a source/linuxlibs/x86_64/
```

`-DCMAKE_POSITION_INDEPENDENT_CODE=ON` is required — without it, linking
these into `libpackJPG.so` (the `make so` target) fails since PIC/non-PIC
object code can't mix in a shared object.

## Verifying a rebuild

```bash
cd source
make clean && make
ldd packJPG   # should show no libcharls/libjxl dependency
./packJPG a -np some.jls   # round-trip should stay byte-exact
```
