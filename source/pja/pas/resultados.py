#!/usr/bin/env python3
"""Corta el build si una funcion nunca nombra `Result` fuera de un Exit(...).

FPC no avisa "el resultado no parece asignado" si ALGUN camino hace
Exit(valor), aunque otro camino llegue al `end` sin asignarlo. Paso en
pjafs.Padre (2026-10-09): devolvia lo que quedara en el registro, y el
diferencial lo mostro como un fallo intermitente, 1 corrida de cada ~10.

La regla es de estilo y no de flujo: alcanza con que el cuerpo use `Result`
(asignado, o pasado a algo que lo llena, como WriteStr o un parametro out).
Uso: resultados.py <dir_pas>"""
import re, sys, glob, os

def revisar(f):
    s = open(f, encoding='utf-8', errors='replace').read()
    k = s.lower().find('implementation')
    cuerpo_unidad = s[k:] if k >= 0 else s
    malas = []
    for m in re.finditer(r'\nfunction\s+([\w.]+)\s*(\([^)]*\))?\s*:\s*[\w.<>]+\s*;', cuerpo_unidad):
        ini = m.end()
        sig = re.search(r'\n(function|procedure|constructor|destructor)\s', cuerpo_unidad[ini:])
        cuerpo = cuerpo_unidad[ini: ini + (sig.start() if sig else len(cuerpo_unidad))]
        if re.match(r'\s*(stdcall|cdecl)?\s*;?\s*external\b', cuerpo) or re.search(r'\bexternal\b', cuerpo.split('\n', 1)[0]):
            continue
        sin_exit = re.sub(r'\bExit\s*\([^)]*\)', '', cuerpo, flags=re.I)
        if not re.search(r'\bResult\b', sin_exit, re.I):
            malas.append(m.group(1))
    return malas

d = sys.argv[1]
total = 0
for f in sorted(glob.glob(f'{d}/*.pas') + glob.glob(f'{d}/*/*.pas')):
    for n in revisar(f):
        print(f'  {os.path.relpath(f, d)}: {n} nunca nombra Result fuera de Exit(...)'); total += 1
print(f'{total} funciones sin Result')
sys.exit(1 if total else 0)
