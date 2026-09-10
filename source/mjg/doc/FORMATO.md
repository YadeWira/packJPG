# Formato del contenedor — borrador

Sin código. El nombre y la extensión están sin decidir (MJP / PPJG / PJGS); acá
va `MJG` como marcador de posición.

El layout sale de lo que pidió `POLITICA.md`: índice antes de los payloads, los
dos tamaños declarados por entrada, el modo de ruta en la cabecera y el hash
dentro del índice.

---

## 1. Layout

```
CABECERA — siempre en claro
  magia         4 B   "MJG\x01"
  version       1 B
  flags         1 B   bit0 cifrado · bit1 preserva rutas · bit2 sólido
  reservado     2 B   cero, rechazar si no
  tam_indice    u32   bytes del índice ya serializado
  [ si cifrado ]
  sal          16 B   Argon2id
  nonce_base   24 B   XChaCha20

ÍNDICE — cifrado si bit0
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
está cifrado. `tam_indice` sí va en claro porque hace falta para leerlo — eso
filtra la cantidad *aproximada* de miembros, y se acepta: el tamaño del archivo
ya la filtra igual.

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
| magia equivocada | rechaza, "no es un contenedor MJG" |
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
| dos entradas con el mismo nombre | rechaza al abrir |

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
| hash no coincide tras decodificar | reporta el miembro, y **el archivo escrito no se da por bueno** |

---

## 5. Lo que queda decidido y lo que no

**Decidido:** layout, orden de apertura, cifrado por trozos con AAD contra
reordenar y truncar, y las cinco baterías de casos.

**Sin decidir:** el nombre y la extensión; la letra del switch de cifrado; y qué
se hace con el archivo ya escrito cuando el hash no coincide — borrarlo,
dejarlo, o renombrarlo. Esa última toca la CLI, la librería y a packPDF, que
vendorizó `libpackJPG.so`.
