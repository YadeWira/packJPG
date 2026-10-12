# Formato PJA

Un `.pja` es **un JPEG comprimido con integridad y, si se pide, cifrado**: el
flujo `.pjg` de siempre, más el tamaño y el hash BLAKE3-128 del JPEG original.
Layout y razones en `doc/FORMATO.md`, y límites en `doc/POLITICA.md`.

**Es lo que escribe `packJPG a` por defecto desde la 6.0** (`--pjg` para el
formato de antes). `pjatool.cpp` es la demostración mínima punta a punta: usa
`pjglib` para el códec y esta biblioteca para el formato, en el mismo orden
que el CLI.

```sh
pjatool a foto.jpg foto.pja [contraseña]
pjatool x foto.pja foto.jpg [contraseña]     # decodifica, verifica tamaño y hash, y recién ahí escribe
```

## Historia corta

- **Contenedor de varios archivos → un archivo (12/10/2026).** La idea era que
  fotos parecidas comprimieran mejor juntas. Medido, compartir los modelos del
  códec entre archivos no paga: da −0,7 % a +0,2 % en fotos normales. Se
  descartaron el índice de miembros, los nombres y rutas, la contención al
  extraer, el append y el modo sólido. Queda en el historial de git, hasta
  `51c8c29`.
- **Rust → FreePascal (25/09/2026).** Rust para Windows 7 es Tier 3 en todos
  los targets, y packJPG declara soporte desde Windows 7 SP1 con binarios de
  32 bits. FreePascal tiene `i386-win32` como destino principal desde siempre.
  El port se validó con diferenciales contra el Rust, módulo por módulo, y el
  Rust se retiró junto con el contenedor. Lo único que quedó de él son los
  vectores de `pas/pruebas/kat.txt`: Argon2id, el cifrado por trozos byte a
  byte en los bordes de 64 KiB, y BLAKE3.
- **El cifrado no se escribe en Pascal**: va en C, con Monocypher 4.0.3 y la
  implementación oficial de BLAKE3 1.8.7 (`pas/c/`).

## Estructura

| | |
|---|---|
| `pas/pjaformato.pas` | el formato: cabecera, descriptor, abrir y escribir, con la misma validación de los dos lados |
| `pas/pjacifrado.pas` | AEAD por trozos de 64 KB, número y marca de último en el AAD |
| `pas/pjacripto.pas`, `pas/c/` | BLAKE3, Argon2id, XChaCha20-Poly1305 y el generador del sistema, en C |
| `pas/pjalimites.pas` | los números de `POLITICA.md` |
| `pas/pjafs.pas` | escribir la salida (`pja_guardar`): sin seguir enlaces, sin escrituras a medias, sin dejar con su nombre un archivo que no verifica, y sobrescribiendo solo con algo que verificó |
| `pas/pjaffi.pas` | la frontera C (`include/pjacore.h`) |
| `pas/frontera.sh` | `libpjaffi_pas.a` para enlazar estática en Linux |
| `pas/frontera_win.sh` | `pjaffi_x64.dll` / `pjaffi_x86.dll` para Windows, con ASLR y DEP, y su biblioteca de importación |
| `pas/fpc_i386_win32.sh` | el compilador cruzado de FreePascal para Windows de 32 bits, armado desde `fpc-source` (Debian no lo trae); ~12 s |
| `test_frontera.cpp`, `pjatool.cpp` | consumidores C++ de la frontera |

## Frontera C

Entran punteros con largo y salen códigos de estado. **Ninguna propiedad de
memoria cruza**: los buffers los provee quien llama, y los `*_largo` sirven
para preguntar el tamaño antes de reservar.

**`pja_iniciar(argc, argv, envp)` va al principio de `main`**, antes de
cualquier otra `pja_*`, y `pja_terminar()` al final. Enlazada estática no hay
cargador que arranque el runtime de FPC, y sin runtime la protección de rango
se apaga en silencio. Por eso todo devuelve `PJA_ERR_NO_INIT` hasta que se la
llame. Al enlazar hace falta `-lpthread -ldl`. En Windows es una DLL y el
runtime arranca al cargarla.

**Lo que queda del lado de quien llama**, porque el núcleo no tiene el códec:

1. decodificar con `pja_tam_orig` como tope (`pjglib_set_max_output_size`);
2. verificar que el JPEG mida `pja_tam_orig` y tenga el hash de `pja_hash`.

Sin el paso 2, un `.pjg` alterado puede decodificar a otro JPEG válido sin que
nada lo note. `pjatool.cpp` lo hace en `extraer()`.

