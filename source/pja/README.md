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
| `indice` | portado — 25 pruebas + diferencial de 20.644 contenedores hostiles, 0 distintas, en 64 y 32 bits; 12/13 mutantes detectados, el 13.º equivalente con prueba |
| BLAKE3 | en C (1.8.7 oficial, `pas/c/`), detrás de `pja_cripto.h`; 11 pruebas desde Pascal contra los vectores del Rust |
| `escritor` | portado — 30 pruebas (con round-trip de 10 `.pjg` reales) + diferencial de 10.579 conjuntos, **archivo byte a byte igual al del Rust**, 0 distintos, en 64 y 32 bits; 12/12 mutantes reales detectados |
| `contenedor` | portado — 42 pruebas con `.pjg` reales (incluido el ataque de confirmación de nombres, con su control positivo) + diferencial de 13.596 casos (`escribir` con y sin cifrado, `abrir` de contenedores dañados y **resellados**: dañados por dentro y cifrados después, para llegar al camino que corre tras autenticar), 0 distintos, en 64 y 32 bits; 14/14 mutantes reales detectados, 1 equivalente (borrar la clave derivada, que el Rust no hace) |
| `corrupcion` | portado — las 2 pruebas dan las mismas cuentas que el Rust (1.047 celdas de un bit: 1.041 rechazos, 6 lecturas iguales, todas en el payload; 104 de 104 truncados rechazados) + diferencial **celda por celda** de 80.223 celdas sobre el contenedor entero (cada bit de cabecera e índice, también **resellados** para llegar a las validaciones de miembros reales; valores, truncado en cada largo, agregados), 0 distintas, en 64 y 32 bits. La prueba portada exige además lo que el Rust sólo imprime (`lee_distinto = 0`, y que lo que se lee igual caiga en el payload): sin eso, un `Iguales` roto pasaba. Mutantes: por sí sola atrapa 7 de los 14 de `indice` (control incluido); los otros 7 piden formas que 6 `.pjg` reales no tienen —cifrado, rutas, duplicados, 8 GiB— y los atrapa `dif_indice`. Arnés: 5 de 8, los 3 restantes equivalentes |
| `cifrado` | portado — el esquema por trozos en Pascal, las primitivas (XChaCha20-Poly1305, Argon2id) en C con Monocypher 4.0.3; 33 pruebas con KAT del Rust (Argon2id y cifrado **byte a byte** en los bordes de 64 KiB) + diferencial de 2.219 casos (claves, cifrados y contenedores alterados), 0 distintos, en 64 y 32 bits; 13/13 mutantes reales detectados, 2 equivalentes con prueba |
| `pjafs` (rutas al extraer) | portado — **antes, cuatro arreglos al Rust de referencia**, medidos con pruebas que fallaban: (1) un enlace simbólico en el destino con el nombre del miembro hacía escribir **afuera** (con sobrescribir pisaba el archivo apuntado; colgante, lo creaba, y lo reportaba `Verificado`); ahora el archivo se **crea** (`O_EXCL`/`CREATE_NEW`, no sigue enlaces) y sobrescribir borra la entrada antes, como tar; también cubre enlaces duros; (2) el largo para Windows se medía sobre la ruta sin resolver (destino relativo: 249 en vez de 344) y en bytes; ahora sobre la resuelta, en unidades UTF-16; (3) en Windows los nombres `SoloWindows` (`CON.jpg`, `foto?.jpg`, `foto.`) pasaban: ahora se rechazan allá, como dice POLITICA 3.2; (4) si la escritura fallaba al abrir, se borraba un archivo que no habíamos escrito. Port: 62 pruebas (las 14 del Rust + conteo UTF-16, contención por componentes, `Padre`); diferencial de 4.710 casos sobre **árboles de disco reales** que arma un tercero igual para las dos puntas (enlaces que salen, que entran, colgantes, duros, a `/`, directorios sin permiso, nombres no UTF-8, `.corrupto` agotados), comparando la salida **y el árbol entero después** (28.636 entradas), y exigiendo que ningún caso que pase por `destino_de` toque `afuera` (con control positivo); una segunda pasada con `ulimit -f` corta escrituras a la mitad (EFBIG). 0 distintos, en 64 y 32 bits. 22/24 mutantes, 2 equivalentes. **Windows real**: 50/50 en Windows 10 y en Windows 7, 32 y 64 bits; con *junctions*, la que sale da `EscapaDelDestino` y la que entra se acepta |
| frontera FFI | pendiente — en Windows va como DLL (ver abajo) |

Reglas del port, todas medidas y no obvias — las tres primeras están en `pas/pja.inc`:

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
- **En i386, `Int64` no es ordinal**: no sirve de variable de `for`, y el error
  aparece recién al compilar para 32 bits. Contadores en `SizeInt`; posiciones
  en bytes en `Int64`.
- **`for s in ['corto', 'mas_largo']` recorta los literales** al largo del
  primero (`'trozo_justo'` llegó como `'trozo'`). Recorrer un arreglo constante
  declarado.
- **En Unix, `TFileStream.Create(f, fmOpenRead)` toma un `flock` exclusivo.**
  Una segunda apertura del mismo archivo —aun en el mismo proceso— falla con
  `EAGAIN` ("Try again"). Se vio corriendo mutantes en paralelo sobre el mismo
  corpus. Para leer: `fmOpenRead or fmShareDenyNone`. Va a importar cuando la
  librería abra `.pja`: dos packJPG leyendo el mismo archivo chocarían.
- **FPC no avisa de un `Result` sin asignar si algún camino hace `Exit(valor)`.**
  `pjafs.Padre` salía por `Exit(False)` en los bordes y llegaba al `end` sin
  asignar `Result` en el caso normal: devolvía lo que quedara en el registro.
  Se vio como un fallo **intermitente** del diferencial (1 corrida de cada ~10),
  y en `DestinoDe` un falso hacía verificar la contención contra el destino y
  no contra el padre. `pas/resultados.py` corta el build si una función nunca
  nombra `Result` fuera de un `Exit`.
- **Pascal no distingue mayúsculas, y el Rust sí.** Al portar `indice`, una
  variable local `version` tapó a la constante `VERSION`: la comparación quedó
  `version > version`, siempre falsa, y ninguna versión futura se rechazaba. El
  compilador no avisa. Lo agarró el diferencial (63 de 63 `VersionFutura`), y
  ahora `pas/colisiones.py` corta el build antes de compilar si reaparece un
  choque así.

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
