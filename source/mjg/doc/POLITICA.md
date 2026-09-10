# Política de límites y nombres del contenedor MJG

Documento de diseño, **sin código**. Decide el layout del formato, así que va
antes del parser. Todos los números que se apoyan en medición dicen cuál.

---

## 1. Por qué las guardas actuales no sirven

packJPG tiene hoy dos guardas anti-bomba y las dos son **por archivo**:

| guarda | valor |
|---|---|
| `pjg_max_output_size` | 256 MB (configurable con `-maxout`) |
| `PJG_MAX_BLOWUP_RATIO` | 500× |

Un contenedor las multiplica por N y las deja intactas: mil miembros de 256 MB
son 256 GB, y **cada miembro pasa el chequeo**. La guarda funciona perfecto y no
sirve de nada. Hace falta un presupuesto del contenedor, no sólo del miembro.

**Medido sobre 40 `.pjg` del corpus:** la expansión real jpg/pjg va de **1,08×
a 2,14×, media 1,34×**. La guarda de 500× es un tope de último recurso, no una
cota ajustada — y está bien que lo sea, pero conviene saber que el caso legítimo
vive dos órdenes de magnitud por debajo.

---

## 2. Límites, con sus números

El índice declara, por miembro, el tamaño original y el tamaño del payload. Eso
permite algo que el `.pjg` suelto **no puede hacer**: rechazar una bomba *antes
de decodificar un solo byte*. Los chequeos 1 a 5 son todos previos al decode.

| # | regla | valor | por qué |
|---|---|---|---|
| 1 | `count` ≤ tope absoluto | **1.048.576** | acotar antes de reservar el índice; un `u32` crudo son 4.000 millones de entradas |
| 2 | `count × 32 ≤ tamaño del archivo` | 32 B = entrada mínima | un contenedor de 2 KB no puede declarar 10.000 miembros |
| 3 | `Σ tam_payload + tam_índice == tamaño del archivo` | exacto | detecta truncación y relleno; es la opción 1 del diseño de checksum, gratis acá |
| 4 | `Σ tam_original ≤ 500 × tamaño del contenedor` | ratio | **escala solo**: el mismo criterio vale para 2 miembros y para 200.000 |
| 5 | `Σ tam_original ≤` presupuesto absoluto | **8 GB** por defecto | un timelapse de 240 cuadros de 20 MB son 4,8 GB legítimos, así que 256 MB rompería el caso real. `0` = sin límite |
| 6 | cada `tam_payload` ≥ 12 y ≤ tamaño del archivo | 12 B = cabecera `.pjg` mínima | ningún miembro vacío ni imposible |

**`-maxout` pasa a significar el presupuesto agregado.** El tope por miembro
sigue existiendo y no cambia; el agregado es el que faltaba.

**Regla 4 contra regla 5:** la 4 es la que importa, porque no hay que elegir un
número. La 5 es un techo para el usuario, no una defensa.

---

## 3. Nombres

`.pjg` nunca llevó un nombre adentro. Un contenedor sí, y eso trae la clase de
vulnerabilidad que muerde a todo archivador nuevo.

La política es **rechazar, no sanear** — un nombre saneado en silencio es un
nombre que el usuario no escribió. Pero *cuándo* se rechaza depende de si el
problema es **peligro** o **incompatibilidad**, y eso no es lo mismo.

### 3.1 Se rechaza siempre, al crear — es peligro

Vale para los dos modos, por componente:

- bytes de control (`0x00`–`0x1F`, `0x7F`)
- `/` o `\` dentro de un componente
- el componente `..`, en cualquier posición
- ruta absoluta, o letra de unidad (`C:`)
- `:` en cualquier posición (flujos alternos NTFS: `foto.jpg:carga`)
- UTF-8 inválido
- nombres duplicados dentro del índice

### 3.2 Se advierte al crear y se rechaza al extraer — es incompatibilidad

**Todos estos son nombres legales en Linux.** Rechazarlos al crear le impediría
a un usuario archivar un archivo suyo perfectamente válido; ignorarlos haría que
el archivo sea silenciosamente inextraíble en Windows. Entonces: se avisa al
crear —que es cuando el usuario todavía tiene el original a mano— y se rechaza
al extraer **en la plataforma donde son ilegales**, con opción de remapear.

- `*  ?  <  >  |  "` — ilegales en Windows, legales en Linux
- nombres reservados de Windows, con o sin extensión, sin distinguir mayúsculas:
  `CON PRN AUX NUL COM1..COM9 LPT1..LPT9`
