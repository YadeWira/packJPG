packJPG v3.0 test 5 (03/27/2026)
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

packJPG is a lossless JPEG compression program. It compresses JPEG files
to the PJG format and decompresses them back with bit-for-bit identical
reconstruction. Typical file size reduction: ~20%.

Supported platforms: Linux x64, Windows 7 and later (x86/x64).
Note: Windows XP may work in some cases but is not supported and will
not receive bug fixes.


LGPL v3 license and special permissions
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

All programs in this package are free software; you can redistribute 
them and/or modify them under the terms of the GNU Lesser General Public 
License as published by the Free Software Foundation; either version 3 
of the License, or (at your option) any later version. 

The package is distributed in the hope that it will be useful, but 
WITHOUT ANY WARRANTY; without even the implied warranty of 
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU Lesser 
General Public License for more details at 
http://www.gnu.org/copyleft/lgpl.html. 

If the LGPL v3 license is not compatible with your software project you 
might contact us and ask for a special permission to use the packJPG 
library under different conditions. In any case, usage of the packJPG 
algorithm under the LGPL v3 or above is highly advised and special 
permissions will only be given where necessary on a case by case basis. 
This offer is aimed mainly at closed source freeware developers seeking 
to add PJG support to their software projects. 

Copyright 2006...2014 by HTW Aalen University and Matthias Stirner.
Copyright 2006...2026 by Yade Bravo & Matthias Stirner.


Usage of packJPG
~~~~~~~~~~~~~~~~

A subcommand is required to tell packJPG what to do:

 "packJPG <subcommand> [switches] [filename(s)]"

Subcommands:

 a       compress JPEG files to PJG (archive)
 x       decompress PJG files back to JPEG (extract)
 mix     auto-detect and process both directions (use with caution)
 list    display info about PJG files without decompressing

packJPG recognizes file types by content, not by extension. Files that
are neither JPEG nor PJG are silently skipped.

packJPG supports wildcards like "*.jpg", "*.*" and drag and drop of
multiple files. Filenames for output files are created automatically.
In default mode, files are never overwritten. If a filename is already
in use, packJPG creates a new filename by adding underscores.

On Windows, wildcard expansion is handled internally by packJPG since
cmd.exe does not expand wildcards automatically. Filenames with accented
or special characters are fully supported on Windows 7 and later.

Directories in the file list are silently ignored unless -r is given.
To recurse into subdirectories, pass the -r flag explicitly.

If "-" is used as a filename, input is read from stdin and output is
written to stdout. This can be useful if jpegtran is used as a
preprocessor.

Usage examples:

 "packJPG a *.jpg"
 "packJPG a lena.jpg"
 "packJPG a kodim??.jpg"
 "packJPG x *.pjg"
 "packJPG x -r archive/"
 "packJPG mix *.*"
 "packJPG list *.pjg"
 "packJPG - < sail.pjg > sail.jpg"
 "packJPG a -th0 -o -np -odout/ *.jpg"


Subcommands in detail
~~~~~~~~~~~~~~~~~~~~~

a -- compress (archive)
  Processes JPEG files and compresses them to PJG. PJG files and
  unrecognized file types are silently skipped.

  "packJPG a -th0 -o -np *.jpg"
  "packJPG a -r -np photos/"

x -- decompress (extract)
  Processes PJG files and decompresses them back to JPEG. JPEG files
  and unrecognized file types are silently skipped.

  "packJPG x -th0 -o -np *.pjg"
  "packJPG x -r -np archive/"

mix -- mixed mode
  Auto-detects each file and compresses or decompresses accordingly.
  Useful for folders containing both JPG and PJG files.

  WARNING: Running mix on a folder that was already compressed will
  decompress the PJG files back — potentially undoing previous work.
  A warning is printed at the end if both directions were used.

  "packJPG mix -o -np *.*"

list -- list PJG info
  Displays version and packed size for each PJG file without
  decompressing it.

  "packJPG list *.pjg"
  "packJPG list -r archive/"

  Output example:
    photos/lena.pjg
      version : v3.0
      packed  : 288.1 KB


