#!/usr/bin/env python3
"""Escenarios de disco para el diferencial de pjafs.

    escenarios_fs.py generar <raiz_rust> <raiz_pascal> <casos.txt>
    escenarios_fs.py listar  <raiz>

`generar` arma el MISMO arbol en las dos raices (tienen que tener el mismo
largo canonico: los limites de largo dependen de eso) y escribe los casos. Lo
arma un tercero a proposito: si cada punta preparara su propio disco, un error
en esa preparacion se veria como diferencia del port, o peor, se taparia.

`listar` vuelca el arbol sin seguir enlaces (tipo, permisos, tamano, hash,
destino del enlace, cantidad de enlaces duros), relativo a la raiz: despues de
correr las dos puntas, los dos listados tienen que ser iguales.

Los casos que escriben (W, X) tienen cada uno su escenario: lo que uno deja
en disco no puede cambiar lo que ve el siguiente. Los D y C solo resuelven y
comparten uno."""
import os, sys, stat, shutil, hashlib

def h(b): return b.hex() if b else '-'

def limpiar(raiz):
    if os.path.lexists(raiz):
        for d, ds, fs in os.walk(raiz):
            for x in ds:
                p = os.path.join(d, x)
                if not os.path.islink(p): os.chmod(p, 0o755)
        shutil.rmtree(raiz)
    os.makedirs(raiz)

RAROS = [b'\xff', b'inv\xe1\x80x', b'\xed\xa0\x80', b'\xf0\x9f\x98', b'ok\xc3\xb1']

def escenario(s):
    """El arbol de un escenario: destino `d` y un `afuera` al lado."""
    os.makedirs(f'{s}/afuera'); os.makedirs(f'{s}/d/sub'); os.makedirs(f'{s}/d/dir_lleno')
    for p, c in [('afuera/victima.txt', b'original'), ('afuera/victima2.txt', b'original2'),
                 ('d/foto.jpg', b'existente'), ('d/sub/interno.jpg', b'interno'), ('d/archivo', b'x'),
                 ('d/dir_lleno/x', b'x'), ('d/foto.jpg.corrupto', b'viejo')]:
        open(f'{s}/{p}', 'wb').write(c)
    for dst, src in [('d/enlace_afuera', '../afuera'), ('d/enlace_adentro', 'sub'),
                     ('d/enlace_colgante', '../afuera/no_existe_dir'), ('d/colgante.jpg', '../afuera/nuevo.jpg'),
                     ('d/final_afuera.jpg', '../afuera/victima.txt'), ('d/g.jpg.corrupto', 'no_existe'),
                     ('d/arriba', '..'), ('d/raiz', '/'), ('d/propio', '.'), ('d/sub/atras', '..'),
                     ('d/sub/afuera_rel', '../../afuera')]:
        os.symlink(src, f'{s}/{dst}')
    os.link(f'{s}/afuera/victima2.txt', f'{s}/d/duro.jpg')
    for r in RAROS: os.makedirs(os.fsencode(f'{s}/d/') + r)
    os.makedirs(f'{s}/d/ro'); os.chmod(f'{s}/d/ro', 0o555)

def largo16(b):
    return len(b.decode('utf-8', 'replace').encode('utf-16-le')) // 2

