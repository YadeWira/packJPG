# Rework de la línea de comandos

**Aplicado** en `source/packjpg.cpp` (`initialize_options`, `show_help`).
Medido con 43 celdas: 43/43 acá, 1/43 contra v5.0f, que es el control de que la
batería discrimina en vez de aceptar todo.

**Corte limpio, sin alias de compatibilidad.** Decidido: los scripts existentes
se rompen. Lo que sigue incluye cómo hacer que rompan con un mensaje útil, y así
está implementado: cada grafía retirada está en `cli_retirados[]` y falla
nombrando su reemplazo, no con "unknown option".

Lo que se agregó al implementar, y que este documento no preveía: **un nombre de
salida que ya existe se rechaza salvo que se pase `-f`.** Sin eso,
`packJPG a -o a.jpg b.jpg` —que en la grafía vieja era *sobrescribir, dos
entradas*— comprimía `b.jpg` encima de `a.jpg` en silencio. El cambio de
significado de `-o` es el único del rework que no rompe ruidosamente por sí
solo, así que necesita esa guarda.

La mayoría de los switches actuales vienen del packJPG original y arrastran
nombres que no se adivinan. Los **comandos** (`a`, `x`, `list`, `stats`) son de
este proyecto y **no cambian** — salvo `mix`, que se retiró (ver abajo).

Se dejó de decirles «subcomandos»: con los switches en forma larga estilo GNU,
`packJPG a foto.jpg` se lee como `git commit`, y **comando** es la palabra más
honesta. Es sólo terminología; nada del parseo depende de ella.

## 0. `mix` se retira

No cambiaba el procesamiento: el códec detecta el tipo por magia archivo por
archivo, y `a`/`x` son **filtros** que saltean el tipo contrario. `mix` era «sin
filtro», y su único efecto real era imprimir al final una advertencia que
desaconsejaba usarlo:

    Running -mix on already-processed files can undo previous work.
    Use 'a' or 'x' for safer operation.

El trabajo seguro ya se consigue con los globs del shell —`a *.jpg` y después
`x *.pjg`—, que separan justamente lo que `mix` mezclaba. Lo único que `mix`
podía hacer y los globs no es cuando la extensión miente sobre el contenido, o
sea el caso peligroso. Tampoco estaba en el estándar acordado con packMP3 y
packPNG, que cubre `a`/`x`/`list`.

---

## 1. Tabla de equivalencias

| hoy | nuevo | nota |
|---|---|---|
| `-o` | `-f`, `--force` | **libera `-o`** |
| `-p` | `--proceed` | |
| `-d` | `--discard-meta` | |
| `-ver` | `--verify` | |
| `-v2` | `-v -v` o `--verbose=2` | un solo eje |
| `-vp` | `--progress` | eje aparte |
| `-np` | `--no-pause` | |
| `-th4` | `-th 4`, `--threads=N` | se mantiene; ver 4.1 |
| `-sfth` | `--parallel-stages` | dice qué hace |
| `-maxout256` | `--max-output=256M` | con unidad |
| `-odsalida/` | `-o` (ver 2.1), `--output-dir=` | `-C` descartado |
| `-fs` | `--keep-structure` | |
| `-r` | `-r`, `--recursive` | se queda |
| `-dry` | `-n`, `--dry-run` | convención |
| `-module` | `--porcelain` | |
| `--no-color` | `--no-color` | se queda |

## 2. Switches nuevos: el formato `.pja`

Un `.pja` es un JPEG por archivo (`FORMATO.md`). El contenedor de varios
archivos que esta sección describía antes (`--archive`, `-C`, rutas adentro)
se descartó el 12/10/2026.

| switch | qué hace |
|---|---|
| `--pja` | comprimir a `.pja` en vez de `.pjg`: el JPEG con su tamaño y su hash, verificados al extraer |
| `-e`, `--encrypt` | `.pja` cifrado; pide la contraseña interactiva, **sin eco**, dos veces al crear |
| `--password=TEXTO` | la contraseña en la línea de comandos (ver §3) |
| `--password-stdin` | la contraseña por la entrada estándar (patrón de docker) |
| `--password-file=RUTA` | para scripts; rechaza si el archivo tiene permisos más amplios que `0600` |
| `--keep-corrupt` | al extraer, un JPEG cuyo hash no coincide se renombra a `<nombre>.corrupto` en vez de borrarse |

Extraer no necesita switch: el `.pja` se reconoce por la magia, y si está
cifrado se pide la contraseña.

