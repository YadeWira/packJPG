#!/bin/bash
# Pruebas de la capa Pascal del contenedor: unitarias portadas del Rust y
# diferenciales contra el Rust REAL. Lo llama `make pja-pas-tests`.
#
# set -e es a proposito: si algo no compila o no corre, se corta aca, en vez de
# comparar despues contra un archivo vacio. Y cada diferencial CUENTA lineas:
# dos salidas vacias no pasan por "iguales".
set -euo pipefail
FPC=${FPC:-fpc}; CARGO=${CARGO:-cargo}; CC=${PAS_CC:-gcc}
PJA=${PJA_DIR:?}; PAS=$PJA/pas; OUT=${PAS_OUT:-$PAS/build}
mkdir -p "$OUT/c"

echo "== identificadores que chocan sin distinguir mayusculas"
python3 "$PAS/colisiones.py" "$PAS"
echo "== funciones que nunca asignan Result (FPC no avisa si algun camino hace Exit)"
python3 "$PAS/resultados.py" "$PAS"

echo "== cripto en C (BLAKE3 1.8.7 portable, Monocypher 4.0.3 + la frontera pja_cripto)"
for f in pja_cripto blake3/blake3 blake3/blake3_dispatch blake3/blake3_portable monocypher/monocypher; do
  $CC -O2 -std=c99 -DBLAKE3_NO_SSE2 -DBLAKE3_NO_SSE41 -DBLAKE3_NO_AVX2 -DBLAKE3_NO_AVX512 \
      -I"$PAS/c" -c "$PAS/c/$f.c" -o "$OUT/c/$(basename "$f").o"
done
LIBGCC=$(dirname "$($CC -print-libgcc-file-name)")

echo "== compilar"
for prog in pruebas/prueba_nombres pruebas/prueba_cripto pruebas/prueba_indice pruebas/prueba_escritor pruebas/prueba_cifrado pruebas/prueba_contenedor \
            pruebas/prueba_corrupcion pruebas/prueba_pjafs diferencial/dif_nombres diferencial/dif_indice diferencial/dif_escritor diferencial/dif_cifrado \
            diferencial/dif_contenedor diferencial/dif_corrupcion diferencial/dif_pjafs; do
  $FPC -O2 -Fu"$PAS" -Fi"$PAS" -Fo"$OUT/c" -FU"$OUT" -FE"$OUT" -Fl"$LIBGCC" "$PAS/$prog.pas" > "$OUT/fpc.log" 2>&1 \
    || { cat "$OUT/fpc.log"; exit 1; }
done

echo "== referencias Rust"
$CARGO build --release --manifest-path "$PJA/Cargo.toml" \
  --example dif_nombres --example dif_indice --example dif_escritor --example dif_cifrado --example dif_contenedor --example dif_corrupcion \
  --example dif_pjafs --example kat_cripto
EX=$PJA/target/release/examples
"$EX/kat_cripto" "$OUT/kat" > /dev/null

