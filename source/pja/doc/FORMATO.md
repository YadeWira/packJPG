# Formato PJA

**Un `.pja` es UN JPEG comprimido.** Lleva adentro el flujo `.pjg` de siempre,
junto con el tamaño y el hash del JPEG original, y puede ir cifrado. La
extensión es `.pja`. El despacho es por magia, no por extensión, igual que el
del `.pjg`.

Hasta el 12/10/2026 el formato iba a ser un contenedor de varios archivos
(versión 1 del layout). Se descartó: la idea era que fotos parecidas
comprimieran mejor juntas, y medido no pasa. Compartir los modelos del códec
entre archivos da entre −0,7 % y +0,2 % en fotos de tamaño normal; ni el mismo
archivo repetido cinco veces gana más de 0,24 %. Los contadores del modelo
saturan en 255 y se reescalan, así que el modelo olvida en pocos KB y no hay
contenido que heredar. Solo las miniaturas ganan (+1,8 % a +3,4 %). El
experimento está en `IA_LAB/agentes/PJPG/solido-calentar/`.

Lo que el `.pja` agrega sobre el `.pjg`, y por qué cada cosa:

| | por qué |
|---|---|
| **hash BLAKE3-128 del JPEG original** | Un `.pjg` alterado puede decodificar a **otro JPEG válido** sin ningún error. Medido sobre los JPEG de `test-files/`, volteando 8.000 bits por archivo: entre el 1 % y el 21 % de los bits terminan así. El hash los delata. |
| **tamaño original declarado** | Permite rechazar una bomba **antes de decodificar**. Además es el tope del decodificador: la salida no puede pasarlo. |
| **cifrado autenticado** | Argon2id + XChaCha20-Poly1305 por trozos. Se verifica antes de que un byte llegue al códec. |

---

## 1. Layout

```
CABECERA — 8 B, siempre en claro
  magia        4 B   "PJA\x01"
  version      1 B   2                    (1 fue el contenedor descartado)
  flags        1 B   bit0 cifrado; los demás en cero
  kdf          1 B   perfil de Argon2id si cifrado (0 = V1); 0 si no
  reservado    1 B   0

SIN CIFRAR                                CIFRADO
  tam_orig   u64  LE                        sal          16 B
  hash       16 B                           nonce_base   24 B
  payload    el resto: el .pjg              trozos AEAD de:
                                              copia de la CABECERA   8 B
                                              tam_orig             u64
                                              hash                16 B
                                              payload           el resto
```

**Con cifrado no queda nada en claro más que los 8 bytes de cabecera, la sal y
el nonce.** El hash del JPEG en claro sería un oráculo de confirmación: quien
sospecha qué foto hay adentro calcula su hash y compara, sin contraseña. El
tamaño también se oculta, y lo que queda visible es el largo del archivo.

**La copia de la cabecera adentro del cifrado** tiene que coincidir con la de
afuera. Hoy esos 8 bytes ya están atados de otra forma: la magia, la versión,
el reservado y el bit de cifrado los fija la validación, y el perfil de KDF
cambia la clave. La copia es para el primer flag o perfil nuevo que **no**
cambie la clave; sin ella, quedaría afuera sin autenticar.

---

## 2. Cifrado: por trozos, no en un bloque

Un solo AEAD sobre todo el archivo obligaría a tener el contenido entero en
memoria antes de verificar el tag. Por eso se cifra **por trozos de 64 KB**,
cada uno con su tag (en disco: largo `u32` ‖ cifrado ‖ tag de 16 B):

- la clave sale de Argon2id sobre la contraseña, con la sal de la cabecera
  (perfil V1: m = 64 MiB, t = 3, p = 1). El perfil va por número, no por sus
  parámetros: un archivo que declarara `m` y `t` crudos podría pedir memoria
  arbitraria antes de validar nada.
- nonce por trozo: el `nonce_base` con el contador del trozo mezclado. **Nunca
  se reutiliza un nonce.** La sal y el nonce salen del generador del sistema
  (`getrandom`; `RtlGenRandom` en Windows).
- el número de trozo va en el AAD, así **reordenar trozos falla**.
- el último trozo se marca en su propio AAD, así **truncar falla**.
- **nada puede seguir al trozo marcado como último**, ni basura ni un trozo
  que autentique (`SobranTrozos`).

Sin las reglas del AAD, un atacante puede reordenar o cortar sin romper ningún
tag individual. Es el error clásico del cifrado por trozos.

Con la contraseña equivocada falla el primer trozo. Un primer trozo alterado
también falla ahí, y el AEAD no distingue un caso del otro, así que los dos
dan `PJA_ERR_CLAVE`.

---

## 3. Orden de operaciones

**Al abrir** (`pja_abrir`), y es el orden lo que da la seguridad:

1. validar la cabecera: magia, versión, flags conocidos, reservado en cero, y
   el perfil de KDF (con cifrado) o cero (sin cifrado)
2. con cifrado: derivar la clave y **autenticar todos los trozos**; después,
   que la copia de la cabecera coincida
3. validar el descriptor: `tam_orig` entre 1 y 500 × el largo del payload
   (`ValidarDescriptor`), y payload de al menos 12 B (la cabecera `.pjg`
   mínima)
4. recién ahí, el payload queda disponible

**Al extraer** (lo que hace quien llama, porque el núcleo no tiene el códec:
ver `pjatool.cpp`):

