# Contenedor PJA — núcleo en Rust

Prototipo del contenedor multi-JPEG con integridad y cifrado. **No está
enganchado a la CLI todavía**: `pjatool.cpp` es la demostración punta a punta
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
| `pjacore/` | lógica, `no_std`, testeable — límites, nombres, índice, escritor, cifrado |
| `pjaffi/` | shim FFI, `staticlib`. La frontera es angosta a propósito |
| `pjafs/` | extracción: lo que sólo se decide contra el disco |
| `include/pjacore.h` | la interfaz C |
| `gen/` | generador de contenedores reales para la prueba de frontera en C++ |
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
cargo test                                  # 43 pruebas
cargo build --release
g++ -std=c++17 -O2 -Iinclude test_frontera.cpp target/release/libpjaffi.a -o frontera

# la frontera necesita un contenedor de verdad; el gen los arma
./target/release/gen /tmp/claro.pja   -           a.pjg b.pjg c.pjg
./target/release/gen /tmp/cif.pja     secreta123  a.pjg b.pjg c.pjg
./frontera /tmp/claro.pja
./frontera /tmp/cif.pja secreta123
```

**Al agregar un miembro al workspace, cuidado con las features de `blake3`.**
Cargo las unifica: si alguno lo pide con `std`, `blake3` se compila con `std`
para todos y `pjaffi` —que es `no_std` y define su propio `panic_handler`— deja
de linkear con «duplicate lang item `panic_impl`». El error aparece en `pjaffi`,
que ni siquiera depende del crate que lo causó.

## Lo que falta

- engancharlo a la CLI (`--archive`, `-o`, `-e`, `--keep-structure`,
  `--keep-corrupt`) — va junto con el rework de switches de `doc/CLI.md`
- que el `Makefile` sepa de `source/pja/`; hoy el core se compila con `cargo`
  aparte y `pjatool.cpp` necesita los objetos de packJPG con `-DBUILD_LIB`
- modo sólido, condicionado a conseguir material real: en el corpus no hay ni
  una ráfaga, y lo medido dice que la predicción sólo paga con bloques
  alineados