echo "== pruebas portadas"
"$OUT/prueba_nombres" | tail -1
"$OUT/prueba_cripto" "$OUT/kat" | tail -1
"$OUT/prueba_indice" | tail -1
"$OUT/prueba_cifrado" "$OUT/kat" | tail -1
# .pjg reales para el round-trip: los genera `make pja-corpus` con el packJPG de este arbol
CORPUS=$PJA/pruebas/corpus
ls "$CORPUS"/*.pjg > /dev/null 2>&1 || { echo "FALLA: no hay .pjg en $CORPUS (make pja-corpus)"; exit 1; }
"$OUT/prueba_escritor" "$CORPUS" | tail -1
"$OUT/prueba_contenedor" "$CORPUS" | tail -1
"$OUT/prueba_corrupcion" "$CORPUS" | tail -1
# pjafs toca disco: un directorio propio, ya resuelto (la prueba compara contra
# rutas canonicas, y un enlace en el camino la haria fallar sin motivo)
mkdir -p "$OUT/tmp_pjafs"; "$OUT/prueba_pjafs" "$(realpath "$OUT/tmp_pjafs")" | tail -1

diferencial() {   # nombre, cantidad minima de entradas, comando rust, comando pascal
  local n=$1 min=$2 corpus=$3 rust=$4 pas=$5
  # las dos puntas son independientes: en paralelo. `wait PID` devuelve el rc
  # de cada una, asi que set -e sigue cortando si alguna falla.
  local pr pp
  "$rust" "$corpus" > "$OUT/$n.rust.txt" & pr=$!
  "$pas"  "$corpus" > "$OUT/$n.pascal.txt" & pp=$!
  wait $pr; wait $pp
  local c r p d
  c=$(wc -l < "$corpus"); r=$(wc -l < "$OUT/$n.rust.txt"); p=$(wc -l < "$OUT/$n.pascal.txt")
  if [ "$c" -lt "$min" ] || [ "$r" -ne "$c" ] || [ "$p" -ne "$c" ]; then
    echo "FALLA $n: corpus $c lineas, rust $r, pascal $p -- tienen que coincidir y ser >= $min"; exit 1
  fi
  d=$(paste -d'|' "$OUT/$n.rust.txt" "$OUT/$n.pascal.txt" | awk -F'|' '$1 != $2' | wc -l)
  echo "diferencial $n: $d distintas de $c entradas"
  if [ "$d" -ne 0 ]; then
    paste -d'|' "$OUT/$n.rust.txt" "$OUT/$n.pascal.txt" | awk -F'|' '$1 != $2' | head -5 | cut -c1-200
    exit 1
  fi
}
echo "== diferenciales"
python3 "$PAS/diferencial/corpus.py" "$OUT/corpus_nombres.hex" > /dev/null
diferencial nombres 100000 "$OUT/corpus_nombres.hex" "$EX/dif_nombres" "$OUT/dif_nombres"
"$EX/dif_indice" generar "$OUT/corpus_indice.hex" 2> /dev/null
rust_indice()   { "$EX/dif_indice" leer "$1"; }
diferencial indice 20000 "$OUT/corpus_indice.hex" rust_indice "$OUT/dif_indice"
"$EX/dif_escritor" generar "$OUT/corpus_escritor.txt" 2> /dev/null
rust_escritor() { "$EX/dif_escritor" leer "$1"; }
diferencial escritor 10000 "$OUT/corpus_escritor.txt" rust_escritor "$OUT/dif_escritor"
# cifrado: el corpus es un directorio (corpus.txt + los contenedores base); las
# dos puntas reciben el directorio, y el conteo de lineas va contra corpus.txt
"$EX/dif_cifrado" generar "$OUT/corpus_cifrado" 2> /dev/null
rust_cifrado()   { "$EX/dif_cifrado" leer "$(dirname "$1")"; }
pascal_cifrado() { "$OUT/dif_cifrado" "$(dirname "$1")"; }
diferencial cifrado 2000 "$OUT/corpus_cifrado/corpus.txt" rust_cifrado pascal_cifrado
# contenedor: lo mismo, y la linea K (la clave de las E) no produce salida
"$EX/dif_contenedor" generar "$OUT/corpus_contenedor" 2> /dev/null
grep -v '^K ' "$OUT/corpus_contenedor/corpus.txt" > "$OUT/corpus_contenedor/casos.txt"
rust_contenedor()   { "$EX/dif_contenedor" leer "$(dirname "$1")"; }
pascal_contenedor() { "$OUT/dif_contenedor" "$(dirname "$1")"; }
diferencial contenedor 10000 "$OUT/corpus_contenedor/casos.txt" rust_contenedor pascal_contenedor
# corrupcion: el contenedor real se arma en cada punta desde los mismos .pjg;
# la primera linea compara ese contenedor, las demas cada celda de dano
"$EX/dif_corrupcion" generar "$CORPUS" "$OUT/corpus_corrupcion.txt" 2> /dev/null
rust_corrupcion()   { "$EX/dif_corrupcion" leer "$CORPUS" "$1"; }
pascal_corrupcion() { "$OUT/dif_corrupcion" "$CORPUS" "$1"; }
diferencial corrupcion 50000 "$OUT/corpus_corrupcion.txt" rust_corrupcion pascal_corrupcion
# pjafs: un tercero (escenarios_fs.py) arma el MISMO arbol en dos raices del
# mismo largo; cada punta corre los casos sobre la suya. Se comparan las salidas
# y despues los dos arboles enteros, y se exige que ningun caso que pase por
# destino_de haya tocado `afuera` (con control positivo: los X si lo tocan).
FS=$OUT/fs; mkdir -p "$FS"
python3 "$PAS/diferencial/escenarios_fs.py" generar "$FS/r" "$FS/p" "$FS/casos.txt" 2> /dev/null
rust_pjafs()   { "$EX/dif_pjafs" "$(realpath "$FS/r")" "$1"; }
pascal_pjafs() { "$OUT/dif_pjafs" "$(realpath "$FS/p")" "$1"; }
diferencial pjafs 4000 "$FS/casos.txt" rust_pjafs pascal_pjafs
python3 "$PAS/diferencial/escenarios_fs.py" listar "$FS/r" > "$FS/arbol_r.txt"
python3 "$PAS/diferencial/escenarios_fs.py" listar "$FS/p" > "$FS/arbol_p.txt"
if ! cmp -s "$FS/arbol_r.txt" "$FS/arbol_p.txt" || [ "$(wc -l < "$FS/arbol_r.txt")" -lt 20000 ]; then
  echo "FALLA pjafs: los arboles despues de correr difieren (o son demasiado chicos)"
  diff "$FS/arbol_r.txt" "$FS/arbol_p.txt" | head -5; exit 1
fi
echo "arbol pjafs: iguales, $(wc -l < "$FS/arbol_r.txt") entradas"
for r in r p; do python3 "$PAS/diferencial/escenarios_fs.py" afuera "$FS/$r" "$FS/casos.txt" | sed "s/^/  $r: /"; done
# Lo mismo con `ulimit -f`: las escrituras de 200.000 B fallan a la mitad con
# EFBIG (SIGXFSZ ignorada, y eso se hereda), que es el unico camino a "una
# escritura a medias no se deja tirada". Arbol nuevo: el anterior ya se escribio.
python3 "$PAS/diferencial/escenarios_fs.py" generar "$FS/r" "$FS/p" "$FS/casos.txt" 2> /dev/null
# la salida va por un pipe a cat, que corre SIN el limite: si no, el propio
# volcado a archivo tambien choca con ulimit -f
limitado() ( trap '' XFSZ; ulimit -f 100; exec "$@" )
rust_pjafs_l()   { limitado "$EX/dif_pjafs" "$(realpath "$FS/r")" "$1" | cat; }
pascal_pjafs_l() { limitado "$OUT/dif_pjafs" "$(realpath "$FS/p")" "$1" | cat; }
diferencial pjafs_efbig 4000 "$FS/casos.txt" rust_pjafs_l pascal_pjafs_l
n=$(grep -c 'Io(27)' "$OUT/pjafs_efbig.rust.txt" || true)
[ "$n" -gt 0 ] || { echo "FALLA pjafs_efbig: ninguna escritura llego a EFBIG, la pasada no probo nada"; exit 1; }
python3 "$PAS/diferencial/escenarios_fs.py" listar "$FS/r" > "$FS/arbol_r.txt"
python3 "$PAS/diferencial/escenarios_fs.py" listar "$FS/p" > "$FS/arbol_p.txt"
cmp -s "$FS/arbol_r.txt" "$FS/arbol_p.txt" || { echo "FALLA pjafs_efbig: los arboles difieren"; exit 1; }
echo "arbol pjafs_efbig: iguales, $n escrituras cortadas por EFBIG"
