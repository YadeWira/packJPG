#!/bin/bash
# Arma libpjaffi_pas.a: la capa Pascal entera (con su runtime y la cripto en C)
# en UN objeto, para enlazar estatica adentro de un ejecutable C++ en Linux.
#
#   PJA_DIR=... PAS_OUT=... [FPC=fpc] [PAS_CC=gcc] frontera.sh
#
# Receta medida en el spike (fpc-link/RESULTADOS.md), automatizada:
#  1. FPC compila la libreria con -s (no enlaza) y deja en link.res la lista
#     EXACTA de objetos que usaria para la .so: los de la capa, los del RTL y
#     los de C. Se toma de ahi y no de una lista a mano, que se desactualiza en
#     silencio al sumar una unidad.
#  2. si_dll.o define _start, que choca con el de crt1: se localiza.
#  3. `ld -r` junta todo en un objeto, y objcopy deja GLOBALES solo los pja_* y
#     los dos puntos de arranque del runtime. El RTL de FPC trae cientos de
#     simbolos que no tienen por que verse desde el C++.
#  4. Se agrega pja_inicio.c (pja_iniciar/pja_terminar).
# El que enlaza la .a necesita ademas: -lpthread -ldl (y libgcc, que g++ ya pone).
set -euo pipefail
FPC=${FPC:-fpc}; CC=${PAS_CC:-gcc}
PJA=$(realpath "${PJA_DIR:?}"); PAS=$PJA/pas; OUT=${PAS_OUT:-$PAS/build}
mkdir -p "$OUT"; OUT=$(realpath "$OUT")    # absolutas: mas abajo se compila con cd
F=$OUT/frontera; rm -rf "$F"; mkdir -p "$F" "$OUT/c"

for f in pja_cripto blake3/blake3 blake3/blake3_dispatch blake3/blake3_portable monocypher/monocypher; do
  $CC -O2 -fPIC -std=c99 -DBLAKE3_NO_SSE2 -DBLAKE3_NO_SSE41 -DBLAKE3_NO_AVX2 -DBLAKE3_NO_AVX512 \
      -I"$PAS/c" -c "$PAS/c/$f.c" -o "$OUT/c/$(basename "$f").o"
done
LIBGCC=$(dirname "$($CC -print-libgcc-file-name)")

( cd "$F" && $FPC -O2 -s -Fu"$PAS" -Fi"$PAS" -Fo"$OUT/c" -FU"$F" -FE"$F" -Fl"$LIBGCC" "$PAS/pjaffi.pas" > fpc.log 2>&1 ) \
  || { cat "$F/fpc.log"; exit 1; }
# Con ensamblador EXTERNO (aarch64; en x86_64, con -Aas), -s deja .s y un
# ppas.sh con lo que falta, y ningun .o: se corre solo la parte de ensamblar,
# hasta el primer "Linking". Lo destapo el CI de ARM64 (12/10/2026). En
# x86_64 FPC ensambla adentro y ppas.sh solo trae el enlace, que no se corre.
if [ -f "$F/ppas.sh" ]; then
  ( cd "$F" && sed '/^echo Linking/,$d' ppas.sh > ppas_asm.sh && sh ppas_asm.sh > asm.log 2>&1 ) \
    || { cat "$F/asm.log"; exit 1; }
fi

# objetos del primer INPUT( ... ) de link.res, sin los crt* del cargador
mapfile -t OBJS < <(awk '/^INPUT\(/{n++; next} /^\)/{next} n==1 && /\.o$/ {print}' "$F"/link*.res \
                    | grep -vE '/crt(i|n|beginS|endS)\.o$')
[ "${#OBJS[@]}" -gt 10 ] || { echo "FALLA: link.res con ${#OBJS[@]} objetos, algo cambio en FPC"; exit 1; }
for i in "${!OBJS[@]}"; do
  o=${OBJS[$i]}; [[ $o = ./* ]] && o=$F/${o#./}
  if [[ $(basename "$o") = si_dll.o ]]; then
    objcopy --localize-symbol=_start "$o" "$F/si_dll_local.o"; o=$F/si_dll_local.o
  fi
  OBJS[$i]=$o
done

ld -r -o "$F/pjaffi_todo.o" "${OBJS[@]}"
{ grep -oE '^ +pja_[a-z0-9_]+;' "$F"/link*.res | tr -d ' ;'; echo FPC_SHARED_LIB_START; echo FPC_LIB_EXIT; } > "$F/globales.txt"
objcopy --keep-global-symbols="$F/globales.txt" "$F/pjaffi_todo.o" "$F/pjaffi_pas.o"

$CC -O2 -std=c99 -I"$PJA/include" -c "$PAS/c/pja_inicio.c" -o "$F/pja_inicio.o"
rm -f "$OUT/libpjaffi_pas.a"
ar rcs "$OUT/libpjaffi_pas.a" "$F/pjaffi_pas.o" "$F/pja_inicio.o"

n=$(nm -g --defined-only "$OUT/libpjaffi_pas.a" | grep -c ' T ')
echo "[OK] $OUT/libpjaffi_pas.a: ${#OBJS[@]} objetos, $n simbolos globales"
