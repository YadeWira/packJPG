#!/usr/bin/env bash
# El .pja desde el CLI: lo que un usuario hace con packJPG, celda por celda.
#
#   cli_pja.sh [binario] [dir con jpgs]     (por defecto ./packJPG y ../test-files)
#
# Cada celda dice que espera. Se cuentan: menos celdas de las previstas es una
# falla, no un verde.
set -u
BIN=$(realpath "${1:-./packJPG}")
JPGS=$(realpath "${2:-../test-files}")
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
cd "$T"

celdas=0; fallas=0
ok()   { celdas=$((celdas+1)); printf '  %-68s ok\n' "$1"; }
mal()  { celdas=$((celdas+1)); fallas=$((fallas+1)); printf '  %-68s FALLA\n' "$1"; }
chk()  { if eval "$2"; then ok "$1"; else mal "$1"; fi; }
# el comando (a, x, list) va primero: packJPG <comando> [switches] [archivos]
pj()   { local c=$1; shift; "$BIN" "$c" --no-pause "$@" > "$T/ultimo.log" 2>&1; }

fresco() { rm -rf "$T/w"; mkdir -p "$T/w"; cp "$JPGS"/*.jpg "$T/w/"; cd "$T/w"; }
n_jpg=$(ls "$JPGS"/*.jpg | wc -l)

echo "--- a escribe .pja por defecto, x lo devuelve igual"
fresco
pj a *.jpg; chk "a: rc 0" '[ $? -eq 0 ]'
chk "a: un .pja por JPEG ($n_jpg)" '[ $(ls *.pja | wc -l) -eq '$n_jpg' ]'
chk "a: ningun .pjg" '! ls *.pjg >/dev/null 2>&1'
chk "la magia es PJA" '[ "$(head -c 4 color_photo.pja | od -An -c | tr -d " ")" = "PJA001" ]'
mkdir out; pj x -o out/ *.pja; chk "x: rc 0" '[ $? -eq 0 ]'
iguales=0; for f in *.jpg; do cmp -s "$f" "out/$f" && iguales=$((iguales+1)); done
chk "x: $n_jpg de $n_jpg JPEG byte a byte" '[ $iguales -eq '$n_jpg' ]'
pj list color_photo.pja
chk "list: dice .pja v2, sin cifrar, y el tamano" 'grep -q "pja v2, not encrypted" "$T/ultimo.log" && grep -q "JPEG size   : $(stat -c %s color_photo.jpg) bytes" "$T/ultimo.log"'

echo "--- --pjg: el formato de antes, y se sigue leyendo"
fresco
pj a --pjg color_photo.jpg; chk "a --pjg: escribe .pjg" '[ -f color_photo.pjg ] && [ ! -f color_photo.pja ]'
chk "  con la magia JS" '[ "$(head -c 2 color_photo.pjg)" = "JS" ]'
mkdir out; pj x -o out/ color_photo.pjg; chk "x de un .pjg: igual" 'cmp -s color_photo.jpg out/color_photo.jpg'
pj a --pjg -e --password=x color_photo.jpg; chk "--pjg con contrasena: rechaza" '[ $? -ne 0 ] && grep -q "cannot be encrypted" "$T/ultimo.log"'

echo "--- cifrado, por cada fuente de contrasena"
fresco
printf 'clave segura\n' > pass.txt; chmod 600 pass.txt
pj a --password-file=pass.txt color_photo.jpg; chk "a --password-file (0600): rc 0" '[ $? -eq 0 ]'
chk "  el .pja dice cifrado (byte 5 = 1)" '[ "$(od -An -tu1 -j5 -N1 color_photo.pja | tr -d " ")" = "1" ]'
chk "  ni el hash ni el JPEG en claro" 'python3 -c "
import sys,hashlib
j=open(\"color_photo.jpg\",\"rb\").read(); p=open(\"color_photo.pja\",\"rb\").read()
sys.exit(1 if any(j[i:i+16] in p for i in range(0,len(j)-16,997)) else 0)"'
mkdir out
pj x -o out/ color_photo.pja; chk "x sin contrasena (sin terminal): rechaza, y dice que pide contrasena" '[ $? -ne 0 ] && grep -q "this .pja is encrypted -- give the password" "$T/ultimo.log"'
chk "  y no escribe nada" '[ ! -e out/color_photo.jpg ]'
pj x -o out/ --password=otra color_photo.pja; chk "x con la equivocada: rechaza" '[ $? -ne 0 ] && grep -q "wrong password" "$T/ultimo.log"'
chk "  y no escribe nada" '[ ! -e out/color_photo.jpg ]'
printf 'clave segura\n' | "$BIN" x --no-pause -o out/ --password-stdin color_photo.pja > "$T/ultimo.log" 2>&1
chk "x --password-stdin (una linea, sin el fin de linea): igual" 'cmp -s color_photo.jpg out/color_photo.jpg'
rm -f out/*
pj x -o out/ "--password=clave segura" color_photo.pja; chk "x --password=: igual" 'cmp -s color_photo.jpg out/color_photo.jpg'
chmod 644 pass.txt
pj a -f --password-file=pass.txt baseline_444.jpg; chk "--password-file 0644: rechaza, nombra chmod 600" '[ $? -ne 0 ] && grep -q "chmod 600" "$T/ultimo.log" && [ ! -e baseline_444.pja ]'
chmod 600 pass.txt
pj a --password-file=pass.txt --password=y baseline_444.jpg; chk "dos fuentes de contrasena: rechaza" '[ $? -ne 0 ] && grep -q "one way only" "$T/ultimo.log"'
pj a -e baseline_444.jpg < /dev/null; chk "-e sin terminal: rechaza y dice como" '[ $? -ne 0 ] && grep -q "needs a terminal" "$T/ultimo.log"'
pj a --password= baseline_444.jpg; chk "contrasena vacia al cifrar: rechaza" '[ $? -ne 0 ] && grep -q "empty" "$T/ultimo.log"'
pj a --password=uno baseline_444.jpg && pj a -f --password=uno -o otro.pja baseline_444.jpg
chk "dos cifrados del mismo JPEG: distintos (sal del sistema)" '! cmp -s baseline_444.pja otro.pja'

echo "--- lo que no verifica no queda con su nombre"
fresco
pj a color_photo.jpg
# un byte del hash declarado (offset 16..31): el JPEG decodifica perfecto, el hash no
python3 - color_photo.pja <<'EOF'
import sys; p=sys.argv[1]; d=bytearray(open(p,'rb').read()); d[20]^=1; open(p,'wb').write(d)
EOF
mkdir out; pj x -o out/ color_photo.pja
chk "hash alterado: rechaza" '[ $? -ne 0 ] && grep -q "does not match the hash" "$T/ultimo.log"'
chk "  y no queda color_photo.jpg" '[ ! -e out/color_photo.jpg ] && [ -z "$(ls out)" ]'
pj x -o out/ --keep-corrupt color_photo.pja
chk "con --keep-corrupt: queda .corrupto y rc != 0" '[ $? -ne 0 ] && [ -f out/color_photo.jpg.corrupto ] && [ ! -e out/color_photo.jpg ]'
chk "  y el .corrupto es el JPEG decodificado" 'cmp -s color_photo.jpg out/color_photo.jpg.corrupto'
cp color_photo.jpg viejo.jpg; cp color_photo.jpg out/color_photo.jpg; echo distinto >> out/color_photo.jpg; cp out/color_photo.jpg esperado.jpg
pj x -f -o out/ color_photo.pja
chk "-f y un .pja que falla: el archivo que habia NO se borra" '[ $? -ne 0 ] && cmp -s out/color_photo.jpg esperado.jpg'
pj a -f grayscale.jpg
python3 - grayscale.pja <<'EOF'
import sys; p=sys.argv[1]; d=bytearray(open(p,'rb').read()); d[8]^=0xFF; open(p,'wb').write(d)
EOF
pj x -o out/ grayscale.pja; chk "tam_orig alterado: rechaza sin escribir" '[ $? -ne 0 ] && [ ! -e out/grayscale.jpg ]'
chk "  y dice que el tamano no coincide" 'grep -q "declares 689 bytes and the JPEG has 590" "$T/ultimo.log"'
pj x -o out/ --keep-corrupt grayscale.pja
chk "  con --keep-corrupt: .corrupto, el JPEG decodificado" '[ $? -ne 0 ] && [ ! -e out/grayscale.jpg ] && cmp -s grayscale.jpg out/grayscale.jpg.corrupto'
cp grayscale.jpg g2.jpg; pj a g2.jpg
python3 - g2.pja <<'EOF2'
import sys; p=sys.argv[1]; d=bytearray(open(p,'rb').read()); d[8]=100; d[9]=0; open(p,'wb').write(d)
EOF2
pj x -o out/ g2.pja; chk "tam_orig mas chico que el JPEG: lo corta el decodificador" '[ $? -ne 0 ] && grep -qE "size limit|too large" "$T/ultimo.log" && [ ! -e out/g2.jpg ]'
head -c 30 color_photo.jpg > corto.jpg; cp baseline_444.jpg b.jpg; pj a -f b.jpg
truncate -s 40 b.pja; pj x -o out/ b.pja; chk ".pja truncado: rechaza" '[ $? -ne 0 ] && [ ! -e out/b.jpg ]'

echo "--- --max-output contra el tamano declarado, ANTES de decodificar"
fresco
pj a color_photo.jpg
pj x --max-output=10K color_photo.pja; chk "declara 21 KB, tope 10K: rechaza sin decodificar" '[ $? -ne 0 ] && grep -q "over --max-output" "$T/ultimo.log" && [ ! -e color_photo_.jpg ]'

echo "--- la salida no se escribe a traves de un enlace"
fresco
pj a color_photo.jpg; rm color_photo.jpg
mkdir afuera; echo original > afuera/victima.txt; ln -s "$PWD/afuera/victima.txt" color_photo.jpg
pj x -f color_photo.pja
chk "x -f con un enlace en el nombre: escribe" '[ $? -eq 0 ] && [ ! -L color_photo.jpg ] && cmp -s color_photo.jpg "$JPGS/color_photo.jpg"'
chk "  y lo de afuera queda intacto" '[ "$(cat afuera/victima.txt)" = original ]'

echo "--- hilos, pipes, -n"
fresco
mkdir mezcla; for f in *.jpg; do cp "$f" "mezcla/c_$f"; done
pj a --password=hilos mezcla/c_*.jpg; pj a mezcla/[bg]*.jpg 2>/dev/null; pj a *.jpg
rm -f mezcla/*.jpg
mkdir out; pj x -th 4 --password=hilos -o out/ *.pja mezcla/*.pja
chk "x -th 4, cifrados y sin cifrar mezclados: rc 0" '[ $? -eq 0 ]'
iguales=0; for f in *.jpg; do cmp -s "$f" "out/$f" && cmp -s "$f" "out/c_$f" && iguales=$((iguales+1)); done
chk "  $n_jpg de $n_jpg, los dos" '[ $iguales -eq '$n_jpg' ]'
"$BIN" a --no-pause - < color_photo.jpg > pipe.pja 2>/dev/null
chk "a - (pipe): sale un .pja por stdout" '[ "$(head -c 3 pipe.pja)" = PJA ]'
"$BIN" x --no-pause - < pipe.pja > pipe.jpg 2>/dev/null
chk "x - (pipe): vuelve igual" 'cmp -s pipe.jpg color_photo.jpg'
rm -f *.pja; pj a -n *.jpg; chk "-n: no escribe ningun .pja" '! ls *.pja >/dev/null 2>&1'

echo
echo "$celdas celdas, $fallas fallas"
[ "$celdas" -ge 43 ] || { echo "FALLA: esperaba al menos 43 celdas"; exit 2; }
[ "$fallas" -eq 0 ]