Enlace, medido: en Linux el código Pascal va **adentro** del ejecutable. En
Windows va como **DLL**, porque metido en el `.exe` obliga a apagar la sección
de relocaciones y el ejecutable entero pierde ASLR. La DLL de FPC, en Windows
10 19044, dio **0 de 20** cuelgues con hilos creados antes del `LoadLibrary`,
contra un control con la DLL de packJPG v5.0d que colgó 3 de 6.

## Probar

Desde `source/`:

```sh
make pja          # pas/build/libpjaffi_pas.a
make pja-tests    # test_frontera y pjatool (este ultimo necesita packJPGlib.a)
make pja-check    # la suite entera
make pja-clean
```

Desde la 6.0 `make all` construye el núcleo, porque `packJPG` lo enlaza: hace
falta FreePascal 3.2. Si `fpc` no está, el target falla con una instrucción;
`make PJA=0` compila sin el núcleo, y entonces `a` exige `--pjg`.

Qué corre `make pja-check` (`pas/correr_pruebas.sh`):

| | |
|---|---|
| guardias de fuente | `colisiones.py` (identificadores que chocan sin distinguir mayúsculas, también contra funciones) y `resultados.py` (funciones que nunca asignan `Result`) |
| `prueba_cripto` | BLAKE3, Argon2id y el cifrado contra `kat.txt`, y el generador del sistema |
| `prueba_cifrado` | el esquema por trozos: cada alteración con su error |
| `prueba_formato` | ida y vuelta con `.pjg` reales, cada error de cabecera y descriptor, escritor y lector con el mismo veredicto |
| `prueba_corrupcion` | 410.758 variantes sin cifrar (ninguna lee igual que el original) y 31.466 cifradas (todas rechazadas) |
| `prueba_pjafs` | enlaces simbólicos, duros y colgantes, sobrescribir, `.corrupto` |
| `test_frontera` | el contrato de `pjacore.h` desde C++, con 8 hilos |
| `sin_init` | sin `pja_iniciar`, todo da `NO_INIT`, también desde 8 hilos |
| `pjatool` | ida y vuelta con el códec, sin cifrar y cifrado; y `corrupcion`: bits al azar sobre un `.pja`, extraídos como lo haría el CLI, **sin un solo JPEG distinto entregado como bueno** |

Y desde `source/`, la del CLI: `test/cli_pja.sh` (43 celdas: cada fuente de
contraseña, `.pja` alterados, `-f`, `--keep-corrupt`, enlaces, hilos, pipes).

Cada prueba exige su cuenta mínima de celdas: una que corre cero no pasa por
verde. Los mutantes van aparte (`IA_LAB/agentes/PJPG/mutantes-formato/`).

## Reglas de FreePascal, todas medidas y ninguna obvia

Las tres primeras están en `pas/pja.inc`.

- **`{$R+}` no controla accesos por puntero.** `p[10]` con `p: PByte` lee fuera
  de rango sin ningún error. La validación trabaja solo sobre arreglos; lo que
  llega por la frontera como puntero y largo se copia a un arreglo primero.
- **Con `{$Q+}`, `for i := 0 to n - 1` con `n` sin signo y `n = 0` lanza
  `EIntOverflow`.** Largos e índices van con signo, y los recorridos usan `High()`.
- **Cada función exportada es una cáscara** sin variables administradas ni
  `try`, que chequea que el runtime esté inicializado antes de llamar a la
  implementación. Sin eso, olvidarse la inicialización apaga `{$R+}` en
  silencio, y FPC arma el marco de excepciones en el prólogo antes de que
  corra cualquier chequeo.
- **En i386, `Int64` no es ordinal**: no sirve de variable de `for`, y el error
  aparece recién al compilar para 32 bits. Contadores en `SizeInt`, y
  posiciones en bytes en `Int64`.
- **`for s in ['corto', 'mas_largo']` recorta los literales** al largo del
  primero, y con números arma un **conjunto** de bytes. Hay que recorrer un
  arreglo constante declarado.
- **En Unix, `TFileStream.Create(f, fmOpenRead)` toma un `flock` exclusivo.**
  Una segunda apertura del mismo archivo, aun en el mismo proceso, falla con
  `EAGAIN`. Para leer: `fmOpenRead or fmShareDenyNone`.
- **FPC no avisa de un `Result` sin asignar si algún camino hace `Exit(valor)`.**
  `pjafs.Padre` devolvía lo que quedara en el registro, y se vio como un fallo
  **intermitente** (1 corrida de cada ~10). `pas/resultados.py` corta el build.
- **Pascal no distingue mayúsculas.** Una variable `version` tapó a la
  constante `VERSION` y ninguna versión futura se rechazaba; una variable
  `plano` tapó a la función `Plano`. El compilador no avisa en ninguno de los
  dos casos (el segundo lo frenó solo porque los tipos no coincidían).
  `pas/colisiones.py` corta el build.