Command line switches
~~~~~~~~~~~~~~~~~~~~~

 -ver      verify files after processing
 -v?       level of verbosity; 0,1 or 2 is allowed (default 0)
 -np       no pause after processing files
 -o        overwrite existing files
 -od<path> write output files to directory <path> (created if needed)
 -th<n>    number of worker threads; 0 = auto-detect (default: 1)
 -sfth     parallel single-file compression using 3 threads (Y/Cb/Cr)
 -r        recurse into subdirectories
 -dry      dry run: simulate without writing output files
 -module   machine-friendly output: OK/ERROR + elapsed seconds
 -p        proceed on warnings
 -d        discard meta-info

By default, compression is cancelled on warnings. If warnings are 
skipped by using "-p", most files with warnings can also be compressed, 
but JPEG files reconstructed from PJG files might not be bitwise 
identical with the original JPEG files. There won't be any loss to 
image data or quality however.

Unnecessary meta information can be discarded using "-d". This reduces 
compressed files' sizes. Be warned though, reconstructed files won't be 
bitwise identical with the original files and meta information will be 
lost forever. As with "-p" there won't be any loss to image data or 
quality. 

There is no known case in which a file compressed by packJPG (without 
the "-p" option, see above) couldn't be reconstructed to exactly the 
state it was before. If you want an additional layer of safety you can 
also use the verify option "-ver". In this mode, files are compressed, 
then decompressed and the decompressed file compared to the original 
file. If this test doesn't pass there will be an error message and the 
compressed file won't be written to the drive. 

Please note that the "-ver" option should never be used in conjunction 
with the "-d" and/or "-p" options. As stated above, the "-p" and "-d" 
options will most likely lead to reconstructed JPG files not being 
bitwise identical to the original JPG files. In turn, the verification 
process may fail on various files although nothing actually went wrong. 


Multi-threaded mode (-th)
~~~~~~~~~~~~~~~~~~~~~~~~~

The "-th<n>" switch enables parallel batch processing using n worker
threads. Use "-th0" to auto-detect the number of CPU cores (on x86
builds the auto limit is 2 to prevent out-of-memory errors with large
images; on x64 there is no cap).

In multi-threaded mode, verification is always enabled automatically:
each file is compressed and immediately decompressed and compared
bit-for-bit before the output is written. This ensures no silent
corruption can occur even under heavy parallel load.

Pressing Ctrl+C during multi-threaded processing stops all workers
cleanly, removes any partial output files, and prints a summary of
how many files were completed before the interrupt.

Single-threaded mode (default, no -th flag) behaves exactly as in
previous versions.


Single-file parallel mode (-sfth)
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Standard packJPG processes the components of a JPEG (Y, Cb, Cr)
sequentially — one after another in a single thread. The -sfth switch
changes this by encoding all three components simultaneously, each in
its own thread. This is fundamentally different from -th, which
parallelizes across files, not within a single file.

To make the distinction clear:

 -th<n>   : runs N files at the same time, each file uses 1 thread
 -sfth    : runs 1 file at a time, but splits it into 3 parallel threads
 -th<n> -sfth : runs N files at the same time, each using 3 threads

This means -sfth is useful even when processing a single file, while
-th only helps when processing multiple files in a batch.

Benchmark on a single file (Intel Xeon E5-2697 v4):

 without -sfth :  0.23 sec  1.81 MB/s  ratio 67.29%
 with    -sfth :  0.16 sec  2.54 MB/s  ratio 67.30%

The ratio difference (0.01%) comes from the fact that each component
uses its own independent arithmetic coder context. This is the expected
and documented behavior — files are still valid and fully lossless.

Important notes:
 - Files compressed with -sfth use a new PJG format (0x01 marker).
   They require packJPG v3.0 or later to decompress. Attempting to
   decompress them with v2.x will produce a clean error message.
 - Files compressed without -sfth remain fully compatible with v2.x.
 - A warning is shown if -sfth is used with fewer than 3 detected cores.

Optimal usage for machines with N threads:

 "packJPG a -th<N/3> -sfth -o -np *.jpg"

This fills all N cores: N/3 files in parallel, each using 3 threads.
Example on an 18-core machine: -th6 -sfth = 6 x 3 = 18 threads.

For single-file compression: -sfth alone is sufficient.
For batch-only parallelism without intra-file: use -th<n> without -sfth.


FreeArc integration
~~~~~~~~~~~~~~~~~~~

packJPG can be used as an external compressor in FreeArc, acting as a
JPEG preprocessor before FreeArc applies its own compression on top.
Since FreeArc processes one file at a time in this mode, -sfth is the
right flag to use here — -th would have no effect.

