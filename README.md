# packJPG Multi-threaded

packJPG compresses JPEG files losslessly: a `.jpg` becomes a `.pjg` about
**20 % smaller**, and the `.pjg` decompresses back to the original file, bit
for bit, metadata included. It also recompresses **JPEG-LS** (`.jls`), about
16 % smaller.

It is meant for storing and moving JPEGs you want back exactly as they were:
archives, backups, image repositories. `.pjg` is not an image format a viewer
or a browser can open.

**Platforms:** Linux x64 and ARM64 · macOS 10.15+ (Apple Silicon and Intel) ·
Windows 7 SP1+ (x86 and x64)

**📖 [Wiki](https://github.com/YadeWira/packJPG/wiki)** — usage in depth,
threading, library API, format compatibility, building, FAQ, troubleshooting.


## Install

**Linux and macOS:**

```bash
curl -sL https://raw.githubusercontent.com/YadeWira/packJPG/master/install.sh | bash
```

On Debian/Ubuntu x86_64 it sets up the apt repository, so updates come with
`apt upgrade`; elsewhere it installs the latest release into `/usr/local/bin`.

**Windows, or by hand:** download the binary from the
[latest release](https://github.com/YadeWira/packJPG/releases/latest).

| File | For |
|---|---|
| `packJPG_win_x64.exe` / `packJPG_win_x86.exe` | Windows 7 SP1+, 64 / 32 bit |
| `packJPG_linux_x64` | Linux x64, glibc 2.35+ (also `.deb`, `.rpm`, `.tar.gz`) |
| `packJPG_linux_arm64` | Linux ARM64, glibc 2.35+ (also `.tar.gz`) |
| `packJPG_macos` | macOS 10.15+, one binary for Apple Silicon and Intel (also `.tar.gz`) |

The macOS binary is not signed: if a browser downloaded it, run
`xattr -d com.apple.quarantine packJPG_macos` once.


## Usage

```
packJPG <command> [switches] [files]
```

| Command | Does |
|---|---|
| `a` | compress JPEG / JPEG-LS files to `.pjg` |
| `x` | decompress `.pjg` files back |
| `list` | show the version and size of `.pjg` files (reads the header only) |
| `stats` | show JPEG info without compressing |
| `mix` | compress or decompress each file, whichever applies |

```
packJPG a *.jpg                   # compress everything here
packJPG a -th0 -np -odout/ *.jpg  # all cores, no pause, output into out/
packJPG a -r photos/              # recurse into photos/
packJPG x *.pjg                   # decompress
packJPG x - < in.pjg > out.jpg    # stdin to stdout
```

Files are recognized by content, not by extension. Existing files are never
overwritten unless you pass `-o`.

| Switch | |
|---|---|
| `-th<n>` | files in parallel (`0` = one per core) |
| `-sfth` | one file on 3 threads |
| `-o` | overwrite existing output |
| `-od<dir>` | write output into `<dir>` |
| `-r`, `-fs` | recurse; keep the folder structure under `-od` |
| `-ver` | decompress and compare each file before writing it |
| `-np` | no pause at the end |
| `-dry` | do everything but write |
| `-module` | one-line `OK`/`ERROR` output for scripts |
| `-maxout<MB>` | refuse to decompress beyond this size (default 256, `0` = no limit) |
| `-p`, `-d` | proceed on warnings; discard metadata (**both give up the byte-exact copy**) |
| `-v<n>`, `-vp`, `--no-color` | verbosity, progress bar, no colors |

Every switch, with what it trades off:
[Usage](https://github.com/YadeWira/packJPG/wiki/Usage) ·
[Threading](https://github.com/YadeWira/packJPG/wiki/Threading).


## Library

packJPG also builds as a static library, a Linux `.so` or a Windows DLL with a
C API (`source/packjpglib.h`), for embedding in archivers and other tools.
See [Library API](https://github.com/YadeWira/packJPG/wiki/Library-API) —
on Windows, read its thread-model section before linking.


## Compatibility

Every release since v4.0b writes the same `.pjg` bytes and reads the files of
the others. A `.pjg` made from JPEG-LS needs v5.0 or later. Files from v3.x
and older need an old binary.
[Format and compatibility](https://github.com/YadeWira/packJPG/wiki/Format-and-compatibility)
has the full matrix.


## Building

```bash
cd source && make                # this machine
bash build_all.sh                # every release binary into dist/
```

C++17 (g++ 13 / clang 18). The JPEG-LS libraries are vendored, so nothing
else is needed on Linux; Windows needs mingw-w64 with the **posix** thread
model. Details in [docs/howtocompile.md](docs/howtocompile.md) and
[Building](https://github.com/YadeWira/packJPG/wiki/Building).


## License

LGPL v3 or later; see [docs/lgpl-3.0.txt](docs/lgpl-3.0.txt). If the LGPL
does not fit your project, mainly closed-source freeware that wants to read or
write PJG, you can ask for a special permission.

Copyright 2006–2014 HTW Aalen University and Matthias Stirner.
Copyright 2006–2026 Yade Bravo & Matthias Stirner.

Version history: [CHANGELOG.md](CHANGELOG.md).


## Acknowledgements

packJPG was created by **Matthias Stirner** ([@packjpg](https://github.com/packjpg)),
who designed the algorithm, wrote the original implementation and maintained
[`packjpg/packJPG`](https://github.com/packjpg/packJPG) for years. It began
as his final-year project at Hochschule Aalen, with support from Prof. Dr.
Gerhard Seelmann. Everything in this fork builds on his work.

Logo and icon by Michael Kaufmann.


## Contact

[Issues](https://github.com/YadeWira/packJPG/issues) ·
[encode.su thread](https://encode.su/threads/4482-packJPG-Multi-threaded) ·
[Patreon](https://www.patreon.com/YadeWira) ·
[original developer blog](http://packjpg.encode.ru/)
