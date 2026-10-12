# Política de límites del formato PJA

Los números del formato y de dónde sale cada uno. El layout está en
`FORMATO.md`.

Esta política era mucho más grande cuando el `.pja` iba a ser un contenedor de
varios archivos: tenía un presupuesto agregado de 8 GiB, topes de miembros,
nombres y rutas con sus reglas por plataforma, y el límite de 260 de Windows al
extraer. Todo eso se fue con el contenedor (12/10/2026). Con un solo archivo,
el nombre de la salida lo elige el usuario, no el archivo, y la única bomba
posible es la de siempre: un `.pjg` que se expande demasiado.

---

## 1. Límites

| regla | valor | por qué |
|---|---|---|
| payload ≥ 12 B | 12 B = cabecera `.pjg` mínima | ningún payload vacío ni imposible |
| `tam_orig` ≥ 1 | | un JPEG vacío no existe |
| `tam_orig` ≤ 2^63 − 1 | | `pja_tam_orig` devuelve `int64_t` |
| `tam_orig` ≤ 500 × payload | igual que `PJG_MAX_BLOWUP_RATIO` del códec | ver abajo |
| `tam_orig` ≤ `--max-output` | 256 MB por defecto en el códec; `0` = sin límite | el techo del usuario; lo aplica quien llama, antes de decodificar |

**El 500× es un tope de último recurso, no una cota ajustada.** Medido sobre
40 `.pjg` del corpus, la expansión real jpg/pjg va de **1,08× a 2,14×**, con
media de **1,34×**. Lo que importa no es el número sino *cuándo* se aplica:
el `.pjg` suelto solo puede abortar una bomba **mientras** decodifica, y el
`.pja` la rechaza **antes**, porque declara el tamaño.

**El tamaño declarado es además el tope del decodificador.** Quien extrae le
pasa `tam_orig` a `pjglib_set_max_output_size`. Así un `tam_orig` mentiroso no
compra nada: si es más chico que la salida real, el códec corta; si es más
grande, la verificación del tamaño falla.

**El escritor aplica las mismas reglas que el lector, con la misma función**
(`ValidarDescriptor`). El contenedor anterior no lo hacía: escribía archivos
que su propio lector rechazaba.

---

## 2. Contraseñas

- **la vacía es una contraseña**: un archivo cifrado con `""` se abre con `""`
  y no sin contraseña. Distinguir "nula" de "vacía" es trabajo de quien llama
  (`pass` NULL en `pja_abrir`).
- el perfil de Argon2id va **por número** en la cabecera, no por sus
  parámetros. Un archivo que declarara `m` y `t` crudos podría pedir memoria
  arbitraria antes de validar nada.

---

## 3. Lo que esta política no cubre

- **Lo que pasa dentro del códec.** El hash del `.pja` garantiza que lo que se
  entrega es el JPEG original. No garantiza que decodificar un `.pjg` hostil
  sea seguro: eso es trabajo del códec. Probando el `.pja` punta a punta
  aparecieron, al decodificar `.pjg` con un bit alterado, una escritura por
  puntero nulo y lecturas fuera de rango del heap (AddressSanitizer). El mismo
  código tenía escrituras fuera de rango alcanzables con un `.pjg` armado.
  Se arreglaron en `packjpg.cpp`, en `pjg_unoptimize_header` y `recode_jpeg`
  (12/10/2026).
