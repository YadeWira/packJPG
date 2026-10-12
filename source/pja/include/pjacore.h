/* pjacore.h — frontera C++ <-> nucleo del formato .pja (FreePascal).
 *
 * Un .pja es UN JPEG comprimido (el flujo .pjg) con el tamaño y el hash
 * BLAKE3-128 del original declarados y, opcionalmente, cifrado
 * (Argon2id + XChaCha20-Poly1305 por trozos). Layout en doc/FORMATO.md.
 *
 * Contrato, deliberadamente angosto:
 *   - entra puntero + largo, sale un codigo de estado; 0 es exito
 *   - NINGUNA propiedad de memoria cruza el borde: los buffers los provee
 *     el llamador, y el unico objeto con estado es un manejador opaco con
 *     su abrir/cerrar
 *   - los `*_largo` existen para preguntar el tamaño ANTES de reservar
 *   - ninguna excepcion cruza el borde: un defecto interno vuelve como
 *     PJA_ERR_INTERNO
 *   - ANTES de cualquier otra llamada, pja_iniciar(argc, argv, envp) al
 *     principio de main; pja_terminar() al final. Enlazada estatica (Linux),
 *     sin pja_iniciar todo devuelve PJA_ERR_NO_INIT: sin runtime la
 *     proteccion de rango del lado Pascal se apaga en silencio, y eso no
 *     puede pasar callado. En la DLL (Windows) el runtime arranca al
 *     cargarla y pja_iniciar solo lo confirma.
 *
 * Lo que queda del lado del llamador, porque el nucleo no tiene el codec:
 * decodificar el payload, y verificar que el JPEG que sale mida pja_tam_orig
 * y tenga el hash de pja_hash. Sin esa verificacion, un .pjg alterado puede
 * decodificar a OTRO JPEG valido sin que nada lo note.
 */
#ifndef PJACORE_H
#define PJACORE_H
#include <stddef.h>
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif

#define PJA_OK              0
#define PJA_ERR_NULL       -1
#define PJA_ERR_BUF_CHICO  -2
#define PJA_ERR_FORMATO    -3   /* no es un .pja, o version o cabecera invalidas */
#define PJA_ERR_LIMITE     -4   /* descriptor imposible: payload chico, tam_orig 0 o > 500x */
/*      -5 era PJA_ERR_NOMBRE, del contenedor de varios archivos */
#define PJA_ERR_CLAVE      -6   /* contraseña faltante, sobrante o incorrecta (*) */
#define PJA_ERR_ALTERADO   -7   /* cifrado: un trozo despues del primero, truncado, cabecera */
/*      -8 era PJA_ERR_RANGO, del indice de miembros */
#define PJA_ERR_INTERNO    -9   /* defecto nuestro: una excepcion adentro */
#define PJA_ERR_NO_INIT   -10   /* falto pja_iniciar */
#define PJA_ERR_ALEATORIO -11   /* el sistema no dio bytes aleatorios para la sal */
#define PJA_ERR_IO        -12   /* pja_guardar: no se pudo escribir (ver *codigo) */
/* (*) Con la contraseña equivocada falla el primer trozo, y un primer trozo
 *     alterado falla igual: el AEAD no los distingue. Los dos dan CLAVE. */

int32_t pja_iniciar(int argc, char** argv, char** envp);
void    pja_terminar(void);
/* 1 si el runtime esta arrancado. */
int32_t pja_inicializado(void);
/* 1 si el nucleo se compilo con control de rango. Una prueba que no lo mire
 * podria pasar con la red apagada. */
int32_t pja_rango_activo(void);
/* La version del formato que escribe (2). */
uint32_t pja_version(void);

/* Solo la cabecera en claro, sin derivar nada: si es un .pja y si pide
 * contraseña (*cifrado = 1). Para decidir si preguntarla. */
int32_t pja_examinar(const uint8_t* datos, size_t largo, int32_t* cifrado);

typedef struct PjaAbierto PjaAbierto;

