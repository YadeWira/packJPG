#!/bin/bash
# Arma el nucleo .pja entero como DLL para Windows 64 y/o 32 bits, mas
# test_frontera.exe enlazado contra ella.
#
# La DLL sale con el nombre de su arquitectura, pjaffi_x64.dll y pjaffi_x86.dll,
# porque las dos van al mismo dist/ junto a sus packJPG.exe. Renombrar el
# archivo no alcanza: el .exe importa el nombre INTERNO de la DLL (PJAFFI.dll,
# medido). Por eso se arma una biblioteca de importacion con dlltool desde un
# .def que dice LIBRARY pjaffi_x64.dll, y el .exe se enlaza contra ella.
#   $OUT/<64|32>/pjaffi_<x64|x86>.dll y libpjaffi_<x64|x86>.dll.a
#
#   PJA_DIR=... OUT=... [ARCH="64 32"] [PPC386=/ruta/ppc386] [RTL386=/ruta/units/i386-win32] frontera_win.sh
#
# Por que DLL y no estatica (medido, fpc-link/RESULTADOS.md): metida en el .exe
# obliga a --disable-reloc-section y el ejecutable ENTERO pierde ASLR. La DLL
# sale reubicable, y {$SetPEOptFlags $140} en pjaffi.pas la declara apta para
# ASLR y DEP. En Windows el runtime de FPC arranca al cargar la DLL:
# pja_iniciar solo lo confirma.
#
# 64 bits: el fpc del sistema con las unidades x86_64-win64.
# 32 bits: un ppc386 cruzado y el RTL i386-win32 (Debian no los trae; receta en
#          fpc-link/RESULTADOS.md, "El compilador cruzado de 32 bits").
# Probado en Windows 10 19044 y Windows 7 SP1 reales, 32 y 64 bits.
set -euo pipefail
PJA=$(realpath "${PJA_DIR:?}"); PAS=$PJA/pas
OUT=${OUT:?}; mkdir -p "$OUT"; OUT=$(realpath "$OUT")
for a in ${ARCH:-64 32}; do
  if [ "$a" = 64 ]; then
    T=x86_64-w64-mingw32; FPCW=(fpc -Twin64 -Px86_64); ARQ=x64
  else
    T=i686-w64-mingw32; ARQ=x86
    FPCW=("${PPC386:?falta PPC386 para 32 bits}" -Twin32 -Fu"${RTL386:?falta RTL386}")
  fi
  D=$OUT/$a; rm -rf "$D"; mkdir -p "$D/c"
  for f in pja_cripto blake3/blake3 blake3/blake3_dispatch blake3/blake3_portable monocypher/monocypher; do
    $T-gcc -O2 -std=c99 -DBLAKE3_NO_SSE2 -DBLAKE3_NO_SSE41 -DBLAKE3_NO_AVX2 -DBLAKE3_NO_AVX512 \
        -I"$PAS/c" -c "$PAS/c/$f.c" -o "$D/c/$(basename "$f").o"
  done
  ( cd "$D" && "${FPCW[@]}" -O2 -Fu"$PAS" -Fi"$PAS" -Fo"$D/c" -FU"$D" -FE"$D" \
      -Fl"$(dirname "$($T-gcc -print-libgcc-file-name)")" -Fl"/usr/$T/lib" "$PAS/pjaffi.pas" > fpc.log 2>&1 ) \
    || { cat "$D/fpc.log"; exit 1; }
  # g++ con hilos posix: todo artefacto Windows del proyecto es posix (memoria
  # mingw-posix-thread-model), y std::thread lo necesita.
  # .def desde la tabla de exportacion real, no una lista a mano que se desactualiza
  { echo "LIBRARY pjaffi_$ARQ.dll"; echo "EXPORTS";
    $T-objdump -p "$D/pjaffi.dll" | sed -n '/Ordinal\/Name Pointer/,/^$/p' | awk '/\+base/ {print "  " $NF}'; } > "$D/pjaffi_$ARQ.def"
  n=$(grep -c '^  pja_' "$D/pjaffi_$ARQ.def")
  [ "$n" -ge 15 ] || { echo "FALLA: el .def salio con $n exportaciones"; exit 1; }
  cp "$D/pjaffi.dll" "$D/pjaffi_$ARQ.dll"
  $T-dlltool -d "$D/pjaffi_$ARQ.def" -l "$D/libpjaffi_$ARQ.dll.a"
  $T-g++-posix -O2 -std=c++17 -static -I"$PJA/include" "$PJA/test_frontera.cpp" "$D/libpjaffi_$ARQ.dll.a" -o "$D/test_frontera.exe"
  imp=$($T-objdump -p "$D/test_frontera.exe" | grep -i 'DLL Name.*pjaffi\|Nombre DLL.*pjaffi' | awk '{print $NF}')
  [ "$imp" = "pjaffi_$ARQ.dll" ] || { echo "FALLA: test_frontera.exe importa '$imp', esperaba pjaffi_$ARQ.dll"; exit 1; }
  car=$($T-objdump -p "$D/pjaffi.dll" | awk '/DllCharacteristics/ {print $2}')
  [ "$car" = 00000140 ] || { echo "FALLA: DllCharacteristics $car, esperaba 00000140 (ASLR + DEP)"; exit 1; }
  echo "[OK] $D: pjaffi_$ARQ.dll (ASLR+DEP, $n exportaciones), libpjaffi_$ARQ.dll.a, test_frontera.exe"
done