5. rechazar si `tam_orig` pasa el tope del usuario (`--max-output`)
6. decodificar con `tam_orig` **como tope** del decodificador
7. verificar que el JPEG mida `tam_orig` y tenga el hash declarado
8. recién ahí, escribirlo con su nombre (`pja_guardar`, `pjafs.EscribirVerificado`)

El CLI de packJPG hace exactamente eso desde la 6.0 (`a` escribe `.pja` por
defecto); `pjatool.cpp` es la versión mínima.

**El escritor valida con la misma función que el lector.** Lo que se escribe
se puede abrir, y lo que se rechaza al abrir no se puede escribir. Es la regla
que rompía el contenedor anterior: escribía archivos de más de 8 GiB que su
propio lector rechazaba.

---

## 4. Casos hostiles

Cada fila es un caso con su resultado esperado, y está en las pruebas.

### 4.1 Cabecera (`prueba_formato`)

| caso | esperado |
|---|---|
| 0 a 7 bytes | `ArchivoCorto` |
| magia equivocada, basura | `NoEsPja` (no "falta contraseña", aunque el byte 5 sea impar) |
| versión 3 o más | `VersionFutura(n)` |
| versión 0 o 1 (el contenedor descartado) | `VersionVieja(n)` |
| un flag desconocido | `FlagDesconocido` |
| reservado ≠ 0; kdf ≠ 0 sin cifrado | `ReservadoNoCero` |
| perfil de KDF desconocido | `PerfilKdfDesconocido(n)` |

### 4.2 Descriptor (en el escritor **y** en el lector, con el mismo veredicto)

| caso | esperado |
|---|---|
| `tam_orig` = 0 | `TamOrigInvalido` |
| `tam_orig` > 2^63 − 1 (`pja_tam_orig` es `int64_t`) | `TamOrigInvalido` |
| `tam_orig` = 500 × payload | acepta |
| `tam_orig` = 500 × payload + 1 | `RatioExcedido`, sin multiplicar (dividiendo: no desborda) |
| payload de 11 B | `PayloadFueraDeRango` |

### 4.3 Cifrado (`prueba_cifrado`, `prueba_formato`)

| caso | esperado |
|---|---|
| contraseña equivocada, falta o sobra | `CLAVE`, sin llegar al códec |
| un bit de la sal o del nonce | `TrozoAlterado(0)`: otra clave u otro nonce |
| un bit en el trozo n | `TrozoAlterado(n)` |
| dos trozos intercambiados | falla por el AAD |
| sin el último trozo | `Truncado` |
| el último trozo repetido, o basura al final | `SobranTrozos` |
| la copia de la cabecera distinta (armado con la clave) | `CabeceraAlterada` |
| un descriptor inválido adentro del cifrado (armado con la clave) | el mismo error que sin cifrar |

### 4.4 Corrupción (`prueba_corrupcion`, `pjatool corrupcion`)

- **Sin cifrar:** cada bit de 10 `.pjg` reales, cada valor de la cabecera y
  del descriptor, cada truncado y agregados al final, 410.758 variantes en
  total. Ninguna **lee igual** que el original: cada byte significa algo. Las
  que el formato no puede rechazar (un bit en el payload) leen un payload
  distinto, y las delata la verificación del paso 7.
- **Cifrado:** 31.466 variantes, todas rechazadas.
- **Punta a punta, con el códec:** bits al azar sobre un `.pja` sin cifrar,
  extraídos como lo haría el CLI. **Ninguno termina en un JPEG distinto
  entregado como bueno**: el resultado es rechazo del formato, rechazo del
  códec, falla de verificación, o (un bit que el códec no usa) el mismo JPEG.

### 4.5 Escritura de la salida (`prueba_pjafs`)

| caso | esperado |
|---|---|
| enlace (simbólico o duro) con el nombre de la salida | sin sobrescribir: el nombre está ocupado (un enlace colgante también lo ocupa); con sobrescribir, se reemplaza la entrada y **nunca se escribe a través** |
| la salida ya existe | rechaza, salvo que se pida sobrescribir |
| con sobrescribir | se escribe a un temporal nuevo del mismo directorio y se renombra encima: **lo que había solo se reemplaza por algo que verificó** |
| la salida es un directorio | rechaza, aunque se pida sobrescribir |
| hash que no coincide | **no se escribe nada** con ese nombre (el hash se mira antes de escribir) |
| lo mismo, con `--keep-corrupt` | se escribe como `<nombre>.corrupto`; si ya existe, `.corrupto.1`, `.corrupto.2`… |
| lo mismo, y no hay nombre `.corrupto` libre | error, sin escribir nada |
| falla la escritura a mitad de camino | se borra lo escrito antes de devolver el error |
| no se pudo crear el archivo | **no se borra nada**: lo que haya ahí no lo escribimos nosotros |

Hasta el 12/10 sobrescribir **borraba primero** lo que había. Desde el CLI eso
quería decir que un `x -f` de un `.pja` que no verificaba destruía el JPEG que
el usuario ya tenía, y no dejaba nada en su lugar.

> **Un archivo que sigue en disco con su propio nombre pasó la verificación.**

Un archivo con nombre bueno y contenido malo es peor que ningún archivo.
`--keep-corrupt` existe porque un JPEG parcial suele verse y a veces se quiere
rescatar, pero lo rescata con **otro nombre**.