/* Abre un .pja en memoria. `pass` NULL = sin contraseña; con pass_largo 0 y
 * pass no nulo, la contraseña vacia. Con cifrado, autentica todo antes de
 * volver. Al volver PJA_OK, `*salida` debe liberarse con pja_cerrar. */
int32_t pja_abrir(const uint8_t* datos, size_t largo,
                  const uint8_t* pass, size_t pass_largo,
                  PjaAbierto** salida);
void    pja_cerrar(PjaAbierto* h);

/* Tamaño declarado del JPEG original: para rechazar antes de decodificar. */
int64_t pja_tam_orig(const PjaAbierto* h);
int64_t pja_payload_largo(const PjaAbierto* h);
int32_t pja_payload(const PjaAbierto* h, uint8_t* buf, size_t buf_largo);
/* BLAKE3-128 declarado del JPEG original (16 bytes). */
int32_t pja_hash(const PjaAbierto* h, uint8_t* buf, size_t buf_largo);

/* BLAKE3-128 de un buffer: el hash del JPEG para pja_escribir, y para
 * verificar contra pja_hash tras decodificar. */
int32_t pja_hash128(const uint8_t* datos, size_t largo, uint8_t* buf, size_t buf_largo);

/* --- escritura --- */

/* Cuantos bytes ocupa el .pja de un payload de ese largo, cifrado o no. Es
 * exacto y no valida nada mas: los errores los da pja_escribir. */
int64_t pja_escribir_largo(size_t payload_largo, int32_t cifrado);
/* `payload` es el .pjg; `hash` y `tam_orig`, los del JPEG original. Con
 * `pass` no nulo cifra, con una sal y un nonce del sistema (y deriva Argon2id:
 * 64 MiB, del orden de un segundo). Valida lo mismo que pja_abrir: lo que se
 * escribe se puede abrir. */
int32_t pja_escribir(const uint8_t* payload, size_t payload_largo,
                     const uint8_t hash[16], uint64_t tam_orig,
                     const uint8_t* pass, size_t pass_largo,
                     uint8_t* buf, size_t buf_largo);

/* --- guardar la salida ---
 *
 * Escribe `datos` en `ruta` (UTF-8, sin NUL; en Windows se pasa a UTF-16) y
 * verifica que su BLAKE3-128 sea `esperado` ANTES de dejarlo con ese nombre:
 *
 *   - el archivo se CREA (O_EXCL / CREATE_NEW): nunca se escribe a traves de
 *     un enlace simbolico o duro que ya tenga ese nombre, y uno colgante
 *     tambien ocupa el nombre;
 *   - con `sobrescribir`, lo que haya se borra antes (un directorio, no);
 *   - si el hash no coincide, el archivo se BORRA, o con `conservar` queda
 *     como <ruta>.corrupto (o .corrupto.1, .2...): nunca con su nombre;
 *   - una escritura que falla a la mitad no deja nada; si no se pudo crear,
 *     no se borra nada (lo que haya ahi no lo escribimos nosotros);
 *   - crea los directorios que falten.
 *
 * *desenlace: PJA_GUARDADO_*. *codigo: errno o GetLastError si fallo (-1 si
 * el error no vino del sistema). `ruta_final` (opcional) recibe la ruta
 * donde quedo el archivo, terminada en NUL y recortada al buffer;
 * *ruta_final_usado, su largo completo. */
#define PJA_GUARDADO_VERIFICADO 0
#define PJA_GUARDADO_BORRADO    1   /* el hash no coincidia: no queda nada */
#define PJA_GUARDADO_CONSERVADO 2   /* no coincidia: quedo en ruta_final */
int32_t pja_guardar(const char* ruta, size_t ruta_largo, const uint8_t* datos, size_t largo,
                    const uint8_t esperado[16], int32_t conservar, int32_t sobrescribir,
                    int32_t* desenlace, int32_t* codigo,
                    char* ruta_final, size_t ruta_final_largo, size_t* ruta_final_usado);

#ifdef __cplusplus
}
#endif
#endif
