#!/bin/bash
# La suite del formato .pja. Lo llama `make pja-check`.
#
# Sin referencia externa desde que se retiro el Rust (12/10/2026): lo que
# quedo de el son los vectores de pruebas/kat.txt. La cobertura sale de que
# cada prueba exija su propia cuenta minima de celdas --una prueba que corre
# cero celdas no pasa por verde-- y de los mutantes (fuera del repo, ver
# README).
#
# set -e es a proposito: si algo no compila o no corre, se corta aca.
set -euo pipefail
FPC=${FPC:-fpc}; CC=${PAS_CC:-gcc}; CXX=${PAS_CXX:-g++}
PJA=${PJA_DIR:?}; PAS=$PJA/pas; OUT=${PAS_OUT:-$PAS/build}
mkdir -p "$OUT/c"

echo "== identificadores que chocan sin distinguir mayusculas"
python3 "$PAS/colisiones.py" "$PAS"
echo "== funciones que nunca asignan Result (FPC no avisa si algun camino hace Exit)"
python3 "$PAS/resultados.py" "$PAS"

echo "== cripto en C (BLAKE3 1.8.7 portable, Monocypher 4.0.3 + la frontera pja_cripto)"
for f in pja_cripto blake3/blake3 blake3/blake3_dispatch blake3/blake3_portable monocypher/monocypher; do
  $CC -O2 -std=c99 -DBLAKE3_NO_SSE2 -DBLAKE3_NO_SSE41 -DBLAKE3_NO_AVX2 -DBLAKE3_NO_AVX512 -DBLAKE3_USE_NEON=0 \
      -I"$PAS/c" -c "$PAS/c/$f.c" -o "$OUT/c/$(basename "$f").o"
done
LIBGCC=$(dirname "$($CC -print-libgcc-file-name)")

echo "== compilar"
for prog in prueba_cripto prueba_cifrado prueba_formato prueba_corrupcion prueba_pjafs; do
  $FPC -O2 -Fu"$PAS" -Fi"$PAS" -Fo"$OUT/c" -FU"$OUT" -FE"$OUT" -Fl"$LIBGCC" "$PAS/pruebas/$prog.pas" > "$OUT/fpc.log" 2>&1 \
    || { cat "$OUT/fpc.log"; exit 1; }
done

# .pjg reales: los genera `make pja-corpus` con el packJPG de este arbol
CORPUS=$PJA/pruebas/corpus
ls "$CORPUS"/*.pjg > /dev/null 2>&1 || { echo "FALLA: no hay .pjg en $CORPUS (make pja-corpus)"; exit 1; }

echo "== pruebas"
"$OUT/prueba_cripto" "$PAS/pruebas/kat.txt" | tail -1
"$OUT/prueba_cifrado" | tail -1
"$OUT/prueba_formato" "$CORPUS" | tail -1
"$OUT/prueba_corrupcion" "$CORPUS" | grep -E '^  (sin cifrar|cifrado):|celdas, '
# pjafs toca disco: un directorio propio
mkdir -p "$OUT/tmp_pjafs"; "$OUT/prueba_pjafs" "$(realpath "$OUT/tmp_pjafs")" | tail -1

echo "== frontera C (pjacore.h): nucleo enlazado estatico"
FPC=$FPC PAS_CC=$CC PJA_DIR=$PJA PAS_OUT=$OUT bash "$PAS/frontera.sh"
LIB=$OUT/libpjaffi_pas.a
$CXX -O2 -std=c++17 -I"$PJA/include" "$PJA/test_frontera.cpp" "$LIB" -lpthread -ldl -o "$OUT/test_frontera"
"$OUT/test_frontera" "$CORPUS/n_color_photo.pjg" | tail -1
# el anfitrion que se olvida de pja_iniciar: PJA_ERR_NO_INIT en todo, tambien en hilos
$CXX -O2 -std=c++17 -I"$PJA/include" "$PAS/pruebas/sin_init.cpp" "$LIB" -lpthread -ldl -o "$OUT/sin_init"
"$OUT/sin_init"

# Punta a punta: pjatool (codec + formato).
[ -n "${PJG_LIB:-}" ] && [ -f "$PJG_LIB" ] || { echo "FALLA: falta PJG_LIB (packJPGlib.a) para pjatool"; exit 1; }
$CXX -O2 -std=c++17 -DBUILD_LIB -I"${PJG_INC:-.}" -I"$PJA/include" "$PJA/pjatool.cpp" "$PJG_LIB" "$LIB" \
    ${PJG_LIBS:-} -lpthread -ldl -o "$OUT/pjatool"
RT=$OUT/rt; rm -rf "$RT"; mkdir -p "$RT"
t=0; ok=0; okc=0
for f in "$PJA"/../../test-files/*.jpg; do
  t=$((t+1)); b=$(basename "$f" .jpg)
  "$OUT/pjatool" a "$f" "$RT/$b.pja" > /dev/null && "$OUT/pjatool" x "$RT/$b.pja" "$RT/$b.jpg" > /dev/null \
    && cmp -s "$f" "$RT/$b.jpg" && ok=$((ok+1))
  # cifrado: Argon2id por archivo, de ida y de vuelta
  "$OUT/pjatool" a "$f" "$RT/$b.c.pja" clave > /dev/null && "$OUT/pjatool" x "$RT/$b.c.pja" "$RT/$b.c.jpg" clave > /dev/null \
    && cmp -s "$f" "$RT/$b.c.jpg" && okc=$((okc+1))
done
[ "$t" -ge 5 ] && [ "$ok" -eq "$t" ] && [ "$okc" -eq "$t" ] \
  || { echo "FALLA ida y vuelta pjatool: $ok y $okc de $t"; exit 1; }
echo "ida y vuelta pjatool: $ok de $t JPEG byte a byte sin cifrar, $okc cifrados"
# y lo que no tiene que pasar: contraseña equivocada no escribe nada
if "$OUT/pjatool" x "$RT/$b.c.pja" "$RT/no.jpg" otra > /dev/null || [ -e "$RT/no.jpg" ]; then
  echo "FALLA: con la contraseña equivocada se extrajo algo"; exit 1
fi
# La propiedad del formato con el codec de verdad: bits al azar sobre un .pja
# sin cifrar no terminan NUNCA en un JPEG distinto entregado como bueno.
"$OUT/pjatool" corrupcion "$PJA/../../test-files/color_photo.jpg" 3000 | tail -6
"$OUT/pjatool" corrupcion "$PJA/../../test-files/baseline_444.jpg" 3000 | tail -1
echo "todo en verde"