def generar(rr, rp, salida):
    raices = list(dict.fromkeys((rr, rp)))   # una sola si son la misma (los mutantes)
    for r in raices: limpiar(r)
    cr, cp = os.path.realpath(rr), os.path.realpath(rp)
    assert len(cr) == len(cp), f'las raices tienen que tener el mismo largo: {cr} {cp}'
    casos, escs = [], []
    def nuevo_esc():
        n = f's{len(escs)}'; escs.append(n); return n

    E = lambda s: s.encode()
    nombres = [E(x) for x in ['foto.jpg', 'nuevo.jpg', 'ñandú.jpg', '写真.jpg', '😀.jpg', 'archivo .jpg',
               'CON.jpg', 'foto?.jpg', 'a.', 'b ', '../x', '/etc/passwd', '', 'a:b', 'a\\b',
               'colgante.jpg', 'final_afuera.jpg', 'duro.jpg', 'sub', 'archivo', 'dir_lleno', 'enlace_afuera',
               'enlace_colgante', 'g.jpg', 'sub/foto.jpg', 'sub/interno.jpg', 'nuevo/dir/foto.jpg',
               'enlace_afuera/x.jpg', 'enlace_adentro/x.jpg', 'enlace_colgante/x.jpg', 'enlace_colgante/y/x.jpg',
               'archivo/x.jpg', 'ro/x.jpg', 'ro/n/x.jpg', 'a/../b', './a', 'sub/CON', 'sub/', 'a//b',
               'arriba/x.jpg', 'arriba/d/x.jpg', 'raiz/tmp/x.jpg', 'propio/x.jpg', 'propio/propio/x.jpg',
               'enlace_afuera/a/b.jpg', 'sub/atras/x.jpg', 'sub/atras/arriba/x.jpg', 'sub/afuera_rel/x.jpg',
               'arriba', 'raiz', 'sub/atras',
               'x/' * 31 + 'f.jpg', 'x/' * 32 + 'f.jpg']] + [b'x\x01', b'\xff.jpg', b'a' * 255, b'a' * 256]
    dests = [b'd', b'd/sub', b'd/enlace_afuera', b'd/enlace_adentro', b'd/noexiste', b'd/archivo',
             b'd/enlace_colgante', b'd/ro', b'', b'd/foto.jpg'] + [b'd/' + r for r in RAROS]

    # D: solo resuelven, un escenario para todos
    s0 = nuevo_esc()
    for dest in dests:
        base = os.fsencode(cr) + b'/' + s0.encode() + (b'/' + dest if dest else b'')
        # nombres en el borde de 260, contados como cuenta Windows
        borde = []
        lb = largo16(os.path.realpath(base)) if os.path.isdir(os.path.realpath(base)) else largo16(base)
        for extra in (-2, -1, 0, 1, 2):
            k = 260 - lb - 1 + extra
            for relleno, u in ((b'x', 1), ('ñ'.encode(), 1), ('😀'.encode(), 2)):
                if k >= u and (k // u) * len(relleno) <= 255:
                    borde.append(relleno * (k // u) + b'x' * (k % u))
        for nom in nombres + borde:
            for rutas in '01':
                for sobr in '01':
                    casos.append(f'D {s0} {h(dest)} {h(nom)} {rutas} {sobr}')
    # destino `/`: absoluto (join lo reemplaza entero). Solo resuelven; llegar a
    # la raiz al subir buscando el ancestro que existe es el unico camino a Padre('/x')
    for nom in [b'nuevo_pjafs/x.jpg', b'no_existe_pjafs/a/b.jpg', b'tmp', b'x_pjafs.jpg', b'tmp/x_pjafs/y.jpg']:
        for sobr in '01':
            casos.append(f'D {s0} {h(b"/")} {h(nom)} 1 {sobr}')
    # C: destino relativo, con la cwd en el escenario
    for dest in (b'd', b'd/sub', b'', b'.', b'd/../d', b'd/enlace_afuera'):
        for nom in [b'foto.jpg', b'nuevo.jpg', b'sub/x.jpg'] + [b'x' * k for k in range(150, 256, 7)]:
            casos.append(f'C {s0} {h(dest)} {h(nom)} 1 0')

    # W: resuelven y escriben, un escenario cada uno
    wnoms = [E(x) for x in ['nuevo.jpg', 'foto.jpg', 'colgante.jpg', 'final_afuera.jpg', 'duro.jpg', 'sub',
             'dir_lleno', 'archivo', 'g.jpg', 'nuevo/dir/foto.jpg', 'enlace_adentro/x.jpg', 'archivo/x.jpg',
             'ro/x.jpg', 'ro/n/x.jpg', 'CON.jpg', '😀.jpg', 'enlace_colgante/x.jpg', 'enlace_afuera/x.jpg',
             'arriba/x.jpg', 'arriba/afuera/x.jpg', 'sub/afuera_rel/victima.txt', 'propio/x.jpg', 'sub/atras/x.jpg']]
    semillas = ['0', '5', '70000', '200000']
    i = 0
    for dest in (b'd', b'd/sub', b'd/enlace_adentro', b'd/ro'):
        for nom in wnoms:
            for sobr in '01':
                for ok in '10':
                    for si in 'BC':
                        casos.append(f'W {nuevo_esc()} {h(dest)} {h(nom)} 1 {sobr} {semillas[i % 4]} {ok} {si}')
                        i += 1
    # X: escribir_verificado directo, sobre lo que destino_de no deja pasar (la carrera)
    for ruta in ['d/colgante.jpg', 'd/final_afuera.jpg', 'd/duro.jpg', 'd/foto.jpg', 'd/sub', 'd/ro/x.jpg',
                 'd/nuevo.jpg', 'd/archivo/x.jpg', 'd/enlace_colgante/x.jpg', 'd/enlace_colgante/y/x.jpg',
                 'd/enlace_afuera/x.jpg', 'd/g.jpg', 'd/ro/n/x.jpg', 'd/dir_lleno', 'd/arriba/afuera/victima.txt',
                 'd/sub/afuera_rel/nuevo.jpg']:
        for sobr in '01':
            for ok in '10':
                for si in 'BC':
                    casos.append(f'X {nuevo_esc()} {h(E(ruta))} {sobr} {semillas[i % 4]} {ok} {si}')
                    i += 1
    # .corrupto agotados: 999 ocupados (queda el .999) y los 1000 (no queda ninguno)
    for ocupados in (999, 1000):
        s = nuevo_esc()
        casos.append(f'W {s} {h(b"d")} {h(b"z.jpg")} 1 0 5 0 C')
    for r in raices:
        for s in escs: escenario(f'{r}/{s}')
        for k, ocupados in ((-2, 999), (-1, 1000)):
            s = escs[k]
            for n in range(ocupados):
                open(f'{r}/{s}/d/z.jpg.corrupto' + (f'.{n}' if n else ''), 'wb').write(b'')
    with open(salida, 'w') as o:
        for c in casos: o.write(c + '\n')
    print(f'{len(casos)} casos, {len(escs)} escenarios', file=sys.stderr)

def listar(raiz):
    out = []
    raiz = os.fsencode(raiz)
    for d, ds, fs in os.walk(raiz):
        ds.sort()
        for x in sorted(ds + fs):
            p = os.path.join(d, x); st = os.lstat(p); r = os.path.relpath(p, raiz)
            m = stat.S_IMODE(st.st_mode)
            if stat.S_ISLNK(st.st_mode): out.append(f'{h(r)} l {h(os.readlink(p))}')
            elif stat.S_ISDIR(st.st_mode): out.append(f'{h(r)} d {m:o}')
            else:
                out.append(f'{h(r)} f {m:o} {st.st_size} {st.st_nlink} '
                           f'{hashlib.blake2b(open(p, "rb").read(), digest_size=8).hexdigest()}')
    for l in sorted(set(out)): print(l)

def afuera(raiz, casos):
    """Cuantos escenarios terminaron con `afuera` distinto del inicial, por tipo de
    caso. Los W pasan por destino_de: tienen que ser 0. Los X escriben directo a
    traves de enlaces que salen: tienen que ser > 0 (control positivo)."""
    ini = {'victima.txt': b'original', 'victima2.txt': b'original2'}
    cuenta = {'W': [0, 0], 'X': [0, 0]}
    for l in open(casos):
        w = l.split()
        if w[0] not in cuenta: continue
        a = os.path.join(raiz, w[1], 'afuera')
        ahora = {x: open(os.path.join(a, x), 'rb').read() for x in os.listdir(a)}
        cuenta[w[0]][0] += 1
        if ahora != ini: cuenta[w[0]][1] += 1
    for k, (n, c) in cuenta.items(): print(f'{k} {c} de {n} escenarios con afuera cambiado')
    if cuenta['W'][1] != 0: sys.exit(1)      # violacion: algo que paso por destino_de escribio afuera
    if cuenta['X'][1] == 0: sys.exit(2)      # el control positivo no escribio: el chequeo no prueba nada

if __name__ == '__main__':
    if sys.argv[1] == 'generar': generar(sys.argv[2], sys.argv[3], sys.argv[4])
    elif sys.argv[1] == 'listar': listar(sys.argv[2])
    elif sys.argv[1] == 'afuera': afuera(sys.argv[2], sys.argv[3])
    else: sys.exit('uso: escenarios_fs.py generar <rr> <rp> <casos> | listar <raiz>')
