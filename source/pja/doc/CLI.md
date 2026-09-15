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
| `-fs` | `--keep-structure` | lo reusa el contenedor |
| `-r` | `-r`, `--recursive` | se queda |
| `-dry` | `-n`, `--dry-run` | convención |
| `-module` | `--porcelain` | |
| `--no-color` | `--no-color` | se queda |

## 2. Switches nuevos

| switch | qué hace |
|---|---|
| `--archive` | crear un contenedor multi-archivo |
| `-o NOMBRE` | nombre del contenedor de salida |
| `-e`, `--encrypt` | pedir contraseña interactiva, **sin eco**, dos veces al crear |
| `--password-file=RUTA` | para scripts; rechaza si el archivo tiene permisos más amplios que `0600` |
| `--keep-structure` | preservar rutas dentro del contenedor |
| `--keep-corrupt` | al extraer, un miembro cuyo hash no coincide se renombra a `<nombre>.corrupto` en vez de borrarse |

**`list` sobre un contenedor cifrado pide contraseña.** No es una decisión de
la CLI sino del formato: el índice viaja adentro del cifrado, así que no hay
nada que listar sin la clave. Ver `FORMATO.md` §1.

**`-o` y `-C` no colisionan porque significan cosas distintas:** `-o` es un
archivo de salida (convención de `gcc`, `curl`), `-C` es un directorio destino
(convención de `tar`). Si el argumento de uno tiene la forma del otro, se
rechaza con un mensaje que nombra el correcto.

```
crear:     packJPG --archive -o timelapse.pjg *.jpg
extraer:   packJPG x timelapse.pjg -C fotos/
```


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

## 3. Lo que nunca va a existir

`--password TEXTO`. Queda en el historial del shell, en `ps` para cualquier otro
usuario de la máquina, y en `/proc/<pid>/cmdline`. **Que no exista es la única
forma de que nadie la use.**

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
