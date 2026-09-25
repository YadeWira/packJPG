# Contenedor PJA

Prototipo del contenedor multi-JPEG con integridad y cifrado. **No está
enganchado a la CLI todavía**: `pjatool.cpp` es la demostración punta a punta
que usa `pjglib` y esta biblioteca.

## Port a FreePascal, en curso

**Decisión del 25/09/2026: esta capa pasa de Rust a FreePascal.** Rust para
Windows 7 es **Tier 3 en todos los targets**, y `i686-pc-windows-gnu` (MinGW 32
bits, lo que usa este proyecto) es Tier 2 y exige Windows 10. packJPG declara
soporte desde Windows 7 SP1 y publica binarios de 32 bits. FreePascal tiene
`i386-win32` como destino principal desde siempre.

El **cifrado no se escribe en Pascal**: va en C, con Monocypher 4 y la
implementación oficial de BLAKE3. Medido antes de empezar: dan exactamente lo
mismo que las primitivas Rust de hoy, byte a byte, en Linux 32/64 y en Windows 7
real de 32/64 bits. El formato en disco no cambia.

El código Rust **se queda como referencia** hasta que el port termine: cada
módulo portado se da por bueno cuando da lo mismo que su versión Rust sobre el
mismo corpus, línea por línea (`make pja-pas-tests`).

| módulo | estado |
|---|---|
| `limites` | portado |
| `nombres` | portado — 52 pruebas + diferencial de 150.605 entradas, 0 distintas, en 64 **y 32 bits** |
| `indice`, `escritor`, `contenedor`, `corrupcion` | pendiente |
| `cifrado` | pendiente — pasa a C (Monocypher + BLAKE3) |
| `pjafs` (rutas al extraer) | pendiente |
| frontera FFI | pendiente — en Windows va como DLL (ver abajo) |

Tres reglas del port, las tres medidas y no obvias — están en `pas/pja.inc`:

- **`{$R+}` no controla accesos por puntero.** `p[10]` con `p: PByte` lee fuera
  de rango sin ningún error. La validación trabaja sólo sobre arreglos; lo que
  llega por la frontera como puntero y largo se copia a un arreglo primero.
- **Con `{$Q+}`, `for i := 0 to n - 1` con `n` sin signo y `n = 0` lanza
  `EIntOverflow`.** Largos e índices con signo; recorridos con `High()`.
- **Cada función exportada es una cáscara** sin variables administradas ni
  `try`, que chequea que el runtime esté inicializado antes de llamar a la
  implementación. Sin eso, olvidarse la inicialización apaga `{$R+}` en
  silencio, y FPC arma el marco de excepciones en el prólogo antes de que
  cualquier chequeo corra.

Enlace, medido: en Linux el código Pascal va **adentro** del ejecutable; en
Windows va como **DLL**, porque metido en el `.exe` obliga a apagar la sección de
relocaciones y el ejecutable entero pierde ASLR. La DLL de FPC, en Windows 10
19044, dio **0 de 20** cuelgues con hilos creados antes del `LoadLibrary`,
contra un control con la DLL de packJPG v5.0d que colgó 3 de 6.

## Por qué Rust, y por qué sólo acá (la decisión original, reemplazada por el port)

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