Add the following to your arc.ini:

  [External compressor:jpg]
  packcmd   = packjpg a -sfth -module -np -o $$arcdatafile$$.jpg
  unpackcmd = packjpg x -sfth -module -np -o $$arcdatafile$$.pjg
  datafile   = $$arcdatafile$$.jpg
  packedfile = $$arcdatafile$$.pjg
  solid = 0

Then use it when creating an archive:

  arc a -m"jpg" archive.arc *.jpg

FreeArc will convert each JPEG to PJG before storing it, and
automatically convert back when extracting. The -module flag ensures
FreeArc can parse the result (OK/ERROR + elapsed seconds per file).


Dry run mode (-dry)
~~~~~~~~~~~~~~~~~~~

The "-dry" switch simulates processing without writing any output
files. Useful for previewing compression ratios before committing
to a batch operation.

 "packJPG a -dry -np *.jpg"       preview ratios, no files written
 "packJPG a -dry -th0 -np *.jpg"  same, using all cores


Module mode (-module)
~~~~~~~~~~~~~~~~~~~~~

The "-module" switch produces minimal machine-friendly output: a single
line with OK or ERROR and the elapsed time in seconds. Useful for
integration with external tools like FreeArc.

 "packJPG a -module -np file.jpg"  ->  OK 0.72
 "packJPG a -module -np bad.jpg"   ->  ERROR 1 0.00


Known Limitations
~~~~~~~~~~~~~~~~~

packJPG is a compression program for JPEG files only. Other file types
are silently skipped.

packJPG has low error tolerance. JPEG files might not work with packJPG
even if they work perfectly with other image processing software. This
happens because packJPG needs to understand the internal structure of a
JPEG deeply enough to re-compress the DCT coefficients — it is more
strict than a regular image viewer that just renders the pixels.

Common causes of warnings or errors that -p can work around:

 - Inefficient Huffman coding: some encoders generate Huffman tables
   where the last AC coefficient in a block is zero. Technically valid,
   but packJPG cannot reconstruct it bit-for-bit without -p.
 - Incorrect RST markers: restart markers inserted at wrong positions
   or with wrong counters. Other decoders ignore them; packJPG counts
   and validates them.
 - Inconsistent padding bits: bits used to fill the last byte of a
   Huffman scan. The spec requires 1-bits; some encoders write 0-bits.
 - Garbage data after EOI: some files have extra bytes after the end-
   of-image marker. packJPG preserves them but may warn on edge cases.

With -p, packJPG accepts all these cases and compresses them anyway.
The reconstructed image will be visually identical but may not be
bit-for-bit equal to the original. For this reason, -p should never
be combined with -ver.

If you try to drag and drop too many files at once on Windows, there
might be a windowed error message about missing privileges. In that
case try again with fewer files or use the command prompt instead.

Compressed PJG files are not compatible between different packJPG 
versions. You will get an error message if you try to decompress PJG 
files with a different version than the one used for compression. You 
may download older versions of packJPG from:
https://github.com/packjpg/packJPG

On 32-bit Windows builds (x86), the ratio and speed summary may display
as 0.00% and 0.00 MB/s. This is a display-only cosmetic issue — the
compressed files are valid and can be decompressed normally. It affects
the statistics output only and is caused by integer size limitations in
32-bit builds. Use -th2 maximum on 32-bit to avoid out-of-memory errors
with large images.


Open source release / developer info
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

The packJPG source code is in the "source" subdirectory.

The source code requires a C++17 compliant compiler. Tested with
clang 18 and g++ 13. Cross-compilation for Windows is supported via
mingw-w64. Run build_all.sh to build all targets at once:

 ./build_all.sh    build Linux x64, Windows x64, Windows x86

Binaries are stripped automatically during the build to reduce file size.


History
~~~~~~~

v1.9a (04/20/2007) (non public)
 - first released version
 - only for testing purposes

v2.0  (05/28/2007) (public)
 - first public version of packJPG
 - minor improvements to overall compression
 - minor bugfixes

v2.2  (08/05/2007) (public)
 - around 40% faster compression & decompression
 - major improvements to overall compression (around 2% on average)
 - reading from stdin, writing to stdout
 - smaller executable
 - minor bugfixes
 - various minor improvements

