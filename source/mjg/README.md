# Contenedor MJG — núcleo en Rust

Prototipo del contenedor multi-JPEG con integridad y cifrado. **No está
enganchado a la CLI todavía**: `mjgtool.cpp` es la demostración punta a punta
que usa `pjglib` y esta biblioteca.

## Por qué Rust, y por qué sólo acá

De los nueve defectos medidos en v5.0e, **cinco los previene el lenguaje** y
están concentrados en los parsers, no en el códec. Por eso el perímetro de
entrada no confiable —contenedor, índice, límites, nombres, cripto— va en Rust,
y el códec (10.368 líneas) se queda en C++: reescribirlo costaría meses con una
verificación de bit-exactitud brutal y compraría poco.

El defecto más grande por impacto —las 818 salidas incorrectas de una validación
sin cablear— es de los que **ningún lenguaje atrapa**.

## `no_std`, y no es preferencia

La `std` de Rust en Windows importa `WaitOnAddress` de
`api-ms-win-core-synch-l1-2-0.dll`, que existe **desde Windows 8**, y
`build_all.sh` declara soporte desde Windows 7 SP1. Medido:

| | con `std` | con `no_std` |
|---|---|---|
| imports | 7 DLL, una de Win8+ | `KERNEL32.dll`, `msvcrt.dll` |
| `WaitOnAddress` | presente | 0 ocurrencias |
| tamaño del exe | 2.376.160 B | 790.225 B |

## Estructura

| | |
|---|---|
| `mjgcore/` | lógica, `no_std`, testeable — límites, nombres, índice, escritor, cifrado |
| `mjgffi/` | shim FFI, `staticlib`. La frontera es angosta a propósito |
| `mjgfs/` | extracción: lo que sólo se decide contra el disco |
| `include/mjgcore.h` | la interfaz C |
| `doc/` | política, formato y CLI, con los números medidos |

## Contrato de la frontera

Entran punteros con largo, salen códigos de estado, **ninguna propiedad de
memoria cruza**. Los `*_largo` existen para preguntar el tamaño antes de
reservar. Rust y C++ comparten un solo heap (el asignador usa `malloc`).

`panic = "abort"`: un panic que desenrollara hacia C++ sería comportamiento
indefinido. El perfil va en la **raíz** del workspace — puesto en el manifiesto
de un miembro se ignora en silencio.

## Probar

```sh
cargo test                                  # 39 pruebas
g++ -std=c++17 -O2 -Iinclude test_frontera.cpp target/release/libmjgffi.a -o frontera
```

## Lo que falta

- engancharlo a la CLI (`--archive`, `-o`, `-e`, `--keep-structure`) — va junto
  con el rework de switches de `doc/CLI.md`, que es corte limpio
- modo sólido, condicionado a medir el techo de redundancia entre archivos