```
crear:     packJPG a --pja -e foto.jpg       -> foto.pja, cifrado
extraer:   packJPG x foto.pja                -> foto.jpg, si el hash coincide
```

**Sin decidir:** si `--pja` pasa a ser el formato por defecto de `a`, con el
`.pjg` como opción. A favor: la verificación del hash detecta los `.pjg`
alterados que decodifican a otro JPEG válido (entre el 1 % y el 21 % de los
bits volteados, medido). En contra: 24 bytes por archivo, y los `.pjg` que ya
consumen packPDF y los demás.

### 2.1 `-o`, con semántica de `cp`

`-o` toma una ruta y se comporta como el destino de `cp`:

```
packJPG a foto.jpg                 -> foto.pjg
packJPG a foto.jpg -o pana.pjg     -> pana.pjg
packJPG x foto/pana.pjg            -> foto.jpg
packJPG x foto/pana.pjg -o CARPETA -> CARPETA/foto.jpg
```

| el argumento de `-o` | se interpreta como |
|---|---|
| existe y es directorio | directorio destino |
| termina en `/` | directorio destino, aunque no exista |
| no existe, o es un archivo | **nombre** de salida |

**Y con más de una entrada, si el destino no es un directorio: error.** Sin esa
guarda, `packJPG a *.jpg -o pana.pjg` escribiría cincuenta veces sobre el mismo
archivo y ganaría el último, en silencio. Es la misma regla que aplica `cp`.

`--output-dir=` queda como forma larga que **sólo** acepta directorios, para
scripts que prefieran ser inequívocos.

## 3. `--password` en la línea de comandos

**Existe, por decisión del 15/09/2026:** el usuario decide qué usar. La
exposición es real (el historial del shell, `ps` y `/proc/<pid>/cmdline` para
cualquier usuario de la máquina), así que va con mitigaciones y con
alternativas mejores al lado, no en su lugar:

- el argumento se **borra de `argv` apenas se parsea**. Medido en Linux:
  sobrescribirlo in situ cambia lo que muestra `/proc/self/cmdline`. Queda una
  ventana entre el `exec` y el borrado, y no ayuda con el historial del shell.
  **En Windows no está medido**: la línea de comandos vive en el PEB y
  sobrescribir el `argv` de la CRT puede no cambiar lo que ven WMI o Process
  Explorer.
- `--password-stdin`, `--password-file=` y el prompt sin eco no tienen esa
  exposición.

## 4. Reglas del parseo


- valores con `=` o espacio, **nunca pegados**: `-j 4` o `--jobs=4`, no `-th4`
- forma larga con `--`, corta con `-`, sin mezclar (`-module` era un nombre largo
  con guion simple)
- `-v` repetible; `--verbose=N` para el mismo eje
- **nunca definir un `-t` a secas.** `-th` es de dos letras, así que si algún día
  se agrega `-h/--help` y el parser agrupa cortos, `-th` se volvería ambiguo entre
  el switch y `-t -h`. Dejando `-t` sin usar, `-th` es inequívoco para siempre.
  Medido: `-t` significa "probar integridad" en gzip, xz, zstd y bzip2, y
  "directorio destino" en `cp` — tres sentidos distintos, ninguno el nuestro.
- `--` termina las opciones: todo lo que sigue es un archivo, aunque empiece con
  guion

## 5. Romper bien

Sin alias, la única red es el mensaje. Dos casos merecen uno propio:

| entrada vieja | qué pasa | mensaje |
|---|---|---|
| `-o foto.jpg` | **cambia de significado**, no desaparece: antes activaba sobrescritura, ahora nombra un archivo de salida | *«`-o` ahora es el archivo de salida; para forzar sobrescritura usá `-f`»* |
| `-th4`, `-maxout256`, `-odsalida/` | switch desconocido | nombrar el reemplazo exacto en el error |

**`-o` es el peligroso** y por eso lleva mensaje propio: es el único que cambia
de sentido en lugar de dejar de existir, así que un script viejo no falla —
hace otra cosa.

**Todos los avisos y errores van a stderr.** En stdout se meterían en la salida
de `--porcelain` y romperían justo a quien parsea.

## 6. Pendiente

Un error de tipo de archivo desconocido hoy imprime **«1 error(s)» y ninguna
línea de explicación** — verificado alimentándole un archivo con magia ajena.
El rework tiene que darle un mensaje.