- terminados en `.` o en espacio: Windows los recorta **en silencio**, así que
  dos entradas distintas colisionarían al extraer

### 3.3 Lo que pasa sin objeción

Acentos, `ñ`, CJK, emoji, espacios internos, paréntesis, guiones. Son UTF-8
válido y no hay motivo para tocarlos.

### 3.4 Largos — **son bytes, no caracteres**

Es la confusión más común y tiene consecuencia práctica. Medido en esta máquina:

| prueba | resultado |
|---|---|
| 255 caracteres ASCII (255 bytes) | OK |
| 255 caracteres acentuados (510 bytes) | **`File name too long`** |
| 127 caracteres acentuados (254 bytes) | OK |

Un nombre con acentos entra a la mitad; en CJK o emoji, a un tercio.

Y no hay **un** límite sino cuatro que no coinciden:

| límite | valor | dónde |
|---|---|---|
| `NAME_MAX` por componente | **255 bytes** | Linux (medido) |
| `PATH_MAX` ruta completa | **4096 bytes** | Linux (medido) |
| `MAX_PATH` ruta completa | **260 caracteres** | Windows, salvo opt-in explícito |
| NTFS por componente | 255 unidades UTF-16 | Windows |

**Lo que se guarda y se valida va en bytes**, que es lo inequívoco y lo que el
sistema de archivos realmente aplica:

- componente ≤ **255 bytes**
- ruta completa ≤ **1024 bytes**
- profundidad ≤ **32** componentes

**Y el límite de Windows no se puede chequear al crear**, porque el total de 260
incluye el directorio destino, que se elige al extraer. Una ruta de 800 bytes es
válida en Linux e **inextraíble en Windows**. Entonces se verifica la ruta
*resuelta* al extraer, y se falla con un mensaje claro — nunca truncando.

### 3.5 Al extraer — defensa en profundidad

Además de repetir 3.1 y aplicar 3.2 según la plataforma:

- se resuelve la ruta contra el directorio destino y se **verifica que la ruta
  resuelta siga adentro**
- se verifica el largo de la ruta resuelta contra el límite de la plataforma
- se rechaza si el destino existe y no se pidió sobrescribir

Resolver-y-verificar es redundante con la validación, y va igual: la validación
sola ya falló en archivadores conocidos.

## 4. Lo que esto le pide al layout

1. **El índice va antes de los payloads.** Permite `list` sin decodificar y hace
   posibles los chequeos 1–6 antes de tocar el códec.
2. **Cada entrada declara los dos tamaños** — original y payload. El original es
   una afirmación del atacante, y por eso mismo sirve: permite rechazar temprano.
3. **Un flag de modo de ruta en la cabecera**, no por miembro. El contenedor es
   plano o preserva rutas; mezclarlo complica la validación sin comprar nada.
4. **El hash va en la entrada del índice**, no junto al payload, para que
   verificar la integridad declarada no requiera recorrer el archivo entero.

---

## 5. Lo que esta política **no** cubre

- **Modo sólido (fase 2):** con los modelos compartidos entre miembros, un
  miembro no se puede rechazar sin haber procesado los anteriores, así que el
  rechazo temprano desaparece y el presupuesto agregado queda como única defensa.
  Es un argumento para que sólido sea un flag y no el modo natural.
- **El residuo del `.pjg` suelto:** las 70 truncaciones superficiales y los 4
  bit-flips que reconstruyen algo incorrecto en silencio siguen igual. Este
  documento no los toca.
