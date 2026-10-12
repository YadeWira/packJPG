#!/bin/bash
# Arma el compilador cruzado de FreePascal para Windows de 32 bits (ppc386 +
# las unidades i386-win32), sin tocar el sistema. Debian/Ubuntu no lo
# empaquetan: traen el de 64 bits (fp-units-win-rtl) y las fuentes
# (fpc-source), y con eso alcanza.
#
#   fpc_i386_win32.sh <dir>     -> <dir>/ppc386 y <dir>/units/i386-win32
#
# Despues:  frontera_win.sh con PPC386=<dir>/ppc386 RTL386=<dir>/units/i386-win32
#
# La receta salio de armarlo a mano (IA_LAB/agentes/PJPG/fpc-link/RESULTADOS.md),
# con dos trampas:
#  - el compilador se arma con PPC_TARGET=i386 y SIN OS_TARGET=win32: con el,
#    las herramientas del propio build (msg2inc) se compilan para Windows y el
#    build se rompe;
#  - Debian quita rtl/i386/makefile.cpu, que es escrito a mano y no generado.
#    Va abajo tal cual el del tag release_3_2_2.
# Necesita: fpc (ppcx64), fpcmake, fpc-source, make.
set -euo pipefail
OUT=${1:?uso: fpc_i386_win32.sh <dir>}
VER=$(fpc -iV)
FUENTE=/usr/share/fpcsrc/$VER
[ -d "$FUENTE/compiler" ] || { echo "FALLA: no estan las fuentes de FPC $VER en $FUENTE (paquete fpc-source)"; exit 1; }
MSG=$(ls -d /usr/lib/*/fpc/$VER/msg 2>/dev/null | head -1)
[ -n "$MSG" ] || { echo "FALLA: no encuentro los .msg de FPC $VER"; exit 1; }
mkdir -p "$OUT"; OUT=$(realpath "$OUT")
if [ -x "$OUT/ppc386" ] && [ -f "$OUT/units/i386-win32/system.ppu" ]; then
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
( cd "$S/compiler" && make PPC_TARGET=i386 PP=ppcx64 compiler > "$OUT/compilador.log" 2>&1 ) \
  || { tail -20 "$OUT/compilador.log"; exit 1; }
cp "$S/compiler/ppc386" "$OUT/ppc386"
( cd "$S/rtl" && make OS_TARGET=win32 CPU_TARGET=i386 FPC="$OUT/ppc386" > "$OUT/rtl.log" 2>&1 ) \
  || { tail -20 "$OUT/rtl.log"; exit 1; }
mkdir -p "$OUT/units"; rm -rf "$OUT/units/i386-win32"
cp -r "$S/rtl/units/i386-win32" "$OUT/units/"
n=$(ls "$OUT/units/i386-win32"/*.ppu | wc -l)
[ "$n" -ge 50 ] || { echo "FALLA: el RTL salio con $n unidades"; exit 1; }
rm -rf "$S"
echo "[OK] $OUT/ppc386 y $OUT/units/i386-win32 ($n unidades)"
