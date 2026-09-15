# Append incremental — diseño

**Borrador para revisar. Sin código todavía.**

El problema: una carpeta que gana archivos a diario contra un `.pja` único. Con
el layout actual —cabecera, índice, payloads— agregar un miembro corre todos los
payloads, o sea reescribir el archivo entero. Medido sobre 100 miembros /
23,5 MB: **336 MB/s sin cifrar, 196 MB/s cifrado**. Para un backup de 5 GB son
~15 s (o ~25 s cifrado) **todos los días, para agregar 2 MB**. Y con cifrado
además hay que re-cifrar todo, con el peligro que eso trae (ver §5).

La referencia es zpaq/zpaqfranz, medido acá con ese mismo escenario:

    día 1 — 19 imágenes        201 ms
    día 2 — UNA imagen nueva    19 ms
    día 3 — nada cambió         13 ms, el archivo no creció

---

## 1. Estructura: transacciones que sólo se agregan

```
CABECERA GLOBAL — 28 B + prefijo de cifrado, se escribe UNA vez
  magia         4 B   "PJA\x01"
  version       1 B
  flags         1 B   bit0 cifrado · bit1 rutas · bit2 sólido
  kdf           1 B   perfil de derivación (0 = Argon2id 64 MiB, t=3)
  reservado     1 B   cero
  [ si cifrado ]
  sal          16 B
  nonce_base   24 B

TRANSACCIÓN 0
TRANSACCIÓN 1
...
```

Cada actualización **agrega una transacción al final**. Nada de lo ya escrito se
toca nunca. De ahí sale que el append sea O(lo nuevo) y no O(archivo).

### La transacción

```
ENCABEZADO
  magia_tx      4 B   "PJAT"           permite resincronizar al escanear
  numero        u32   monótono: 0, 1, 2…
  contador_ini  u64   primer índice de trozo AEAD de esta transacción (§5)
  tam_indice    u32
  tam_payloads  u64
  hash_enc     16 B   BLAKE3-128 del encabezado (sin este campo) + índice

ÍNDICE   — sólo los cambios de esta transacción
  count         u32
  por entrada:
    accion      1 B   0 = alta/reemplazo · 1 = baja (lápida)
    nombre_len  u16
    nombre      nombre_len B
    tam_orig    u64   \
    tam_payload u64    |  ausentes si accion = baja
    hash       16 B   /
    m_flags     1 B   bit0 arranca bloque sólido

PAYLOADS  — contiguos, en el orden del índice

CIERRE — lo que zpaq NO tiene
  magia_fin     4 B   "PJAZ"
  numero        u32   el MISMO de arriba
  contador_fin  u64   primer trozo libre después de esta transacción
  hash_tx      16 B   BLAKE3-128 de la transacción entera
```

**El estado actual es el pliegue de todas las transacciones, en orden.** Un
nombre que aparece dos veces gana la última; una lápida lo saca.

---

## 2. El cierre, que es el punto del diseño

La wiki de zpaqfranz documenta esto de su propio formato:

> «an incomplete transaction at point 27 will result in all subsequent versions
> appearing to be intact but actually being corrupted»

**Una transacción interrumpida deja versiones que parecen intactas y no lo
están.** Es exactamente la clase de corrupción silenciosa que cerramos en el
códec —un `.pjg` truncado que decodificaba a *otro* JPEG— y sería incoherente
importarla acá. zpaq la trata con un comando de reparación posterior; nosotros
la cerramos en el formato.

Tres reglas:

1. **Una transacción sin su cierre válido está incompleta**, y eso es un error,
   no algo que se ignora. El `hash_tx` del cierre cubre la transacción entera:
   un corte a mitad de camino no lo puede producir.
2. **Nada puede venir después de una transacción incompleta.** Si hay bytes
   después, se rechaza el archivo. Ese es justo el caso donde zpaq pierde datos
   en silencio.
3. **Descartarla es explícito.** `--descartar-incompleta` la tira y lo dice; sin
   eso, abrir falla con un mensaje que nombra el número de transacción.

