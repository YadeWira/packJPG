# Formato del contenedor PJA

**Nombre decidido: PJA** (packJPG Archive). La extensión sigue siendo `.pjg`;
el despacho es por magia, no por extensión, igual que en el `.pjg` de un solo
archivo. `MJG` se descartó por colisión con Motion JPEG, que es un formato de
video que ya existe.

El layout sale de lo que pidió `POLITICA.md`: índice antes de los payloads, los
dos tamaños declarados por entrada, el modo de ruta en la cabecera y el hash
dentro del índice.

---

## 1. Layout

```
CABECERA — 28 B, siempre presente
  magia         4 B   "PJA\x01"          en claro siempre
  version       1 B                      en claro siempre
  flags         1 B   bit0 cifrado · bit1 preserva rutas · bit2 sólido
  reservado     2 B   cero, rechazar si no
  tam_indice    u32   bytes del índice ya serializado
  hash_indice  16 B   BLAKE3-128 de (cabecera[0..12] ‖ índice)
  [ si cifrado ]                         tam_indice y hash_indice van EN CERO
  sal          16 B   Argon2id           acá; los de verdad viajan cifrados
  nonce_base   24 B   XChaCha20

ÍNDICE — cifrado si bit0
  [ si cifrado, precedido por ]
  tam_indice    u32   el de verdad
  hash_indice  16 B   el de verdad
  count         u32
  por miembro:
    nombre_len  u16
    nombre      nombre_len B, UTF-8, sin NUL
    tam_orig    u64
    tam_payload u64
    hash        16 B   BLAKE3-128 del JPEG original
    m_flags     1 B    bit0 independiente / predicho (reservado, fase 2)

PAYLOADS — cifrados si bit0
  contiguos, en el orden del índice
```

**`count` va adentro del índice, no en la cabecera**, para no filtrarlo cuando
está cifrado.

**Decidido: con cifrado, el índice va cifrado — y con él `tam_indice` y
`hash_indice`.** La consecuencia práctica es que `list` no funciona sin
contraseña: no se puede ver qué hay adentro sin poder abrirlo. Se acepta.

Un borrador anterior dejaba esos dos campos en claro "porque hacen falta para
cortar el índice". Es falso que hagan falta antes de descifrar, y dejarlos
tenía un costo que no habíamos visto: `hash_indice` es BLAKE3 del índice, y el
índice **es** la lista de nombres. En claro, eso convierte el archivo en un
**oráculo de confirmación** — alguien que sospeche qué fotos hay adentro arma
el índice candidato, calcula el hash y compara, sin contraseña y sin tocar el
cifrado. `tam_indice` por su lado da la cantidad de miembros y el largo de sus
nombres con bastante precisión; el tamaño del archivo no da eso.

Entonces, cifrado puesto: los 20 bytes se escriben **en cero** en la cabecera
de disco y se llevan al frente del cuerpo cifrado, donde el AEAD ya los
autentica. Al abrir se reponen y de ahí para abajo el camino es exactamente el
mismo que sin cifrar. Y esos 20 bytes en cero **se verifican**: si llegan con
cualquier otra cosa se rechaza, porque si no serían 160 bits del archivo que no
significan nada y que un bit volteado no cambiaría — un agujero justo en lo que
mide la batería de corrupción.

En claro quedan 8 bytes: magia, versión, flags y reservado. Lo mínimo para
saber qué archivo es y que pide contraseña.

---

## 2. Cifrado — por trozos, no en un bloque

Un solo AEAD sobre todo el archivo obligaría a tener el contenedor entero en
memoria antes de verificar el tag. Con 5 GB no es viable, y **el requisito de
verificar el MAC antes de que un byte llegue al códec no es negociable**.

Entonces: **AEAD por trozos** de 64 KB, cada uno con su tag.

- clave: Argon2id sobre la contraseña, con la sal de la cabecera
- nonce por trozo: `nonce_base` con el contador del trozo mezclado — **nunca se
  reutiliza un nonce**
- el número de trozo va en el AAD, así **reordenar trozos falla**
- el último trozo se marca en su propio AAD, así **truncar falla**
- índice y payloads viajan en la misma secuencia de trozos: el índice no se
  puede leer sin autenticar

Sin las dos últimas reglas, un atacante puede reordenar o cortar sin romper
ningún tag individual. Es el error clásico del cifrado por trozos.

---

## 3. Orden de operaciones al abrir

Es el orden lo que da la seguridad, no los chequeos sueltos:

1. leer y validar la cabecera (magia, versión, reservado en cero)
2. si cifrado: derivar clave, **verificar el trozo del índice**
3. deserializar el índice
4. **límites 1–6 de `POLITICA.md`** — todos, antes de tocar el códec
5. validar todos los nombres — todos, antes de escribir nada
6. recién ahí, decodificar

Los pasos 4 y 5 son **completos antes de continuar**: no se procesa el miembro 1
mientras el 900 tiene un nombre inválido.

---

## 4. Casos hostiles — se escriben con el parser, no después

Es la primera vez que conocemos las formas de antemano. Cada fila es un caso
determinista con su resultado esperado.

### 4.1 Cabecera

| caso | esperado |
|---|---|
| magia equivocada | rechaza, "no es un contenedor PJA" |
| versión futura | rechaza, "generado por una versión más nueva" |
| reservado ≠ 0 | rechaza |
| archivo de 0 bytes, y de 11 bytes | rechaza, sin leer fuera |
| `tam_indice` > tamaño del archivo | rechaza |
| `tam_indice` = 0xFFFFFFFF | rechaza, **sin reservar** |

### 4.2 Índice