v2.3  (09/18/2007) (public)
 - compatibility with JPEG progressive mode
 - compatibility with JPEG extended sequential mode
 - compatibility with the CMYK color space
 - compatibility with older CPUs
 - around 15% faster compression & decompression
 - new switch: [-d] (discard meta-info)
 - various bugfixes

v2.3a (11/21/2007) (public)
 - crash issue with certain images fixed
 - compatibility with packJPG v2.3 maintained

v2.3b (12/20/2007) (public)
 - some minor errors in the packJPG library fixed
 - compatibility with packJPG v2.3 maintained

v2.4 (03/24/2010) (public)
 - major improvements (1%...2%) to overall compression
 - around 10% faster compression & decompression
 - major improvements to JPG compatibility
 - size of executable reduced to ~33%
 - new switch: [-ver] (verify file after processing)
 - new switch: [-np] (no pause after processing)
 - new progress bar output mode
 - arithmetic coding routines rewritten from scratch
 - various smaller improvements too numerous to list here
 - new SFX (self extracting) archive format

v2.5 (11/11/2011) (public)
 - improvements (~0.5%) to overall compression
 - several minor bugfixes
 - major code cleanup
 - removed packJPX from the package
 - added packARC to the package
 - packJPG is now open source!

v2.5a (11/21/11) (public)
 - source code compatibility improvements (Gerhard Seelmann)
 - avoid some compiler warnings (Gerhard Seelmann)
 - source code clean up (Gerhard Seelmann)

v2.5b (01/27/12) (public)
 - further removal of redundant code
 - some fixes for the packJPG static library
 - compiler fix for Mac OS (thanks to Sergio Lopez)
 - improved compression ratio calculation
 - eliminated the need for temp files

v2.5c (04/13/12) (public)
 - various source code optimizations

v2.5d (07/03/12) (public)
 - fixed a rare bug with progressive JPEG

v2.5e (07/03/12) (public)
 - some minor source code optimizations
 - changed packJPG licensing to LGPL
 - moved packARC to a separate package

v2.5f (02/24/13) (public)
 - fixed a minor bug in the JPG parser (thanks to Stephan Busch)

v2.5g (09/14/13) (public)
 - fixed a rare crash bug with manipulated JPEG files

v2.5h (12/07/13) (public)
 - added a warning for inefficient huffman coding (thanks to Moinak Ghosh)

v2.5i (12/26/13) (public)
 - fixed possible crash with malformed JPEG (thanks to Moinak Ghosh)

v2.5j (01/15/14) (public)
 - various source code optimizations (using cppcheck)

v2.5k (01/22/16) (public)
 - updated contact info
 - fixed a minor bug

