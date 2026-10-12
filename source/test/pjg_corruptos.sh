#!/usr/bin/env bash
# .pjg con UN bit alterado que rompian el decodificador: una escritura por
# puntero nulo en recode_jpeg y lecturas fuera del heap en
# pjg_unoptimize_header y jpg_parse_jfif. Los encontro el 12/10/2026 la prueba
# punta a punta del formato .pja (pjatool corrupcion), volteando bits bajo
# AddressSanitizer; el fuzzer no habia llegado.
#
# Cada uno tiene que RECHAZARSE con un error, sin reporte de los sanitizers y
# sin dejar un .jpg. El nombre dice de que archivo de test-files/ sale, que bit
# del .pja se volteo, y donde rompia.
#
#   pjg_corruptos.sh [binario]   (sin argumento, compila packJPG con ASan+UBSan)
set -eu
SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CASOS="$SRC_DIR/test/pjg_corruptos"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

BIN=${1:-}
if [ -z "$BIN" ]; then
  BIN=$TMP/packJPG_asan
  L=$SRC_DIR/linuxlibs/x86_64
  ${CXX:-g++} -O1 -g -fsanitize=address,undefined -fno-omit-frame-pointer -std=c++17 \
      -DHAVE_JPEGLS -DCHARLS_STATIC -DJXL_STATIC_DEFINE -I"$SRC_DIR/winlibs/include" -DUNIX -I"$SRC_DIR" \
      "$SRC_DIR"/aricoder.cpp "$SRC_DIR"/bitops.cpp "$SRC_DIR"/jpegls.cpp "$SRC_DIR"/packjpg.cpp \
      "$L"/libcharls.a "$L"/libjxl.a "$L"/libjxl_threads.a "$L"/libjxl_cms.a "$L"/liblcms2.a "$L"/libhwy.a \
      "$L"/libbrotlienc.a "$L"/libbrotlidec.a "$L"/libbrotlicommon.a -lpthread -o "$BIN"
fi

n=0; mal=0
for f in "$CASOS"/*.pjg; do
  n=$((n+1)); d=$TMP/caso$n; mkdir -p "$d"; cp "$f" "$d/x.pjg"
  rc=0; out=$(cd "$d" && UBSAN_OPTIONS=halt_on_error=1:print_stacktrace=1 "$BIN" x --no-pause -f x.pjg 2>&1) || rc=$?
  if echo "$out" | grep -qE 'ERROR: AddressSanitizer|runtime error:'; then
    echo "FALLA $(basename "$f"): reporte del sanitizer"; echo "$out" | grep -m3 -E 'ERROR|runtime error|#[0-3] '; mal=$((mal+1))
  elif [ "$rc" -eq 0 ] || [ "$rc" -gt 128 ]; then
    echo "FALLA $(basename "$f"): rc=$rc (tenia que rechazarse con un error)"; mal=$((mal+1))
  elif [ -e "$d/x.jpg" ]; then
    echo "FALLA $(basename "$f"): dejo un x.jpg"; mal=$((mal+1))
  else
    echo "ok    $(basename "$f"): $(echo "$out" | grep -m1 -A1 'fatal error' | tail -1 | sed 's/^ *//')"
  fi
done
[ "$n" -ge 6 ] || { echo "FALLA: solo $n casos"; exit 1; }
echo "$n casos, $mal fallas"
[ "$mal" -eq 0 ]
