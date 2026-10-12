#!/usr/bin/env python3
"""Busca identificadores que chocan sin distinguir mayusculas.

Pascal no distingue mayusculas: una variable `version` tapa a una constante
VERSION y el compilador no avisa. Paso de verdad al portar indice.rs (Rust SI
distingue, y su convencion garantiza pares FOO / foo): la comparacion quedo
`version > version` y ninguna version futura se rechazaba.

Heuristico a proposito: junta los nombres de constantes, tipos, funciones y
procedimientos de todas las unidades y los compara contra cada variable y
parametro declarado. Sale != 0 si hay un choque.

Las funciones se agregaron el 12/10/2026: una variable `plano` tapaba a la
funcion `Plano` en pjaformato y esto daba "0 choques" (lo freno el compilador
porque los tipos no coincidian; con tipos compatibles hubiera compilado).
Contra una funcion choca el nombre IGUAL tambien, no solo con otras
mayusculas: en Pascal una variable local con el nombre de una funcion la tapa
en todo el cuerpo."""
import re, sys, glob, os
d = sys.argv[1] if len(sys.argv) > 1 else '.'
fuentes = glob.glob(os.path.join(d, '*.pas')) + glob.glob(os.path.join(d, '*/*.pas'))
globales = {}
for f in fuentes:
    s = re.sub(r'\{[^}]*\}|\(\*.*?\*\)|//[^\n]*', '', open(f, encoding='utf-8', errors='replace').read(), flags=re.S)
    for m in re.finditer(r'^\s*([A-Za-z_][A-Za-z0-9_]*)\s*(?::\s*[^=;]+)?=\s*[^=]', s, re.M):
        n = m.group(1)
        if n.lower() in ('result',): continue
        globales.setdefault(n.lower(), set()).add((n, os.path.basename(f), False))
rutinas = {}   # archivo -> [(nombre, visible desde otras unidades)]
for f in fuentes:
    s = re.sub(r'\{[^}]*\}|\(\*.*?\*\)|//[^\n]*', '', open(f, encoding='utf-8', errors='replace').read(), flags=re.S)
    impl = re.search(r'^implementation\b', s, re.M | re.I)
    es_unidad = re.search(r'^\s*unit\b', s, re.M | re.I) is not None
    # En columna 0: los metodos de un record van indentados, y `r.Ok` no lo
    # tapa ninguna variable `ok`.
    for m in re.finditer(r'^(?:function|procedure)\s+([A-Za-z_][A-Za-z0-9_]*)\s*[(:;]', s, re.M | re.I):
        visible = es_unidad and impl is not None and m.start() < impl.start()
        rutinas.setdefault(f, []).append((m.group(1), visible))
choques = 0
for f in fuentes:
    s = re.sub(r'\{[^}]*\}|\(\*.*?\*\)|//[^\n]*', '', open(f, encoding='utf-8', errors='replace').read(), flags=re.S)
    # declaraciones "a, b: Tipo" en listas de var y de parametros
    # las rutinas que se ven desde este archivo: las suyas y las de interfaz de las demas
    vistas = {}
    for g, rs in rutinas.items():
        for (n, visible) in rs:
            if g == f or visible:
                vistas.setdefault(n.lower(), set()).add((n, os.path.basename(g), True))
    for m in re.finditer(r'(?:^|[;(]|\bvar\b|\bconst\b|\bout\b)\s*([A-Za-z_][A-Za-z0-9_]*(?:\s*,\s*[A-Za-z_][A-Za-z0-9_]*)*)\s*:\s*[A-Za-z]', s, re.M):
        for n in re.split(r'\s*,\s*', m.group(1)):
            for (g, gf, es_rutina) in globales.get(n.lower(), set()) | vistas.get(n.lower(), set()):
                # mismo nombre con otras mayusculas: el MISMO identificador en
                # Pascal; contra una rutina, igual tambien
                if g != n or es_rutina:
                    print(f"  {os.path.basename(f)}: '{n}' choca con '{g}' ({gf})"); choques += 1
print(f"{choques} choques")
sys.exit(1 if choques else 0)
