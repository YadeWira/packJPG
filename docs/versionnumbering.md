# Version Numbering Guideline

The packJPG version consists of two parts: the main version number and
the subversion string. Example: `packJPG v2.4a` has main version `2.4`
and subversion string `a`.


## Compatibility rules

Subversions are compatible with each other: files compressed by v2.4
can be decompressed by v2.4a, v2.4b, etc., and vice versa.

A change in the main version number may break compatibility: files
compressed by v2.4 cannot be decompressed by v2.3 or v3.0.

The PJG format version is embedded in every compressed file. Attempting
to decompress a file with the wrong version produces a clear error.


## Subversion string

The subversion string indicates smaller changes that do not break
compatibility: bug fixes, speed improvements, minor additions. It can
be empty (first release of a new main version) and is enumerated as
`a`, `b`, `c`, ..., `z`, `aa`, `ab`, ..., `zz`. It may also be used
descriptively for targeted releases, e.g. `packJPG v2.5fast`.


## Where to change the version

The version is defined in `packjpg.cpp` via two constants:

```cpp
appversion   // unsigned char, encodes major*10 + minor (e.g. 31 = v3.1)
subversion   // const char*, subversion string (e.g. "" or "a")
```

These are also written into every PJG file header and checked on
decompression to enforce compatibility.


## Special format markers

In addition to the version byte, PJG files may contain format markers
before the version byte:

| Marker | Description |
|---|---|
| `0x00` | custom compression settings block follows (8 bytes) |
| `0x01` | parallel format: file was compressed with `-sfth` (v3.0+) |
| `0x02` | v4.0b features (diagonal DC neighbor context, cross-component DC) |

Files with the `0x01` marker require packJPG v3.0 or later to decompress.
Files with the `0x02` marker require packJPG v4.0b or later to decompress;
v4.0/v4.0a binaries reading them produce a clean `unknown header code`
error. Files without `0x02` decode under any v4.0+ build with the v4.0b
features off. v4.0c and v4.0d did not introduce new markers — their
`.pjg` output is byte-exact with v4.0b's.


## LTS / feature line distinction

Subversion releases of the same main version (`4.0a`, `4.0b`, `4.0c`,
`4.0d`, …) form an **LTS** line: format-stable, binary filename
`packJPG`. Bug-fix and small additive changes only after the initial
drop. The current LTS is **v4.0**, with v4.0d as its latest update.

A new main version (`4.1`, `5.0`, …) is reserved for feature-bearing
releases that may break format. None is currently in roadmap.

---
packJPG by Yade Bravo, 05/06/2026