v2.6 (03/19/2026) (public)
 - ported to C++17; removed dependency on std::experimental::filesystem
 - clang 18 support: removed GCC-only -fsched-spec-load flag
 - fixed segfault: current_order going negative on malformed input (#41/#35)
 - fixed heap-buffer-overflow: shift_context() lacked bounds check on links[] (#33)
 - fixed global-buffer-overflow: qtable_id not validated before indexing qtables[] (#32)
 - fixed global-buffer-overflow: errormessage buffer 128->512 bytes, sprintf->snprintf (#30)
 - fixed alloc-dealloc mismatch: BitWriter::get_c_bytes() now uses malloc (#31)
 - fixed memory leaks: early returns in read_jpeg() now clean up all allocations (#34)
 - fixed undefined behaviour: DEVLI macro triggered negative shift when s=0
 - removed dead code: plocoi, median_int, median_float, unused ccode field
 - new switch: [-od<path>] write output files to a specified directory (#37)
 - performance: BitWriter and MemoryWriter pre-allocate buffers using input size hint
 - cross-compilation targets for Linux x64, Windows x64 and Windows x86 added to Makefile
 - maintainer: Yade Bravo (https://github.com/YadeWira)

v2.7 (03/20/2026) (public)
 - new switch: [-th<n>] multi-threaded batch processing (0 = auto-detect cores)
 - multi-threaded mode automatically enables bit-for-bit verification per file
 - Windows: wildcard expansion now handled internally (*.jpg works in cmd.exe)
 - [-od<path>] now creates the output directory automatically if it does not exist
 - build: fixed icon embedding for Windows x64/x86 targets (windres -O coff)
 - build: wall-clock time now reported correctly in multi-threaded mode
 - maintainer: Yade Bravo (https://github.com/YadeWira)

v2.8 (03/21/2026) (public)
 - compression: improved AC sign context using top-left diagonal neighbor
   (mod_sgn 9->27 states), ~0.04% better ratio on typical camera photos
 - new switch: [-r] recurse into subdirectories
 - new switch: [-list] display PJG file info without decompressing
 - new switch: [-dry] dry run: simulate without writing output files
 - MT mode: Ctrl+C stops workers cleanly, removes partial output files
 - summary now reports speed in MB/s
 - thread info shows detected core count
 - fixed: -list no longer creates empty .jpg output files
 - fixed: MT progress bar no longer shows stray characters after completion
 - fixed: unique_filename() now respects -od output directory
 - maintainer: Yade Bravo (https://github.com/YadeWira)

v2.9 (03/25/2026) (public)
 - new subcommand interface: a (compress), x (decompress), mix, list
   subcommand is now required; running without one shows the help screen
 - new subcommand: [a] compress only -- process JPG files, skip PJG
 - new subcommand: [x] decompress only -- process PJG files, skip JPG
 - new subcommand: [mix] mixed mode -- auto-detect, warns if both directions used
 - new subcommand: [list] list PJG info (replaces -list flag)
 - new switch: [-module] machine-friendly output: OK/ERROR + elapsed seconds
 - passing a directory as argument now automatically recurses into it
 - fixed: crash with accented/special characters in path (Windows drag & drop)
 - fixed: file count wrong with wildcard expansion on Windows
 - fixed: wildcard expansion now uses FindFirstFileW (Unicode filenames)
 - fixed: comp. ratio 0.00% in single-thread mode
 - fixed: comp. ratio 100% in multi-thread mode with verify
 - fixed: unknown file types (.exe, .png, etc.) now skipped silently
 - fixed: em dash display issue in Windows console (codepage)
 - help screen now shows program description
 - build: binaries stripped automatically (strip --strip-unneeded)
 - minimum supported platform: Linux x64, Windows 7+
 - maintainer: Yade Bravo (https://github.com/YadeWira)

v3.0 test 5 (03/27/2026) (public - non build)
 - new flag: [-sfth] parallel single-file compression using 3 threads (Y/Cb/Cr)
   ~25-30% faster on 3+ thread machines; ratio preserved (~0.01% delta)
   generates new .pjg format (0x01 marker); requires v3.0+ to decompress
   both encode and decode are parallelized
 - warning shown when -sfth is used with fewer than 3 detected threads
 - optimal batch+single-file usage: -th<N/3> -sfth on an N-thread machine
 - fixed: [a] mode no longer creates empty .pjg files for skipped JPEGs
 - fixed: [x] mode no longer creates empty .jpg files for skipped PJGs
 - fixed: skipped files in a/x mode are now silent (no warning printed)
 - fixed: unrecognized flags (e.g. -th=) now print a clear error message
   instead of being silently treated as filenames
 - fixed: jpgfilesize/pjgfilesize changed from int to int64_t — prevents
   0.00% ratio reporting on large files (>2GB) and on 32-bit builds
 - fixed: -th0 on x86 now caps at 2 threads to prevent OOM; x64/Linux
   still uses all available cores
 - fixed: progress counter now shows only processable files (e.g. "2 of 2"
   instead of "5 of 5" when 3 of the 5 files are skipped)
 - fixed: verbose mode (-v1/-v2) no longer prints header lines for skipped
   files — only processed files appear in the output
 - fixed: skipped files (wrong type) no longer print warnings in MT mode
   (-th2 or higher)
 - fixed: directories from wildcard expansion are now silently ignored;
   use -r explicitly to recurse into subdirectories
 - maintainer: Yade Bravo (https://github.com/YadeWira/packJPG)


Acknowledgements
~~~~~~~~~~~~~~~~

packJPG is the result of countless hours of research and development. It
is part of Matthias Stirner's final year project for Hochschule Aalen.

Prof. Dr. Gerhard Seelmann from Hochschule Aalen supported the
development of packJPG with his extensive knowledge in the field of data
compression. Without his advice, packJPG would not be possible.

packJPG logo and icon are designed by Michael Kaufmann.


Contact
~~~~~~~

Project repository:
 https://github.com/YadeWira/packJPG
 https://www.patreon.com/YadeWira

Original developer blog:
 http://packjpg.encode.ru/

For questions and bug reports:
 packjpg (at) matthiasstirner.com


____________________________________
packJPG by Yade Bravo, 03/2026