Y del lado del escritor: **antes de agregar, verificar que la última transacción
esté completa.** Si no lo está, negarse y pedir la decisión.

---

## 3. Leer: sigue siendo una sola pasada hacia adelante

El orden de apertura no cambia, se aplica por transacción:

    cabecera global → por cada transacción: encabezado, hash, índice, límites,
    nombres → y recién ahí sus payloads quedan disponibles para el códec

Se mantiene la propiedad que no queríamos negociar: **ni un byte llega al códec
antes de haber validado todo lo que lo describe.** Y se puede leer de un pipe.

Costo respecto de hoy: para saber qué contiene el archivo hay que recorrer todas
las transacciones, no sólo el índice del principio. Es leer los índices, no los
payloads, así que es proporcional a la cantidad de miembros y no al tamaño.

---

## 4. Lo que NO se toma de zpaq

**La deduplicación por fragmentos.** zpaq parte los archivos con un hash rodante
y los identifica por SHA-1 (~65 KB promedio). Dos razones para no copiarla:
guardamos el JPEG **recomprimido**, y datos comprimidos no deduplican a nivel de
bytes; y para el caso que importa en un backup diario —«este archivo ya está»—
alcanza con comparar el **BLAKE3-128 por miembro que ya tenemos**, que es
muchísimo más barato. La propia wiki admite el riesgo de colisión de SHA-1.

Regla de dedup nuestra, entonces: al agregar, si el nombre ya está con el mismo
hash, **no se escribe nada**. Es lo que hace que «no cambió nada» cueste 13 ms.

---

## 5. Cifrado: el contador nunca retrocede

zpaq usa un solo keystream continuo «como si las partes estuvieran
concatenadas». Es lo que hace que agregar no reutilice nonce, y hay que
copiarlo.

Nuestro equivalente: el contador de trozos AEAD **es global al archivo y
monótono**. La transacción N arranca en el `contador_fin` que dejó la N-1.

- **Se declara y se verifica:** `contador_ini` en el encabezado, `contador_fin`
  en el cierre. El lector exige `contador_ini(N) >= contador_fin(N-1)`.
- **Tras descartar una transacción incompleta**, la siguiente NO arranca donde
  arrancaba la descartada: arranca en un valor estrictamente mayor que
  cualquiera que la parcial pudiera haber usado, que se calcula de su largo en
  bytes. **Sin esta regla, descartar y volver a agregar reutiliza nonces con
  contenido distinto — y en ChaCha20-Poly1305 eso no degrada el cifrado, lo
  rompe:** se filtra el XOR de los dos textos planos y se pueden falsificar tags.

**Lo que NO se copia de zpaq: su cifrado.** La wiki dice literalmente
«Encryption provides secrecy but not authentication. An attacker who knows or
can guess any bits of the plaintext can set them without knowing the key» —
AES-CTR sin MAC. Nosotros seguimos con XChaCha20-Poly1305, que es AEAD, con el
número de trozo y la marca de último en el AAD. Y el KDF sigue siendo Argon2id
con 64 MiB frente a los 16 MB del scrypt de zpaq.

El índice de cada transacción viaja adentro del cifrado, así que `list` sigue
pidiendo contraseña. Sin cambios respecto de lo decidido.

---

## 6. Qué queda por decidir

- **Consolidar.** Un archivo con mil transacciones se degrada. Hace falta un
  `consolidar` que reescriba todo en una sola. Es la operación cara que hoy
  sería cada append.
- **Versionado expuesto.** La estructura ya permite extraer un estado pasado.
  ¿Se expone en la CLI, o el versionado queda como propiedad interna?
- **Límites.** Los seis límites de `POLITICA.md` hoy se aplican al índice
  completo. Con transacciones hay que decidir si se aplican por transacción o al
  estado plegado. **Al estado plegado**, o mil transacciones de un miembro
  esquivan el límite de miembros.
- **Bloques sólidos y append.** Una transacción nueva no puede predecir desde
  una anterior sin obligar a leerla. Lo más simple: **cada transacción arranca
  bloque sólido**. Pierde algo de ratio entre tandas; mantiene el append barato.
