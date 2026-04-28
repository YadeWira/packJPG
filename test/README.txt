SITX vs packJPG benchmark package (Linux x64)
==============================================

Files:
  sitx       - SITX dequantized binary (Linux x64, REQUIRES AVX2)
  packJPG    - packJPG v4.0 binary (Linux x64)
  bench.sh   - bench script
  README.txt - this file

Quick start:
  chmod +x sitx packJPG bench.sh
  mkdir jpgs
  cp /path/to/test/*.jpg ./jpgs/   # 10-30 diverse JPGs
  ./bench.sh ./jpgs > results.txt
  cat results.txt

Recommended corpus mix:
  - 5-10 camera photos (smartphone / DSLR)
  - 5-10 web images (mid-quality)
  - 3-5 scans / screenshots
  - mix baseline + progressive
  - mix grayscale + RGB
  - sizes: small (<100KB), medium (100KB-1MB), large (>1MB)

Notes:
  - sitx requires AVX2. Xeon E5-2697 v4 has it.
  - sitx mode 2 = dequantized (the "5% better than JXL" mode per source).
  - "sitx_err" in winner column = SITX doesn't handle that JPG flavor.
  - "pjg_err" in winner column = packJPG doesn't handle it.

Output columns:
  file     - JPG filename
  orig     - original .jpg size in bytes
  sitx     - SITX output size (out.enc)
  packjpg  - packJPG output size (.pjg)
  delta%   - SITX size vs packJPG size (negative = SITX smaller = win)
  winner   - SITX | packJPG | tie | sitx_err | pjg_err
