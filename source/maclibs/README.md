# Vendored macOS JPEG-LS libraries (static, universal)

`source/maclibs/universal/` holds the same static set as `linuxlibs/`
(CharLS + libjxl and libjxl's own dependencies: highway, brotli, lcms2), built
for macOS with both slices in each `.a`: arm64 (Apple Silicon) and x86_64
(Intel). Minimum macOS 10.15, the first with `std::filesystem`.

```
maclibs/
  universal/
    libcharls.a libjxl.a libjxl_threads.a libjxl_cms.a
    liblcms2.a libhwy.a libbrotlienc.a libbrotlidec.a libbrotlicommon.a
```

Same versions as `linuxlibs/README.md`: CharLS 2.4.2, libjxl 0.11.2, lcms2
2.16, highway 1.2.0, brotli 1.1.0. Static for the same reason as on Linux:
Homebrew ships these as dylibs, and a binary linked against them only runs on
a Mac with the same Homebrew packages installed.

## How they are built

By `.github/workflows/vendor-libs.yml`, on a GitHub macOS runner, because
there is no Mac here to build them on. It runs when that file changes, or by
hand (`workflow_dispatch`), and uploads the set as the `maclibs-universal`
artifact; the build scripts never rebuild them, they link the committed files.

One cmake build per architecture, then `lipo -create`. A single
`CMAKE_OSX_ARCHITECTURES="arm64;x86_64"` build is not used: libjxl and highway
probe compiler flags per ISA, and a probe that passes for x86_64 would then be
applied to the arm64 half of the same compile.

To check a set before committing it:

```bash
for f in source/maclibs/universal/*.a; do lipo -info "$f"; done   # on a Mac
file source/maclibs/universal/*.a                                 # anywhere
```

## Using them

`make` on a Mac picks `maclibs/universal` by itself (the Makefile chooses the
vendored set by `uname`). `make macos` builds the release binary,
`bin/packJPG_macos`, universal and stripped.
