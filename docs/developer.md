# Developer Functions

packJPG includes debug and analysis functions intended for developers.
These are only available in builds compiled with `DEV_BUILD` defined
(see [howtocompile.md](howtocompile.md)). They are not available in library builds.

To compile with developer functions:

```
make dev
```


## Enabling developer mode at runtime

Even in a `DEV_BUILD` binary, developer switches are locked behind the
`-dev` flag. You must pass `-dev` first for any developer switch to work:

```
packJPG -dev <subcommand> [dev-switches] [files]
```


## Developer switches

| Switch | Description |
|---|---|
| `-dev` | unlock developer functions (required for all switches below) |
| `-test` | test algorithms, keep output if error (like `-ver` but non-fatal) |
| `-split` | split JPEG into header data and huffman image data |
| `-coll?` | dump DCT coefficients to file (`?` = order: 0=std, 1=dhf, 2=squ, 3=unc) |
| `-fcol?` | dump DC-predicted DCT coefficients (same order options as `-coll?`) |
| `-zdst` | dump zero distribution lists to file |
| `-info` | dump JPEG structure info to `.nfo` text file |
| `-dist` | dump coefficient distribution data to file |
| `-pgm` | convert each color component to a `.pgm` grayscale image |
| `-s?` | set global number of segments (1 ≤ s ≤ 49) |
| `-t?` | set global noise threshold (0 ≤ t ≤ 10) |
| `-s?,?` | set number of segments for a specific component |
| `-t?,?` | set noise threshold for a specific component |


## Switch descriptions

### `-test`
Like the user-facing `-ver` option, but non-fatal: if verification fails,
all intermediate output files are kept so the developer can inspect them.

### `-split`
Splits a JPEG into two files: one containing the header (quantization
tables, Huffman tables, image dimensions, etc.) and one containing the
raw Huffman-coded image data. Useful for low-level JPEG inspection.

### `-coll?` / `-fcol?`
Dumps decompressed DCT coefficients for each color component to separate
files. Coefficients are stored as 16-bit signed integers.
The `?` specifies the storage order:
- `0` = standard (zigzag within block, blocks in raster order)
- `1` = DHF (by frequency band across all blocks)
- `2` = SQU (square interleaved)
- `3` = UNC (uncompressed raw order)

`-coll?` dumps raw DC coefficients; `-fcol?` replaces DC with prediction errors.

### `-zdst`
Writes zero distribution lists to files (one per color component).
Each value represents the number of non-zero AC coefficients in one 8×8
block. Stored as unsigned bytes. Used internally by packJPG to replace
JPEG's EOB symbol and to segment the data for arithmetic coding.

### `-info`
Writes a `.nfo` text file with structural information about the JPEG:
header layout, scan structure, coding type, and quantization tables
for each component.

### `-dist`
Writes coefficient distribution data to `.dist` files (one per component).
For each DCT band, the file contains counts of coefficients with absolute
value 0, 1, 2, 3, ... Useful for analysing the statistical properties of
a file.

### `-pgm`
Applies the IDCT to each color component and dumps the result as a
`.pgm` (Portable GrayMap) file. Primarily a sanity check for the DCT
implementation.

### `-s?` / `-t?`
Override the automatic compression parameter selection. Normally packJPG
chooses segmentation (`-s`) and noise threshold (`-t`) values automatically
based on file size. These switches allow manual tuning to explore the
compression space. Default segmentation is 10; default noise threshold
is adaptive (larger files get a higher threshold).

---
packJPG by Yade Bravo, 03/31/2026
