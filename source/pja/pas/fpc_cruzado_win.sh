#!/bin/bash
# Arma lo que hace falta para compilar el nucleo .pja para Windows, sin tocar
# el sistema y solo desde fpc-source: el compilador cruzado de 32 bits
# (ppc386) con las unidades i386-win32, y las unidades x86_64-win64 para el
# ppcx64 del sistema. Debian no empaqueta el de 32 bits, y Ubuntu 22.04
# tampoco trae las unidades de win64 (fp-units-win-rtl): lo descubrio el CI.
#
#   fpc_cruzado_win.sh <dir>  -> <dir>/ppc386, <dir>/units/i386-win32, <dir>/units/x86_64-win64
#
# Despues:  frontera_win.sh con PPC386=<dir>/ppc386 RTL386=<dir>/units/i386-win32
#                                RTLW64=<dir>/units/x86_64-win64
#
# La receta salio de armarlo a mano (IA_LAB/agentes/PJPG/fpc-link/RESULTADOS.md),
# con dos trampas:
#  - el compilador se arma con PPC_TARGET=i386 y SIN OS_TARGET=win32: con el,
#    las herramientas del propio build (msg2inc) se compilan para Windows y el
#    build se rompe;
#  - Debian quita rtl/<cpu>/makefile.cpu, que es escrito a mano y no generado.
#    Van abajo los de i386 y x86_64 tal cual los del tag release_3_2_2
#    (gitlab.com/freepascal.org/fpc/source), verificados byte a byte.
# Necesita: fpc (ppcx64), fpcmake, fpc-source, make.
set -euo pipefail
OUT=${1:?uso: fpc_cruzado_win.sh <dir>}
VER=$(fpc -iV)
FUENTE=/usr/share/fpcsrc/$VER
[ -d "$FUENTE/compiler" ] || { echo "FALLA: no estan las fuentes de FPC $VER en $FUENTE (paquete fpc-source)"; exit 1; }
MSG=$(ls -d /usr/lib/*/fpc/$VER/msg 2>/dev/null | head -1)
[ -n "$MSG" ] || { echo "FALLA: no encuentro los .msg de FPC $VER"; exit 1; }
mkdir -p "$OUT"; OUT=$(realpath "$OUT")
if [ -x "$OUT/ppc386" ] && [ -f "$OUT/units/i386-win32/system.ppu" ] && [ -f "$OUT/units/x86_64-win64/system.ppu" ]; then
  echo "[OK] ya estaba: $OUT"; exit 0
fi
S=$OUT/src; rm -rf "$S"; mkdir -p "$S"
cp -r "$FUENTE/compiler" "$FUENTE/rtl" "$S/"
[ -f "$FUENTE/Makefile.fpc" ] && cp "$FUENTE/Makefile.fpc" "$S/" || true
( cd "$S/compiler" && fpcmake -Tall -r > /dev/null )
( cd "$S/rtl" && fpcmake -Tall -r > /dev/null )
mkdir -p "$S/compiler/msg"; cp "$MSG"/*.msg "$S/compiler/msg/"
cat > "$S/rtl/i386/makefile.cpu" <<'EOF'
#
# Here we set processor dependent include file names.
#

CPUNAMES=fastmove i386 int64p math set setjump setjumph cpuh
CPUINCNAMES=$(addsuffix .inc,$(CPUNAMES))

EOF
cat > "$S/rtl/x86_64/makefile.cpu" <<'EOF'
#
# Here we set processor dependent include file names.
#

CPUNAMES=int64p math set setjump setjumph x86_64 cpuh
CPUINCNAMES=$(addsuffix .inc,$(CPUNAMES))
#
EOF
( cd "$S/compiler" && make PPC_TARGET=i386 PP=ppcx64 compiler > "$OUT/compilador.log" 2>&1 ) \
  || { tail -20 "$OUT/compilador.log"; exit 1; }
cp "$S/compiler/ppc386" "$OUT/ppc386"
( cd "$S/rtl" && make OS_TARGET=win32 CPU_TARGET=i386 FPC="$OUT/ppc386" > "$OUT/rtl.log" 2>&1 ) \
  || { tail -20 "$OUT/rtl.log"; exit 1; }
( cd "$S/rtl" && make OS_TARGET=win64 CPU_TARGET=x86_64 FPC=ppcx64 > "$OUT/rtl64.log" 2>&1 ) \
  || { tail -20 "$OUT/rtl64.log"; exit 1; }
mkdir -p "$OUT/units"; rm -rf "$OUT/units/i386-win32" "$OUT/units/x86_64-win64"
cp -r "$S/rtl/units/i386-win32" "$S/rtl/units/x86_64-win64" "$OUT/units/"
for u in i386-win32 x86_64-win64; do
  n=$(ls "$OUT/units/$u"/*.ppu | wc -l)
  [ "$n" -ge 50 ] || { echo "FALLA: el RTL $u salio con $n unidades"; exit 1; }
done
[ -n "${PJA_CONSERVAR_FUENTES:-}" ] || rm -rf "$S"
echo "[OK] $OUT/ppc386, $OUT/units/i386-win32 y $OUT/units/x86_64-win64"
