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

Desde `source/`, con el Makefile:

```sh
make pja          # compila el workspace de Rust -> target/release/libpjaffi.a
make pja-tests    # + test_frontera y pjatool (este ultimo necesita packJPGlib.a)
make pja-clean    # borra target/ de cargo, que `make clean` NO toca a proposito
```

`pja` **no** es parte de `make all`: quien sólo quiere packJPG no necesita una
toolchain de Rust, y no se la vamos a pedir. Si `cargo` no está, `make pja`
falla con una instrucción en vez de con «command not found».

Las pruebas de Rust van aparte, porque `cargo test` compila con `std` y el
Makefile construye el `staticlib` `no_std`:

```sh
cargo test --release --manifest-path pja/Cargo.toml     # 43 pruebas
```

La prueba de frontera necesita un contenedor de verdad; `gen` los arma:

```sh
./pja/target/release/gen /tmp/claro.pja  -           a.pjg b.pjg c.pjg
./pja/target/release/gen /tmp/cif.pja    secreta123  a.pjg b.pjg c.pjg
./pja/test_frontera /tmp/claro.pja
./pja/test_frontera /tmp/cif.pja secreta123
```

Y el round-trip entero, contenedor incluido:

```sh
./pja/pjatool crear   cont.pjg  ent/*.jpg
./pja/pjatool extraer cont.pjg  sal/
```

**Al agregar un miembro al workspace, cuidado con las features de `blake3`.**
Cargo las unifica: si alguno lo pide con `std`, `blake3` se compila con `std`
para todos y `pjaffi` —que es `no_std` y define su propio `panic_handler`— deja
de linkear con «duplicate lang item `panic_impl`». El error aparece en `pjaffi`,
que ni siquiera depende del crate que lo causó.

## Lo que falta

- engancharlo a la CLI (`--archive`, `-o`, `-e`, `--keep-structure`,
  `--keep-corrupt`) — va junto con el rework de switches de `doc/CLI.md`
- modo sólido, condicionado a conseguir material real: en el corpus no hay ni
  una ráfaga, y lo medido dice que la predicción sólo paga con bloques
  alineados
