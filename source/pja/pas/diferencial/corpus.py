# Corpus para la prueba diferencial nombres Rust vs Pascal. Una entrada por
# linea, en hex. Determinista: la misma semilla da el mismo corpus.
import random, itertools
r = random.Random(20260925)
out = []
def add(b): out.append(bytes(b).hex())

# 1. exhaustivo: toda entrada de 0, 1 y 2 bytes
add(b'')
for x in range(256): add([x])
for x in range(256):
    for y in range(256): add([x, y])

# 2. UTF-8 sistematico: cada primer byte de 3 y 4 bytes contra los bordes de
#    cada rango de continuacion (80, 8F, 90, 9F, A0, BF, C0 y fuera)
bordes = [0x00, 0x7F, 0x80, 0x8F, 0x90, 0x9F, 0xA0, 0xBF, 0xC0, 0xFF]
for lead in range(0xE0, 0x100):
    for c1 in bordes:
        for c2 in bordes: add([lead, c1, c2])
for lead in range(0xF0, 0x100):
    for c1 in bordes:
        for c2 in (0x80, 0xBF, 0xC0):
            for c3 in (0x80, 0xBF, 0x7F): add([lead, c1, c2, c3])

# 3. cerca de cada limite
for n in (254, 255, 256, 257):
    add(b'a' * n); add(b'a' * (n - 2) + b'\xc3\xa1'); add('á'.encode() * (n // 2))
for n in (1022, 1023, 1024, 1025, 1026):
    s = (b'ab/' * 400)[:n]; add(s); add(s.rstrip(b'/') + b'x')
for prof in (30, 31, 32, 33, 34):
    add(b'/'.join([b'd'] * prof)); add(b'/'.join([b'd'] * prof) + b'/')

# 4. reservados y sus vecinos
for base in ['CON','PRN','AUX','NUL','COM0','COM1','COM9','COM10','LPT1','LPT9','LPT','CO','CONN','NULL']:
    for var in [base, base.lower(), base.title(), base + '.', base + '.jpg', base + '.JPG.bak',
                base + ' ', base + '..', '.' + base, base + 'x.jpg']:
        add(var.encode())

# 5. al azar, sesgado a los bytes que deciden algo
alfa = [ord(c) for c in 'aAzZ09.. //\\\\::*?<>|"CONnulLPT'] + [0x00, 0x1F, 0x20, 0x7F, 0x80, 0xBF,
        0xC0, 0xC1, 0xC2, 0xDF, 0xE0, 0xED, 0xEF, 0xF0, 0xF4, 0xF5, 0xFF]
for _ in range(60000):
    n = r.choice([1, 2, 3, 4, 5, 8, 12, 20, 40])
    add([r.choice(alfa) for _ in range(n)])
# y UTF-8 valido de verdad, mezclado con separadores
chars = 'aé写ñ😀/.-_ ' 
for _ in range(20000):
    add(''.join(r.choice(chars) for _ in range(r.randint(1, 30))).encode())

import sys
open(sys.argv[1] if len(sys.argv) > 1 else 'corpus.hex', 'w').write('\n'.join(out) + '\n')
print(len(out), 'entradas')