| caso | esperado |
|---|---|
| `count` = 0xFFFFFFFF | rechaza por tope absoluto, sin reservar |
| `count` = 10.000 en archivo de 2 KB | rechaza por regla 2 |
| `Σ tam_payload` ≠ tamaño real | rechaza por regla 3 |
| `Σ tam_orig` = 2^63 | rechaza por regla 4, **sin desbordar la suma** |
| `tam_payload` = 0 | rechaza por regla 6 |
| `nombre_len` pasa el fin del índice | rechaza |
| dos entradas con el mismo nombre | rechaza al abrir, en el índice del **primero** cuyo nombre ya apareció |
| 1.048.576 nombres **distintos** (el tope), sumas que no cuadran | rechaza por regla 3 **en tiempo casi lineal**: 49 MB en 0,49 s |
| `Σ tam_payload + tam_índice + 28` pasa 2^64 | rechaza por desborde, **no** da la vuelta |

La penúltima fila salió de medir, no de pensar. El chequeo de duplicados era un
bucle contra todos los anteriores: cuadrático. Con un archivo armado a mano
—cabecera válida y el hash del índice bien calculado, que no es secreto—,
60.000 nombres distintos en 2,82 MB tardaban **7,1 s**, y llevado al tope se
estimaban **~39 minutos** con nombres cortos y **~2,4 horas** con nombres de
250 B. Todo **antes** de que la regla 3 notara que las sumas no cuadraban: la
bomba que esta capa existe para parar, pasando por adentro de la capa.

### 4.3 Nombres

| caso | esperado |
|---|---|
| `../../etc/passwd` | rechaza al crear y al extraer |
| `/etc/passwd`, `C:\Windows\x` | rechaza |
| `a/../../b` | rechaza — `..` en cualquier posición |
| `foto.jpg:carga` | rechaza |
| nombre con `0x00` o `0x0A` | rechaza |
| UTF-8 inválido (`\xff\xfe`) | rechaza |
| componente de 256 bytes | rechaza |
| 128 caracteres acentuados (256 B) | rechaza — **el límite es en bytes** |
| ruta de 33 niveles | rechaza |
| `CON.jpg`, `nul.JPG` | avisa al crear · rechaza al extraer **en Windows** |
| `archivo.jpg ` (espacio final), `archivo.` | avisa al crear · rechaza al extraer en Windows |
| `archivo .jpg` (espacio **en el medio**) | **acepta** — es legal en Windows |
| `foto?.jpg` | avisa al crear · rechaza al extraer en Windows · **acepta en Linux** |
| `ñandú.jpg`, `写真.jpg`, `foto 1 (a).jpg` | **acepta en todas las plataformas** |

### 4.4 Cifrado

| caso | esperado |
|---|---|
| contraseña incorrecta | rechaza, **sin llegar al códec** |
| un bit del payload volteado | falla el tag, sin llegar al códec |
| un bit de la sal volteado | rechaza |
| dos trozos intercambiados | falla por el AAD |
| último trozo eliminado | falla por la marca de fin |
| trozo duplicado | falla por el contador |

### 4.5 Extracción

| caso | esperado |
|---|---|
| destino con enlace simbólico que sale afuera | rechaza tras resolver |
| ruta resuelta pasa `MAX_PATH` en Windows | rechaza con mensaje, **no trunca** |
| el destino ya existe | rechaza salvo que se pida sobrescribir |
| hash no coincide tras decodificar | **se borra el archivo**, se nombra el miembro, se sigue con los demás, y el código de salida es != 0 |
| lo mismo, con `--keep-corrupt` | se renombra a `<nombre>.corrupto`; si ya existe, `.corrupto.1`, `.corrupto.2`… |
| lo mismo, y el renombre falla | **se borra igual** y se devuelve error |
| falla la escritura a mitad de camino | se borra lo escrito antes de devolver el error |

---

## 5. Verificación al extraer — se escribe primero y se verifica después

El orden es ese, y no al revés, porque la reconstrucción del `.pjg` sale del
códec en streaming: verificar antes obligaría a tener el archivo entero en
memoria, que es justo lo que el contenedor evita cuando hay 5 GB de fotos.

La garantía que queda es la que importa, y se enuncia así:

> **Un archivo que sigue en disco con su propio nombre pasó la verificación.**

De ahí salen las reglas de 4.5. Un archivo con nombre bueno y contenido malo es
peor que ningún archivo: es exactamente la clase de corrupción silenciosa que
venimos cerrando en el códec —un `.pjg` truncado que decodificaba a *otro* JPEG
sin avisar— y sería incoherente cerrarla ahí y abrirla acá.

`--keep-corrupt` existe porque un JPEG parcial suele verse y a veces se quiere
rescatar. Pero rescata con **otro nombre**: lo que nunca puede pasar es que el
archivo se quede con el suyo.

---

## 6. Lo que queda decidido y lo que no

**Decidido:** el nombre (**PJA**, extensión `.pjg`); el layout, con `tam_indice`
y `hash_indice` adentro del cifrado; el orden de apertura; el cifrado por trozos
con AAD contra reordenar y truncar; qué pasa con un archivo cuyo hash no
coincide (se borra, `--keep-corrupt` renombra); y las cinco baterías de casos.

**Sin decidir:** el modo sólido —`m_flags` bit0 y el bit2 de `flags` están
reservados para él— porque depende de material que todavía no tenemos: medido
sobre el corpus, la predicción entre imágenes sólo paga si los bloques están
alineados (con alineación difiere el 0,15 % de los coeficientes; sin ella la
predicción *empeora* entre 31 % y 43 %), y no hay ni una ráfaga real en las 90
imágenes disponibles. La consecuencia de diseño ya está tomada: cuando entre,
la predicción es **por bloque**, no global.
