#!/usr/bin/env python3
"""Busca identificadores que chocan sin distinguir mayusculas.

Pascal no distingue mayusculas: una variable `version` tapa a una constante
VERSION y el compilador no avisa. Paso de verdad al portar indice.rs (Rust SI
distingue, y su convencion garantiza pares FOO / foo): la comparacion quedo
`version > version` y ninguna version futura se rechazaba.

Heuristico a proposito: junta los nombres de constantes y tipos de todas las
unidades y los compara contra cada variable y parametro declarado. Sale != 0 si
hay un choque."""
import re, sys, glob, os
d = sys.argv[1] if len(sys.argv) > 1 else '.'
fuentes = glob.glob(os.path.join(d, '*.pas')) + glob.glob(os.path.join(d, '*/*.pas'))
globales = {}
for f in fuentes:
    s = re.sub(r'\{[^}]*\}|\(\*.*?\*\)|//[^\n]*', '', open(f, encoding='utf-8', errors='replace').read(), flags=re.S)
    for m in re.finditer(r'^\s*([A-Za-z_][A-Za-z0-9_]*)\s*(?::\s*[^=;]+)?=\s*[^=]', s, re.M):
        n = m.group(1)
        if n.lower() in ('result',): continue
        globales.setdefault(n.lower(), set()).add((n, os.path.basename(f)))
choques = 0
for f in fuentes:
    s = re.sub(r'\{[^}]*\}|\(\*.*?\*\)|//[^\n]*', '', open(f, encoding='utf-8', errors='replace').read(), flags=re.S)
    # declaraciones "a, b: Tipo" en listas de var y de parametros
    for m in re.finditer(r'(?:^|[;(]|\bvar\b|\bconst\b|\bout\b)\s*([A-Za-z_][A-Za-z0-9_]*(?:\s*,\s*[A-Za-z_][A-Za-z0-9_]*)*)\s*:\s*[A-Za-z]', s, re.M):
        for n in re.split(r'\s*,\s*', m.group(1)):
            for (g, gf) in globales.get(n.lower(), ()):
                if g != n:   # mismo nombre con otras mayusculas = otro identificador en Rust, el MISMO en Pascal
                    print(f"  {os.path.basename(f)}: '{n}' choca con '{g}' ({gf})"); choques += 1
print(f"{choques} choques")
sys.exit(1 if choques else 0)
